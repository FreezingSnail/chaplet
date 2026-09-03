local util = require("chaplet.util")
local hl = require("chaplet.hl")
local bd = require("chaplet.bd")

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

local EPIC_CACHE_NIL = {}
local epic_cache = {}

function M.clear_epic_cache()
  epic_cache = {}
end

function M.fetch_epic(id)
  local cached = epic_cache[id]
  if cached == EPIC_CACHE_NIL then
    return nil
  end
  if cached ~= nil then
    return cached
  end

  local bead = bd.show(id)
  epic_cache[id] = bead or EPIC_CACHE_NIL
  return bead
end

function M.group_by_epic(beads, fetch_epic)
  fetch_epic = fetch_epic or M.fetch_epic

  local by_parent = {}
  local epics_in_view = {}
  local orphans = {}

  for _, bead in ipairs(beads or {}) do
    if bead.issue_type == "epic" then
      epics_in_view[bead.id] = bead
      by_parent[bead.id] = by_parent[bead.id] or {}
    elseif bead.parent ~= nil then
      by_parent[bead.parent] = by_parent[bead.parent] or {}
      table.insert(by_parent[bead.parent], bead)
    else
      table.insert(orphans, bead)
    end
  end

  local epic_ids = {}
  for epic_id in pairs(by_parent) do
    table.insert(epic_ids, epic_id)
  end
  table.sort(epic_ids, function(left, right)
    return tostring(left) < tostring(right)
  end)

  local ordered = {}
  for _, epic_id in ipairs(epic_ids) do
    local epic = epics_in_view[epic_id] or fetch_epic(epic_id)
    if epic ~= nil then
      table.insert(ordered, { bead = epic, indent = false })
    end
    for _, child in ipairs(by_parent[epic_id]) do
      table.insert(ordered, { bead = child, indent = true })
    end
  end

  for _, bead in ipairs(orphans) do
    table.insert(ordered, { bead = bead, indent = false })
  end

  return ordered
end

-- Lifecycle entry point arrives with the later list-view implementation.
function M.set_view()
  vim.notify("chaplet: list not available yet", vim.log.levels.WARN)
end

return M
