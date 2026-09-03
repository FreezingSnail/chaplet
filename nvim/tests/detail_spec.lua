describe("chaplet.detail", function()
  local saved_bd
  local saved_refresh
  local saved_actions
  local saved_notify
  local detail
  local beads
  local comments
  local notifications
  local refresh_calls

  local function full_bead()
    return {
      id = "bd-1",
      title = "Ship detail",
      status = "deferred",
      priority = 2,
      issue_type = "task",
      owner = "alice",
      created_at = "2026-01-02",
      labels = { "staged", "ui" },
      description = "A description.",
      design = "A design.",
      acceptance = "An acceptance.",
    }
  end

  before_each(function()
    saved_bd = package.loaded["chaplet.bd"]
    saved_refresh = package.loaded["chaplet.refresh"]
    saved_actions = package.loaded["chaplet.actions"]
    saved_notify = vim.notify
    beads = { ["bd-1"] = full_bead(), ["bd-2"] = { id = "bd-2", title = "Open", status = "open" } }
    comments = { ["bd-1"] = { { author = "bob", body = "body fallback" } }, ["bd-2"] = {} }
    notifications = {}
    refresh_calls = {}

    package.loaded["chaplet.bd"] = {
      STAGED_LABEL = "staged",
      show = function(id)
        return beads[id]
      end,
      comments = function(id)
        return comments[id]
      end,
    }
    package.loaded["chaplet.refresh"] = {
      attach = function(bufnr, fn)
        refresh_calls[bufnr] = fn
      end,
      mark_fetch = function(bufnr)
        refresh_calls.marked = bufnr
      end,
    }
    package.loaded["chaplet.actions"] = {
      comment = function() end,
      approve = function() end,
      reject = function() end,
    }
    package.loaded["chaplet.detail"] = nil
    detail = require("chaplet.detail")
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message, level }
    end
  end)

  after_each(function()
    local bufnr = vim.fn.bufnr("*chaplet:detail*")
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    package.loaded["chaplet.bd"] = saved_bd
    package.loaded["chaplet.refresh"] = saved_refresh
    package.loaded["chaplet.actions"] = saved_actions
    package.loaded["chaplet.detail"] = nil
    vim.notify = saved_notify
  end)

  it("renders a complete bead and comment body fallback exactly", function()
    assert.equals(table.concat({
      "# Ship detail",
      "",
      "*id:* bd-1 · *status:* deferred · *priority:* 2 · *type:* task · *owner:* alice · *created:* 2026-01-02",
      "*labels:* staged, ui",
      "",
      "## Description",
      "",
      "A description.",
      "",
      "## Design",
      "",
      "A design.",
      "",
      "## Acceptance",
      "",
      "An acceptance.",
      "",
      "## Comments",
      "",
      "- **bob** — body fallback",
      "",
    }, "\n"), detail.render(beads["bd-1"], comments["bd-1"]))
  end)

  it("omits blank sections, labels, and comments", function()
    local bead = {
      id = "bd-2", title = "Minimal", status = "open",
      description = " ", design = "", acceptance = "\n",
    }
    assert.equals(
      "# Minimal\n\n*id:* bd-2 · *status:* open · *priority:*  · *type:*  · *owner:*  · *created:* \n",
      detail.render(bead, {})
    )
  end)

  it("reuses one read-only markdown buffer and attaches refresh", function()
    local first = detail.open("bd-1")
    local second = detail.open("bd-2")
    assert.equals(first, second)
    assert.equals(detail.BUFFER_NAME, vim.api.nvim_buf_get_name(first):sub(-#detail.BUFFER_NAME))
    assert.equals("bd-2", detail.id(first))
    assert.equals("markdown", vim.bo[first].filetype)
    assert.equals("nofile", vim.bo[first].buftype)
    assert.equals("hide", vim.bo[first].bufhidden)
    assert.is_false(vim.bo[first].swapfile)
    assert.is_false(vim.bo[first].modifiable)
    assert.is_true(vim.bo[first].readonly)
    assert.is_not_nil(refresh_calls[first])
    assert.equals(first, refresh_calls.marked)
  end)

  it("skips unchanged writes and preserves the cursor", function()
    local bufnr = detail.open("bd-1")
    vim.api.nvim_win_set_cursor(0, { 3, 4 })
    local original = vim.api.nvim_buf_set_lines
    local writes = 0
    vim.api.nvim_buf_set_lines = function(...)
      writes = writes + 1
      return original(...)
    end
    detail.populate(bufnr, "bd-1")
    vim.api.nvim_buf_set_lines = original
    assert.equals(0, writes)
    assert.same({ 3, 4 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("maps state-dependent keys and removes stale lifecycle keys", function()
    local bufnr = detail.open("bd-1")
    local function mapped()
      local result = {}
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if vim.tbl_contains({ "q", "g", "c", "a", "r" }, map.lhs) then
          result[map.lhs] = true
        end
      end
      return result
    end
    assert.same({ q = true, g = true, c = true, a = true, r = true }, mapped())

    detail.populate(bufnr, "bd-2")
    assert.same({ q = true, g = true, c = true }, mapped())
  end)

  it("notifies on a missing bead without changing contents", function()
    local bufnr = detail.open("bd-1")
    local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    beads["missing"] = nil
    detail.populate(bufnr, "missing")
    assert.same(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.same({ { "chaplet: no bead missing", vim.log.levels.ERROR } }, notifications)
  end)
end)
