local hl = require("chaplet.hl")

local function color(name, attribute)
  return string.format("#%06x", vim.api.nvim_get_hl(0, { name = name })[attribute])
end

describe("chaplet.hl", function()
  before_each(function()
    vim.o.background = "dark"
    hl.setup()
  end)

  it("applies every palette group for dark and light backgrounds", function()
    for name, expected in pairs(hl.PALETTE.dark) do
      assert.equals(expected, color(name, "fg"))
    end

    vim.o.background = "light"
    hl.apply()
    for name, expected in pairs(hl.PALETTE.light) do
      assert.equals(expected, color(name, "fg"))
      assert.not_equals(hl.PALETTE.dark[name], expected)
    end
  end)

  it("gives state groups blended backgrounds", function()
    for _, name in ipairs(hl.STATE_GROUPS) do
      assert.not_equals(color(name, "fg"), color(name, "bg"))
    end
  end)

  it("blends channels by alpha", function()
    assert.equals("#800000", hl.blend("#ff0000", "#000000", 0.5))
    assert.equals("#46403d", hl.blend("#d19a66", "#282c34", 0.18))
  end)

  it("reapplies highlights after ColorScheme", function()
    vim.api.nvim_set_hl(0, "ChapletStateOpen", { fg = "#000000" })
    vim.cmd("doautocmd ColorScheme")

    assert.equals(hl.PALETTE.dark.ChapletStateOpen, color("ChapletStateOpen", "fg"))
  end)

  it("keeps one ColorScheme autocmd across repeated setup", function()
    hl.setup()
    hl.setup()

    local autocmds = vim.api.nvim_get_autocmds({ group = "ChapletHl", event = "ColorScheme" })
    assert.equals(1, #autocmds)
  end)

  it("maps states, priorities, and types", function()
    local states = {
      deferred = "ChapletStateDeferred",
      in_progress = "ChapletStateInProgress",
      blocked = "ChapletStateBlocked",
      closed = "ChapletStateClosed",
      open = "ChapletStateOpen",
    }
    local priorities = {
      [2] = "ChapletPriorityHigh",
      [1] = "ChapletPriorityMedium",
      [0] = "ChapletPriorityLow",
    }
    local types = {
      epic = "ChapletTypeEpic",
      task = "ChapletTypeTask",
      bug = "ChapletTypeBug",
    }

    for value, group in pairs(states) do
      assert.equals(group, hl.state_group(value))
    end
    for value, group in pairs(priorities) do
      assert.equals(group, hl.priority_group(value))
      assert.equals(group, hl.priority_group(tostring(value)))
    end
    for value, group in pairs(types) do
      assert.equals(group, hl.type_group(value))
    end

    assert.is_nil(hl.state_group("review"))
    assert.is_nil(hl.priority_group("high"))
    assert.is_nil(hl.type_group("feature"))
  end)

  it("returns the effective state color as hex", function()
    assert.matches("^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$", hl.state_color("open"))
    assert.is_nil(hl.state_color("review"))
  end)
end)
