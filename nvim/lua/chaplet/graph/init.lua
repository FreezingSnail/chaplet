local bar = require("chaplet.bar")
local detail = require("chaplet.detail")
local bd = require("chaplet.bd")
local graph_nodes = require("chaplet.graph.nodes")
local refresh = require("chaplet.refresh")
local text = require("chaplet.graph.text")
local util = require("chaplet.util")

local M = {}

M.BUFFER_NAME = "*chaplet:graph*"
M.DEFAULT_VIEW = "all"
M.SPECS = {
  { key = "n", label = "next" },
  { key = "p", label = "prev" },
  { key = "<CR>", label = "open focused" },
  { key = "d", label = "dependents" },
  { key = "f", label = "deps" },
  { key = "g", label = "refresh" },
  { key = "v", label = "view switch" },
  { key = "c", label = "closed" },
  { key = "q", label = "quit" },
}
M.EXTRAS = {
  { key = "mouse-1", label = "open node" },
  { key = "mouse-2", label = "dependents" },
}
M.namespace = vim.api.nvim_create_namespace("chaplet_graph")
M.ns_id = M.namespace
M._state = {}

local states = M._state

local function state_for(bufnr)
  local state = states[bufnr]
  if state == nil then
    state = {
      view = M.DEFAULT_VIEW,
      closed = false,
      beads = nil,
      nodes = nil,
      edges = nil,
      focus = nil,
      rendered_view = nil,
      rendered_closed = nil,
      rendered_focus = nil,
      line_ids = {},
      attached = false,
    }
    states[bufnr] = state
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

