local util = require("chaplet.util")

describe("chaplet.util display cells", function()
  it("measures display width through Neovim", function()
    for _, value in ipairs({ "ascii", "●", "·", "✔", "日本語" }) do
      assert.equals(vim.fn.strdisplaywidth(value), util.width(value))
    end
  end)

  it("truncates at display-cell boundaries", function()
    assert.equals("ab", util.truncate("abcd", 2))

    local glyphs = { "●", "·", "✔" }
    for _, glyph in ipairs(glyphs) do
      local glyph_width = util.width(glyph)
      assert.equals(glyph, util.truncate(glyph .. "x", glyph_width))
      if glyph_width > 0 then
        assert.equals("", util.truncate(glyph, glyph_width - 1))
      end
    end
    assert.equals("a●", util.truncate("a●b", util.width("a●")))
  end)

  it("never emits a partial UTF-8 sequence", function()
    local value = "a●·✔"
    for width = 0, vim.fn.strdisplaywidth(value) do
      local truncated = util.truncate(value, width)
      local character_count = vim.str_utfindex(truncated)
      assert.equals(truncated, vim.fn.strcharpart(value, 0, character_count))
      assert.is_true(util.width(truncated) <= width)
    end
  end)

  it("pads narrow values and leaves wider values unchanged", function()
    assert.equals("a   ", util.pad("a", 4))
    local glyph = "●"
    assert.equals(glyph .. string.rep(" ", 3 - util.width(glyph)), util.pad(glyph, 3))
    assert.equals("abcd", util.pad("abcd", 2))
  end)

  it("truncates and pads to exactly the requested display width", function()
    for _, value in ipairs({ "", "ascii", "●", "·", "✔", "a●·✔", "日本語" }) do
      for target_width = 0, 8 do
        local cell = util.cell(value, target_width)
        assert.equals(target_width, util.width(cell), value .. " at " .. target_width)
      end
    end
    assert.equals(4, util.width(util.cell(nil, 4)))
  end)
end)

describe("chaplet.util.deep_equal", function()
  it("compares nested tables by value", function()
    assert.is_true(util.deep_equal({ 1, { name = "bead", labels = { "human" } } }, {
      1,
      { name = "bead", labels = { "human" } },
    }))
    assert.is_true(util.deep_equal({}, {}))
    assert.is_true(util.deep_equal(nil, nil))
  end)

  it("rejects differing key sets in either direction", function()
    assert.is_false(util.deep_equal({ id = "bd-1" }, { id = "bd-1", status = "open" }))
    assert.is_false(util.deep_equal({ id = "bd-1", status = "open" }, { id = "bd-1" }))
    assert.is_false(util.deep_equal({ nested = { id = "bd-1" } }, { nested = {} }))
    assert.is_false(util.deep_equal({ 1, 2 }, { 1 }))
  end)

  it("rejects differing values and types", function()
    assert.is_false(util.deep_equal({ priority = 1 }, { priority = 2 }))
    assert.is_false(util.deep_equal({ priority = 1 }, { priority = "1" }))
    assert.is_false(util.deep_equal({ value = "1" }, { value = 1 }))
    assert.is_false(util.deep_equal({}, ""))
    assert.is_false(util.deep_equal(nil, {}))
  end)
end)
