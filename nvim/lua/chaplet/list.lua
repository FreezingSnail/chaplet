local util = require("chaplet.util")
local hl = require("chaplet.hl")
local bd = require("chaplet.bd")
local refresh = require("chaplet.refresh")

local M = {}

M.BUFFER_NAME = "*chaplet*"
M.DEFAULT_VIEW = "inbox"
M.namespace = vim.api.nvim_create_namespace("chaplet_list")
M.ns_id = M.namespace
M._state = {}

local buffers = M._state

M.COLUMNS = {
  { name = "ID", width = 12 },
  { name = "Type", width = 10 },
  { name = "State", width = 12 },
  { name = "P", width = 3 },
  { name = "Staged", width = 7 },
  { name = "Title", width = 60 },
}

local HEADER_GROUP = "ChapletHeader"
local ID_GROUP = "ChapletId"
local STAGED_GROUP = "ChapletStaged"

local function string_value(value)
  if value == nil then
    return ""
  end
  return tostring(value)
end

function M.priority_cell(priority)
  if priority == nil then
    return ""
  end

  local numeric = type(priority) == "number" and priority or tonumber(priority)
  local mark = numeric >= 2 and "●" or "·"
  return mark .. tostring(priority)
end

function M.staged(bead)
  if not bead or bead.status ~= "deferred" then
    return false
  end

  for _, label in ipairs(bead.labels or {}) do
    if label == require("chaplet.bd").STAGED_LABEL then
      return true
    end
  end
  return false
end

