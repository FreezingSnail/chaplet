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
