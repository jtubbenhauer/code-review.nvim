-- UI management for code-review.nvim - tab and window layout
local M = {}

local state = require("code-review.state")
local config = require("code-review.config")

-- Help text for the file list (generated dynamically from config)
local function get_help_lines()
	local km = config.options.keymaps
	local lines = {
		"Code Review Help",
		"════════════════════════════",
		"",
		"File List Keymaps",
		"─────────────────",
		(km.open or "<CR>") .. "/" .. (km.open_alt or "o") .. "      Open file",
		(km.toggle_reviewed or "r") .. "           Toggle reviewed",
		(km.refresh or "R") .. "           Refresh file list",
		(km.close or "q") .. "           Close review",
		(km.next_unreviewed or "]u") .. "          Next unreviewed",
		(km.prev_unreviewed or "[u") .. "          Prev unreviewed",
		(km.open_next_unreviewed or "<C-n>") .. "       Open next unreviewed",
		(km.help or "g?") .. "          Show this help",
		"",
		"Global Keymaps",
		"──────────────",
		"<leader>cr     Start review",
		"<leader>crc    Close review",
		"<leader>crr    Refresh",
		"<leader>crn    Mark reviewed & next",
		"<leader>crm    Toggle reviewed",
		"<leader>cru    Next unreviewed",
	}

	-- Add unified diff info if available
	local unified = require("code-review.unified")
	if unified.available() then
		table.insert(lines, "<leader>crd    Toggle unified diff")
		table.insert(lines, "")
		table.insert(lines, "Unified diff: " .. (state.state.unified_enabled and "ON" or "OFF"))
	end

	table.insert(lines, "")
	table.insert(lines, "Press any key to close")

	return lines
end

-- Show help popup
function M.show_help()
	local help_lines = get_help_lines()
	local width = 28
	local height = #help_lines

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	-- Calculate position (center of screen)
	local ui_info = vim.api.nvim_list_uis()[1]
	local row = math.floor((ui_info.height - height) / 2)
	local col = math.floor((ui_info.width - width) / 2)

	-- Create floating window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Help ",
		title_pos = "center",
	})

	-- Highlight the title
	vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, -1, "Comment", 1, 0, -1)

	-- Close on Escape
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, nowait = true })

	-- Close on q
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, nowait = true })

	-- Close on BufLeave
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		once = true,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
	})
end

-- Check if review tab still exists
function M.tab_exists()
	if not state.state.tab_id then
		return false
	end
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		if tab == state.state.tab_id then
			return true
		end
	end
	return false
end

-- Switch to review tab
function M.switch_to_tab()
	if M.tab_exists() then
		vim.api.nvim_set_current_tabpage(state.state.tab_id)
		return true
	end
	return false
end

-- Create the file list buffer
local function create_list_buffer()
	local buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "code_review_list", { buf = buf })
	vim.api.nvim_buf_set_name(buf, "Code Review")

	return buf
end

-- Set up keymaps for the file list buffer
local function setup_list_keymaps(buf)
	local opts = { buffer = buf, silent = true }
	local km = config.options.keymaps

	-- Open file under cursor
	if km.open then
		vim.keymap.set("n", km.open, function()
			M.open_file_under_cursor()
		end, opts)
	end
	if km.open_alt then
		vim.keymap.set("n", km.open_alt, function()
			M.open_file_under_cursor()
		end, opts)
	end

	-- Toggle reviewed
	if km.toggle_reviewed then
		vim.keymap.set("n", km.toggle_reviewed, function()
			M.toggle_reviewed_under_cursor()
		end, opts)
	end

	-- Refresh
	if km.refresh then
		vim.keymap.set("n", km.refresh, function()
			require("code-review").refresh()
		end, opts)
	end

	-- Close
	if km.close then
		vim.keymap.set("n", km.close, function()
			require("code-review").close()
		end, opts)
	end

	-- Navigation - next/prev unreviewed
	if km.next_unreviewed then
		vim.keymap.set("n", km.next_unreviewed, function()
			M.jump_to_unreviewed("next")
		end, opts)
	end
	if km.prev_unreviewed then
		vim.keymap.set("n", km.prev_unreviewed, function()
			M.jump_to_unreviewed("prev")
		end, opts)
	end

	-- Open next unreviewed
	if km.open_next_unreviewed then
		vim.keymap.set("n", km.open_next_unreviewed, function()
			M.open_next_unreviewed()
		end, opts)
	end

	-- Help
	if km.help then
		vim.keymap.set("n", km.help, function()
			M.show_help()
		end, opts)
	end
end

