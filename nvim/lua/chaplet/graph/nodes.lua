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

--- Assign each node its longest root-to-node dependency path length.
function M.layers(list)
  local ids = {}
  local known = {}
  local deps_of = {}
  local indegree = {}
  local dependents = {}
  local layers = {}

  for _, item in ipairs(list or {}) do
    local id = item.id
    ids[#ids + 1] = id
    known[id] = true
    deps_of[id] = item.deps or {}
    indegree[id] = 0
    dependents[id] = {}
  end
  table.sort(ids)

  for _, id in ipairs(ids) do
    for _, dependency in ipairs(deps_of[id]) do
      if known[dependency] then
        indegree[id] = indegree[id] + 1
        dependents[dependency][#dependents[dependency] + 1] = id
      end
    end
  end

  local queue = {}
  for _, id in ipairs(ids) do
    if indegree[id] == 0 then
      queue[#queue + 1] = id
    end
  end

  while #queue > 0 do
    local id = table.remove(queue, 1)
    local layer = 0
    for _, dependency in ipairs(deps_of[id]) do
      layer = math.max(layer, (layers[dependency] or 0) + 1)
    end
    layers[id] = layer

    for _, consumer in ipairs(dependents[id]) do
      indegree[consumer] = indegree[consumer] - 1
      if indegree[consumer] == 0 then
        queue[#queue + 1] = consumer
        table.sort(queue)
      end
    end
  end

  for _, id in ipairs(ids) do
    if layers[id] == nil then
      local layer = 0
      for _, dependency in ipairs(deps_of[id]) do
        layer = math.max(layer, (layers[dependency] or 0) + 1)
      end
      layers[id] = layer
    end
  end

  return layers
end

--- Return a copied list sorted by ascending node id.
function M.sort_by_id(list)
  local result = vim.list_extend({}, list or {})
  table.sort(result, function(left, right)
    return left.id < right.id
  end)
  return result
end

--- Group nodes into ascending layer rows, sorting each row by id.
function M.rows(list, layers)
  local buckets = {}
  local layer_keys = {}

  for _, item in ipairs(list or {}) do
    local layer = (layers and layers[item.id]) or 0
    if not buckets[layer] then
      buckets[layer] = {}
      layer_keys[#layer_keys + 1] = layer
    end
    buckets[layer][#buckets[layer] + 1] = item
  end

  table.sort(layer_keys)
  local result = {}
  for _, layer in ipairs(layer_keys) do
    result[#result + 1] = {
      layer = layer,
      nodes = M.sort_by_id(buckets[layer]),
    }
  end
  return result
end

--- Return nodes flattened by ascending layer, then ascending id.
function M.order(list)
  local result = {}
  local layers = M.layers(list or {})
  for _, row in ipairs(M.rows(list, layers)) do
    vim.list_extend(result, row.nodes)
  end
  return result
end

--- Return dependency edges in node and dependency encounter order.
function M.edges(list)
  local result = {}
  for _, item in ipairs(list or {}) do
    for _, dependency in ipairs(item.deps or {}) do
      result[#result + 1] = { from = item.id, to = dependency }
    end
  end
  return result
end

--- Return dependent ids per node, preserving reverse edge encounter order.
function M.dependents(edges, order)
  local result = {}
  for _, item in ipairs(order or {}) do
    result[item.id] = {}
  end
  for _, edge in ipairs(edges or {}) do
    result[edge.to] = result[edge.to] or {}
    table.insert(result[edge.to], 1, edge.from)
  end
  return result
end

--- Convert beads, complete missing dependency ghosts, and return nodes/edges.
function M.graph(beads)
  local list = M.add_ghosts(M.from_beads(beads))
  return list, M.edges(list)
end

return M
