-- Autocommands for code-review.nvim
local M = {}

local state = require("code-review.state")

local augroup = vim.api.nvim_create_augroup("CodeReview", { clear = true })

-- Set up all autocommands
function M.setup()
	local filelist = require("code-review.filelist")

	-- Auto-unreview on file save, or drop file if no longer changed
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		pattern = "*",
		callback = function(args)
			if not state.state.active then
				return
			end

			local filepath = vim.api.nvim_buf_get_name(args.buf)
			local cwd = vim.fn.getcwd()

			-- Make relative path
			if filepath:sub(1, #cwd) == cwd then
				filepath = filepath:sub(#cwd + 2)
			end

			-- Check if this file is in our review list
			if not state.state.files[filepath] then
				return
			end

			-- Check if the file is tracked by git
			local is_tracked_cmd =
				string.format("git ls-files --error-unmatch %s 2>/dev/null", vim.fn.shellescape(filepath))
			vim.fn.system(is_tracked_cmd)
			local is_tracked = vim.v.shell_error == 0

			if not is_tracked then
				-- Untracked file: it's new, so it always "has changes"
				-- If it was reviewed, mark it unreviewed since it was just saved (content changed)
				if state.state.files[filepath].reviewed then
					state.mark_unreviewed(filepath)
					filelist.render()
				end
				return
			end

			-- Check if file still has changes against the base branch
			local cmd =
				string.format("git diff --quiet %s -- %s 2>/dev/null", state.state.diff_base, vim.fn.shellescape(filepath))
			vim.fn.system(cmd)
			local has_changes = vim.v.shell_error ~= 0

			if not has_changes then
				-- File no longer has changes, remove from list
				state.state.files[filepath] = nil
				state.save()
				filelist.render()

				-- Jump to next unreviewed file (defer to avoid issues mid-save)
				vim.schedule(function()
					local next_file = state.get_first_unreviewed()
					if next_file then
						local ui = require("code-review.ui")
						ui.open_file(next_file)
						-- Also update cursor in file list
						local files = state.get_file_list()
						for i, file in ipairs(files) do
							if
								file.path == next_file
								and state.state.list_win
								and vim.api.nvim_win_is_valid(state.state.list_win)
							then
								vim.api.nvim_win_set_cursor(state.state.list_win, { i, 0 })
								break
							end
						end
					end
				end)
			elseif state.state.files[filepath].reviewed then
				-- File still has changes but was reviewed, mark unreviewed
				state.mark_unreviewed(filepath)
				filelist.render()
			end
		end,
	})

	-- Highlight current file in list when entering a buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		pattern = "*",
		callback = function()
			if not state.state.active then
				return
			end

			-- Defer to avoid issues during buffer switching
			vim.defer_fn(function()
				local ui = require("code-review.ui")
				ui.highlight_current_file()
			end, 10)
		end,
	})

	-- Cleanup when tab is closed
	vim.api.nvim_create_autocmd("TabClosed", {
		group = augroup,
		callback = function()
			if not state.state.active then
				return
			end

			-- Check if our tab still exists
			local ui = require("code-review.ui")
			if not ui.tab_exists() then
				-- Tab was closed externally
				require("code-review").cleanup()
			end
		end,
	})

	-- Auto-refresh on focus gained
	vim.api.nvim_create_autocmd("FocusGained", {
		group = augroup,
		callback = function()
			if not state.state.active then
				return
			end

			-- Defer to avoid issues
			vim.defer_fn(function()
				M.check_and_refresh()
			end, 100)
		end,
	})
end

-- Check if git state changed and refresh if needed
function M.check_and_refresh()
	if not state.state.active or not state.state.branch then
		return
	end

	local current_files = state.get_changed_files(state.state.diff_base)
	if not current_files then
		return
	end

	-- Quick check: has the file count changed?
	local current_count = #current_files
	local stored_count = 0
	for _ in pairs(state.state.files) do
		stored_count = stored_count + 1
	end

	local filelist = require("code-review.filelist")

	if current_count ~= stored_count then
		-- File list changed, refresh
		state.refresh()
		filelist.render()
		vim.notify("Code Review: File list updated", vim.log.levels.INFO)
		return
	end

	-- Check if any files are different
	local current_set = {}
	for _, f in ipairs(current_files) do
		current_set[f] = true
	end

	for filepath in pairs(state.state.files) do
		if not current_set[filepath] then
			-- A file was removed/renamed
			state.refresh()
			filelist.render()
			vim.notify("Code Review: File list updated", vim.log.levels.INFO)
			return
		end
	end
end

-- Clean up autocommands (re-clear the augroup)
function M.cleanup()
	vim.api.nvim_create_augroup("CodeReview", { clear = true })
end

return M
