local bar = require("chaplet.bar")
local bd = require("chaplet.bd")
local config = require("chaplet.config")
local graph = require("chaplet.graph")
local refresh = require("chaplet.refresh")

local function delete_graph_buffer()
  local bufnr = vim.fn.bufnr(graph.BUFFER_NAME)
  if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function ids(bufnr)
  local result = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.lhs == "g" or mapping.lhs == "q" then
      result[mapping.lhs] = true
    end
  end
  return result
end

describe("chaplet.graph buffer", function()
  local saved_graph_data
  local saved_mark_fetch
  local saved_notify
  local notifications

  before_each(function()
    config.setup({ auto_refresh = false })
    saved_graph_data = bd.graph_data
    saved_mark_fetch = refresh.mark_fetch
    saved_notify = vim.notify
    notifications = {}
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message, level }
    end
  end)

  after_each(function()
    bd.graph_data = saved_graph_data
    refresh.mark_fetch = saved_mark_fetch
    vim.notify = saved_notify
    delete_graph_buffer()
  end)

  it("reuses one read-only scratch buffer and installs truthful chrome", function()
    local first = graph.buffer()
    local second = graph.buffer()

    assert.equals(first, second)
    local name = vim.api.nvim_buf_get_name(first)
    assert.equals(graph.BUFFER_NAME, name:sub(-#graph.BUFFER_NAME))
    assert.equals("nofile", vim.bo[first].buftype)
    assert.equals("hide", vim.bo[first].bufhidden)
    assert.is_false(vim.bo[first].swapfile)
    assert.is_false(vim.bo[first].modifiable)
    assert.is_true(vim.bo[first].readonly)
    assert.same({ g = true, q = true }, ids(first))
  end)

  it("renders text lines, extmarks, line ids, bar and statusline", function()
    local bufnr = graph.buffer()
    local nodes = {
      { id = "root", title = "Root", deps = {} },
      { id = "child", title = "Child", deps = { "root" }, state = "open" },
    }
    local edges = { { from = "child", to = "root" } }
    graph.render(bufnr, nodes, edges, "child")

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals(2, #lines)
    assert.equals("root", graph.line_id(bufnr, 1))
    assert.equals("child", graph.line_id(bufnr, 2))
    assert.is_nil(graph.line_id(bufnr, 3))
    assert.equals("root", graph.id_at_cursor(bufnr))
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    assert.equals("child", graph.id_at_cursor(bufnr))

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, graph.namespace, 0, -1, {})
    assert.equals(3, #marks)
    assert.equals(" [g] refresh [q] quit [mouse-1] open node [mouse-2] dependents",
      bar.rendered(bufnr).winbar)
    assert.matches("chaplet all · 0 beads", bar.rendered(bufnr).statusline)
  end)
end)

describe("chaplet.graph refresh", function()
  local saved_graph_data
  local saved_mark_fetch
  local saved_notify
  local fetches
  local marks
  local notifications

  before_each(function()
    config.setup({ auto_refresh = false })
    saved_graph_data = bd.graph_data
    saved_mark_fetch = refresh.mark_fetch
    saved_notify = vim.notify
    fetches = 0
    marks = 0
    notifications = {}
    bd.graph_data = function(filters)
      fetches = fetches + 1
      assert.same({ all = true }, filters)
      return {
        { id = "bd-1", title = "One", status = "open", dependencies = {} },
      }
    end
    refresh.mark_fetch = function()
      marks = marks + 1
    end
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message, level }
    end
  end)

  after_each(function()
    bd.graph_data = saved_graph_data
    refresh.mark_fetch = saved_mark_fetch
    vim.notify = saved_notify
    delete_graph_buffer()
  end)

  it("skips unchanged writes while marking every fetch", function()
    local bufnr = graph.buffer()
    graph.refresh(bufnr)
    local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
    graph.refresh(bufnr)

    assert.equals(2, fetches)
    assert.equals(2, marks)
    assert.equals(changedtick, vim.api.nvim_buf_get_changedtick(bufnr))
  end)

  it("notifies on an empty fetch without clearing the prior canvas", function()
    local bufnr = graph.buffer()
    graph.refresh(bufnr)
    local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    bd.graph_data = function()
      return nil
    end

    graph.refresh(bufnr)

    assert.same(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.same({ { "chaplet: no graph data", vim.log.levels.WARN } }, notifications)
    assert.equals(2, marks)
  end)

  it("drops focus when its node disappears", function()
    local bufnr = graph.buffer()
    graph.refresh(bufnr)
    local state = graph.state(bufnr)
    state.focus = "bd-1"
    state.rendered_focus = "bd-1"
    bd.graph_data = function()
      return {
        { id = "bd-2", title = "Two", status = "open", dependencies = {} },
      }
    end

    graph.refresh(bufnr)

    assert.is_nil(state.focus)
    assert.is_nil(state.rendered_focus)
    assert.equals("bd-2", graph.line_id(bufnr, 1))
    assert.is_false(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]:find("▶", 1, true) ~= nil)
  end)
end)
