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

describe("chaplet.bd relational and human writes", function()
  before_each(function()
    config.setup({ bd_program = fake_bd })
    bd._last_argv = nil
  end)

  it("adds and removes dependencies", function()
    assert_write({ "dep", "add", "bd-1", "bd-2" }, function()
      return bd.dependency_add("bd-1", "bd-2")
    end)
    assert_write({ "dep", "remove", "bd-1", "bd-2" }, function()
      return bd.dependency_remove("bd-1", "bd-2")
    end)
  end)

  it("duplicates and supersedes", function()
    assert_write({ "duplicate", "bd-1", "--of", "bd-2" }, function()
      return bd.duplicate("bd-1", "bd-2")
    end)
    assert_write({ "supersede", "bd-1", "--with", "bd-2" }, function()
      return bd.supersede("bd-1", "bd-2")
    end)
  end)

  it("responds to and dismisses human beads", function()
    assert_write({ "human", "respond", "bd-1", "--response", "Answer" }, function()
      return bd.human_respond("bd-1", "Answer")
    end)
    assert_write({ "human", "dismiss", "bd-1" }, function()
      return bd.human_dismiss("bd-1", nil)
    end)
    assert_write({ "human", "dismiss", "bd-1" }, function()
      return bd.human_dismiss("bd-1", "")
    end)
    assert_write({ "human", "dismiss", "bd-1", "--reason", "Not needed" }, function()
      return bd.human_dismiss("bd-1", "Not needed")
    end)
  end)

  it("returns false when a relational write fails", function()
    config.setup({ bd_program = fake_bd .. ".missing" })

    assert.is_false(bd.dependency_add("bd-1", "bd-2"))
  end)

  it("rejects nil ids before spawning", function()
    local ok, err = pcall(bd.human_dismiss, nil, "Reason")

    assert.is_false(ok)
    assert.matches("chaplet: incomplete bd command", err)
    assert.is_nil(bd._last_argv)
  end)
end)
