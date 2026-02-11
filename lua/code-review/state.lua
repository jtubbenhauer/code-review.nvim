-- State management and persistence for code-review.nvim
local M = {}

local config = require("code-review.config")

-- In-memory state
M.state = {
	active = false,
	branch = nil,
	files = {}, -- { [path] = { reviewed = bool } }
	tab_id = nil,
	list_buf = nil,
	list_win = nil,
	file_win = nil,
	git_dir = nil,
	unified_enabled = false, -- Whether unified.nvim inline diff is enabled
}

-- Get the git directory for the current repo
local function get_git_dir()
	local result = vim.fn.systemlist("git rev-parse --git-dir")[1]
	if vim.v.shell_error ~= 0 then
		return nil
	end
	-- Make absolute if relative
	if not result:match("^/") then
		result = vim.fn.getcwd() .. "/" .. result
	end
	return result
end

-- Get persistence file path
local function get_persist_path()
	local git_dir = M.state.git_dir or get_git_dir()
	if not git_dir then
		return nil
	end
	return git_dir .. "/code-review-state.json"
end

-- Load persisted state
function M.load()
	local path = get_persist_path()
	if not path then
		return nil
	end

	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()

	local ok, data = pcall(vim.json.decode, content)
	if not ok or type(data) ~= "table" then
		return nil
	end

	return data
end

-- Save state to persistence file
function M.save()
	local path = get_persist_path()
	if not path then
		return false
	end

	local reviewed = {}
	for filepath, info in pairs(M.state.files) do
		if info.reviewed then
			table.insert(reviewed, filepath)
		end
	end

	local data = {
		branch = M.state.branch,
		reviewed = reviewed,
	}

	local file = io.open(path, "w")
	if not file then
		return false
	end

	file:write(vim.json.encode(data))
	file:close()
	return true
end

-- Get list of changed files from git
function M.get_changed_files(branch)
	branch = branch or config.options.default_branch

	-- Use two-dot syntax to include both committed AND uncommitted changes
	-- (three-dot only shows committed changes between merge-base and HEAD)
	local cmd = string.format("git diff --name-only %s 2>/dev/null", branch)
	local files = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 then
		return nil
	end

	-- Also check for untracked files that might be new
	-- (git diff doesn't show untracked files)
	-- For now, we only show tracked files with changes

	return files
end

-- Initialize state for a new review session
function M.init(branch)
	branch = branch or config.options.default_branch

	M.state.git_dir = get_git_dir()
	if not M.state.git_dir then
		vim.notify("Not in a git repository", vim.log.levels.ERROR)
		return false
	end

	local files = M.get_changed_files(branch)
	if not files or #files == 0 then
		vim.notify("No changed files against " .. branch, vim.log.levels.WARN)
		return false
	end

	-- Load persisted state if same branch
	local persisted = M.load()
	local reviewed_set = {}
	if persisted and persisted.branch == branch and persisted.reviewed then
		for _, path in ipairs(persisted.reviewed) do
			reviewed_set[path] = true
		end
	end

	-- Build files table
	M.state.files = {}
	for _, filepath in ipairs(files) do
		M.state.files[filepath] = {
			reviewed = reviewed_set[filepath] or false,
		}
	end

	M.state.branch = branch
	M.state.active = true

	-- Save immediately to persist branch
	M.save()

	return true
end

-- Toggle reviewed state for a file
function M.toggle_reviewed(filepath)
	if not M.state.files[filepath] then
		return false
	end

	M.state.files[filepath].reviewed = not M.state.files[filepath].reviewed
	M.save()
	return true
end

-- Mark a file as reviewed
function M.mark_reviewed(filepath)
	if not M.state.files[filepath] then
		return false
	end

	if not M.state.files[filepath].reviewed then
		M.state.files[filepath].reviewed = true
		M.save()
		return true
	end
	return false
end

-- Mark a file as unreviewed
function M.mark_unreviewed(filepath)
	if not M.state.files[filepath] then
		return false
	end

	if M.state.files[filepath].reviewed then
		M.state.files[filepath].reviewed = false
		M.save()
		return true
	end
	return false
end

-- Get sorted list of files
function M.get_file_list()
	local list = {}
	for filepath, info in pairs(M.state.files) do
		table.insert(list, {
			path = filepath,
			reviewed = info.reviewed,
		})
	end

	-- Sort: unreviewed first, then alphabetically within each group
	table.sort(list, function(a, b)
		if a.reviewed ~= b.reviewed then
			return not a.reviewed
		end
		return a.path < b.path
	end)

	return list
end

-- Get counts
function M.get_counts()
	local total = 0
	local reviewed = 0
	for _, info in pairs(M.state.files) do
		total = total + 1
		if info.reviewed then
			reviewed = reviewed + 1
		end
	end
	return reviewed, total
end

-- Get first unreviewed file
function M.get_first_unreviewed()
	local files = M.get_file_list()
	for _, file in ipairs(files) do
		if not file.reviewed then
			return file.path
		end
	end
	return nil
end

-- Refresh file list from git (preserving reviewed state)
function M.refresh()
	if not M.state.active or not M.state.branch then
		return false
	end

	local files = M.get_changed_files(M.state.branch)
	if not files then
		return false
	end

	-- Build new files table, preserving reviewed state
	local old_files = M.state.files
	M.state.files = {}

	for _, filepath in ipairs(files) do
		local was_reviewed = old_files[filepath] and old_files[filepath].reviewed or false
		M.state.files[filepath] = {
			reviewed = was_reviewed,
		}
	end

	M.save()
	return true
end

-- Reset state
function M.reset()
	M.state = {
		active = false,
		branch = nil,
		files = {},
		tab_id = nil,
		list_buf = nil,
		list_win = nil,
		file_win = nil,
		git_dir = nil,
		unified_enabled = false,
	}
end

-- Get relative path of current buffer
function M.get_current_file_relative()
	local current_file = vim.api.nvim_buf_get_name(0)
	local cwd = vim.fn.getcwd()

	-- Make relative
	if current_file:sub(1, #cwd) == cwd then
		return current_file:sub(#cwd + 2)
	end
	return current_file
end

return M
