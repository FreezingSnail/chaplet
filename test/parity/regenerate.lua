local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(root .. "/nvim")

local config = require("chaplet.config")
local bd = require("chaplet.bd")
local actions = require("chaplet.actions")
local nodes = require("chaplet.graph.nodes")
local text = require("chaplet.graph.text")

local function read_json(path)
  local file = assert(io.open(path, "rb"))
  local value = vim.json.decode(file:read("*a"))
  file:close()
  return value
end

local function write_json(path, value)
  local file = assert(io.open(path, "wb"))
  file:write(vim.json.encode(value))
  file:close()
end

local function write_text(path, value)
  local file = assert(io.open(path, "wb"))
  file:write(value)
  file:close()
end

local manifest = read_json(root .. "/test/parity/cases.json")
for _, case in ipairs(manifest) do
  local fixture = read_json(root .. "/test/parity/" .. case.fixture)
  if case.kind == "graph" then
    config.setup({ graph = case.opts or {} })
    local graph, edges = nodes.graph(fixture.beads)
    local layers = nodes.layers(graph)
    local rows = {}
    for _, row in ipairs(nodes.rows(graph, layers)) do
      local ids = {}
      for _, node in ipairs(row.nodes) do
        ids[#ids + 1] = node.id
      end
      rows[#rows + 1] = { layer = row.layer, ids = ids }
    end
    local order = {}
    for _, node in ipairs(nodes.order(graph)) do
      order[#order + 1] = node.id
    end
    local base = root .. "/test/parity/"
    write_json(base .. case.goldens.layers, layers)
    write_json(base .. case.goldens.rows, rows)
    write_json(base .. case.goldens.order, order)
    write_text(base .. case.goldens.gutter, text.gutter(graph, edges))
  elseif case.kind == "normalize" then
    local normalized = {}
    for _, bead in ipairs(fixture.beads) do
      normalized[#normalized + 1] = bd._normalize(bead)
    end
    write_json(root .. "/test/parity/" .. case.goldens.normalize, normalized)
  elseif case.kind == "filters" then
    local result = { views = bd.views, args = {}, expr = {} }
    for _, item in ipairs(fixture.args) do
      result.args[#result.args + 1] = {
        filters = item.filters,
        expect = bd.filters_to_args(item.filters),
      }
    end
    for _, item in ipairs(fixture.expr) do
      result.expr[#result.expr + 1] = {
        filters = item.filters,
        expect = bd.filters_to_expr(item.filters),
      }
    end
    write_json(root .. "/test/parity/" .. case.goldens.filters, result)
  elseif case.kind == "actions" then
    local result = {}
    for _, item in ipairs(fixture.cases) do
      result[#result + 1] = {
        state = item.state,
        staged = item.staged,
        human = item.human,
        actions = actions.for_state(item.state, item.staged, item.human),
      }
    end
    write_json(root .. "/test/parity/" .. case.goldens.actions, result)
  end
end
