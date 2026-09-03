local config = require("chaplet.config")

local M = {}

local refreshers = {}
local last_fetch = {}
local groups = {}
local timer = nil

M.now = function()
  return vim.loop.now()
end

local function notify_failure(bufnr, err)
  vim.notify(
    string.format("chaplet: refresh failed for buffer %d: %s", bufnr, tostring(err)),
    vim.log.levels.WARN
  )
end

local function invoke(bufnr)
  local refresher = refreshers[bufnr]
  if not refresher then
    return
  end

  local ok, err = pcall(refresher)
  if not ok then
    notify_failure(bufnr, err)
  end
end

local function live(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
end

local function visible(bufnr)
  return vim.fn.bufwinid(bufnr) ~= -1
end

local function registry_keys()
  local keys = {}
  for bufnr in pairs(refreshers) do
    table.insert(keys, bufnr)
  end
  return keys
end

function M.register(bufnr, fn)
  refreshers[bufnr] = fn
end

function M.unregister(bufnr)
  refreshers[bufnr] = nil
  last_fetch[bufnr] = nil

  local group = groups[bufnr]
  if group then
    groups[bufnr] = nil
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
end

function M.attach(bufnr, fn)
  M.register(bufnr, fn)

  local group_name = "chaplet_refresh_" .. bufnr
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  groups[bufnr] = group

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    buffer = bufnr,
    group = group,
    callback = function()
      M.on_focus(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    group = group,
    callback = function()
      M.unregister(bufnr)
    end,
  })
end

function M.mark_fetch(bufnr)
  last_fetch[bufnr] = M.now()
end

function M.stale(bufnr)
  local fetched = last_fetch[bufnr]
  if fetched == nil then
    return true
  end

  local delay = config.get("refresh_delay") or 0
  return M.now() - fetched > delay * 1000
end

function M.stop_timer()
  if timer then
    vim.fn.timer_stop(timer)
    timer = nil
  end
end

function M.ensure_timer()
  local interval = config.get("refresh_interval")
  if not config.get("auto_refresh") or not interval or interval <= 0 then
    M.stop_timer()
    return
  end

  if not timer then
    local milliseconds = interval * 1000
    timer = vim.fn.timer_start(milliseconds, M.tick, { ["repeat"] = milliseconds })
  end
end

function M.on_focus(bufnr)
  if not config.get("auto_refresh") then
    return
  end

  M.ensure_timer()
  if not live(bufnr) then
    M.unregister(bufnr)
    return
  end
  if M.stale(bufnr) then
    invoke(bufnr)
  end
end

function M.tick()
  if not config.get("auto_refresh") then
    M.stop_timer()
    return
  end

  local any_visible = false
  for _, bufnr in ipairs(registry_keys()) do
    if not live(bufnr) then
      M.unregister(bufnr)
    elseif visible(bufnr) then
      any_visible = true
      if M.stale(bufnr) then
        invoke(bufnr)
      end
    end
  end

  if not any_visible then
    M.stop_timer()
  end
end

function M.refresh_all()
  for _, bufnr in ipairs(registry_keys()) do
    if not live(bufnr) then
      M.unregister(bufnr)
    else
      invoke(bufnr)
    end
  end
end

return M
