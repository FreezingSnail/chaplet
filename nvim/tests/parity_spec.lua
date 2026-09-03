local config = require("chaplet.config")
local bd = require("chaplet.bd")
local actions = require("chaplet.actions")
local nodes = require("chaplet.graph.nodes")
local text = require("chaplet.graph.text")

local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = vim.fn.fnamemodify(source, ":h")
local root = vim.fn.fnamemodify(test_dir .. "/../..", ":p")
local parity = root .. "/test/parity/"

local function read_json(relative)
  local path = parity .. relative
  local file = assert(io.open(path, "rb"), "missing parity file: " .. path)
  local value = vim.json.decode(file:read("*a"))
  file:close()
  return value
end

local function read_text(relative)
  local path = parity .. relative
  local file = assert(io.open(path, "rb"), "missing parity file: " .. path)
  local value = file:read("*a")
  file:close()
  return value
end

local manifest = read_json("cases.json")

describe("chaplet parity manifest", function()
  for _, case in ipairs(manifest) do
    it(case.name .. " is covered", function()
      local fixture = read_json(case.fixture)
      assert.is_not_nil(case.kind)
      assert.is_not_nil(case.goldens)

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

        assert.same(read_json(case.goldens.layers), layers)
        assert.same(read_json(case.goldens.rows), rows)
        assert.same(read_json(case.goldens.order), order)
        assert.equals(read_text(case.goldens.gutter), text.gutter(graph, edges))
      elseif case.kind == "normalize" then
        local normalized = {}
        for _, bead in ipairs(fixture.beads) do
          normalized[#normalized + 1] = bd._normalize(bead)
        end
        assert.same(read_json(case.goldens.normalize), normalized)
      elseif case.kind == "filters" then
        local golden = read_json(case.goldens.filters)
        assert.same(golden.views, bd.views)
        for index, item in ipairs(fixture.args) do
          assert.same(golden.args[index].expect, bd.filters_to_args(item.filters))
        end
        for index, item in ipairs(fixture.expr) do
          assert.equals(golden.expr[index].expect, bd.filters_to_expr(item.filters))
        end
      elseif case.kind == "actions" then
        local golden = read_json(case.goldens.actions)
        for index, item in ipairs(fixture.cases) do
          assert.same(golden[index].actions,
            actions.for_state(item.state, item.staged, item.human))
        end
      else
        error("unknown parity case kind: " .. tostring(case.kind))
      end
    end)
  end
end)
