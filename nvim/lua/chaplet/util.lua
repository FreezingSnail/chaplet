local M = {}

function M.width(value)
  return vim.fn.strdisplaywidth(value)
end

function M.truncate(value, max_width)
  local result = {}
  local used_width = 0
  local character_count = vim.str_utfindex(value)

  for character_index = 0, character_count - 1 do
    local character = vim.fn.strcharpart(value, character_index, 1)
    local character_width = M.width(character)
    if used_width + character_width > max_width then
      break
    end
    result[#result + 1] = character
    used_width = used_width + character_width
  end

  return table.concat(result)
end

function M.pad(value, target_width)
  local padding = target_width - M.width(value)
  if padding <= 0 then
    return value
  end
  return value .. string.rep(" ", padding)
end

function M.cell(value, target_width)
  value = value or ""
  return M.pad(M.truncate(value, target_width), target_width)
end

--- Return a Chaplet-owned scratch buffer identified by a persistent buffer marker.
function M.scratch_buffer(name, marker)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr][marker] then
      return bufnr
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.b[bufnr][marker] = true
  return bufnr
end

function M.deep_equal(left, right)
  if left == right then
    return true
  end
  if type(left) ~= "table" or type(right) ~= "table" then
    return false
  end

  for key, value in pairs(left) do
    if not M.deep_equal(value, right[key]) then
      return false
    end
  end
  for key, value in pairs(right) do
    if not M.deep_equal(value, left[key]) then
      return false
    end
  end

  return true
end

--- Restore the buffer hidden by a scratch view, or close only if safe.
function M.restore_previous_buffer_or_close(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local previous = vim.b[bufnr].chaplet_previous_buffer
  if previous ~= nil and previous ~= bufnr and vim.api.nvim_buf_is_valid(previous) then
    local ok = pcall(vim.api.nvim_set_current_buf, previous)
    if ok then
      return true
    end
  end

  local windows = vim.api.nvim_list_wins()
  if #windows <= 1 then
    return false
  end
  return pcall(vim.api.nvim_win_close, vim.api.nvim_get_current_win(), false)
end

return M
