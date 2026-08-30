local bd = require("chaplet.bd")
local config = require("chaplet.config")

local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = vim.fn.fnamemodify(source, ":h")
local fake_bd = vim.fn.fnamemodify(test_dir .. "/../../test/fake-bd", ":p")
local base

local function set_buffer_path(path)
  local original = vim.api.nvim_get_current_buf()
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buffer)
  vim.api.nvim_buf_set_name(buffer, path)
  return original, buffer
end

local function restore_buffer(original, buffer)
  if vim.api.nvim_buf_is_valid(original) then
    vim.api.nvim_win_set_buf(0, original)
  end
  if vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
end

describe("chaplet.bd", function()
  before_each(function()
    config.setup({ bd_program = fake_bd })
    bd._last_argv = nil
    base = vim.fn.tempname()
    vim.fn.mkdir(base, "p")
  end)

  after_each(function()
    vim.fn.delete(base, "rf")
  end)

  it("prefers a .beads ancestor over a .git ancestor", function()
    local root = base .. "/beads-root"
    local path = root .. "/nested/deeper/file"
    vim.fn.mkdir(root .. "/.beads", "p")
    vim.fn.mkdir(root .. "/.git", "p")
    vim.fn.mkdir(root .. "/nested/deeper", "p")
    local original, buffer = set_buffer_path(path)

    assert.equals(root, bd.root())

    restore_buffer(original, buffer)
  end)

  it("uses a .git ancestor when no .beads ancestor exists", function()
    local root = base .. "/git-root"
    local path = root .. "/nested/file"
    vim.fn.mkdir(root .. "/.git", "p")
    vim.fn.mkdir(root .. "/nested", "p")
    local original, buffer = set_buffer_path(path)

    assert.equals(root, bd.root())

    restore_buffer(original, buffer)
  end)

  it("falls back to cwd when no project marker exists", function()
    local path = base .. "/unmarked/nested/file"
    vim.fn.mkdir(base .. "/unmarked/nested", "p")
    local original, buffer = set_buffer_path(path)

    assert.equals(vim.fn.fnamemodify(vim.fn.getcwd(), ":p"):gsub("/+$", ""), bd.root())

    restore_buffer(original, buffer)
  end)

  it("scopes argv once before command arguments", function()
    local result = bd.invoke({ "list" })
    local root = bd.root()

    assert.equals(0, result.code)
    assert.same({ fake_bd, "-C", root, "list" }, bd._last_argv)
  end)

  it("rejects incomplete command arguments", function()
    local _, nil_error = pcall(bd.invoke, { "show", nil, "bd-1" })
    local _, type_error = pcall(bd.invoke, { "show", 1 })

    assert.matches("incomplete bd command", nil_error)
    assert.matches("incomplete bd command", type_error)
  end)

  it("propagates fake bd output and exit status", function()
    local result = bd.invoke({ "list" })

    assert.equals(0, result.code)
    assert.matches('"id":"bd%-1"', result.stdout)
  end)

  it("maps a missing program to exit code 127", function()
    config.setup({ bd_program = base .. "/missing-bd" })

    assert.same({ code = 127, stdout = "" }, bd.invoke({ "list" }))
  end)

  it("returns the same shape through both spawn capabilities", function()
    if not vim.system then
      return
    end

    local system_result = bd.invoke({ "list" })
    local system = vim.system
    vim.system = nil
    local ok, fallback_result = pcall(bd.invoke, { "list" })
    vim.system = system

    assert.is_true(ok, fallback_result)
    assert.same(system_result, fallback_result)
  end)
end)
