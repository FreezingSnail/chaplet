local config = require("chaplet.config")
local hl = require("chaplet.hl")
local util = require("chaplet.util")

local M = {}

M.TITLE_MAX = config.get("graph.text_title_max") or 20
M.FOCUS_PREFIX = "▶"
M.GHOST_SUFFIX = " ~"

--- Truncate TITLE to the configured display width, preserving UTF-8 characters.
function M.truncate(title)
  title = title or ""
  if util.width(title) <= M.TITLE_MAX then
    return title
  end
  return util.truncate(title, M.TITLE_MAX - 1) .. "…"
end

--- Build a node line and zero-based, end-exclusive byte spans for extmarks.
function M.node_line(node, focus)
  node = node or {}
  local id = node.id or ""
  local title = M.truncate(node.title)
  local state = node.state
  local state_group = hl.state_group(state)
  if node.staged and state_group then
    state_group = "ChapletStaged"
  end

  local parts = {}
  local spans = {}
  local offset = 0
  local function append(value)
    parts[#parts + 1] = value
    offset = offset + #value
  end

  append(node.id and node.id == focus and M.FOCUS_PREFIX or " ")
  append("[")
  local id_start = offset
  append(id)
  local id_end = offset
  append("] ")
  if id_end > id_start then
    spans[#spans + 1] = { group = "ChapletId", start_col = id_start, end_col = id_end }
  end
  append(title)

  if state_group then
    append(" ")
    local state_start = offset
    append(state)
    spans[#spans + 1] = {
      group = state_group,
      start_col = state_start,
      end_col = offset,
    }
  end

  if node.ghost then
    append(M.GHOST_SUFFIX)
  end

  return table.concat(parts), spans
end

return M
