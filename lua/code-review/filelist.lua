-- File list rendering for code-review.nvim
local M = {}

local state = require("code-review.state")
local config = require("code-review.config")

-- Try to load devicons
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

-- Namespace for highlights
local ns = vim.api.nvim_create_namespace("code_review_list")

-- Map git status letters to highlight groups
local status_hl_map = {
	M = "DiffChanged", -- modified
	A = "DiffAdded", -- added
	D = "DiffRemoved", -- deleted
	R = "DiffChanged", -- renamed
	C = "DiffAdded", -- copied
	T = "DiffChanged", -- type changed
	U = "DiagnosticError", -- unmerged
	["?"] = "DiffAdded", -- untracked
}

-- Get icon for a file
local function get_icon(filepath)
	if not has_devicons then
		return "", nil
	end

	local filename = vim.fn.fnamemodify(filepath, ":t")
	local ext = vim.fn.fnamemodify(filepath, ":e")
	local icon, hl = devicons.get_icon(filename, ext, { default = true })
	return icon or "", hl
end

-- Get just the filename from a path
local function get_filename(filepath)
	return vim.fn.fnamemodify(filepath, ":t")
end

-- Render the file list
function M.render()
	local buf = state.state.list_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local icons = config.options.icons
	local status_icons = config.options.status_icons
	local files = state.get_file_list()
	local lines = {}
	local highlights = {}

	for i, file in ipairs(files) do
		local icon, icon_hl = get_icon(file.path)
		local check = file.reviewed and (icons.reviewed .. " ") or (icons.unreviewed .. " ")
		local git_status = file.git_status or "M"
		local status_char = (status_icons and status_icons[git_status]) or git_status
		local display_name = get_filename(file.path)
		local line = check .. status_char .. " " .. icon .. " " .. display_name

		table.insert(lines, line)

		-- Store highlight info
		local status_start = #check
		local status_end = status_start + #status_char
		table.insert(highlights, {
			line = i - 1, -- 0-indexed
			reviewed = file.reviewed,
			icon_hl = icon_hl,
			icon_start = status_end + 1,
			icon_end = status_end + 1 + #icon,
			path_start = status_end + 1 + #icon + 1,
			status_start = status_start,
			status_end = status_end,
			status_hl = status_hl_map[git_status] or "Comment",
		})
	end

	-- Make buffer modifiable temporarily
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	-- Set lines
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		-- Checkmark highlight
		if hl.reviewed then
			vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticOk", hl.line, 0, 1)
		end

		-- Git status highlight
		vim.api.nvim_buf_add_highlight(buf, ns, hl.status_hl, hl.line, hl.status_start, hl.status_end)

		-- Icon highlight
		if hl.icon_hl then
			vim.api.nvim_buf_add_highlight(buf, ns, hl.icon_hl, hl.line, hl.icon_start, hl.icon_end)
		end

		-- Path highlight - dim if reviewed
		if hl.reviewed then
			vim.api.nvim_buf_add_highlight(buf, ns, "Comment", hl.line, hl.path_start, -1)
		end
	end

	-- Make buffer non-modifiable again
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	-- Update window title / buffer name with counts
	local reviewed, total = state.get_counts()
	local title = string.format("Code Review [%d/%d]", reviewed, total)
	vim.api.nvim_buf_set_name(buf, title)
end

return M
