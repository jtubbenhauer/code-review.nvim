-- File list rendering for code-review.nvim
local M = {}

local state = require("code-review.state")
local config = require("code-review.config")

-- Try to load devicons
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

-- Namespace for highlights
local ns = vim.api.nvim_create_namespace("code_review_list")

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
  local files = state.get_file_list()
  local lines = {}
  local highlights = {}

  for i, file in ipairs(files) do
    local icon, icon_hl = get_icon(file.path)
    local check = file.reviewed and (icons.reviewed .. " ") or (icons.unreviewed .. " ")
    local display_name = get_filename(file.path)
    local line = check .. icon .. " " .. display_name

    table.insert(lines, line)

    -- Store highlight info
    table.insert(highlights, {
      line = i - 1, -- 0-indexed
      reviewed = file.reviewed,
      icon_hl = icon_hl,
      icon_start = #check,
      icon_end = #check + #icon,
      path_start = #check + #icon + 1,
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
