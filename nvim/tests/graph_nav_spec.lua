local bar = require("chaplet.bar")
local bd = require("chaplet.bd")
local config = require("chaplet.config")
local detail = require("chaplet.detail")
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
    if vim.tbl_contains({ "n", "p", "<CR>", "d", "f", "g", "q", "<LeftMouse>", "<MiddleMouse>" }, mapping.lhs) then
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
    assert.same({ n = true, p = true, ["<CR>"] = true, d = true, f = true,
      g = true, q = true, ["<LeftMouse>"] = true, ["<MiddleMouse>"] = true }, ids(first))
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
    assert.equals(" [n] next [p] prev [<CR>] open focused [d] dependents [f] deps [g] refresh [q] quit [mouse-1] open node [mouse-2] dependents",
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



describe("chaplet.graph navigation", function()
  local saved_detail_open
  local saved_bar_install
  local saved_graph_data
  local saved_notify
  local notifications

  before_each(function()
    config.setup({ auto_refresh = false })
    saved_detail_open = detail.open
    saved_bar_install = bar.install
    saved_graph_data = bd.graph_data
    saved_notify = vim.notify
    notifications = {}
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message, level }
    end
  end)

  after_each(function()
    detail.open = saved_detail_open
    bar.install = saved_bar_install
    bd.graph_data = saved_graph_data
    vim.notify = saved_notify
    delete_graph_buffer()
  end)

  local function rendered_graph(nodes, edges)
    local bufnr = graph.buffer()
    graph.render(bufnr, nodes, edges or {}, nil)
    return bufnr
  end

  it("walks renderer order, wraps, and starts next at the first node", function()
    local bufnr = rendered_graph({
      { id = "b", title = "B", deps = { "a" } },
      { id = "a", title = "A", deps = {} },
      { id = "c", title = "C", deps = { "a" } },
    })

    graph.focus_next(bufnr)
    assert.equals("a", graph.state(bufnr).focus)
    graph.focus_next(bufnr)
    assert.equals("b", graph.state(bufnr).focus)
    graph.focus_prev(bufnr)
    assert.equals("a", graph.state(bufnr).focus)
    graph.focus_prev(bufnr)
    assert.equals("c", graph.state(bufnr).focus)
  end)

  it("makes focus moves visual-only", function()
    local fetches = 0
    local installs = 0
    bd.graph_data = function()
      fetches = fetches + 1
      return {}
    end
    bar.install = function(...)
      installs = installs + 1
      return saved_bar_install(...)
    end
    local bufnr = rendered_graph({ { id = "a", title = "A", deps = {} } })
    local before = bar.rendered(bufnr)

    graph.focus_set(bufnr, "a")

    assert.equals(0, fetches)
    assert.equals(1, installs)
    assert.same(before, bar.rendered(bufnr))
    assert.equals("a", graph.state(bufnr).rendered_focus)
  end)

  it("opens focused nodes and reports missing focus", function()
    local opened
    detail.open = function(id)
      opened = id
    end
    local bufnr = rendered_graph({ { id = "a", title = "A", deps = {} } })

    graph.open_focused(bufnr)
    assert.same({ { "chaplet: no focused node", vim.log.levels.WARN } }, notifications)
    graph.focus_next(bufnr)
    graph.open_focused(bufnr)
    assert.equals("a", opened)
  end)

  it("takes first matching edge for deterministic dependency jumps", function()
    local bufnr = rendered_graph({
      { id = "a", title = "A", deps = {} },
      { id = "b", title = "B", deps = { "a" } },
      { id = "c", title = "C", deps = { "a" } },
      { id = "d", title = "D", deps = { "b", "c" } },
    }, {
      { from = "b", to = "a" },
      { from = "c", to = "a" },
      { from = "d", to = "b" },
      { from = "d", to = "c" },
    })

    graph.focus_set(bufnr, "a")
    graph.jump_dependents(bufnr)
    assert.equals("b", graph.state(bufnr).focus)
    graph.focus_set(bufnr, "d")
    graph.jump_deps(bufnr)
    assert.equals("b", graph.state(bufnr).focus)
    graph.jump_dependents(bufnr)
    assert.equals("d", graph.state(bufnr).focus)
    graph.focus_set(bufnr, "c")
    graph.jump_dependents(bufnr)
    assert.equals("d", graph.state(bufnr).focus)
  end)

  it("notifies when a jump has no target or focus", function()
    local bufnr = rendered_graph({ { id = "a", title = "A", deps = {} } })

    graph.jump_dependents(bufnr)
    graph.jump_deps(bufnr)
    assert.same({
      { "chaplet: no dependents (no focus)", vim.log.levels.WARN },
      { "chaplet: no deps (no focus)", vim.log.levels.WARN },
    }, notifications)
    graph.focus_next(bufnr)
    graph.jump_dependents(bufnr)
    assert.same({ "chaplet: no dependents", vim.log.levels.WARN }, notifications[3])
  end)

  it("resolves mouse ids through line_id and notifies off-node", function()
    local opened
    detail.open = function(id)
      opened = id
    end
    local bufnr = rendered_graph({ { id = "a", title = "A", deps = {} } })
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    graph.mouse_open(bufnr)
    assert.equals("a", opened)
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].readonly = false
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "blank" })
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].readonly = true
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    graph.mouse_open(bufnr)
    graph.mouse_dependents(bufnr)
    assert.same({
      { "chaplet: no node at click", vim.log.levels.WARN },
      { "chaplet: no node at click", vim.log.levels.WARN },
    }, notifications)
  end)

  it("middle mouse focuses the clicked node before jumping", function()
    local bufnr = rendered_graph({
      { id = "a", title = "A", deps = {} },
      { id = "b", title = "B", deps = { "a" } },
    }, { { from = "b", to = "a" } })
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    graph.mouse_dependents(bufnr)

    assert.equals("b", graph.state(bufnr).focus)
  end)
end)
