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

local function notify_missing_id()
  vim.notify("chaplet: no bead at point", vim.log.levels.ERROR)
end

local function with_id(id, fn)
  if type(id) ~= "string" or id == "" then
    notify_missing_id()
    return
  end
  fn(id)
end

local function prompt(opts, fn)
  vim.ui.input(opts, function(value)
    if value ~= nil then
      fn(value)
    end
  end)
end

local function finish()
  require("chaplet.refresh").refresh_all()
end

local function write(id, fn)
  with_id(id, function(valid_id)
    fn(require("chaplet.bd"), valid_id)
    finish()
  end)
end

function M.approve(id)
  write(id, function(bd, valid_id)
    bd.undefer(valid_id)
    bd.label_remove(valid_id, "staged")
  end)
end

function M.reject(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Reject feedback: " }, function(feedback)
      local bd = require("chaplet.bd")
      bd.comment(valid_id, "rejected: " .. feedback)
      finish()
    end)
  end)
end

function M.comment(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Comment: " }, function(text)
      require("chaplet.bd").comment(valid_id, text)
      finish()
    end)
  end)
end

function M.edit_design(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Design: " }, function(design)
      require("chaplet.bd").update_design(valid_id, design)
      finish()
    end)
  end)
end

local EDITABLE_FIELDS = { "title", "description", "type", "design", "acceptance" }

function M.edit_field(id)
  with_id(id, function(valid_id)
    local bd = require("chaplet.bd")
    local bead = bd.show(valid_id) or {}
    vim.ui.select(EDITABLE_FIELDS, { prompt = "Field: " }, function(field)
      if field == nil then
        return
      end
      local value = bead[field]
      if field == "type" and value == nil then
        value = bead.issue_type
      end
      prompt({ prompt = field .. ": ", default = value or "" }, function(new_value)
        bd.update(valid_id, field, new_value)
        finish()
      end)
    end)
  end)
end

function M.assign(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Assignee (blank = unassign): " }, function(assignee)
      require("chaplet.bd").assign(valid_id, assignee)
      finish()
    end)
  end)
end

function M.set_priority(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Priority (0-4): " }, function(priority)
      if not vim.tbl_contains({ "0", "1", "2", "3", "4" }, priority) then
        vim.notify("chaplet: priority must be 0–4", vim.log.levels.ERROR)
        return
      end
      require("chaplet.bd").priority(valid_id, priority)
      finish()
    end)
  end)
end

function M.add_label(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Add label: " }, function(label)
      require("chaplet.bd").label(valid_id, label)
      finish()
    end)
  end)
end

function M.remove_label(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Remove label: " }, function(label)
      require("chaplet.bd").label_remove(valid_id, label)
      finish()
    end)
  end)
end

function M.add_dependency(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Depends on: " }, function(depends_on)
      require("chaplet.bd").dependency_add(valid_id, depends_on)
      finish()
    end)
  end)
end

function M.remove_dependency(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Remove dependency: " }, function(depends_on)
      require("chaplet.bd").dependency_remove(valid_id, depends_on)
      finish()
    end)
  end)
end

function M.claim(id)
  write(id, function(bd, valid_id)
    bd.claim(valid_id)
  end)
end

function M.defer(id)
  write(id, function(bd, valid_id)
    bd.defer(valid_id)
  end)
end

local function prompt_reason(id, prompt_text, fn)
  with_id(id, function(valid_id)
    prompt({ prompt = prompt_text }, function(reason)
      fn(require("chaplet.bd"), valid_id, reason)
      finish()
    end)
  end)
end

function M.close(id)
  prompt_reason(id, "Close reason (optional): ", function(bd, valid_id, reason)
    bd.close(valid_id, reason)
  end)
end

function M.reopen(id)
  prompt_reason(id, "Reopen reason (optional): ", function(bd, valid_id, reason)
    bd.reopen(valid_id, reason)
  end)
end

local function confirmed_relation(id, prompt_text, question, fn)
  with_id(id, function(valid_id)
    prompt({ prompt = prompt_text }, function(other_id)
      if vim.fn.confirm(string.format(question, valid_id, other_id), "&Yes\\n&No", 2) ~= 1 then
        return
      end
      fn(require("chaplet.bd"), valid_id, other_id)
      finish()
    end)
  end)
end

function M.duplicate(id)
  confirmed_relation(id, "Canonical bead: ", "Mark %s duplicate of %s?", function(bd, valid_id, canonical)
    bd.duplicate(valid_id, canonical)
  end)
end

function M.supersede(id)
  confirmed_relation(id, "Replacement bead: ", "Mark %s superseded by %s?", function(bd, valid_id, replacement)
    bd.supersede(valid_id, replacement)
  end)
end

function M.human_respond(id)
  with_id(id, function(valid_id)
    prompt({ prompt = "Response: " }, function(response)
      require("chaplet.bd").human_respond(valid_id, response)
      finish()
    end)
  end)
end

function M.human_dismiss(id)
  prompt_reason(id, "Dismiss reason (optional): ", function(bd, valid_id, reason)
    bd.human_dismiss(valid_id, reason)
  end)
end

function M.new()
  prompt({ prompt = "Title: " }, function(title)
    prompt({ prompt = "Type (task/bug/feature/epic): " }, function(issue_type)
      prompt({ prompt = "Description: " }, function(description)
        require("chaplet.bd").create(title, issue_type, description)
        finish()
      end)
    end)
  end)
end

return M
