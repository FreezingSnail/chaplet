local bd = require("chaplet.bd")

local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = vim.fn.fnamemodify(source, ":h")
local fixture_path = vim.fn.fnamemodify(test_dir .. "/../../test/views.json", ":p")
local fixture = vim.json.decode(table.concat(vim.fn.readfile(fixture_path), "\n"))

local function filters(filters)
  return filters or {}
end

describe("chaplet.bd views", function()
  it("matches the shared canonical view fixture", function()
    assert.same(fixture.views, bd.views)
    assert.same(vim.tbl_map(function(view)
      return view.name
    end, fixture.views), bd.view_names())

    for _, view in ipairs(fixture.views) do
      assert.same(view.filters, bd.view_filters(view.name))
    end
    assert.is_nil(bd.view_filters("missing"))
  end)

  it("translates shared filter argument cases", function()
    assert.same({}, bd.filters_to_args(nil))
    for _, case in ipairs(fixture.args) do
      assert.same(case.expect, bd.filters_to_args(filters(case.filters)))
    end
  end)

  it("translates shared filter expression cases", function()
    assert.equals("", bd.filters_to_expr(nil))
    for _, case in ipairs(fixture.expr) do
      assert.equals(case.expect, bd.filters_to_expr(filters(case.filters)))
    end
  end)

  it("rejects unknown filters", function()
    assert.has_error(function()
      bd.filters_to_args({ unknown = true })
    end, "chaplet-bd: unknown filter unknown")
    assert.has_error(function()
      bd.filters_to_expr({ unknown = true })
    end, "chaplet-bd: unknown filter unknown")
  end)
end)
