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

M.namespace = vim.api.nvim_create_namespace("chaplet_actions")
M._context = nil
M._bufnr = nil
M._winid = nil

local function has_label(bead, label)
  for _, value in ipairs(bead.labels or {}) do
    if value == label then
      return true
    end
  end
  return false
end

function M.context(id)
  if type(id) ~= "string" or id == "" then
    return nil
  end

  local bead = require("chaplet.bd").show(id)
  if bead == nil then
    return nil
  end

  return {
    id = id,
    state = bead.status,
    staged = require("chaplet.list").staged(bead),
    human = has_label(bead, require("chaplet.bd").HUMAN_LABEL),
  }
end

function M.lines(ctx)
  local lines = {}
  local spans = {}
  local previous_group
  for _, spec in ipairs(M.SPEC) do
    if M.visible(spec.action, ctx) then
      if spec.group ~= previous_group then
        previous_group = spec.group
        lines[#lines + 1] = spec.group
        spans[#spans + 1] = {
          { col = 0, end_col = #spec.group, hl = "ChapletHeader" },
        }
      end
      local line = "  " .. spec.key .. " " .. spec.label
      lines[#lines + 1] = line
      spans[#spans + 1] = {
        { col = 2, end_col = 2 + #spec.key, hl = "ChapletId" },
      }
    end
  end
  return lines, spans
end

local function menu_dimensions(lines)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  return width, math.max(1, #lines)
end

local function menu_position(width, height)
  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  }
end

local function configure_menu_buffer(bufnr, lines, spans)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  for row, row_spans in ipairs(spans) do
    for _, span in ipairs(row_spans) do
      vim.api.nvim_buf_set_extmark(bufnr, M.namespace, row - 1, span.col, {
        end_row = row - 1,
        end_col = span.end_col,
        hl_group = span.hl,
      })
    end
  end
end

function M.dismiss()
  local winid = M._winid
  local bufnr = M._bufnr
  M._context = nil
  M._winid = nil
  M._bufnr = nil

  if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function run(action, id)
  M.dismiss()
  local handler = M.handlers[action]
  if handler ~= nil then
    handler(id)
  end
end

local function install_menu_keys(bufnr, ctx)
  for _, spec in ipairs(M.SPEC) do
    if M.visible(spec.action, ctx) then
      vim.keymap.set("n", spec.key, function()
        run(spec.action, ctx.id)
      end, { buffer = bufnr, silent = true, nowait = true })
    end
  end
  vim.keymap.set("n", "q", M.dismiss, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", M.dismiss, { buffer = bufnr, silent = true, nowait = true })
end

function M.menu(ctx)
  if ctx == nil then
    return nil, nil
  end

  M.dismiss()
  local lines, spans = M.lines(ctx)
  local bufnr = vim.api.nvim_create_buf(false, true)
  configure_menu_buffer(bufnr, lines, spans)
  local title = string.format("Bead %s (%s)", ctx.id, tostring(ctx.state))
  local width, height = menu_dimensions(lines)
  local winid = vim.api.nvim_open_win(bufnr, true, vim.tbl_extend("force", menu_position(width, height), {
    title = title,
    title_pos = "center",
  }))

  M._context = ctx
  M._bufnr = bufnr
  M._winid = winid
  install_menu_keys(bufnr, ctx)
  return bufnr, winid
end

function M.open_menu(bufnr)
  M.dismiss()
  local id = require("chaplet.list").id_at_cursor(bufnr)
  if id == nil then
    notify_missing_id()
    return nil, nil
  end

  local ctx = M.context(id)
  if ctx == nil then
    vim.notify("chaplet: no bead " .. id, vim.log.levels.ERROR)
    return nil, nil
  end
  return M.menu(ctx)
end

local function refresh_all()
  require("chaplet.refresh").refresh_all()
end

local function switch_view()
  require("chaplet.list").switch_view()
end

M.handlers = {
  approve = function(id) return M.approve(id) end,
  reject = function(id) return M.reject(id) end,
  claim = function(id) return M.claim(id) end,
  assign = function(id) return M.assign(id) end,
  close = function(id) return M.close(id) end,
  reopen = function(id) return M.reopen(id) end,
  duplicate = function(id) return M.duplicate(id) end,
  supersede = function(id) return M.supersede(id) end,
  comment = function(id) return M.comment(id) end,
  ["edit-design"] = function(id) return M.edit_design(id) end,
  ["edit-field"] = function(id) return M.edit_field(id) end,
  priority = function(id) return M.set_priority(id) end,
  ["label-add"] = function(id) return M.add_label(id) end,
  ["label-remove"] = function(id) return M.remove_label(id) end,
  ["dependency-add"] = function(id) return M.add_dependency(id) end,
  ["dependency-remove"] = function(id) return M.remove_dependency(id) end,
  defer = function(id) return M.defer(id) end,
  new = function(id) return M.new(id) end,
  ["human-respond"] = function(id) return M.human_respond(id) end,
  ["human-dismiss"] = function(id) return M.human_dismiss(id) end,
  refresh = refresh_all,
  view = switch_view,
}

return M
