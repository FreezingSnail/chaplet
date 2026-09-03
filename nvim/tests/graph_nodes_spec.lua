local nodes = require("chaplet.graph.nodes")
local util = require("chaplet.util")

describe("nodes", function()
  it("converts normalized beads and computes staged state", function()
    assert.same({
      id = "bd-1",
      title = "Review",
      state = "deferred",
      staged = true,
      type = "task",
      priority = 2,
      deps = { "bd-0" },
    }, nodes.node({
      id = "bd-1",
      title = "Review",
      status = "deferred",
      labels = { "staged", "other" },
      issue_type = "task",
      priority = 2,
      dependencies = { "bd-0" },
    }))
    assert.is_false(nodes.node({ status = "deferred", labels = { "other" } }).staged)
    assert.is_false(nodes.node({ status = "open", labels = { "staged" } }).staged)
  end)

  it("defaults missing dependencies to an empty table", function()
    assert.same({}, nodes.node({ id = "bd-1", title = "No deps" }).deps)
    assert.equals("bd-1", nodes.from_beads({ { id = "bd-1", title = "One" } })[1].id)
  end)

  it("truncates titles to the configured display width", function()
    local title = "日本語" .. string.rep("x", 30)
    local truncated = nodes.truncate(title, nodes.TITLE_MAX)

    assert.equals(nodes.TITLE_MAX, util.width(truncated))
    assert.equals(util.truncate(title, nodes.TITLE_MAX - 1) .. "…", truncated)
    assert.equals(truncated, nodes.node({ title = title }).title)
    assert.equals(title, nodes.truncate(title, util.width(title)))
  end)

  it("creates closed ghost nodes with a bounded title", function()
    local ghost = nodes.ghost("missing-id")

    assert.same({
      id = "missing-id",
      title = "missing-id (closed)",
      state = "closed",
      deps = {},
      ghost = true,
    }, ghost)
    assert.equals(nodes.TITLE_MAX, util.width(nodes.ghost(string.rep("x", 40)).title))
  end)

  it("appends each unknown dependency once after real nodes", function()
    local real = nodes.from_beads({
      { id = "a", title = "A", dependencies = { "missing", "b" } },
      { id = "b", title = "B", dependencies = { "missing", "other" } },
    })
    local all = nodes.add_ghosts(real)

    assert.same({ "a", "b", "missing", "other" }, vim.tbl_map(function(item)
      return item.id
    end, all))
    assert.is_true(all[3].ghost)
    assert.equals("closed", all[3].state)
    assert.is_true(all[4].ghost)
  end)

  it("assigns chain layers from roots", function()
    assert.same({ a = 0, b = 1, c = 2 }, nodes.layers({
      { id = "a", deps = {} },
      { id = "b", deps = { "a" } },
      { id = "c", deps = { "b" } },
    }))
  end)

  it("uses the longest path in a diamond", function()
    local layers = nodes.layers({
      { id = "a", deps = {} },
      { id = "b", deps = { "a" } },
      { id = "c", deps = { "a" } },
      { id = "d", deps = { "b", "c" } },
      { id = "e", deps = { "d", "a" } },
    })
    assert.equals(2, layers.d)
    assert.equals(3, layers.e)
  end)

  it("treats unknown dependencies as virtual roots", function()
    local layers = nodes.layers({
      { id = "a", deps = { "missing" } },
      { id = "b", deps = { "a", "ghost" } },
    })
    assert.equals(1, layers.a)
    assert.equals(2, layers.b)
    assert.is_nil(layers.missing)
    assert.is_nil(layers.ghost)
  end)

  it("starts disconnected components at zero", function()
    assert.same({ a = 0, b = 1, x = 0, y = 1 }, nodes.layers({
      { id = "a", deps = {} },
      { id = "b", deps = { "a" } },
      { id = "x", deps = {} },
      { id = "y", deps = { "x" } },
    }))
  end)

  it("assigns every node when dependencies contain a cycle", function()
    local layers = nodes.layers({
      { id = "a", deps = { "b" } },
      { id = "b", deps = { "a" } },
    })
    assert.equals(1, layers.a)
    assert.equals(2, layers.b)
  end)

  it("is invariant under input permutation", function()
    local original = {
      { id = "a", deps = {} },
      { id = "b", deps = { "a" } },
      { id = "c", deps = { "a" } },
      { id = "d", deps = { "b", "c" } },
    }
    local shuffled = { original[4], original[2], original[1], original[3] }
    assert.same(nodes.layers(original), nodes.layers(shuffled))
  end)

  describe("rows", function()
    it("sorts nodes inside ascending layer rows and defaults missing layers to zero", function()
      local a = { id = "a", deps = {} }
      local b = { id = "b", deps = { "a" } }
      local c = { id = "c", deps = { "a" } }
      local list = { c, b, a, { id = "z", deps = {} } }
      local rows = nodes.rows(list, { a = 1, b = 3, c = 3 })

      assert.same({
        { layer = 0, nodes = { list[4] } },
        { layer = 1, nodes = { a } },
        { layer = 3, nodes = { b, c } },
      }, rows)
    end)
  end)

  describe("order", function()
    it("does not mutate input while sorting by id", function()
      local first = { id = "z", deps = {} }
      local second = { id = "a", deps = {} }
      local list = { first, second }

      assert.same({ second, first }, nodes.sort_by_id(list))
      assert.same({ first, second }, list)
    end)

    it("puts dependencies before dependents in a diamond", function()
      local list = {
        { id = "d", deps = { "b", "c" } },
        { id = "c", deps = { "a" } },
        { id = "b", deps = { "a" } },
        { id = "a", deps = {} },
      }
      local ordered = nodes.order(list)

      assert.same({ "a", "b", "c", "d" }, vim.tbl_map(function(item)
        return item.id
      end, ordered))
    end)

    it("orders ghost-completed chains with the ghost first", function()
      local all = nodes.add_ghosts({
        { id = "b", deps = { "a" } },
        { id = "a", deps = { "missing" } },
      })

      assert.same({ "missing", "a", "b" }, vim.tbl_map(function(item)
        return item.id
      end, nodes.order(all)))
    end)
  end)

  describe("edges and dependents", function()
    it("includes every dependency in node and dependency order", function()
      local list = {
        { id = "b", deps = { "a", "missing" } },
        { id = "c", deps = { "a" } },
      }

      assert.same({
        { from = "b", to = "a" },
        { from = "b", to = "missing" },
        { from = "c", to = "a" },
      }, nodes.edges(list))
    end)

    it("seeds leaves and pushes dependents in reverse encounter order", function()
      local order = {
        { id = "a" },
        { id = "b" },
        { id = "c" },
        { id = "d" },
      }
      local edges = {
        { from = "b", to = "a" },
        { from = "c", to = "a" },
        { from = "d", to = "b" },
      }

      assert.same({ a = { "c", "b" }, b = { "d" }, c = {}, d = {} }, nodes.dependents(edges, order))
    end)
  end)

  describe("graph", function()
    it("returns ghost-completed nodes with matching edges", function()
      local all, edges = nodes.graph({
        { id = "b", title = "B", dependencies = { "a" } },
        { id = "a", title = "A", dependencies = { "missing" } },
      })

      assert.same({ "b", "a", "missing" }, vim.tbl_map(function(item)
        return item.id
      end, all))
      assert.is_true(all[3].ghost)
      assert.same({
        { from = "b", to = "a" },
        { from = "a", to = "missing" },
      }, edges)
    end)
  end)
end)
