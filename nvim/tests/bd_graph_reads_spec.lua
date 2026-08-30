local bd = require("chaplet.bd")
local config = require("chaplet.config")

local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = vim.fn.fnamemodify(source, ":h")
local fake_bd = vim.fn.fnamemodify(test_dir .. "/../../test/fake-bd", ":p")

local function expected_argv(args)
  local argv = { fake_bd, "-C", bd.root() }
  vim.list_extend(argv, args)
  return argv
end

describe("chaplet.bd graph reads", function()
  before_each(function()
    config.setup({ bd_program = fake_bd })
    bd._last_argv = nil
  end)

  it("reads DOT for a specific bead without parsing it", function()
    local dot = bd.graph_dot({ id = "bd-42" })

    assert.same(expected_argv({ "graph", "--dot", "bd-42" }), bd._last_argv)
    assert.equals('digraph G { "bd-42"; }\n', dot)
  end)

  it("reads all DOT from list when closed beads are requested", function()
    local dot = bd.graph_dot({ closed = true })

    assert.same(expected_argv({ "list", "--format", "dot", "--all" }), bd._last_argv)
    assert.matches('"bd%-closed"', dot)
  end)

  it("reads the default open graph DOT", function()
    local dot = bd.graph_dot()

    assert.same(expected_argv({ "graph", "--dot", "--all" }), bd._last_argv)
    assert.equals('digraph G { "bd-1" -> "bd-2"; }\n', dot)
  end)

  it("returns nil when DOT reads fail", function()
    config.setup({ bd_program = vim.fn.tempname() .. "/missing-bd" })

    assert.is_nil(bd.graph_dot())
  end)

  it("delegates graph data to normalized list reads", function()
    local beads = bd.graph_data({ status = "open" })

    assert.same(expected_argv({ "list", "--json", "--status=open" }), bd._last_argv)
    assert.same({ "bd-1" }, beads[2].dependencies)
    assert.equals("bd-1", beads[1].id)
  end)
end)
