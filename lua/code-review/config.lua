-- Configuration management for code-review.nvim
local M = {}

local defaults = {
	-- Sidebar width
	width = 50,

	-- Default branch to diff against
	default_branch = "origin/HEAD",

	-- Icons used in the file list
	icons = {
		reviewed = "✓",
		unreviewed = " ",
	},

	-- Git status indicators shown next to each file (set to false to hide)
	status_icons = {
		M = "M", -- modified
		A = "A", -- added
		D = "D", -- deleted
		R = "R", -- renamed
		C = "C", -- copied
		T = "T", -- type changed
		U = "U", -- unmerged
		["?"] = "?", -- untracked
	},

	-- Keymaps for the file list buffer
	-- Set to false to disable a keymap
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
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
