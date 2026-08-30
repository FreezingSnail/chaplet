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

  it("warns without raising when list is unavailable", function()
    local notification
    local notify = vim.notify
    vim.notify = function(message, level)
      notification = { message = message, level = level }
    end

    local ok, err = pcall(vim.cmd, "Chaplet")
    vim.notify = notify

    assert.is_true(ok, err)
    assert.equals("chaplet: list not available yet", notification.message)
    assert.equals(vim.log.levels.WARN, notification.level)
  end)

  it("is safe to call twice", function()
    assert.has_no.errors(function()
      chaplet.setup()
      chaplet.setup()
    end)
  end)
end)
