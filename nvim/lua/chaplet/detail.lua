local bd = require("chaplet.bd")
local refresh = require("chaplet.refresh")
local util = require("chaplet.util")

local M = {}

M.BUFFER_NAME = "*chaplet:detail*"

local function value(field, fallback)
  if field == nil then
    return fallback or ""
  end
  return tostring(field)
end

local function render_header(bead)
  local id = value(bead.id)
  local title = value(bead.title, id)
  local labels = bead.labels
  local lines = {
    "# " .. title,
    "",
    string.format(
      "*id:* %s · *status:* %s · *priority:* %s · *type:* %s · *owner:* %s · *created:* %s",
      id,
      value(bead.status),
      value(bead.priority),
      value(bead.issue_type),
      value(bead.owner),
      value(bead.created_at)
    ),
  }

  if type(labels) == "table" and #labels > 0 then
    local rendered = {}
    for _, label in ipairs(labels) do
      rendered[#rendered + 1] = tostring(label)
    end
    lines[#lines + 1] = "*labels:* " .. table.concat(rendered, ", ")
  end

  return table.concat(lines, "\n") .. "\n"
end

local function render_section(title, body)
  if body == nil then
    return ""
  end
  body = tostring(body)
  if vim.trim(body) == "" then
    return ""
  end
  return string.format("\n## %s\n\n%s\n", title, body)
end

local function render_comments(comments)
  if type(comments) ~= "table" or #comments == 0 then
    return ""
  end

  local lines = {}
  for _, comment in ipairs(comments) do
    local author = comment.author or "unknown"
    local text = comment.text
    if text == nil then
      text = comment.body
    end
    if text == nil then
      text = ""
    end
    lines[#lines + 1] = string.format("- **%s** — %s", author, text)
  end
  return "\n## Comments\n\n" .. table.concat(lines, "\n") .. "\n"
end

function M.render(bead, comments)
  bead = bead or {}
  return render_header(bead)
    .. render_section("Description", bead.description)
    .. render_section("Design", bead.design)
    .. render_section("Acceptance", bead.acceptance)
    .. render_comments(comments)
end

local function close_window()
  util.restore_previous_buffer_or_close(vim.api.nvim_get_current_buf())
end

function M.keys(bead)
  bead = bead or {}
  local id = bead.id
  local keys = {
    { key = "q", action = close_window },
    {
      key = "g",
      action = function()
        M.populate(vim.api.nvim_get_current_buf(), id)
      end,
    },
    {
      key = "c",
      action = function()
        require("chaplet.actions").comment(id)
      end,
    },
  }

  if bead.status == "deferred" then
    keys[#keys + 1] = {
      key = "a",
      action = function()
        require("chaplet.actions").approve(id)
      end,
    }
    local staged = false
    for _, label in ipairs(bead.labels or {}) do
      if label == bd.STAGED_LABEL then
        staged = true
        break
      end
    end
    if staged then
      keys[#keys + 1] = {
        key = "r",
        action = function()
          require("chaplet.actions").reject(id)
        end,
      }
    end
  end

  return keys
end

local function clear_key(bufnr, key)
  pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", key)
end

local function install_keys(bufnr, bead)
  for _, key in ipairs({ "q", "g", "c", "a", "r" }) do
    clear_key(bufnr, key)
  end
  for _, binding in ipairs(M.keys(bead)) do
    vim.keymap.set("n", binding.key, binding.action, { buffer = bufnr, silent = true, nowait = true })
  end
end

local function set_options(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
  vim.bo[bufnr].filetype = "markdown"
end

function M.id(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local ok, id = pcall(vim.api.nvim_buf_get_var, bufnr, "chaplet_detail_id")
  if ok then
    return id
  end
  return nil
end

function M.populate(bufnr, id)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local bead = bd.show(id)
  if not bead then
    vim.notify(string.format("chaplet: no bead %s", id), vim.log.levels.ERROR)
    return
  end

  local rendered = M.render(bead, bd.comments(id))
  local previous = vim.b[bufnr].chaplet_detail_rendered
  if previous ~= rendered then
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].readonly = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(rendered, "\n", { plain = true }))
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].readonly = true
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.api.nvim_win_set_cursor(winid, { 1, 0 })
    end
    vim.b[bufnr].chaplet_detail_rendered = rendered
  end
  vim.b[bufnr].chaplet_detail_id = id
  install_keys(bufnr, bead)
  refresh.mark_fetch(bufnr)
end

function M.open(id)
  local previous = vim.api.nvim_get_current_buf()
  local bufnr = vim.fn.bufnr(M.BUFFER_NAME)
  if bufnr == -1 then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, M.BUFFER_NAME)
  end

  if previous ~= bufnr and vim.api.nvim_buf_is_valid(previous) then
    vim.b[bufnr].chaplet_previous_buffer = previous
  end
  set_options(bufnr)
  vim.b[bufnr].chaplet_detail_id = id
  M.populate(bufnr, id)
  refresh.attach(bufnr, function()
    M.populate(bufnr, id)
  end)
  vim.api.nvim_win_set_buf(0, bufnr)
  return bufnr
end

return M
