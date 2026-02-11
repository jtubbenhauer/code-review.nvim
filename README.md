I am now a full-time code reviewer and needed a tool to help me wade through the mountains of slop before me. I wrote none of this code, nor the description below.

---

<img width="1388" height="981" alt="image" src="https://github.com/user-attachments/assets/1661442a-d998-4337-9132-bfdc17a75681" />

# code-review.nvim

A Neovim plugin for reviewing code changes with a persistent file tree and gitsigns integration.

## Features

- **Persistent file list** - Shows changed files in a sidebar, persisted across sessions
- **Review tracking** - Mark files as reviewed, with state saved to `.git/code-review-state.json`
- **Gitsigns integration** - Automatically sets gitsigns diff base to your target branch
- **Auto-unreview** - Files automatically marked unreviewed when saved
- **Devicons support** - File icons from nvim-web-devicons
- **Unified diff view** - Optional inline diff display via [unified.nvim](https://github.com/axkirillov/unified.nvim)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jtubbenhauer/code-review.nvim",
  dependencies = {
    "lewis6991/gitsigns.nvim", -- optional but recommended
    "nvim-tree/nvim-web-devicons", -- optional
    { "axkirillov/unified.nvim", opts = {} }, -- optional, for inline diff view
  },
  keys = {
    { "<leader>cr", "<cmd>Review<cr>", desc = "Start code review" },
    { "<leader>crc", "<cmd>ReviewClose<cr>", desc = "Close code review" },
    { "<leader>crr", "<cmd>ReviewRefresh<cr>", desc = "Refresh code review" },
    {
      "<leader>crn",
      function()
        require("code-review").mark_and_next()
      end,
      desc = "Mark reviewed & next",
    },
    {
      "<leader>crm",
      function()
        require("code-review").toggle_reviewed()
      end,
      desc = "Toggle reviewed",
    },
    {
      "<leader>cru",
      function()
        require("code-review").next_unreviewed()
      end,
      desc = "Next unreviewed",
    },
    {
      "<leader>crd",
      function()
        require("code-review").toggle_unified_diff()
      end,
      desc = "Toggle unified diff",
    },
  },
  opts = {},
}
```

## Usage

### Commands

- `:Review [branch]` - Start a review session against branch (default: `origin/HEAD`)
- `:ReviewClose` - Close the review session
- `:ReviewRefresh` - Refresh the file list from git

### Global Keymaps

| Key           | Action                    |
| ------------- | ------------------------- |
| `<leader>cr`  | Start code review         |
| `<leader>crc` | Close code review         |
| `<leader>crr` | Refresh file list         |
| `<leader>crn` | Mark reviewed & open next |
| `<leader>crm` | Toggle reviewed state     |
| `<leader>cru` | Jump to next unreviewed   |
| `<leader>crd` | Toggle unified diff view  |

### File List Keymaps

| Key          | Action                  |
| ------------ | ----------------------- |
| `<CR>` / `o` | Open file               |
| `r`          | Toggle reviewed         |
| `R`          | Refresh file list       |
| `q`          | Close review            |
| `]u`         | Jump to next unreviewed |
| `[u`         | Jump to prev unreviewed |
| `<C-n>`      | Open next unreviewed    |
| `g?`         | Show help               |

### API

```lua
local cr = require("code-review")

cr.start("origin/main")      -- Start review against branch
cr.close()                   -- Close review session
cr.refresh()                 -- Refresh file list
cr.mark_reviewed()           -- Mark current file as reviewed
cr.mark_and_next()           -- Mark reviewed and open next unreviewed
cr.next_unreviewed()         -- Jump to next unreviewed file
cr.toggle_reviewed()         -- Toggle reviewed state for current file
cr.toggle_unified_diff()     -- Toggle inline unified diff view
cr.unified_available()       -- Check if unified.nvim is installed
cr.status()                  -- Get {branch, reviewed, total} or nil
```

## Configuration

```lua
require("code-review").setup({
  -- Sidebar width
  width = 50,

  -- Default branch to diff against
  default_branch = "origin/HEAD",

  -- Icons used in the file list
  icons = {
    reviewed = "✓",
    unreviewed = " ",
  },

  -- Keymaps for the file list buffer (set to false to disable)
  keymaps = {
    open = "<CR>",
    open_alt = "o",
    toggle_reviewed = "r",
    refresh = "R",
    close = "q",
    next_unreviewed = "]u",
    prev_unreviewed = "[u",
    open_next_unreviewed = "<C-n>",
    help = "g?",
  },
})
```

## How It Works

1. **Start a review** - Creates a new tab with the file list on the left and file preview on the right
2. **Review files** - Navigate through changed files, mark them as reviewed when done
3. **Persistence** - Review state is saved to `.git/code-review-state.json` so you can continue later
4. **Auto-unreview** - If you save changes to a reviewed file, it's automatically marked unreviewed
5. **Gitsigns diff** - While reviewing, gitsigns shows changes against your target branch

### Unified Diff View

If you have [unified.nvim](https://github.com/axkirillov/unified.nvim) installed, you can toggle an inline diff view with `<leader>crd`. This shows:

- **Deleted lines** as virtual text above the current line
- **Added lines** highlighted with a gutter sign

This provides a more traditional unified diff experience compared to gitsigns' gutter-only approach.

## Acknowledgements

This plugin builds on the work of others:

- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) by Lewis Russell - Git integration and diff highlighting
- [unified.nvim](https://github.com/axkirillov/unified.nvim) by Alexander Kirillov - Inline unified diff display
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) - File icons

## License

MIT
