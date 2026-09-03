local config = require("chaplet.config")
local hl = require("chaplet.hl")
local text = require("chaplet.graph.text")
local util = require("chaplet.util")

local function span_text(line, span)
  return line:sub(span.start_col + 1, span.end_col)
end

describe("chaplet.graph.text node_line", function()
  before_each(function()
    config.setup({})
  end)

  it("keeps focused and unfocused prefixes to one cell", function()
    local focused = text.node_line({ id = "bd-1", title = "Task" }, "bd-1")
    local unfocused = text.node_line({ id = "bd-1", title = "Task" }, nil)

    assert.equals("▶[bd-1] Task", focused)
    assert.equals(" [bd-1] Task", unfocused)
    assert.equals(1, vim.fn.strdisplaywidth(focused:sub(1, 3)))
    assert.equals(focused:sub(4), unfocused:sub(2))
  end)

  it("truncates titles to twenty display cells", function()
    local title = "日本語" .. string.rep("x", 30)
    local truncated = text.truncate(title)

    assert.equals(text.TITLE_MAX, util.width(truncated))
    assert.equals(util.truncate(title, text.TITLE_MAX - 1) .. "…", truncated)
    assert.equals(" [bd-1] " .. truncated,
      text.node_line({ id = "bd-1", title = title }, nil))
  end)

  it("adds a ghost suffix", function()
    local line = text.node_line({ id = "missing", title = "closed", ghost = true }, nil)
    assert.equals(" [missing] closed ~", line)
    assert.equals(text.GHOST_SUFFIX, line:sub(-#text.GHOST_SUFFIX))
  end)

  it("omits unknown and absent states", function()
    local unknown, unknown_spans = text.node_line({ id = "bd-1", title = "Task", state = "review" }, nil)
    local absent, absent_spans = text.node_line({ id = "bd-1", title = "Task" }, nil)

    assert.equals(" [bd-1] Task", unknown)
    assert.equals(" [bd-1] Task", absent)
    assert.equals(1, #unknown_spans)
    assert.equals(1, #absent_spans)
  end)

  it("uses staged highlighting for deferred nodes", function()
    local line, spans = text.node_line({
      id = "bd-1",
      title = "Review",
      state = "deferred",
      staged = true,
    }, nil)

    assert.equals(" [bd-1] Review deferred", line)
    assert.equals("ChapletStaged", spans[2].group)
    assert.equals(hl.state_group("deferred"), hl.STATE_GROUPS[1])
  end)

  it("returns byte spans that slice back to id and state", function()
    local line, spans = text.node_line({
      id = "日本",
      title = "Review",
      state = "open",
    }, nil)

    assert.equals(2, #spans)
    assert.equals("日本", span_text(line, spans[1]))
    assert.equals("open", span_text(line, spans[2]))
    assert.equals("ChapletId", spans[1].group)
    assert.equals(hl.state_group("open"), spans[2].group)
    assert.equals(2, spans[1].start_col)
    assert.is_true(spans[1].start_col < spans[1].end_col)
    assert.is_true(spans[1].end_col <= spans[2].start_col)
  end)
end)

describe("chaplet.graph.text gutter", function()
  local function graph(items)
    local edges = {}
    for _, item in ipairs(items) do
      for _, dependency in ipairs(item.deps or {}) do
        edges[#edges + 1] = { from = item.id, to = dependency }
      end
    end
    return items, edges
  end

  local function box_column(line)
    local column = assert(line:find("%[", 1, false))
    return util.width(line:sub(1, column - 1))
  end

  before_each(function()
    config.setup({})
  end)

  it("renders a chain with one node per line and no leaf lane", function()
    local items, edges = graph({
      { id = "a", title = "Alpha", deps = {} },
      { id = "b", title = "Beta", deps = { "a" } },
      { id = "c", title = "Gamma", deps = { "b" } },
    })

    assert.equals(table.concat({
      "  [a] Alpha",
      "└  [b] Beta",
      "└  [c] Gamma",
    }, "\n"), text.gutter(items, edges))
  end)

  it("renders a diamond sink once with a merge bus", function()
    local items, edges = graph({
      { id = "a", title = "A", deps = {} },
      { id = "b", title = "B", deps = { "a" } },
      { id = "c", title = "C", deps = { "a" } },
      { id = "d", title = "D", deps = { "b", "c" } },
    })

    local canvas = text.canvas(items, edges)
    assert.equals(table.concat({
      "  [a] A",
      "└  [b] B",
      "└│  [c] C",
      "└┐  [d] D",
    }, "\n"), canvas)
    assert.equals(1, select(2, canvas:gsub("%[d%]", "")))
  end)

  it("reuses a freed dependency lane before appending", function()
    local items, edges = graph({
      { id = "a", title = "A", deps = {} },
      { id = "c", title = "C", deps = {} },
      { id = "b", title = "B", deps = { "a" } },
      { id = "d", title = "D", deps = { "c" } },
      { id = "e", title = "E", deps = { "b" } },
    })

    assert.equals(table.concat({
      "  [a] A",
      "│  [c] C",
      "└│  [b] B",
      "│└  [d] D",
      "└  [e] E",
    }, "\n"), text.gutter(items, edges))
  end)

  it("caps drawn lanes without losing hidden lane state", function()
    local items, edges = graph({
      { id = "a", title = "A", deps = {} },
      { id = "b", title = "B", deps = { "a" } },
      { id = "c", title = "C", deps = { "a" } },
      { id = "d", title = "D", deps = { "a" } },
      { id = "e", title = "E", deps = { "b", "c", "d" } },
    })
    config.setup({ graph = { text_lane_max = 2 } })

    local lines = vim.split(text.canvas(items, edges), "\n", { plain = true })
    assert.same({
      "  [a] A",
      "└  [b] B",
      "└│  [c] C",
      "└│  [d] D",
      "└─  [e] E",
    }, lines)
    for _, line in ipairs(lines) do
      assert.is_true(util.width(line:match("^%S*") or "") <= 2)
    end
  end)

  it("right-pads gutters to align node boxes when enabled", function()
    local items, edges = graph({
      { id = "a", title = "A", deps = {} },
      { id = "b", title = "B", deps = { "a" } },
      { id = "c", title = "C", deps = { "a" } },
      { id = "d", title = "D", deps = { "b", "c" } },
    })
    local unaligned = vim.split(text.canvas(items, edges), "\n", { plain = true })
    config.setup({ graph = { text_align = true } })
    local aligned = vim.split(text.canvas(items, edges), "\n", { plain = true })

    assert.is_true(box_column(unaligned[1]) < box_column(unaligned[4]))
    assert.equals(box_column(aligned[1]), box_column(aligned[2]))
    assert.equals(box_column(aligned[2]), box_column(aligned[3]))
    assert.equals(box_column(aligned[3]), box_column(aligned[4]))
  end)

  it("returns empty output for an empty graph", function()
    assert.equals("", text.gutter({}))
    assert.equals("", text.canvas({}))
    local lines, spans = text.lines({})
    assert.same({}, lines)
    assert.same({}, spans)
  end)

  it("shifts node spans past the gutter and separator", function()
    local items, edges = graph({
      { id = "root", title = "Root", deps = {} },
      { id = "日本", title = "Child", state = "open", deps = { "root" } },
    })
    local lines, spans = text.lines(items, edges)
    local child = lines[2]
    local id_span = spans[2][1]
    local state_span = spans[2][2]

    assert.equals("日本", child:sub(id_span.start_col + 1, id_span.end_col))
    assert.equals("open", child:sub(state_span.start_col + 1, state_span.end_col))
    assert.equals("ChapletId", id_span.group)
    assert.equals(6, id_span.start_col)
  end)
end)
