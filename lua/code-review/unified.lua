-- Integration with unified.nvim for inline diff view
-- https://github.com/axkirillov/unified.nvim
local M = {}

local state = require("code-review.state")

-- Check if unified.nvim is available
function M.available()
	local ok = pcall(require, "unified")
	return ok
end

-- Enable unified diff view for current review session
function M.enable()
	if not M.available() then
		vim.notify("unified.nvim is not installed. Install it for inline diff view.", vim.log.levels.WARN)
		return false
	end

	if not state.state.active then
		vim.notify("No active code review", vim.log.levels.WARN)
		return false
	end

	state.state.unified_enabled = true

	-- Show diff for current buffer
	M.show_current()

	vim.notify("Unified diff view enabled", vim.log.levels.INFO)
	return true
end

-- Disable unified diff view
function M.disable()
	if not M.available() then
		return false
	end

	state.state.unified_enabled = false

	-- Clear unified highlights from current buffer
	local unified = require("unified")
	local command = require("unified.command")
	if command and command.reset then
		-- Reset clears all unified state
		command.reset()
	end

	vim.notify("Unified diff view disabled", vim.log.levels.INFO)
	return true
end

-- Toggle unified diff view
function M.toggle()
	if not state.state.active then
		vim.notify("No active code review", vim.log.levels.WARN)
		return
	end

	if state.state.unified_enabled then
		M.disable()
	else
		M.enable()
	end
end

-- Check if unified diff is currently enabled
function M.is_enabled()
	return state.state.unified_enabled or false
end

-- Show unified diff for current buffer (called when opening files during review)
function M.show_current()
	if not M.available() or not state.state.unified_enabled then
		return false
	end

	if not state.state.active or not state.state.branch then
		return false
	end

	local buf = vim.api.nvim_get_current_buf()
	local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })

	-- Don't show diff in our file list buffer
	if ft == "code_review_list" then
		return false
	end

	-- Use unified's diff module to show diff against our branch
	local ok, diff = pcall(require, "unified.diff")
	if ok and diff.show then
		return diff.show(state.state.branch, buf)
	end

	return false
end

-- Clear unified diff from a specific buffer
function M.clear_buffer(buf)
	if not M.available() then
		return
	end

	local ok, config = pcall(require, "unified.config")
	if ok and config.ns_id then
		vim.api.nvim_buf_clear_namespace(buf, config.ns_id, 0, -1)
		vim.fn.sign_unplace("unified_diff", { buffer = buf })
	end
end

return M
