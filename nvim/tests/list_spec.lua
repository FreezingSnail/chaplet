local list = require("chaplet.list")
local bd = require("chaplet.bd")
local hl = require("chaplet.hl")
local util = require("chaplet.util")
local config = require("chaplet.config")

describe("chaplet.list row formatting", function()
  it("exports the fixed columns", function()
    assert.same({
      { name = "ID", width = 12 },
      { name = "Type", width = 10 },
      { name = "State", width = 12 },
      { name = "P", width = 3 },
      { name = "Staged", width = 7 },
      { name = "Title", width = 60 },
    }, list.COLUMNS)
  end)

  it("formats priority cells", function()
    assert.equals("·0", list.priority_cell(0))
    assert.equals("·1", list.priority_cell(1))
    assert.equals("●2", list.priority_cell(2))
    assert.equals("●3", list.priority_cell(3))
    assert.equals("●4", list.priority_cell(4))
    assert.equals("●3", list.priority_cell("3"))
    assert.equals("", list.priority_cell(nil))
  end)

  it("recognizes only staged deferred beads", function()
    assert.is_true(list.staged({ status = "deferred", labels = { "staged" } }))
    assert.is_false(list.staged({ status = "deferred", labels = { "human" } }))
    assert.is_false(list.staged({ status = "open", labels = { "staged" } }))
    assert.is_false(list.staged({ status = "deferred" }))
  end)

  it("formats the header at the fixed display width", function()
    local text, spans = list.header_line()
    local expected = table.concat({
      util.cell("ID", 12), " ",
      util.cell("Type", 10), " ",
      util.cell("State", 12), " ",
      util.cell("P", 3), " ",
      util.cell("Staged", 7), " ",
      util.cell("Title", 60),
    })
    assert.equals(expected, text)
    assert.equals(109, vim.fn.strdisplaywidth(text))
    assert.same({ { col = 0, end_col = #text, hl = "ChapletHeader" } }, spans)
  end)

  it("formats cells and resolver-backed spans", function()
    local row = list.format_row({
      id = "bd-123",
      issue_type = "task",
      status = "deferred",
      priority = "2",
      labels = { "staged" },
      title = "Fix task",
    }, false)
    local expected = table.concat({
      util.cell("bd-123", 12), " ",
      util.cell("task", 10), " ",
      util.cell("deferred", 12), " ",
      util.cell("●2", 3), " ",
      util.cell("✔", 7), " ",
      util.cell("Fix task", 60),
    })
    assert.equals(expected, row.text)
    assert.equals(109, vim.fn.strdisplaywidth(row.text))
    assert.same({
      { col = 0, end_col = 12, hl = "ChapletId" },
      { col = 13, end_col = 23, hl = hl.type_group("task") },
      { col = 24, end_col = 36, hl = hl.state_group("deferred") },
      { col = 37, end_col = 42, hl = hl.priority_group("2") },
      { col = 43, end_col = 52, hl = "ChapletStaged" },
    }, row.spans)
  end)

  it("adds exactly two title-indent cells", function()
    local plain = list.format_row({ title = "title" }, false)
    local indented = list.format_row({ title = "title" }, true)
    assert.equals(109, vim.fn.strdisplaywidth(plain.text))
    assert.equals(109, vim.fn.strdisplaywidth(indented.text))
    assert.equals(string.rep(" ", 2) .. "title", vim.fn.strcharpart(indented.text, 49, 7))
  end)

  it("handles a bead with every optional field missing", function()
    local row = list.format_row({}, false)
    assert.equals(109, vim.fn.strdisplaywidth(row.text))
    assert.equals(string.rep(" ", 109), row.text)
    assert.equals(5, #row.spans)
    for index = 2, #row.spans do
      assert.is_true(row.spans[index - 1].col < row.spans[index].col)
      assert.is_true(row.spans[index - 1].end_col <= row.spans[index].col)
    end
  end)

  it("truncates long titles by display cells", function()
    local row = list.format_row({ title = string.rep("x", 80) }, false)
    assert.equals(109, vim.fn.strdisplaywidth(row.text))
    assert.equals(string.rep("x", 60), vim.fn.strcharpart(row.text, 49, 60))
  end)
end)

describe("chaplet.list grouping", function()
  local original_show

  before_each(function()
    list.clear_epic_cache()
    original_show = bd.show
  end)

  after_each(function()
    bd.show = original_show
    list.clear_epic_cache()
  end)

  it("groups children under epics, keeps childless epics, and sorts groups", function()
    local epic_z = { id = "epic-z", issue_type = "epic", title = "Z" }
    local epic_a = { id = "epic-a", issue_type = "epic", title = "A" }
    local child_z = { id = "task-z", parent = "epic-z", title = "z child" }
    local child_a = { id = "task-a", parent = "epic-a", title = "a child" }
    local orphan = { id = "task-orphan", title = "orphan" }
    local rows = list.group_by_epic({ child_z, orphan, epic_z, child_a, epic_a })

    assert.same({
      { bead = epic_a, indent = false },
      { bead = child_a, indent = true },
      { bead = epic_z, indent = false },
      { bead = child_z, indent = true },
      { bead = orphan, indent = false },
    }, rows)
  end)

  it("resolves absent parents and preserves children when lookup is nil", function()
    local fetched = { id = "epic-fetch", issue_type = "epic", title = "Fetched" }
    local child = { id = "task-fetch", parent = "epic-fetch" }
    local missing_child = { id = "task-missing", parent = "epic-missing" }
    local calls = {}
    local function fetch_epic(id)
      table.insert(calls, id)
      return id == "epic-fetch" and fetched or nil
    end

    assert.same({
      { bead = fetched, indent = false },
      { bead = child, indent = true },
      { bead = missing_child, indent = true },
    }, list.group_by_epic({ child, missing_child }, fetch_epic))
    assert.same({ "epic-fetch", "epic-missing" }, calls)
  end)

  it("negative-caches absent parents across grouping runs", function()
    local calls = 0
    bd.show = function()
      calls = calls + 1
      return nil
    end
    local beads = { { id = "task", parent = "epic-missing" } }

    list.group_by_epic(beads)
    list.group_by_epic(beads)

    assert.equals(1, calls)
    assert.same({ { bead = beads[1], indent = true } }, list.group_by_epic(beads))

    list.clear_epic_cache()
    list.group_by_epic(beads)
    assert.equals(2, calls)
  end)

  it("does not mutate beads or fetch in-view epics", function()
    local epic = { id = "epic", issue_type = "epic" }
    local child = { id = "child", parent = "epic" }
    local beads = { child, epic }
    local snapshot = vim.deepcopy(beads)
    local calls = 0

    local rows = list.group_by_epic(beads, function()
      calls = calls + 1
    end)

    assert.same(snapshot, beads)
    assert.equals(0, calls)
    assert.same({
      { bead = epic, indent = false },
      { bead = child, indent = true },
    }, rows)
  end)
  it("memoizes fetched parents", function()
    local calls = 0
    local fetched = { id = "epic-fetch", issue_type = "epic" }
    bd.show = function(id)
      calls = calls + 1
      assert.equals("epic-fetch", id)
      return fetched
    end
    local beads = { { id = "task", parent = "epic-fetch" } }

    local first = list.fetch_epic("epic-fetch")
    local second = list.group_by_epic(beads)[1].bead

    assert.equals(fetched, first)
    assert.equals(fetched, second)
    assert.equals(1, calls)
  end)
end)

describe("chaplet.list render", function()
  local saved_list
  local saved_show
  local saved_mark_fetch
  local saved_notify
  local saved_detail
  local current_beads
  local list_calls
  local show_calls
  local marked
  local notifications

  before_each(function()
    saved_list = bd.list
    saved_show = bd.show
    saved_mark_fetch = require("chaplet.refresh").mark_fetch
    saved_notify = vim.notify
    saved_detail = package.loaded["chaplet.detail"]
    config.setup({ auto_refresh = false })
    current_beads = {
      { id = "bd-1", issue_type = "task", status = "open", title = "First" },
    }
    list_calls = 0
    show_calls = 0
    marked = {}
    notifications = {}
    bd.list = function()
      list_calls = list_calls + 1
      return vim.deepcopy(current_beads)
    end
    bd.show = function()
      show_calls = show_calls + 1
      return nil
    end
    require("chaplet.refresh").mark_fetch = function(bufnr)
      marked[#marked + 1] = bufnr
    end
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message, level }
    end
    package.loaded["chaplet.detail"] = {
      open = function(id)
        package.loaded["chaplet.detail"].opened = id
      end,
    }
  end)

  after_each(function()
    local bufnr = vim.fn.bufnr(list.BUFFER_NAME)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    bd.list = saved_list
    bd.show = saved_show
    require("chaplet.refresh").mark_fetch = saved_mark_fetch
    config.setup()
    vim.notify = saved_notify
    package.loaded["chaplet.detail"] = saved_detail
  end)

  local function new_buffer()
    local bufnr = list.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  it("reuses one read-only scratch buffer and installs the four keys", function()
    local first = new_buffer()
    local second = list.buffer()

    assert.equals(first, second)
    assert.equals("nofile", vim.bo[first].buftype)
    assert.equals("hide", vim.bo[first].bufhidden)
    assert.is_false(vim.bo[first].swapfile)
    assert.is_false(vim.bo[first].modifiable)
    assert.is_true(vim.bo[first].readonly)
    assert.is_false(vim.wo.wrap)

    local mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(first, "n")) do
      mapped[mapping.lhs] = true
    end
    assert.same({
      ["<CR>"] = true,
      ["<LeftMouse>"] = true,
      q = true,
      v = true,
      ["?"] = true,
    }, mapped)
  end)

  it("renders the header first and maps only row lines to ids", function()
    local bufnr = new_buffer()
    list.render(bufnr, current_beads)

    local header = list.header_line()
    assert.equals(header, vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
    assert.is_nil(list.line_id(bufnr, 1))
    assert.equals("bd-1", list.line_id(bufnr, 2))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    assert.equals("bd-1", list.id_at_cursor(bufnr))

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.is_nil(list.id_at_cursor(bufnr))
    assert.is_nil(list.line_id(bufnr, 3))
    assert.same(current_beads, list.beads(bufnr))
  end)

  it("places extmarks at every formatter span", function()
    local bufnr = new_buffer()
    list.render(bufnr, current_beads)
    local _, header_spans = list.header_line()
    local row = list.format_row(current_beads[1], false)
    local expected = { header_spans, row.spans }
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, list.namespace, 0, -1, { details = true })

    assert.equals(#header_spans + #row.spans, #marks)
    local index = 1
    for line, spans in ipairs(expected) do
      for _, span in ipairs(spans) do
        assert.equals(line - 1, marks[index][2])
        assert.equals(span.col, marks[index][3])
        assert.equals(line - 1, marks[index][4].end_row)
        assert.equals(span.end_col, marks[index][4].end_col)
        index = index + 1
      end
    end
  end)

  it("skips equal refreshes, preserving changedtick and cursor", function()
    local bufnr = new_buffer()
    list.refresh(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 4 })
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    list_calls = 0

    list.refresh(bufnr)

    assert.equals(1, list_calls)
    assert.equals(tick, vim.api.nvim_buf_get_changedtick(bufnr))
    assert.same({ 2, 4 }, vim.api.nvim_win_get_cursor(0))
    assert.same({ bufnr, bufnr }, marked)
  end)

  it("restores cursor position after a changed render", function()
    local bufnr = new_buffer()
    list.refresh(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 4 })
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    current_beads[1].title = "Changed"

    list.refresh(bufnr)

    assert.equals(2, vim.api.nvim_win_get_cursor(0)[1])
    assert.equals(4, vim.api.nvim_win_get_cursor(0)[2])
    assert.is_true(vim.api.nvim_buf_get_changedtick(bufnr) > tick)
  end)

  it("opens row ids and notifies without opening on the header", function()
    local bufnr = new_buffer()
    list.render(bufnr, current_beads)

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local keys = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
    vim.api.nvim_feedkeys(keys, "mx", false)
    assert.equals("bd-1", package.loaded["chaplet.detail"].opened)
    assert.equals(0, show_calls)

    package.loaded["chaplet.detail"].opened = nil
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys(keys, "mx", false)
    assert.is_nil(package.loaded["chaplet.detail"].opened)
    assert.same({ { "chaplet: no bead at point", vim.log.levels.WARN } }, notifications)
    assert.equals(0, show_calls)
    assert.equals(0, list_calls)
  end)
end)


describe("chaplet.list views", function()
  local saved_list
  local saved_query
  local saved_view_filters
  local saved_view_names
  local saved_mark_fetch
  local saved_notify
  local saved_select
  local list_calls
  local query_calls
  local marks
  local notifications

  before_each(function()
    saved_list = bd.list
    saved_query = bd.query
    saved_view_filters = bd.view_filters
    saved_view_names = bd.view_names
    saved_mark_fetch = require("chaplet.refresh").mark_fetch
    saved_notify = vim.notify
    saved_select = vim.ui.select
    list_calls = {}
    query_calls = {}
    marks = {}
    notifications = {}
    config.setup({ auto_refresh = false })
    bd.view_filters = function(view)
      return ({
        inbox = { status = "deferred" },
        open = { status = "open" },
        closed = { status = "closed" },
        all = { all = true },
      })[view]
    end
    bd.view_names = function()
      return { "inbox", "open", "closed", "all" }
    end
    bd.list = function(filters)
      list_calls[#list_calls + 1] = filters and vim.deepcopy(filters) or nil
      return {}
    end
    bd.query = function(expr)
      query_calls[#query_calls + 1] = expr
      return {}
    end
    require("chaplet.refresh").mark_fetch = function(bufnr)
      marks[#marks + 1] = bufnr
    end
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message, level }
    end
  end)

  after_each(function()
    local bufnr = vim.fn.bufnr(list.BUFFER_NAME)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    bd.list = saved_list
    bd.query = saved_query
    bd.view_filters = saved_view_filters
    bd.view_names = saved_view_names
    require("chaplet.refresh").mark_fetch = saved_mark_fetch
    vim.notify = saved_notify
    vim.ui.select = saved_select
    config.setup()
  end)

  it("exports inbox as the default view and opens it", function()
    assert.equals("inbox", list.DEFAULT_VIEW)
    local bufnr = list.open()

    assert.equals("inbox", list.current_view(bufnr))
    assert.equals(1, #query_calls)
    assert.same({ "status=deferred" }, query_calls)
    assert.equals(bufnr, vim.api.nvim_get_current_buf())
  end)

  it("fetches all views with list and filtered views with query", function()
    assert.same({}, list.fetch("all", {}))
    assert.same({}, list.fetch("open", { type = "task", label = "human" }))

    assert.same({ { all = true } }, list_calls)
    assert.same({ "status=open AND type=task AND label=human" }, query_calls)
  end)

  it("sets and clears buffer filters server-side", function()
    local bufnr = list.set_view("all")
    list.set_filters(bufnr, { type = "task", label = "" })

    assert.same({ type = "task" }, list.filters(bufnr))
    assert.same({ { all = true }, { all = true, type = "task" } }, list_calls)
    assert.same({}, query_calls)

    list.set_filters(bufnr, { type = "", label = "" })
    assert.same({}, list.filters(bufnr))
    assert.same({
      { all = true },
      { all = true, type = "task" },
      { all = true },
    }, list_calls)
  end)

  it("marks one fetch before displaying and reuses one buffer across switches", function()
    local events = {}
    local mark = require("chaplet.refresh").mark_fetch
    require("chaplet.refresh").mark_fetch = function(bufnr)
      events[#events + 1] = "mark"
      mark(bufnr)
    end
    local display = vim.api.nvim_set_current_buf
    vim.api.nvim_set_current_buf = function(bufnr)
      events[#events + 1] = "display"
      return display(bufnr)
    end

    local first = list.set_view("open")
    assert.equals("open", list.current_view(first))
    local second = list.set_view("closed")
    assert.equals("closed", list.current_view(second))
    local third = list.set_view("all")
    assert.equals("all", list.current_view(third))
    vim.api.nvim_set_current_buf = display

    assert.equals(first, second)
    assert.equals(second, third)
    assert.same({ "mark", "display", "mark", "display", "mark", "display" }, events)
    assert.equals(3, #marks)
  end)

  it("leaves the current view unchanged for unknown or cancelled switches", function()
    local bufnr = list.set_view("open")
    list.set_view("missing")
    assert.equals("open", list.current_view(bufnr))
    assert.same({ { "chaplet: unknown view missing", vim.log.levels.ERROR } }, notifications)

    vim.ui.select = function(_, _, callback)
      callback(nil)
    end
    list.switch_view(bufnr)
    assert.equals("open", list.current_view(bufnr))
  end)
end)
