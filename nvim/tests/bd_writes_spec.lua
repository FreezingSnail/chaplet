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

local function assert_write(args, write)
  assert.is_true(write())
  assert.same(expected_argv(args), bd._last_argv)
end

describe("chaplet.bd lifecycle writes", function()
  before_each(function()
    config.setup({ bd_program = fake_bd })
    bd._last_argv = nil
  end)

  it("creates and returns the trimmed bead id", function()
    local id = bd.create("New bead", "task", "Description")

    assert.equals("bd-99", id)
    assert.same(expected_argv({ "create", "New bead", "-t", "task", "-d", "Description", "--silent" }), bd._last_argv)
  end)

  it("returns nil when create fails", function()
    config.setup({ bd_program = fake_bd .. ".missing" })

    assert.is_nil(bd.create("New bead", "task", "Description"))
  end)

  it("reports invoke success through _ok", function()
    assert.is_true(bd._ok({ "defer", "bd-1" }))
    assert.same(expected_argv({ "defer", "bd-1" }), bd._last_argv)
  end)

  it("comments", function()
    assert_write({ "comment", "bd-1", "Looks good" }, function()
      return bd.comment("bd-1", "Looks good")
    end)
  end)

  it("undefers", function()
    assert_write({ "undefer", "bd-1" }, function()
      return bd.undefer("bd-1")
    end)
  end)

  it("defers", function()
    assert_write({ "defer", "bd-1" }, function()
      return bd.defer("bd-1")
    end)
  end)

  it("updates design", function()
    assert_write({ "update", "bd-1", "--design", "Design" }, function()
      return bd.update_design("bd-1", "Design")
    end)
  end)

  it("updates acceptance", function()
    assert_write({ "update", "bd-1", "--acceptance", "Accepted" }, function()
      return bd.update_acceptance("bd-1", "Accepted")
    end)
  end)

  it("updates supported fields", function()
    assert_write({ "update", "bd-1", "--title", "Renamed" }, function()
      return bd.update("bd-1", "title", "Renamed")
    end)
  end)

  it("rejects unsupported update fields", function()
    local ok, err = pcall(bd.update, "bd-1", "owner", "alice")

    assert.is_false(ok)
    assert.matches("chaplet%-bd: unsupported update field owner", err)
  end)

  it("adds labels", function()
    assert_write({ "label", "add", "bd-1", "human" }, function()
      return bd.label("bd-1", "human")
    end)
  end)

  it("removes labels", function()
    assert_write({ "label", "remove", "bd-1", "human" }, function()
      return bd.label_remove("bd-1", "human")
    end)
  end)

  it("closes with optional reasons", function()
    assert_write({ "close", "bd-1" }, function()
      return bd.close("bd-1")
    end)
    assert_write({ "close", "bd-1" }, function()
      return bd.close("bd-1", "")
    end)
    assert_write({ "close", "bd-1", "--reason", "Done" }, function()
      return bd.close("bd-1", "Done")
    end)
  end)

  it("reopens with optional reasons", function()
    assert_write({ "reopen", "bd-1" }, function()
      return bd.reopen("bd-1")
    end)
    assert_write({ "reopen", "bd-1" }, function()
      return bd.reopen("bd-1", "")
    end)
    assert_write({ "reopen", "bd-1", "--reason", "Regression" }, function()
      return bd.reopen("bd-1", "Regression")
    end)
  end)

  it("claims", function()
    assert_write({ "update", "bd-1", "--claim" }, function()
      return bd.claim("bd-1")
    end)
  end)

  it("assigns including an empty assignee", function()
    assert_write({ "assign", "bd-1", "alice" }, function()
      return bd.assign("bd-1", "alice")
    end)
    assert_write({ "assign", "bd-1", "" }, function()
      return bd.assign("bd-1", "")
    end)
  end)

  it("sets numeric and string priorities", function()
    assert_write({ "priority", "bd-1", "2" }, function()
      return bd.priority("bd-1", 2)
    end)
    assert_write({ "priority", "bd-1", "2" }, function()
      return bd.priority("bd-1", "2")
    end)
  end)

  it("returns false from writes on nonzero exit", function()
    config.setup({ bd_program = fake_bd .. ".missing" })

    assert.is_false(bd.comment("bd-1", "Looks good"))
  end)

  it("rejects nil ids before spawning", function()
    local ok, err = pcall(bd.comment, nil, "Looks good")

    assert.is_false(ok)
    assert.matches("chaplet: incomplete bd command", err)
  end)
end)
