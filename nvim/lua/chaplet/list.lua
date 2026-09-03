local util = require("chaplet.util")
local hl = require("chaplet.hl")

local M = {}

M.COLUMNS = {
  { name = "ID", width = 12 },
  { name = "Type", width = 10 },
  { name = "State", width = 12 },
  { name = "P", width = 3 },
  { name = "Staged", width = 7 },
  { name = "Title", width = 60 },
}

local HEADER_GROUP = "ChapletHeader"
local ID_GROUP = "ChapletId"
local STAGED_GROUP = "ChapletStaged"

local function string_value(value)
  if value == nil then
    return ""
  end
  return tostring(value)
end

function M.priority_cell(priority)
  if priority == nil then
    return ""
  end

  local numeric = type(priority) == "number" and priority or tonumber(priority)
  local mark = numeric >= 2 and "●" or "·"
  return mark .. tostring(priority)
end

function M.staged(bead)
  if not bead or bead.status ~= "deferred" then
    return false
  end

  for _, label in ipairs(bead.labels or {}) do
    if label == "staged" then
      return true
    end
  end
  return false
end

local function append_cell(parts, spans, value, width, group)
  local cell = util.cell(value, width)
  local start = #table.concat(parts)
  parts[#parts + 1] = cell
  spans[#spans + 1] = { col = start, end_col = start + #cell, hl = group }
end

local function append_separator(parts)
  parts[#parts + 1] = " "
end

function M.header_line()
  local parts = {}
  for index, column in ipairs(M.COLUMNS) do
    parts[#parts + 1] = util.cell(column.name, column.width)
    if index < #M.COLUMNS then
      append_separator(parts)
    end
  end

  local text = table.concat(parts)
  return text, { { col = 0, end_col = #text, hl = HEADER_GROUP } }
end

function M.format_row(bead, indent)
  bead = bead or {}
  local staged = M.staged(bead)
  local cells = {
    string_value(bead.id),
    string_value(bead.issue_type),
    string_value(bead.status),
    M.priority_cell(bead.priority),
    staged and "✔" or "",
    (indent and "  " or "") .. string_value(bead.title),
  }
  local groups = {
    ID_GROUP,
    hl.type_group(bead.issue_type),
    hl.state_group(bead.status),
    hl.priority_group(bead.priority),
    STAGED_GROUP,
    nil,
  }

  local parts = {}
  local spans = {}
  for index, column in ipairs(M.COLUMNS) do
    local cell = util.cell(cells[index], column.width)
    if index <= 5 then
      append_cell(parts, spans, cell, column.width, groups[index])
    else
      parts[#parts + 1] = cell
    end
    if index < #M.COLUMNS then
      append_separator(parts)
    end
  end

  return { text = table.concat(parts), spans = spans }
end

-- Lifecycle entry point arrives with the later list-view implementation.
function M.set_view()
  vim.notify("chaplet: list not available yet", vim.log.levels.WARN)
end

return M
