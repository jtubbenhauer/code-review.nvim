# ReviewLocal + Untracked Files Support

## Context

- Plugin: `code-review.nvim`
- Two issues to address:
  1. Newly added (untracked) files aren't picked up during reviews
  2. Need a way to review uncommitted changes only (`:ReviewLocal`)

## Plan

### Fix 1: Include untracked files in all review modes

**Root cause:** `state.get_changed_files()` only runs `git diff --name-only <branch>`, which doesn't show untracked files. The code has a TODO comment at `state.lua:120-122` acknowledging this.

**File: `lua/code-review/state.lua`**

- Modify `get_changed_files(branch)` (line 108-124) to also run `git ls-files --others --exclude-standard` and merge results (deduplicated)
- This fixes both `:Review <branch>` and the new `:ReviewLocal`

- Modify `get_diff_hash(branch, filepath)` (line 21-28) to handle untracked files
  - For branch reviews: `git diff <branch> -- <file>` works fine for untracked files (shows full file as added)
  - For HEAD-based reviews: `git diff HEAD -- <file>` returns empty for untracked files. Fall back to `md5sum <file>` as the hash
  - Detect empty diff via md5 of empty string: `d41d8cd98f00b204e9800998ecf8427e`

**File: `lua/code-review/autocmds.lua`**

- The BufWritePost handler (line 35-38) uses `git diff --quiet <branch> -- <file>` to detect remaining changes
- For untracked files, this returns "no diff" incorrectly
- Fix: check if the file is untracked first; if so, consider it as always having changes (unless deleted)

### Feature 2: `:ReviewLocal` command

**Concept:** Review all uncommitted changes against HEAD.

**File: `lua/code-review/state.lua`**

- Add `mode` field to `M.state` table: `"branch"` (default) or `"local"`
- `get_changed_files()` for local mode uses `git diff --name-only HEAD` + untracked files
- Save/load/reset all handle the new `mode` field
- Persistence JSON includes `mode`

**File: `lua/code-review/init.lua`**

- New `M.start_local()` public function
- New `:ReviewLocal` user command (no arguments)
- Sets gitsigns base to `HEAD`

**File: `lua/code-review/ui.lua`**

- Update help text to mention `:ReviewLocal`

**File: `lua/code-review/unified.lua`**

- No changes -- `diff.show("HEAD", buf)` works already

## Detailed Changes

### state.lua

1. Add `mode = "branch"` to state table (line 8)

2. New helper:
```lua
local function get_untracked_files()
    local cmd = "git ls-files --others --exclude-standard 2>/dev/null"
    local files = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
        return {}
    end
    return files
end
```

3. Update `get_changed_files(branch)` to merge untracked files:
```lua
function M.get_changed_files(branch)
    branch = branch or config.options.default_branch
    local cmd = string.format("git diff --name-only %s 2>/dev/null", branch)
    local files = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
        return nil
    end

    -- Include untracked files (git diff doesn't show them)
    local untracked = get_untracked_files()
    local seen = {}
    for _, f in ipairs(files) do
        seen[f] = true
    end
    for _, f in ipairs(untracked) do
        if not seen[f] then
            table.insert(files, f)
        end
    end

    return files
end
```

4. Update `get_diff_hash()` to handle untracked/empty diff:
```lua
local function get_diff_hash(branch, filepath)
    local cmd = string.format(
        "git diff %s -- %s 2>/dev/null | md5sum | cut -d' ' -f1",
        branch, vim.fn.shellescape(filepath)
    )
    local result = vim.fn.systemlist(cmd)
    -- d41d8... is md5 of empty string -- means git diff produced no output
    -- This happens for untracked files when diffing against HEAD
    if vim.v.shell_error ~= 0 or not result[1]
        or result[1] == "d41d8cd98f00b204e9800998ecf8427e" then
        -- Fall back to hashing file content directly
        local hash_cmd = string.format(
            "md5sum %s 2>/dev/null | cut -d' ' -f1",
            vim.fn.shellescape(filepath)
        )
        local hash_result = vim.fn.systemlist(hash_cmd)
        if vim.v.shell_error ~= 0 or not hash_result[1] then
            return nil
        end
        return hash_result[1]
    end
    return result[1]
end
```

5. Add `mode` to `init()`, `save()`, `load()`, `reset()`, `refresh()`

### init.lua

1. New `M.start_local()`:
```lua
function M.start_local()
    -- If already in local mode, switch to tab
    if state.state.active and state.state.mode == "local" then
        if ui.switch_to_tab() then return end
        ui.create_layout()
        return
    end
    -- If active on a branch, prompt/close
    if state.state.active then
        local reviewed, total = state.get_counts()
        if reviewed > 0 then
            -- prompt for confirmation...
        end
        M.close()
    end
    start_review("HEAD", "local")
end
```

2. Update `start_review()` to accept mode parameter and pass to `state.init()`

3. Register `:ReviewLocal` command in `M.setup()`

### autocmds.lua

1. Update BufWritePost handler to handle untracked files:
```lua
-- Check if file is tracked by git
local is_tracked_cmd = string.format(
    "git ls-files --error-unmatch %s 2>/dev/null",
    vim.fn.shellescape(filepath)
)
vim.fn.system(is_tracked_cmd)
local is_tracked = vim.v.shell_error == 0

if not is_tracked then
    -- Untracked file: always has changes (it's new)
    -- Just mark unreviewed if it was reviewed
    if state.state.files[filepath] and state.state.files[filepath].reviewed then
        state.mark_unreviewed(filepath)
        filelist.render()
    end
    return
end

-- Existing logic for tracked files...
```

## Files Changed

- `lua/code-review/state.lua` - Untracked file support, mode field, diff hash fallback
- `lua/code-review/init.lua` - `:ReviewLocal` command and `start_local()`
- `lua/code-review/autocmds.lua` - Handle untracked files in BufWritePost
- `lua/code-review/ui.lua` - Update help text

## Notes

- `md5sum` of empty string is `d41d8cd98f00b204e9800998ecf8427e`
- For `:ReviewLocal`, gitsigns base is `HEAD` so gutter signs show uncommitted changes
- Persistence saves `mode: "local"` with `branch: "HEAD"`
- When an untracked file gets committed during a local review, it disappears from both `git diff HEAD` and `git ls-files --others` on next refresh -- correct behavior
- The `open_file()` function in `ui.lua` checks `vim.fn.filereadable()` so untracked files will open fine