-- Create the review layout in a new tab
function M.create_layout()
	local filelist = require("code-review.filelist")

	-- Create new tab
	vim.cmd("tabnew")
	state.state.tab_id = vim.api.nvim_get_current_tabpage()

	-- Create file list buffer
	state.state.list_buf = create_list_buffer()

	-- Set up the split layout
	-- First, set up the file window (will be on the right)
	state.state.file_win = vim.api.nvim_get_current_win()

	-- Create vertical split for file list on the left
	vim.cmd("topleft vsplit")
	vim.cmd("vertical resize " .. config.options.width)
	state.state.list_win = vim.api.nvim_get_current_win()

	-- Set the list buffer in the list window
	vim.api.nvim_win_set_buf(state.state.list_win, state.state.list_buf)

	-- Configure list window
	vim.api.nvim_set_option_value("winfixwidth", true, { win = state.state.list_win })
	vim.api.nvim_set_option_value("number", false, { win = state.state.list_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = state.state.list_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = state.state.list_win })
	vim.api.nvim_set_option_value("cursorline", true, { win = state.state.list_win })
	vim.api.nvim_set_option_value("wrap", false, { win = state.state.list_win })

	-- Set up keymaps
	setup_list_keymaps(state.state.list_buf)

	-- Render the file list
	filelist.render()

	-- Open first file if any
	local files = state.get_file_list()
	if #files > 0 then
		M.open_file(files[1].path)
	end
end

-- Open a file in the file window
function M.open_file(filepath)
	if not state.state.file_win or not vim.api.nvim_win_is_valid(state.state.file_win) then
		return false
	end

	-- Check if file exists
	local full_path = vim.fn.getcwd() .. "/" .. filepath
	if vim.fn.filereadable(full_path) == 0 then
		vim.notify("File not found: " .. filepath, vim.log.levels.WARN)
		return false
	end

	vim.api.nvim_set_current_win(state.state.file_win)
	vim.cmd("edit " .. vim.fn.fnameescape(full_path))

	-- Show unified diff if enabled
	if state.state.unified_enabled then
		-- Defer to allow buffer to fully load
		vim.defer_fn(function()
			local unified = require("code-review.unified")
			unified.show_current()
		end, 10)
	end

	return true
end

-- Get the file path at the current cursor line
function M.get_file_at_cursor()
	local line = vim.api.nvim_win_get_cursor(state.state.list_win)[1]
	local files = state.get_file_list()
	if line > 0 and line <= #files then
		return files[line].path
	end
	return nil
end

-- Open file under cursor
function M.open_file_under_cursor()
	local filepath = M.get_file_at_cursor()
	if filepath then
		M.open_file(filepath)
	end
end

-- Toggle reviewed state for file under cursor
function M.toggle_reviewed_under_cursor()
	local filelist = require("code-review.filelist")
	local filepath = M.get_file_at_cursor()
	if filepath then
		state.toggle_reviewed(filepath)
		filelist.render()
	end
end

-- Jump to next/prev unreviewed file
function M.jump_to_unreviewed(direction)
	local files = state.get_file_list()
	local current_line = vim.api.nvim_win_get_cursor(state.state.list_win)[1]

	if direction == "next" then
		-- Search forward from current line
		for i = current_line + 1, #files do
			if not files[i].reviewed then
				vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
				return
			end
		end
		-- Wrap around
		for i = 1, current_line - 1 do
			if not files[i].reviewed then
				vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
				return
			end
		end
	else
		-- Search backward from current line
		for i = current_line - 1, 1, -1 do
			if not files[i].reviewed then
				vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
				return
			end
		end
		-- Wrap around
		for i = #files, current_line + 1, -1 do
			if not files[i].reviewed then
				vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
				return
			end
		end
	end

	vim.notify("No unreviewed files", vim.log.levels.INFO)
end

-- Open next unreviewed file
function M.open_next_unreviewed()
	M.jump_to_unreviewed("next")
	M.open_file_under_cursor()
end

-- Close the review UI
function M.close()
	if state.state.tab_id and M.tab_exists() then
		-- Switch to review tab first
		vim.api.nvim_set_current_tabpage(state.state.tab_id)
		-- Close the tab
		vim.cmd("tabclose")
	end

	state.state.tab_id = nil
	state.state.list_buf = nil
	state.state.list_win = nil
	state.state.file_win = nil
end

-- Highlight the current file in the list when buffer changes
function M.highlight_current_file()
	if not state.state.active then
		return
	end
	if not state.state.list_win or not vim.api.nvim_win_is_valid(state.state.list_win) then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()
	local current_file = vim.api.nvim_buf_get_name(current_buf)
	local cwd = vim.fn.getcwd()

	-- Make relative
	if current_file:sub(1, #cwd) == cwd then
		current_file = current_file:sub(#cwd + 2)
	end

	local files = state.get_file_list()
	for i, file in ipairs(files) do
		if file.path == current_file then
			-- Don't move cursor if we're in the list window (user is navigating)
			if vim.api.nvim_get_current_win() ~= state.state.list_win then
				vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
			end
			break
		end
	end
end

return M
