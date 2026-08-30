local M = {}

M.defaults = {
  bd_program = "bd",
  auto_refresh = true,
  refresh_interval = 5,
  refresh_delay = 2,
  keymap_prefix = "<leader>b",
  graph = {
    x_gap = 28,
    y_gap = 40,
    node_h = 28,
    title_max = 28,
    pad = 8,
    margin = 16,
    text_title_max = 20,
    text_align = false,
    text_lane_max = nil,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  opts = opts or {}
  for key in pairs(opts) do
    if M.defaults[key] == nil then
      error("chaplet: unknown option " .. key)
    end
  end
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  return M.options
end

function M.get(path)
  local value = M.options
  for key in string.gmatch(path, "[^%.]+") do
    if type(value) ~= "table" then
      return nil
    end
    value = value[key]
  end
  return value
end

return M
