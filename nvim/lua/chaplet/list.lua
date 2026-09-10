local util = require("chaplet.util")
local hl = require("chaplet.hl")
local bd = require("chaplet.bd")
local refresh = require("chaplet.refresh")
local bar = require("chaplet.bar")

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
local BUFFER_MARKER = "chaplet_list_scratch"

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

function M.format_row(bead, indent, prefix)
  bead = bead or {}
  local staged = M.staged(bead)
  local title_prefix = type(prefix) == "string" and prefix or ""
  if title_prefix == "" then
    if type(indent) == "number" and indent > 0 then
      title_prefix = string.rep("  ", indent)
    elseif indent then
      title_prefix = "  "
    end
  end
  local cells = {
    string_value(bead.id),
    string_value(bead.issue_type),
    string_value(bead.status),
    M.priority_cell(bead.priority),
    staged and "✔" or "",
    title_prefix .. string_value(bead.title),
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

local BRANCH = "├── "
local LAST = "└── "
local PIPE = "│   "
local BLANK = "    "

--- Order beads as a bd list tree: every in-result issue that depends on an
--- epic renders beneath that epic — under EVERY epic it depends on, exactly
--- like `bd list`'s recursive expansion.  Roots are issues that are never a
--- child; ordering is (priority asc, natural id asc).  Explicit `parent`
--- links keep PARITY 6 grouping for beads not nested via dependencies, and
--- absent or unresolvable parents render their children under a virtual
--- anchor so nothing is dropped.
function M.group_by_epic(beads, fetch_epic)
  fetch_epic = fetch_epic or M.fetch_epic

  local by_id = {}
  local result_ids = {}
  local epics = {}
  local children = {}
  local is_child = {}

  local function ensure_children(id)
    children[id] = children[id] or {}
  end

  for _, bead in ipairs(beads or {}) do
    by_id[bead.id] = bead
    result_ids[bead.id] = true
    if bead.issue_type == "epic" then
      epics[bead.id] = true
    end
  end

  -- Dependency nesting: a dependency targeting an epic is hierarchical.
  local added_child = {}
  for _, bead in ipairs(beads or {}) do
    local deps = vim.deepcopy(bead.dependencies or {})
    table.sort(deps)
    for _, dep in ipairs(deps) do
      if dep ~= bead.id and epics[dep] and result_ids[dep] then
        local key = dep .. ":" .. bead.id
        if not added_child[key] then
          added_child[key] = true
          ensure_children(dep)
          table.insert(children[dep], bead.id)
          is_child[bead.id] = true
        end
      end
    end
  end

  -- Explicit parent links (PARITY 6) for beads not nested via dependencies.
  local parent_of = {}
  local groups = {}
  for _, bead in ipairs(beads or {}) do
    if bead.parent ~= nil and not is_child[bead.id] then
      parent_of[bead.id] = bead.parent
      groups[bead.parent] = true
      ensure_children(bead.parent)
      table.insert(children[bead.parent], bead.id)
      is_child[bead.id] = true
    end
  end

  -- Absent parents: fetch the epic so the group keeps its header.  A nil
  -- lookup keeps the children indented under a virtual anchor.  Fetch in
  -- ascending id order so the calls stay deterministic.
  local absent = {}
  for _, parent_id in pairs(parent_of) do
    if by_id[parent_id] == nil then
      absent[parent_id] = true
    end
  end
  local absent_ids = {}
  for parent_id in pairs(absent) do
    absent_ids[#absent_ids + 1] = parent_id
  end
  local fetched_roots = {}
  table.sort(absent_ids)
  for _, parent_id in ipairs(absent_ids) do
    local epic = fetch_epic(parent_id)
    if epic ~= nil then
      by_id[parent_id] = epic
      epics[parent_id] = true
      fetched_roots[#fetched_roots + 1] = parent_id
    end
  end

  local function priority_of(id)
    local bead = by_id[id]
    return bead ~= nil and bead.priority or math.huge
  end

  local function compare(left, right)
    local left_priority = priority_of(left)
    local right_priority = priority_of(right)
    if left_priority ~= right_priority then
      return left_priority < right_priority
    end
    return util.natural_compare(tostring(left), tostring(right)) < 0
  end

  for _, child_ids in pairs(children) do
    table.sort(child_ids, function(left, right)
      return compare(left, right)
    end)
  end

  local roots = {}
  for _, bead in ipairs(beads or {}) do
    if not is_child[bead.id] then
      roots[#roots + 1] = bead.id
    end
  end
  for id in pairs(groups) do
    if by_id[id] == nil then
      roots[#roots + 1] = id
    end
  end
  for _, id in ipairs(fetched_roots) do
    roots[#roots + 1] = id
  end
  table.sort(roots, function(left, right)
    local left_priority = priority_of(left)
    local right_priority = priority_of(right)
    if left_priority ~= right_priority then
      return left_priority < right_priority
    end
    local left_epic = by_id[left] ~= nil and by_id[left].issue_type == "epic"
    local right_epic = by_id[right] ~= nil and by_id[right].issue_type == "epic"
    if left_epic ~= right_epic then
      return left_epic
    end
    return util.natural_compare(tostring(left), tostring(right)) < 0
  end)

  local ordered = {}

  local function subtree(id, gutters, level)
    local child_ids = children[id] or {}
    for index, child_id in ipairs(child_ids) do
      local last = index == #child_ids
      if by_id[child_id] ~= nil then
        ordered[#ordered + 1] = {
          bead = by_id[child_id],
          indent = level,
          prefix = gutters .. (last and LAST or BRANCH),
        }
      end
      subtree(child_id, gutters .. (last and BLANK or PIPE), level + 1)
    end
  end

  for _, id in ipairs(roots) do
    if by_id[id] ~= nil then
      ordered[#ordered + 1] = { bead = by_id[id], indent = 0, prefix = "" }
    end
    subtree(id, "", 1)
  end

  -- Unreachable beads (epic-target dependency cycles) render flat, in
  -- natural id order, exactly once.
  local emitted = {}
  for _, row in ipairs(ordered) do
    emitted[row.bead.id] = true
  end
  local leftover = {}
  for _, bead in ipairs(beads or {}) do
    if not emitted[bead.id] then
      leftover[#leftover + 1] = bead
    end
  end
  table.sort(leftover, function(left, right)
    return util.natural_compare(tostring(left.id), tostring(right.id)) < 0
  end)
  for _, bead in ipairs(leftover) do
    ordered[#ordered + 1] = { bead = bead, indent = 0, prefix = "" }
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
  local bufnr = util.scratch_buffer(M.BUFFER_NAME, BUFFER_MARKER)

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
  local rendered_beads = {}
  local rendered_ids = {}

  for _, row in ipairs(rows) do
    local formatted = M.format_row(row.bead, row.indent, row.prefix)
    lines[#lines + 1] = formatted.text
    line_ids[#lines] = row.bead.id
    rendered_spans[#rendered_spans + 1] = formatted.spans
    if not rendered_ids[row.bead.id] then
      rendered_ids[row.bead.id] = true
      rendered_beads[#rendered_beads + 1] = row.bead
    end
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
  bar.update(bufnr, M.current_view(bufnr), rendered_beads)
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

  return bd.list(next(merged) and merged or nil)
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

local function open_at_cursor(bufnr, vertical)
  local id = M.id_at_cursor(bufnr)
  if id == nil then
    vim.notify("chaplet: no bead at point", vim.log.levels.WARN)
    return
  end
  require("chaplet.detail").open(id, { vertical = vertical })
end

local function install_keys(bufnr)
  for _, key in ipairs({ "<CR>", "<LeftMouse>", "q", "v", "?", "|" }) do
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", key)
  end

  vim.keymap.set("n", "<CR>", function()
    open_at_cursor(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "<LeftMouse>", function()
    open_at_cursor(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "|", function()
    open_at_cursor(bufnr, true)
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
  bar.install(bufnr, bar.SPECS)
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
