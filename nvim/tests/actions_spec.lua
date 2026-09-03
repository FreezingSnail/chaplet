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
