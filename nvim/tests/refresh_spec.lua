local config = require("chaplet.config")
local refresh = require("chaplet.refresh")

describe("chaplet.refresh", function()
  local now
  local original_buffer

  before_each(function()
    now = 0
    refresh.now = function()
      return now
    end
    refresh.stop_timer()
    config.setup()
    original_buffer = vim.api.nvim_get_current_buf()
  end)

  after_each(function()
    refresh.stop_timer()
    refresh.now = function()
      return vim.loop.now()
    end
    if vim.api.nvim_buf_is_valid(original_buffer) then
      vim.api.nvim_set_current_buf(original_buffer)
    end
  end)

  local function new_buffer()
    return vim.api.nvim_create_buf(false, true)
  end

  local function cleanup(bufnr)
    refresh.unregister(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  it("registers, replaces, and unregisters refreshers", function()
    local bufnr = new_buffer()
    local first = 0
    local second = 0

    refresh.register(bufnr, function()
      first = first + 1
    end)
    refresh.register(bufnr, function()
      second = second + 1
    end)
    refresh.refresh_all()

    assert.equals(0, first)
    assert.equals(1, second)
    refresh.unregister(bufnr)
    refresh.refresh_all()
    assert.equals(1, second)

    cleanup(bufnr)
  end)

  it("attaches focus and wipe autocmds", function()
    local bufnr = new_buffer()
    refresh.attach(bufnr, function() end)

    local autocmds = vim.api.nvim_get_autocmds({ group = "chaplet_refresh_" .. bufnr })
    assert.equals(3, #autocmds)

    refresh.unregister(bufnr)
    local ok = pcall(vim.api.nvim_get_autocmds, { group = "chaplet_refresh_" .. bufnr })
    assert.is_false(ok)
    cleanup(bufnr)
  end)

  it("marks fetches and becomes stale beyond the configured delay", function()
    local bufnr = new_buffer()
    refresh.register(bufnr, function() end)

    assert.is_true(refresh.stale(bufnr))
    refresh.mark_fetch(bufnr)
    now = 1999
    assert.is_false(refresh.stale(bufnr))
    now = 2001
    assert.is_true(refresh.stale(bufnr))

    cleanup(bufnr)
  end)

  it("debounces focus refreshes and honors auto_refresh", function()
    local bufnr = new_buffer()
    local calls = 0
    config.setup({ refresh_interval = 0 })
    refresh.attach(bufnr, function()
      calls = calls + 1
      refresh.mark_fetch(bufnr)
    end)

    refresh.on_focus(bufnr)
    assert.equals(1, calls)
    now = 1999
    refresh.on_focus(bufnr)
    assert.equals(1, calls)
    now = 2001
    refresh.on_focus(bufnr)
    assert.equals(2, calls)

    config.setup({ auto_refresh = false })
    now = 10000
    refresh.on_focus(bufnr)
    assert.equals(2, calls)
    cleanup(bufnr)
  end)

  it("ticks only stale visible registered buffers", function()
    local visible = new_buffer()
    local hidden = new_buffer()
    local visible_calls = 0
    local hidden_calls = 0
    config.setup({ refresh_interval = 0 })

    refresh.register(visible, function()
      visible_calls = visible_calls + 1
      refresh.mark_fetch(visible)
    end)
    refresh.register(hidden, function()
      hidden_calls = hidden_calls + 1
      refresh.mark_fetch(hidden)
    end)
    vim.api.nvim_set_current_buf(visible)
    refresh.tick()

    assert.equals(1, visible_calls)
    assert.equals(0, hidden_calls)

    cleanup(visible)
    cleanup(hidden)
  end)

  it("stops its timer when no registered buffer is visible", function()
    local hidden = new_buffer()
    local before = #vim.fn.timer_info()
    refresh.register(hidden, function() end)
    config.setup({ refresh_interval = 5 })

    refresh.ensure_timer()
    assert.equals(before + 1, #vim.fn.timer_info())
    refresh.ensure_timer()
    assert.equals(before + 1, #vim.fn.timer_info())

    refresh.tick()
    assert.equals(before, #vim.fn.timer_info())
    cleanup(hidden)
  end)

  it("does not start a timer for a nil interval", function()
    local before = #vim.fn.timer_info()
    config.setup()
    config.options.refresh_interval = nil

    refresh.ensure_timer()
    assert.equals(before, #vim.fn.timer_info())
  end)

  it("refreshes every live buffer even when auto_refresh is disabled", function()
    local first = new_buffer()
    local second = new_buffer()
    local calls = { 0, 0 }
    config.setup({ auto_refresh = false })
    refresh.register(first, function()
      calls[1] = calls[1] + 1
    end)
    refresh.register(second, function()
      calls[2] = calls[2] + 1
    end)

    refresh.refresh_all()

    assert.same({ 1, 1 }, calls)
    cleanup(first)
    cleanup(second)
  end)

  it("contains refresher errors and notifies at WARN level", function()
    local bufnr = new_buffer()
    local notification
    local notify = vim.notify
    vim.notify = function(message, level)
      notification = { message = message, level = level }
    end
    refresh.register(bufnr, function()
      error("broken refresher")
    end)

    local ok, err = pcall(refresh.refresh_all)
    vim.notify = notify

    assert.is_true(ok, err)
    assert.matches("broken refresher", notification.message)
    assert.equals(vim.log.levels.WARN, notification.level)
    cleanup(bufnr)
  end)

  it("drops wiped buffers instead of refreshing them", function()
    local bufnr = new_buffer()
    local calls = 0
    refresh.register(bufnr, function()
      calls = calls + 1
    end)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    refresh.refresh_all()

    assert.equals(0, calls)
    cleanup(bufnr)
  end)
end)
