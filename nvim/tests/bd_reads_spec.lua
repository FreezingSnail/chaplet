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

describe("chaplet.bd JSON reads", function()
  before_each(function()
    config.setup({ bd_program = fake_bd })
    bd._last_argv = nil
  end)

  it("lists normalized beads and preserves command/filter argv", function()
    local beads = bd.list({ status = "open" })

    assert.same(expected_argv({ "list", "--json", "--status=open" }), bd._last_argv)
    assert.equals(2, #beads)
    assert.equals("bd-1", beads[1].id)
    assert.is_nil(beads[1].dependencies)
    assert.same({ "bd-1" }, beads[2].dependencies)
  end)

  it("queries normalized beads", function()
    local beads = bd.query("status=deferred")

    assert.same(expected_argv({ "query", "--json", "status=deferred" }), bd._last_argv)
    assert.equals(1, #beads)
    assert.equals("bd-2", beads[1].id)
    assert.same({ "staged" }, beads[1].labels)
  end)

  it("shows the first normalized bead with the long flag order", function()
    local bead = bd.show("bd-1")

    assert.same(expected_argv({ "show", "--json", "--long", "bd-1" }), bd._last_argv)
    assert.equals("bd-1", bead.id)
    assert.equals("acc1", bead.acceptance)
  end)

  it("shows the fake default for unknown ids", function()
    local bead = bd.show("missing")

    assert.same(expected_argv({ "show", "--json", "--long", "missing" }), bd._last_argv)
    assert.equals("bd-1", bead.id)
  end)

  it("rejects a missing show id before spawning", function()
    local ok, err = pcall(bd.show, nil)

    assert.is_false(ok)
    assert.matches("incomplete bd command", err)
    assert.is_nil(bd._last_argv)
  end)

  it("returns raw comment objects with id-before-flag argv", function()
    local comments = bd.comments("bd-1")

    assert.same(expected_argv({ "comments", "bd-1", "--json" }), bd._last_argv)
    assert.equals("alice", comments[1].author)
    assert.equals("nice bead", comments[1].text)
    assert.equals("2026-01-02T00:00:00Z", comments[1].created_at)
  end)

  it("returns nil for every read on a nonzero exit", function()
    config.setup({ bd_program = vim.fn.tempname() .. "/missing-bd" })

    assert.is_nil(bd.list())
    assert.is_nil(bd.query("status=open"))
    assert.is_nil(bd.show("bd-1"))
    assert.is_nil(bd.comments("bd-1"))
  end)
end)
