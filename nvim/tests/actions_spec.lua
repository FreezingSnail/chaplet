local actions = require("chaplet.actions")

describe("chaplet.actions", function()
  local expected_spec = {
    { action = "approve", key = "a", label = "approve", group = "Lifecycle" },
    { action = "reject", key = "r", label = "reject", group = "Lifecycle" },
    { action = "claim", key = "C", label = "claim", group = "Lifecycle" },
    { action = "assign", key = "A", label = "assign", group = "Lifecycle" },
    { action = "close", key = "x", label = "close", group = "Lifecycle" },
    { action = "reopen", key = "o", label = "reopen", group = "Lifecycle" },
    { action = "duplicate", key = "=", label = "duplicate", group = "Lifecycle" },
    { action = "supersede", key = "S", label = "supersede", group = "Lifecycle" },
    { action = "comment", key = "c", label = "comment", group = "Edit" },
    { action = "edit-design", key = "e", label = "edit design", group = "Edit" },
    { action = "edit-field", key = "E", label = "edit field", group = "Edit" },
    { action = "priority", key = "p", label = "priority", group = "Edit" },
    { action = "label-add", key = "l", label = "add label", group = "Edit" },
    { action = "label-remove", key = "L", label = "remove label", group = "Edit" },
    { action = "dependency-add", key = "d", label = "add dependency", group = "Edit" },
    { action = "dependency-remove", key = "D", label = "remove dependency", group = "Edit" },
    { action = "defer", key = "f", label = "defer", group = "Edit" },
    { action = "new", key = "n", label = "new bead", group = "Edit" },
    { action = "human-respond", key = "h", label = "respond + close", group = "Human" },
    { action = "human-dismiss", key = "H", label = "dismiss", group = "Human" },
    { action = "refresh", key = "g", label = "refresh", group = "General" },
    { action = "view", key = "v", label = "switch view", group = "General" },
  }

  it("exposes the ordered action specification", function()
    assert.same(expected_spec, actions.SPEC)

    local keys = {}
    for _, spec in ipairs(actions.SPEC) do
      assert.is_nil(keys[spec.key])
      keys[spec.key] = true
      assert.is_not.equals("graph", spec.action)
    end
  end)

  describe("visibility", function()
    local states = { "open", "in_progress", "blocked", "deferred", "closed", nil }
    local universal = {
      "comment", "edit-design", "edit-field", "new", "assign", "priority",
      "label-add", "label-remove", "dependency-add", "dependency-remove",
      "refresh", "view",
    }
    local non_closed = { "claim", "defer", "close", "duplicate", "supersede" }

    local function expected(state, staged, human)
      local visible = {}
      for _, spec in ipairs(expected_spec) do
        local action = spec.action
        local is_visible = false
        for _, universal_action in ipairs(universal) do
          if action == universal_action then
            is_visible = true
          end
        end
        if state == "closed" then
          is_visible = is_visible or action == "reopen"
        else
          for _, lifecycle_action in ipairs(non_closed) do
            if action == lifecycle_action then
              is_visible = true
            end
          end
        end
        if state == "deferred" then
          is_visible = is_visible or action == "approve"
          is_visible = is_visible or (staged and action == "reject")
        end
        if human then
          is_visible = is_visible or action == "human-respond" or action == "human-dismiss"
        end
        if is_visible then
          table.insert(visible, action)
        end
      end
      return visible
    end

    for _, state in ipairs(states) do
      for _, staged in ipairs({ true, false }) do
        for _, human in ipairs({ true, false }) do
          it(string.format("state=%s staged=%s human=%s", tostring(state), tostring(staged), tostring(human)), function()
            local context = { state = state, staged = staged, human = human }
            assert.same(expected(state, staged, human), actions.for_state(state, staged, human))
            for _, spec in ipairs(expected_spec) do
              local listed = false
              for _, action in ipairs(actions.for_state(state, staged, human)) do
                if action == spec.action then
                  listed = true
                end
              end
              assert.equals(listed, actions.visible(spec.action, context))
            end
          end)
        end
      end
    end

    it("defaults a missing context to the non-closed lifecycle set", function()
      assert.same(actions.for_state(nil, false, false), actions.for_state(nil))
      assert.is_true(actions.visible("claim"))
      assert.is_false(actions.visible("reopen"))
    end)

    it("treats unknown states as non-closed", function()
      assert.same(actions.for_state("unknown", false, false), actions.for_state("open", false, false))
    end)
  end)
end)


