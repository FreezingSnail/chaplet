local list = require("chaplet.list")
local bd = require("chaplet.bd")
local hl = require("chaplet.hl")
local util = require("chaplet.util")

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
