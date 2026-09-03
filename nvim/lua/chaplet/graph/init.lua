local bar = require("chaplet.bar")
local bd = require("chaplet.bd")
local graph_nodes = require("chaplet.graph.nodes")
local refresh = require("chaplet.refresh")
local text = require("chaplet.graph.text")
local util = require("chaplet.util")

local M = {}

M.BUFFER_NAME = "*chaplet:graph*"
M.DEFAULT_VIEW = "all"
M.SPECS = {
  { key = "g", label = "refresh" },
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
      beads = nil,
      nodes = nil,
      edges = nil,
      focus = nil,
      rendered_view = nil,
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
  for _, key in ipairs({ "g", "q" }) do
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", key)
  end

  vim.keymap.set("n", "g", function()
    M.refresh(bufnr)
  end, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set("n", "q", function()
    vim.cmd("close")
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

--- Write the canonical text renderer and its id-addressable highlights.
function M.render(bufnr, nodes, edges, focus)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = state_for(bufnr)
  nodes = nodes or {}
  edges = edges or {}
  local lines, spans = text.lines(nodes, edges, focus)
  local ordered = graph_nodes.order(nodes)
  local line_ids = {}
  for index, node in ipairs(ordered) do
    line_ids[index] = node.id
  end

  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  for row, row_spans in ipairs(spans) do
    place_spans(bufnr, row - 1, row_spans)
  end
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  state.nodes = nodes
  state.edges = edges
  state.focus = focus
  state.rendered_view = state.view
  state.rendered_focus = focus
  state.line_ids = line_ids
  set_options(bufnr)
  bar.install(bufnr, M.SPECS, M.EXTRAS)
  bar.update(bufnr, state.view, state.beads or {})
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
  local beads = bd.graph_data(bd.view_filters(state.view))
  refresh.mark_fetch(bufnr)
  if type(beads) ~= "table" or #beads == 0 then
    vim.notify("chaplet: no graph data", vim.log.levels.WARN)
    return
  end

  local nodes, edges = graph_nodes.graph(beads)
  local focus = focused_node(nodes, state.focus)
  local changed = not util.deep_equal(beads, state.beads)
    or state.view ~= state.rendered_view
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
  local bufnr = M.buffer()
  local state = state_for(bufnr)
  if view ~= nil then
    state.view = view
  end
  M.refresh(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

return M
