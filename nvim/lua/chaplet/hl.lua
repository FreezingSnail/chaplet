local M = {}

M.PALETTE = {
  dark = {
    ChapletStateDeferred = "#d19a66",
    ChapletStateInProgress = "#61afef",
    ChapletStateBlocked = "#e06c75",
    ChapletStateClosed = "#5c6370",
    ChapletStateOpen = "#98c379",
    ChapletPriorityHigh = "#e06c75",
    ChapletPriorityMedium = "#d19a66",
    ChapletPriorityLow = "#98c379",
    ChapletTypeEpic = "#c678dd",
    ChapletTypeTask = "#61afef",
    ChapletTypeBug = "#e06c75",
    ChapletStaged = "#98c379",
  },
  light = {
    ChapletStateDeferred = "#8a5a12",
    ChapletStateInProgress = "#1f6fb2",
    ChapletStateBlocked = "#b3261e",
    ChapletStateClosed = "#6e7278",
    ChapletStateOpen = "#1f7a3d",
    ChapletPriorityHigh = "#b3261e",
    ChapletPriorityMedium = "#8a5a12",
    ChapletPriorityLow = "#1f7a3d",
    ChapletTypeEpic = "#7b2d8b",
    ChapletTypeTask = "#1f6fb2",
    ChapletTypeBug = "#b3261e",
    ChapletStaged = "#1f7a3d",
  },
}

M.STATE_GROUPS = {
  "ChapletStateDeferred",
  "ChapletStateInProgress",
  "ChapletStateBlocked",
  "ChapletStateClosed",
  "ChapletStateOpen",
}

local state_groups = {
  deferred = "ChapletStateDeferred",
  in_progress = "ChapletStateInProgress",
  blocked = "ChapletStateBlocked",
  closed = "ChapletStateClosed",
  open = "ChapletStateOpen",
}

local priority_groups = {
  [2] = "ChapletPriorityHigh",
  [1] = "ChapletPriorityMedium",
  [0] = "ChapletPriorityLow",
}

local type_groups = {
  epic = "ChapletTypeEpic",
  task = "ChapletTypeTask",
  bug = "ChapletTypeBug",
}

local function hex(color)
  return string.format("#%06x", color)
end

function M.variant()
  return vim.o.background == "light" and "light" or "dark"
end

function M.normal_bg()
  local ok, normal = pcall(vim.api.nvim_get_hl, 0, { name = "Normal" })
  if ok and type(normal.bg) == "number" then
    return hex(normal.bg)
  end
  return M.variant() == "dark" and "#282c34" or "#ffffff"
end

function M.blend(fg, bg, alpha)
  alpha = alpha or 0.18
  local function channel(offset)
    local foreground = tonumber(fg:sub(offset, offset + 1), 16)
    local background = tonumber(bg:sub(offset, offset + 1), 16)
    return math.floor(foreground * alpha + background * (1 - alpha) + 0.5)
  end
  return string.format("#%02x%02x%02x", channel(2), channel(4), channel(6))
end

function M.apply()
  local palette = M.PALETTE[M.variant()]
  local background = M.normal_bg()
  local states = {}
  for _, name in ipairs(M.STATE_GROUPS) do
    states[name] = true
  end

  for name, foreground in pairs(palette) do
    local attributes = { fg = foreground }
    if states[name] then
      attributes.bg = M.blend(foreground, background, 0.18)
    end
    vim.api.nvim_set_hl(0, name, attributes)
  end

  vim.api.nvim_set_hl(0, "ChapletHeader", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "ChapletBar", { default = true, link = "StatusLine" })
  vim.api.nvim_set_hl(0, "ChapletId", { default = true, link = "Identifier" })
end

function M.setup()
  M.apply()
  local group = vim.api.nvim_create_augroup("ChapletHl", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = M.apply,
  })
end

function M.state_group(status)
  return state_groups[status]
end

function M.priority_group(priority)
  if type(priority) == "string" then
    priority = tonumber(priority)
  end
  return priority_groups[priority]
end

function M.type_group(bead_type)
  return type_groups[bead_type]
end

function M.state_color(status)
  local group = M.state_group(status)
  if not group then
    return nil
  end
  local ok, attributes = pcall(vim.api.nvim_get_hl, 0, { name = group })
  if ok and type(attributes.fg) == "number" then
    return hex(attributes.fg)
  end
  return M.PALETTE.dark[group]
end

return M
