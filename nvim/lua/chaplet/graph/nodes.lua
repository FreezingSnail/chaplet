local util = require("chaplet.util")
local bd = require("chaplet.bd")
local config = require("chaplet.config")

local M = {}

M.TITLE_MAX = config.get("graph.title_max") or 28

--- Truncate TITLE to MAX display cells, preserving whole UTF-8 characters.
function M.truncate(title, max)
  if util.width(title) <= max then
    return title
  end
  return util.truncate(title, max - 1) .. "…"
end

local function is_staged(bead)
  if bead.status ~= "deferred" then
    return false
  end
  for _, label in ipairs(bead.labels or {}) do
    if label == bd.STAGED_LABEL then
      return true
    end
  end
  return false
end

--- Convert a normalized bead into the stable graph node shape.
function M.node(bead)
  return {
    id = bead.id,
    title = M.truncate(bead.title or "", M.TITLE_MAX),
    state = bead.status,
    staged = is_staged(bead),
    type = bead.issue_type,
    priority = bead.priority,
    deps = bead.dependencies or {},
  }
end

--- Convert normalized beads without changing their input order.
function M.from_beads(beads)
  local nodes = {}
  for _, bead in ipairs(beads or {}) do
    nodes[#nodes + 1] = M.node(bead)
  end
  return nodes
end

--- Return a ghost node representing an unavailable dependency.
function M.ghost(id)
  return {
    id = id,
    title = M.truncate(id .. " (closed)", M.TITLE_MAX),
    state = "closed",
    type = nil,
    priority = nil,
    deps = {},
    ghost = true,
  }
end

--- Append one ghost for each dependency absent from the real node list.
function M.add_ghosts(list)
  local result = {}
  local known = {}
  local seen = {}

  for _, item in ipairs(list or {}) do
    result[#result + 1] = item
    known[item.id] = true
  end

  for _, item in ipairs(list or {}) do
    for _, dependency in ipairs(item.deps or {}) do
      if not known[dependency] and not seen[dependency] then
        seen[dependency] = true
        result[#result + 1] = M.ghost(dependency)
      end
    end
  end

  return result
end

return M