describe("chaplet.actions write commands", function()
  local saved_bd
  local saved_refresh
  local saved_input
  local saved_select
  local saved_confirm
  local saved_notify
  local calls
  local answers
  local selected
  local confirmed
  local notifications
  local last_input_opts

  local function record(name)
    return function(...)
      local args = { ... }
      table.insert(calls, { name, unpack(args) })
    end
  end

  local function expect_calls(expected)
    assert.same(expected, calls)
    assert.equals(1, calls[#calls][1] == "refresh" and 1 or 0)
  end

  before_each(function()
    saved_bd = package.loaded["chaplet.bd"]
    saved_refresh = package.loaded["chaplet.refresh"]
    saved_input = vim.ui.input
    saved_select = vim.ui.select
    saved_confirm = vim.fn.confirm
    saved_notify = vim.notify
    calls = {}
    answers = {}
    selected = nil
    confirmed = 1
    notifications = {}
    last_input_opts = nil

    package.loaded["chaplet.bd"] = {
      undefer = record("undefer"),
      label_remove = record("label_remove"),
      comment = record("comment"),
      update_design = record("update_design"),
      show = function(id)
        table.insert(calls, { "show", id })
        return { title = "Current title", issue_type = "bug" }
      end,
      update = record("update"),
      assign = record("assign"),
      priority = record("priority"),
      label = record("label"),
      dependency_add = record("dependency_add"),
      dependency_remove = record("dependency_remove"),
      claim = record("claim"),
      defer = record("defer"),
      close = record("close"),
      reopen = record("reopen"),
      duplicate = record("duplicate"),
      supersede = record("supersede"),
      human_respond = record("human_respond"),
      human_dismiss = record("human_dismiss"),
      create = record("create"),
    }
    package.loaded["chaplet.refresh"] = {
      refresh_all = record("refresh"),
    }
    vim.ui.input = function(opts, callback)
      last_input_opts = opts
      callback(table.remove(answers, 1))
    end
    vim.ui.select = function(_, _, callback)
      callback(selected)
    end
    vim.fn.confirm = function()
      return confirmed
    end
    vim.notify = function(message, level)
      table.insert(notifications, { message, level })
    end
  end)

  after_each(function()
    package.loaded["chaplet.bd"] = saved_bd
    package.loaded["chaplet.refresh"] = saved_refresh
    vim.ui.input = saved_input
    vim.ui.select = saved_select
    vim.fn.confirm = saved_confirm
    vim.notify = saved_notify
  end)

  it("approves in order and refreshes once", function()
    actions.approve("bd-1")
    expect_calls({ { "undefer", "bd-1" }, { "label_remove", "bd-1", "staged" }, { "refresh" } })
  end)

  it("rejects with a prefixed comment and does not undefer", function()
    answers = { "not ready" }
    actions.reject("bd-1")
    expect_calls({ { "comment", "bd-1", "rejected: not ready" }, { "refresh" } })
  end)

  it("runs prompted field, metadata, dependency, and lifecycle writes", function()
    answers = { "hello" }
    actions.comment("bd-1")
    assert.same({ { "comment", "bd-1", "hello" }, { "refresh" } }, calls)

    calls = {}
    answers = { "new design" }
    actions.edit_design("bd-1")
    assert.same({ { "update_design", "bd-1", "new design" }, { "refresh" } }, calls)

    calls = {}
    answers = { "alice" }
    actions.assign("bd-1")
    assert.same({ { "assign", "bd-1", "alice" }, { "refresh" } }, calls)

    calls = {}
    answers = { "human" }
    actions.add_label("bd-1")
    assert.same({ { "label", "bd-1", "human" }, { "refresh" } }, calls)

    calls = {}
    answers = { "human" }
    actions.remove_label("bd-1")
    assert.same({ { "label_remove", "bd-1", "human" }, { "refresh" } }, calls)

    calls = {}
    answers = { "bd-2" }
    actions.add_dependency("bd-1")
    assert.same({ { "dependency_add", "bd-1", "bd-2" }, { "refresh" } }, calls)

    calls = {}
    answers = { "bd-2" }
    actions.remove_dependency("bd-1")
    assert.same({ { "dependency_remove", "bd-1", "bd-2" }, { "refresh" } }, calls)

    calls = {}
    actions.claim("bd-1")
    assert.same({ { "claim", "bd-1" }, { "refresh" } }, calls)

    calls = {}
    actions.defer("bd-1")
    assert.same({ { "defer", "bd-1" }, { "refresh" } }, calls)
  end)

  it("accepts blank optional reasons and blank assignees", function()
    answers = { "" }
    actions.assign("bd-1")
    assert.same({ { "assign", "bd-1", "" }, { "refresh" } }, calls)

    calls = {}
    answers = { "" }
    actions.close("bd-1")
    assert.same({ { "close", "bd-1", "" }, { "refresh" } }, calls)

    calls = {}
    answers = { "" }
    actions.reopen("bd-1")
    assert.same({ { "reopen", "bd-1", "" }, { "refresh" } }, calls)

    calls = {}
    answers = { "" }
    actions.human_dismiss("bd-1")
    assert.same({ { "human_dismiss", "bd-1", "" }, { "refresh" } }, calls)
  end)

  it("validates priority before writing", function()
    answers = { "5" }
    actions.set_priority("bd-1")
    assert.same({}, calls)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1][2])

    answers = { "3" }
    actions.set_priority("bd-1")
    assert.same({ { "priority", "bd-1", "3" }, { "refresh" } }, calls)
  end)

  it("edits a selected field using the current value as default", function()
    selected = "type"
    answers = { "feature" }
    actions.edit_field("bd-1")
    assert.equals("bug", last_input_opts.default)
    assert.same({ { "show", "bd-1" }, { "update", "bd-1", "type", "feature" }, { "refresh" } }, calls)
  end)

  it("requires confirmation for duplicate and supersede", function()
    answers = { "bd-2" }
    confirmed = 2
    actions.duplicate("bd-1")
    assert.same({}, calls)

    answers = { "bd-2" }
    confirmed = 1
    actions.duplicate("bd-1")
    assert.same({ { "duplicate", "bd-1", "bd-2" }, { "refresh" } }, calls)

    calls = {}
    answers = { "bd-3" }
    actions.supersede("bd-1")
    assert.same({ { "supersede", "bd-1", "bd-3" }, { "refresh" } }, calls)
  end)

  it("responds, creates, and refreshes completed writes", function()
    answers = { "answer" }
    actions.human_respond("bd-1")
    assert.same({ { "human_respond", "bd-1", "answer" }, { "refresh" } }, calls)

    calls = {}
    answers = { "Title", "task", "Description" }
    actions.new()
    assert.same({ { "create", "Title", "task", "Description" }, { "refresh" } }, calls)
  end)

  it("does not write or refresh after prompt cancellation", function()
    answers = { nil }
    actions.comment("bd-1")
    assert.same({}, calls)

    answers = { "bd-2" }
    confirmed = 2
    actions.duplicate("bd-1")
    assert.same({}, calls)

    selected = nil
    actions.edit_field("bd-1")
    assert.same({ { "show", "bd-1" } }, calls)
  end)

  it("rejects missing, empty, and non-string ids", function()
    actions.comment(nil)
    actions.comment("")
    actions.comment(42)
    assert.same({}, calls)
    assert.equals(3, #notifications)
  end)
end)
