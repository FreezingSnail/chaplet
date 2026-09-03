local config = require("chaplet.config")
local hl = require("chaplet.hl")
local graph_nodes = require("chaplet.graph.nodes")
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

M.GLYPHS = {
  open = "│",
  corner = "└",
  bus = "─",
  join = "┐",
}

local function ordered_graph(list, edges)
  local order = graph_nodes.order(list or {})
  local graph_edges = edges or graph_nodes.edges(list or {})
  return order, graph_nodes.dependents(graph_edges, order)
end

local function lane_positions(lanes, deps)
  local positions = {}
  for i = 1, lanes.n do
    local id = lanes[i]
    if id and vim.tbl_contains(deps, id) then
      positions[#positions + 1] = i
    end
  end
  return positions
end

local function free_lane(lanes, id)
  for i = 1, lanes.n do
    if lanes[i] == id then
      lanes[i] = false
      return i
    end
  end
end

local function compact_lanes(lanes)
  while lanes.n > 0 and not lanes[lanes.n] do
    lanes[lanes.n] = nil
    lanes.n = lanes.n - 1
  end
end

local function place_lane(lanes, preferred, id)
  if preferred and not lanes[preferred] then
    lanes[preferred] = id
    return preferred
  end
  for i = 1, lanes.n do
    if not lanes[i] then
      lanes[i] = id
      return i
    end
  end
  lanes.n = lanes.n + 1
  lanes[lanes.n] = id
  return lanes.n
end

local function gutter_pairs(list, edges, focus)
  local order, dependents = ordered_graph(list, edges)
  local open_count = {}
  for _, node in ipairs(order) do
    local id = node.id
    open_count[id] = #(dependents[id] or {})
  end

  local lanes = { n = 0 }
  local pairs = {}
  local cap = config.get("graph.text_lane_max")
  if type(cap) ~= "number" or cap < 0 or cap % 1 ~= 0 then
    cap = nil
  end

  for _, node in ipairs(order) do
    local deps = node.deps or {}
    local positions = lane_positions(lanes, deps)
    local p0 = positions[1]
    local pk = positions[#positions]
    local drawn = cap and math.min(lanes.n, cap) or lanes.n
    local gutter_parts = {}

    for i = 1, drawn do
      local slot = lanes[i]
      if not slot then
        gutter_parts[#gutter_parts + 1] = " "
      elseif not p0 then
        gutter_parts[#gutter_parts + 1] = M.GLYPHS.open
      elseif i < p0 then
        gutter_parts[#gutter_parts + 1] = M.GLYPHS.open
      elseif i == p0 then
        gutter_parts[#gutter_parts + 1] = M.GLYPHS.corner
      elseif i < pk then
        gutter_parts[#gutter_parts + 1] = M.GLYPHS.bus
      elseif i == pk then
        gutter_parts[#gutter_parts + 1] = M.GLYPHS.join
      else
        gutter_parts[#gutter_parts + 1] = M.GLYPHS.open
      end
    end

    local node_text, node_spans = M.node_line(node, focus)
    pairs[#pairs + 1] = {
      gutter = table.concat(gutter_parts),
      text = node_text,
      spans = node_spans,
    }

    -- Free dependencies before placing this node: its leftmost vacated lane
    -- is the preferred slot, preserving the merge shape through diamonds.
    local preferred
    for _, dependency in ipairs(deps) do
      local count = open_count[dependency] or 0
      if count > 0 then
        count = count - 1
        open_count[dependency] = count
        if count == 0 then
          local freed = free_lane(lanes, dependency)
          if not preferred or (freed and freed < preferred) then
            preferred = freed
          end
        end
      end
    end

    if #(dependents[node.id] or {}) > 0 then
      place_lane(lanes, preferred, node.id)
    end
    compact_lanes(lanes)
  end

  return pairs
end

local function rendered_pairs(list, edges, focus)
  local pairs = gutter_pairs(list, edges, focus)
  local widest = 0
  for _, pair in ipairs(pairs) do
    widest = math.max(widest, util.width(pair.gutter))
  end
  local align = config.get("graph.text_align")
  local rendered = {}
  for _, pair in ipairs(pairs) do
    local gutter = pair.gutter
    if align then
      gutter = util.pad(gutter, widest)
    end
    local line = gutter .. " " .. pair.text
    local spans = {}
    local shift = #gutter + 1
    for _, span in ipairs(pair.spans) do
      spans[#spans + 1] = {
        group = span.group,
        start_col = span.start_col + shift,
        end_col = span.end_col + shift,
      }
    end
    rendered[#rendered + 1] = { line = line, spans = spans }
  end
  return rendered
end

--- Render one gutter-tree line per node, joined by newlines.
function M.gutter(nodes, edges, focus)
  local rendered = rendered_pairs(nodes, edges, focus)
  local lines = {}
  for _, pair in ipairs(rendered) do
    lines[#lines + 1] = pair.line
  end
  return table.concat(lines, "\n")
end

--- Render the empty-safe text canvas.
function M.canvas(nodes, edges, focus)
  if not nodes or #nodes == 0 then
    return ""
  end
  return M.gutter(nodes, edges, focus)
end

--- Return rendered lines and extmark spans shifted past each gutter.
function M.lines(nodes, edges, focus)
  local rendered = rendered_pairs(nodes, edges, focus)
  local lines = {}
  local spans = {}
  for _, pair in ipairs(rendered) do
    lines[#lines + 1] = pair.line
    spans[#spans + 1] = pair.spans
  end
  return lines, spans
end

return M
