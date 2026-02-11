-- code-review.nvim - Main module and public API
-- Review code changes with a persistent file tree and gitsigns integration
local M = {}

local config = require("code-review.config")
local state = require("code-review.state")
local ui = require("code-review.ui")
local autocmds = require("code-review.autocmds")

-- Start or switch to a review session
---@param branch? string Branch to diff against (default: config.default_branch)
function M.start(branch)
	branch = branch or config.options.default_branch

	-- If already active with same branch, just switch to tab
	if state.state.active and state.state.branch == branch then
		if ui.switch_to_tab() then
			return
		end
		-- Tab was closed, recreate
	end

	-- If active with different branch, close first
	if state.state.active then
		M.close()
	end

	-- Initialize state
	if not state.init(branch) then
		return
	end

	-- Set up gitsigns to diff against target branch
	local ok, gitsigns = pcall(require, "gitsigns")
	if ok then
		gitsigns.change_base(branch, true)
	end

	-- Set up autocmds
	autocmds.setup()

	-- Create the UI
	ui.create_layout()

	local reviewed, total = state.get_counts()
	vim.notify(
		string.format(
			"Code Review: %d files to review against %s (%d already reviewed)",
			total - reviewed,
			branch,
			reviewed
		),
		vim.log.levels.INFO
	)
end

-- Close the review session
function M.close()
	if not state.state.active then
		return
	end

	-- Disable unified diff if enabled
	if state.state.unified_enabled then
		local unified = require("code-review.unified")
		unified.disable()
	end

	-- Reset gitsigns base
	local ok, gitsigns = pcall(require, "gitsigns")
	if ok then
		gitsigns.reset_base(true)
	end

	-- Close UI
	ui.close()

	-- Reset state (state is already persisted)
	state.reset()

	vim.notify("Code Review closed", vim.log.levels.INFO)
end

-- Cleanup (called when tab is closed externally)
function M.cleanup()
	if not state.state.active then
		return
	end

	-- Reset gitsigns base
	local ok, gitsigns = pcall(require, "gitsigns")
	if ok then
		gitsigns.reset_base(true)
	end

	-- Reset state
	state.reset()
end

-- Refresh the file list
function M.refresh()
	if not state.state.active then
		vim.notify("No active code review", vim.log.levels.WARN)
		return
	end

	local filelist = require("code-review.filelist")
	if state.refresh() then
		filelist.render()
		local reviewed, total = state.get_counts()
		vim.notify(string.format("Code Review refreshed: %d/%d reviewed", reviewed, total), vim.log.levels.INFO)
	end
end

-- Mark current file as reviewed
function M.mark_reviewed()
	if not state.state.active then
		return false
	end

	local filepath = state.get_current_file_relative()
	if state.mark_reviewed(filepath) then
		local filelist = require("code-review.filelist")
		filelist.render()
		return true
	end
	return false
end

-- Mark current file as reviewed and open next unreviewed file
function M.mark_and_next()
	if not state.state.active then
		return
	end

	local filepath = state.get_current_file_relative()
	state.mark_reviewed(filepath)

	local filelist = require("code-review.filelist")
	filelist.render()

	-- Get next unreviewed file
	local next_file = state.get_first_unreviewed()
	if next_file then
		ui.open_file(next_file)
		-- Update cursor in list
		local files = state.get_file_list()
		for i, file in ipairs(files) do
			if file.path == next_file and state.state.list_win and vim.api.nvim_win_is_valid(state.state.list_win) then
				vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
				break
			end
		end
	else
		local reviewed, total = state.get_counts()
		vim.notify(string.format("All %d files reviewed!", total), vim.log.levels.INFO)
	end
end

-- Jump to next unreviewed file (without marking current as reviewed)
function M.next_unreviewed()
	if not state.state.active then
		return
	end

	local next_file = state.get_first_unreviewed()
	if next_file then
		ui.open_file(next_file)
		-- Update cursor in list
		local files = state.get_file_list()
		for i, file in ipairs(files) do
			if file.path == next_file and state.state.list_win and vim.api.nvim_win_is_valid(state.state.list_win) then
				vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
				break
			end
		end
	else
		vim.notify("No unreviewed files", vim.log.levels.INFO)
	end
end

-- Toggle reviewed state for current file
function M.toggle_reviewed()
	if not state.state.active then
		return false
	end

	local filepath = state.get_current_file_relative()
	if state.toggle_reviewed(filepath) then
		local filelist = require("code-review.filelist")
		filelist.render()
		return true
	end
	return false
end

-- Get current review status
---@return {branch: string, reviewed: number, total: number}|nil
function M.status()
	if not state.state.active then
		return nil
	end

	local reviewed, total = state.get_counts()
	return {
		branch = state.state.branch,
		reviewed = reviewed,
		total = total,
	}
end

-- Toggle unified diff view (requires unified.nvim)
function M.toggle_unified_diff()
	local unified = require("code-review.unified")
	unified.toggle()
end

-- Check if unified diff view is available
function M.unified_available()
	local unified = require("code-review.unified")
	return unified.available()
end

-- Setup function - call from lazy.nvim config
---@param opts? table Configuration options
function M.setup(opts)
	config.setup(opts)

	-- Create user commands
	vim.api.nvim_create_user_command("Review", function(cmd_opts)
		local branch = cmd_opts.args ~= "" and cmd_opts.args or nil
		M.start(branch)
	end, {
		nargs = "?",
		desc = "Start code review against branch",
		complete = function()
			-- Complete with branch names
			local branches = vim.fn.systemlist("git branch -a --format='%(refname:short)'")
			return branches
		end,
	})

	vim.api.nvim_create_user_command("ReviewClose", function()
		M.close()
	end, {
		desc = "Close code review session",
	})

	vim.api.nvim_create_user_command("ReviewRefresh", function()
		M.refresh()
	end, {
		desc = "Refresh code review file list",
	})
end

return M
