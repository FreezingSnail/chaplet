local M = {}

M.SPEC = {
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

local function lifecycle_visible(action, state)
  if state == "closed" then
    return action == "reopen"
  end
  return action == "claim"
    or action == "defer"
    or action == "close"
    or action == "duplicate"
    or action == "supersede"
end

local function action_visible(action, ctx)
  local state = ctx.state
  local universal = {
    comment = true,
    ["edit-design"] = true,
    ["edit-field"] = true,
    new = true,
    assign = true,
    priority = true,
    ["label-add"] = true,
    ["label-remove"] = true,
    ["dependency-add"] = true,
    ["dependency-remove"] = true,
    refresh = true,
    view = true,
  }

  if universal[action] then
    return true
  end
  if lifecycle_visible(action, state) then
    return true
  end
  if state == "deferred" and (action == "approve" or (action == "reject" and ctx.staged)) then
    return true
  end
  return (action == "human-respond" or action == "human-dismiss") and ctx.human == true
end

function M.visible(action, ctx)
  ctx = ctx or {}
  return action_visible(action, ctx) == true
end

function M.for_state(state, staged, human)
  local ctx = { state = state, staged = staged, human = human }
  local visible = {}
  for _, spec in ipairs(M.SPEC) do
    if M.visible(spec.action, ctx) then
      table.insert(visible, spec.action)
    end
  end
  return visible
end

return M
