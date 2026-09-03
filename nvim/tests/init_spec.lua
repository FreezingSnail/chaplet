local chaplet = require("chaplet")
local config = require("chaplet.config")

describe("chaplet.setup", function()
  before_each(function()
    config.setup()
    chaplet.setup()
  end)

  it("registers commands and prefix keymaps", function()
    assert.is_true(vim.fn.exists(":Chaplet") > 0)
    assert.is_true(vim.fn.exists(":ChapletGraph") > 0)

    local inbox = vim.fn.maparg("<leader>bb", "n", false, true)
    local graph = vim.fn.maparg("<leader>bs", "n", false, true)
    assert.equals("<Cmd>Chaplet<CR>", inbox.rhs)
    assert.equals("Chaplet inbox", inbox.desc)
    assert.is_true(inbox.silent == 1)
    assert.equals("<Cmd>ChapletGraph<CR>", graph.rhs)
    assert.equals("Chaplet graph", graph.desc)
    assert.is_true(graph.silent == 1)
  end)

  it("routes Chaplet to list.open", function()
    local list = require("chaplet.list")
    local saved_open = list.open
    local called = false
    list.open = function()
      called = true
    end

    local ok, err = pcall(vim.cmd, "Chaplet")
    list.open = saved_open

    assert.is_true(ok, err)
    assert.is_true(called)
  end)

  it("is safe to call twice", function()
    assert.has_no.errors(function()
      chaplet.setup()
      chaplet.setup()
    end)
  end)
end)
