-- code-review.nvim - Main module and public API
-- Review code changes with a persistent file tree and gitsigns integration
local M = {}

local config = require("code-review.config")
local state = require("code-review.state")
local ui = require("code-review.ui")
local autocmds = require("code-review.autocmds")

-- Start or switch to a review session (internal, no confirmation)
---@param branch string Branch to diff against (or "HEAD" for local mode)
---@param mode? string "branch" (default) or "local"
local function start_review(branch, mode)
	mode = mode or "branch"

	-- Initialize state
	if not state.init(branch, mode) then
		return
	end

	local ok, gitsigns = pcall(require, "gitsigns")
	if ok then
		gitsigns.change_base(state.state.diff_base, true)
	end

	-- Set up autocmds
	autocmds.setup()

	-- Create the UI
	ui.create_layout()

	local reviewed, total = state.get_counts()
	local target = mode == "local" and "HEAD (uncommitted changes)" or branch
	vim.notify(
		string.format(
			"Code Review: %d files to review against %s (%d already reviewed)",
			total - reviewed,
			target,
			reviewed
		),
		vim.log.levels.INFO
	)
end

-- Start or switch to a review session
---@param branch? string Branch to diff against (default: config.default_branch)
---@param opts? { force?: boolean } Options (force: skip confirmation)
function M.start(branch, opts)
	branch = branch or config.options.default_branch
	opts = opts or {}

	-- If already active with same branch, just switch to tab
	if state.state.active and state.state.branch == branch then
		if ui.switch_to_tab() then
			return
		end
		-- Tab was closed, recreate UI without reinitializing state
		ui.create_layout()
		return
	end

	-- If active with different branch, check for progress before overwriting
	if state.state.active then
		local reviewed, total = state.get_counts()
		if reviewed > 0 and not opts.force then
			-- Prompt for confirmation
			local msg = string.format(
				"You have %d/%d files reviewed in the current review (%s).\nStart new review against %s? This will lose your progress.",
				reviewed,
				total,
				state.state.branch,
				branch
			)
			vim.ui.select({ "No, keep current review", "Yes, start new review" }, {
				prompt = msg,
			}, function(choice)
				if choice == "Yes, start new review" then
					M.close()
					start_review(branch)
				else
					vim.notify("Review cancelled", vim.log.levels.INFO)
				end
			end)
			return
		end
		M.close()
	end

	start_review(branch)
end

-- Start a local review session (uncommitted changes against HEAD)
function M.start_local()
	-- If already active in local mode, just switch to tab
	if state.state.active and state.state.mode == "local" then
		if ui.switch_to_tab() then
			return
		end
		-- Tab was closed, recreate UI without reinitializing state
		ui.create_layout()
		return
	end

	-- If active with a different review, check for progress before overwriting
	if state.state.active then
		local reviewed, total = state.get_counts()
		if reviewed > 0 then
			local current_target = state.state.mode == "local" and "HEAD" or state.state.branch
			local msg = string.format(
				"You have %d/%d files reviewed in the current review (%s).\nStart local review? This will lose your progress.",
				reviewed,
				total,
				current_target
			)
			vim.ui.select({ "No, keep current review", "Yes, start local review" }, {
				prompt = msg,
			}, function(choice)
				if choice == "Yes, start local review" then
					M.close()
					start_review("HEAD", "local")
				else
					vim.notify("Review cancelled", vim.log.levels.INFO)
				end
			end)
			return
		end
		M.close()
	end

	start_review("HEAD", "local")
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

	-- Determine next file BEFORE marking, so sort order hasn't shifted yet
	local next_file = state.get_next_unreviewed(filepath)

	state.mark_reviewed(filepath)

	local filelist = require("code-review.filelist")
	filelist.render()
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

	local filepath = state.get_current_file_relative()
	local next_file = state.get_next_unreviewed(filepath)
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

	vim.api.nvim_create_user_command("ReviewLocal", function()
		M.start_local()
	end, {
		desc = "Review uncommitted changes against HEAD",
	})

	vim.api.nvim_create_user_command("ReviewRefresh", function()
		M.refresh()
	end, {
		desc = "Refresh code review file list",
	})
end

return M