local function append_cell(parts, spans, value, width, group)
  local cell = util.cell(value, width)
  local start = #table.concat(parts)
  parts[#parts + 1] = cell
  spans[#spans + 1] = { col = start, end_col = start + #cell, hl = group }
end

local function append_separator(parts)
  parts[#parts + 1] = " "
end

function M.header_line()
  local parts = {}
  for index, column in ipairs(M.COLUMNS) do
    parts[#parts + 1] = util.cell(column.name, column.width)
    if index < #M.COLUMNS then
      append_separator(parts)
    end
  end

  local text = table.concat(parts)
  return text, { { col = 0, end_col = #text, hl = HEADER_GROUP } }
end

function M.format_row(bead, indent)
  bead = bead or {}
  local staged = M.staged(bead)
  local cells = {
    string_value(bead.id),
    string_value(bead.issue_type),
    string_value(bead.status),
    M.priority_cell(bead.priority),
    staged and "✔" or "",
    (indent and "  " or "") .. string_value(bead.title),
  }
  local groups = {
    ID_GROUP,
    hl.type_group(bead.issue_type),
    hl.state_group(bead.status),
    hl.priority_group(bead.priority),
    STAGED_GROUP,
    nil,
  }

  local parts = {}
  local spans = {}
  for index, column in ipairs(M.COLUMNS) do
    local cell = util.cell(cells[index], column.width)
    if index <= 5 then
      append_cell(parts, spans, cell, column.width, groups[index])
    else
      parts[#parts + 1] = cell
    end
    if index < #M.COLUMNS then
      append_separator(parts)
    end
  end

  return { text = table.concat(parts), spans = spans }
end

local EPIC_CACHE_NIL = {}
local epic_cache = {}

function M.clear_epic_cache()
  epic_cache = {}
end

function M.fetch_epic(id)
  local cached = epic_cache[id]
  if cached == EPIC_CACHE_NIL then
    return nil
  end
  if cached ~= nil then
    return cached
  end

  local bead = bd.show(id)
  epic_cache[id] = bead or EPIC_CACHE_NIL
  return bead
end

function M.group_by_epic(beads, fetch_epic)
  fetch_epic = fetch_epic or M.fetch_epic

  local by_parent = {}
  local epics_in_view = {}
  local orphans = {}

  for _, bead in ipairs(beads or {}) do
    if bead.issue_type == "epic" then
      epics_in_view[bead.id] = bead
      by_parent[bead.id] = by_parent[bead.id] or {}
    elseif bead.parent ~= nil then
      by_parent[bead.parent] = by_parent[bead.parent] or {}
      table.insert(by_parent[bead.parent], bead)
    else
      table.insert(orphans, bead)
    end
  end

  local epic_ids = {}
  for epic_id in pairs(by_parent) do
    table.insert(epic_ids, epic_id)
  end
  table.sort(epic_ids, function(left, right)
    return tostring(left) < tostring(right)
  end)

  local ordered = {}
  for _, epic_id in ipairs(epic_ids) do
    local epic = epics_in_view[epic_id] or fetch_epic(epic_id)
    if epic ~= nil then
      table.insert(ordered, { bead = epic, indent = false })
    end
    for _, child in ipairs(by_parent[epic_id]) do
      table.insert(ordered, { bead = child, indent = true })
    end
  end

  for _, bead in ipairs(orphans) do
    table.insert(ordered, { bead = bead, indent = false })
  end

  return ordered
end

local function state_for(bufnr)
  local state = buffers[bufnr]
  if state == nil then
    state = {
      line_ids = {},
      cached_beads = nil,
      view = nil,
      filters = {},
      attached = false,
    }
    buffers[bufnr] = state
  end
  return state
end

local function set_options(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[winid].wrap = false
  end
end

local function attach_refresh(bufnr, state)
  if state.attached then
    return
  end

  refresh.attach(bufnr, function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.refresh(bufnr)
    end
  end)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      buffers[bufnr] = nil
    end,
  })
  state.attached = true
end

function M.buffer()
  local bufnr = vim.fn.bufnr(M.BUFFER_NAME)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, M.BUFFER_NAME)
  end

  set_options(bufnr)
  local state = state_for(bufnr)
  attach_refresh(bufnr, state)
  return bufnr
end

function M.line_id(bufnr, lnum)
  local state = buffers[bufnr]
  if state == nil or lnum == nil then
    return nil
  end
  return state.line_ids[lnum]
end

function M.id_at_cursor(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local winid = vim.fn.bufwinid(bufnr)
  local line = 1
  if winid ~= -1 then
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, winid)
    if ok then
      line = cursor[1]
    end
  end
  return M.line_id(bufnr, line)
end

function M.beads(bufnr)
  local state = buffers[bufnr]
  return state and state.cached_beads or nil
end

local function place_spans(bufnr, row, spans)
  for _, span in ipairs(spans or {}) do
    local opts = {
      end_row = row,
      end_col = span.end_col,
    }
    if span.hl ~= nil then
      opts.hl_group = span.hl
    end
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace, row, span.col, opts)
  end
end

local function restore_cursor(winid, cursor, lines)
  if not cursor or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local line = math.max(1, math.min(cursor[1], #lines))
  local column = math.min(cursor[2], #lines[line])
  pcall(vim.api.nvim_win_set_cursor, winid, { line, column })
end

function M.render(bufnr, beads)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = state_for(bufnr)
  beads = beads or {}
  local rows = M.group_by_epic(beads)
  local header, header_spans = M.header_line()
  local lines = { header }
  local line_ids = {}
  local rendered_spans = { header_spans }

  for _, row in ipairs(rows) do
    local formatted = M.format_row(row.bead, row.indent)
    lines[#lines + 1] = formatted.text
    line_ids[#lines] = row.bead.id
    rendered_spans[#rendered_spans + 1] = formatted.spans
  end

  local winid = vim.fn.bufwinid(bufnr)
  local cursor
  if winid ~= -1 then
    local ok, position = pcall(vim.api.nvim_win_get_cursor, winid)
    if ok then
      cursor = position
    end
  end

  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  for row, spans in ipairs(rendered_spans) do
    place_spans(bufnr, row - 1, spans)
  end

  state.line_ids = line_ids
  state.cached_beads = beads
  set_options(bufnr)
  if winid ~= -1 then
    restore_cursor(winid, cursor, lines)
  end
end

function M.current_view(bufnr)
  local state = buffers[bufnr]
  return (state and state.view) or M.DEFAULT_VIEW
end

function M.filters(bufnr)
  local state = buffers[bufnr]
  return state and vim.deepcopy(state.filters) or {}
end

function M.set_filters(bufnr, filters)
  local state = state_for(bufnr)
  state.filters = {}
  for _, key in ipairs({ "type", "label" }) do
    local value = filters and filters[key]
    if value ~= nil and value ~= "" then
      state.filters[key] = value
    end
  end
  M.refresh(bufnr)
end

function M.fetch(view, filters)
  local merged = {}
  if view ~= nil then
    local view_filters = bd.view_filters(view)
    if view_filters == nil then
      return nil
    end
    for key, value in pairs(view_filters) do
      merged[key] = value
    end
  end
  for key, value in pairs(filters or {}) do
    if value ~= nil and value ~= "" then
      merged[key] = value
    end
  end

  if merged.all or (view == nil and next(merged) == nil) then
    return bd.list(next(merged) and merged or nil)
  end
  return bd.query(bd.filters_to_expr(merged))
end

function M.refresh(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = state_for(bufnr)
  local beads = M.fetch(state.view, state.filters)
  refresh.mark_fetch(bufnr)

  if beads == nil or util.deep_equal(beads, state.cached_beads) then
    return
  end
  M.render(bufnr, beads)
end

local function open_at_cursor(bufnr)
  local id = M.id_at_cursor(bufnr)
  if id == nil then
    vim.notify("chaplet: no bead at point", vim.log.levels.WARN)
    return
  end
  require("chaplet.detail").open(id)
end

local function install_keys(bufnr)
  for _, key in ipairs({ "<CR>", "<LeftMouse>", "q", "v", "?" }) do
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", key)
  end

  vim.keymap.set("n", "<CR>", function()
    open_at_cursor(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "<LeftMouse>", function()
    open_at_cursor(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "q", function()
    vim.cmd("close")
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "v", function()
    M.switch_view(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "?", function()
    require("chaplet.actions").open_menu(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
end

local function attach_refresh_and_keys(bufnr, state)
  attach_refresh(bufnr, state)
  install_keys(bufnr)
end

local original_buffer = M.buffer
M.buffer = function()
  local bufnr = original_buffer()
  attach_refresh_and_keys(bufnr, buffers[bufnr])
  return bufnr
end

function M.switch_view(bufnr)
  vim.ui.select(bd.view_names(), { prompt = "View: " }, function(view)
    if view ~= nil then
      M.set_view(view)
    end
  end)
end

function M.set_view(view)
  if bd.view_filters(view) == nil then
    vim.notify("chaplet: unknown view " .. tostring(view), vim.log.levels.ERROR)
    return nil
  end

  local bufnr = M.buffer()
  local state = state_for(bufnr)
  state.view = view
  M.clear_epic_cache()
  local beads = M.fetch(view, state.filters)
  refresh.mark_fetch(bufnr)
  if beads ~= nil then
    M.render(bufnr, beads)
  else
    vim.notify("chaplet: list not available yet", vim.log.levels.WARN)
  end
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

function M.open()
  return M.set_view(M.DEFAULT_VIEW)
end

return M