local function install_keys(bufnr)
  for _, key in ipairs({ "n", "p", "<CR>", "d", "f", "g", "v", "c", "q", "<LeftMouse>", "<MiddleMouse>" }) do
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", key)
  end

  vim.keymap.set("n", "n", function()
    M.focus_next(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "p", function()
    M.focus_prev(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "<CR>", function()
    M.open_focused(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "d", function()
    M.jump_dependents(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "f", function()
    M.jump_deps(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "g", function()
    M.refresh(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "v", function()
    M.switch_view(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "c", function()
    M.toggle_closed(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "q", function()
    util.restore_previous_buffer_or_close(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "<LeftMouse>", function()
    M.mouse_open(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "<MiddleMouse>", function()
    M.mouse_dependents(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
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
      states[bufnr] = nil
    end,
  })
  state.attached = true
end

--- Return the single unlisted scratch buffer used by every graph view.
function M.buffer()
  local bufnr = vim.fn.bufnr(M.BUFFER_NAME)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, M.BUFFER_NAME)
  end

  local state = state_for(bufnr)
  set_options(bufnr)
  install_keys(bufnr)
  attach_refresh(bufnr, state)
  return bufnr
end

--- Return the buffer state, including cached data and rendered line ids.
function M.state(bufnr)
  return states[bufnr]
end

function M.line_id(bufnr, lnum)
  local state = states[bufnr]
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

local function place_spans(bufnr, row, spans)
  for _, span in ipairs(spans or {}) do
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace, row, span.start_col, {
      end_row = row,
      end_col = span.end_col,
      hl_group = span.group,
    })
  end
end

local function render_visual(bufnr, nodes, edges, focus)
  local lines, spans = text.lines(nodes or {}, edges or {}, focus)

  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  for row, row_spans in ipairs(spans) do
    place_spans(bufnr, row - 1, row_spans)
  end
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
end

--- Write the canonical text renderer and its id-addressable highlights.
function M.render(bufnr, nodes, edges, focus)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = state_for(bufnr)
  nodes = nodes or {}
  edges = edges or {}
  render_visual(bufnr, nodes, edges, focus)
  local ordered = graph_nodes.order(nodes)
  local line_ids = {}
  for index, node in ipairs(ordered) do
    line_ids[index] = node.id
  end

  state.nodes = nodes
  state.edges = edges
  state.focus = focus
  state.rendered_view = state.view
  state.rendered_closed = state.closed
  state.rendered_focus = focus
  state.line_ids = line_ids
  set_options(bufnr)
  bar.install(bufnr, M.SPECS, M.EXTRAS)
  local status_view = state.view .. (state.closed and " [closed]" or "")
  bar.update(bufnr, status_view, state.beads or {})
end

--- Set focus and redraw only the existing graph visual.
function M.focus_set(bufnr, id)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = state_for(bufnr)
  state.focus = id
  state.rendered_focus = id
  render_visual(bufnr, state.nodes, state.edges, id)
end

--- Move focus by DELTA positions in renderer order, wrapping at both ends.
function M.focus_relative(bufnr, delta)
  local state = states[bufnr]
  local ordered = state and graph_nodes.order(state.nodes or {}) or {}
  if #ordered == 0 then
    return
  end

  local position = -1
  for index, node in ipairs(ordered) do
    if node.id == state.focus then
      position = index - 1
      break
    end
  end
  local target = ordered[(position + delta) % #ordered + 1]
  M.focus_set(bufnr, target.id)
end

function M.focus_next(bufnr)
  M.focus_relative(bufnr, 1)
end

function M.focus_prev(bufnr)
  M.focus_relative(bufnr, -1)
end

function M.open_focused(bufnr)
  local state = states[bufnr]
  if state == nil or state.focus == nil then
    vim.notify("chaplet: no focused node", vim.log.levels.WARN)
    return
  end
  detail.open(state.focus)
end

local function jump(bufnr, field, target_field, missing)
  local state = states[bufnr]
  local focus = state and state.focus
  if state ~= nil and focus ~= nil then
    for _, edge in ipairs(state.edges or {}) do
      if edge[field] == focus then
        M.focus_set(bufnr, edge[target_field])
        return
      end
    end
  end
  vim.notify("chaplet: " .. missing .. (focus == nil and " (no focus)" or ""), vim.log.levels.WARN)
end

function M.jump_dependents(bufnr)
  jump(bufnr, "to", "from", "no dependents")
end

function M.jump_deps(bufnr)
  jump(bufnr, "from", "to", "no deps")
end

function M.mouse_open(bufnr)
  local id = M.id_at_cursor(bufnr)
  if id == nil then
    vim.notify("chaplet: no node at click", vim.log.levels.WARN)
    return
  end
  detail.open(id)
end

function M.mouse_dependents(bufnr)
  local id = M.id_at_cursor(bufnr)
  if id == nil then
    vim.notify("chaplet: no node at click", vim.log.levels.WARN)
    return
  end
  M.focus_set(bufnr, id)
  M.jump_dependents(bufnr)
end

function M.closed(bufnr)
  local state = states[bufnr]
  return state ~= nil and state.closed == true
end

function M.set_view(bufnr, view)
  if bd.view_filters(view) == nil then
    vim.notify("chaplet: unknown view " .. tostring(view), vim.log.levels.ERROR)
    return nil
  end
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local state = state_for(bufnr)
  state.view = view
  M.refresh(bufnr)
  return bufnr
end

function M.switch_view(bufnr)
  vim.ui.select(bd.view_names(), { prompt = "View: " }, function(view)
    if view ~= nil then
      M.set_view(bufnr, view)
    end
  end)
end

function M.toggle_closed(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local state = state_for(bufnr)
  state.closed = not state.closed
  M.refresh(bufnr)
  return state.closed
end

local function focused_node(nodes, focus)
  if focus == nil then
    return nil
  end
  for _, node in ipairs(nodes) do
    if node.id == focus then
      return focus
    end
  end
  return nil
end

--- Fetch graph data; retain the prior canvas when the read has no data.
function M.refresh(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = state_for(bufnr)
  local filters = vim.deepcopy(bd.view_filters(state.view) or {})
  if state.closed then
    filters.all = true
  end
  local beads = bd.graph_data(filters)
  refresh.mark_fetch(bufnr)
  bd.graph_dot({ closed = state.closed })
  if type(beads) ~= "table" or #beads == 0 then
    vim.notify("chaplet: no graph data", vim.log.levels.WARN)
    return
  end

  local nodes, edges = graph_nodes.graph(beads)
  local focus = focused_node(nodes, state.focus)
  local changed = not util.deep_equal(beads, state.beads)
    or state.view ~= state.rendered_view
    or state.closed ~= state.rendered_closed
    or focus ~= state.rendered_focus

  state.beads = beads
  state.nodes = nodes
  state.edges = edges
  state.focus = focus
  if changed then
    M.render(bufnr, nodes, edges, focus)
  end
end

--- Open the reused graph buffer, selecting VIEW when supplied.
function M.open(view)
  local previous = vim.api.nvim_get_current_buf()
  local bufnr = M.buffer()
  if previous ~= bufnr and vim.api.nvim_buf_is_valid(previous) then
    vim.b[bufnr].chaplet_previous_buffer = previous
  end
  local state = state_for(bufnr)
  if view ~= nil then
    state.view = view
  end
  M.refresh(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

return M
