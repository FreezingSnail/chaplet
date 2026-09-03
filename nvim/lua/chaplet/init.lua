local config = require("chaplet.config")
local hl = require("chaplet.hl")

local M = {}

local function unavailable(module)
  vim.notify("chaplet: " .. module .. " not available yet", vim.log.levels.WARN)
end

local function open_list()
  local ok, list = pcall(require, "chaplet.list")
  if not ok then
    unavailable("list")
    return
  end
  list.open()
end

local function open_graph()
  local ok, graph = pcall(require, "chaplet.graph")
  if not ok then
    unavailable("graph")
    return
  end
  graph.open()
end

function M.setup(opts)
  local options = config.setup(opts)
  hl.setup()

  vim.api.nvim_create_user_command("Chaplet", open_list, { force = true })
  vim.api.nvim_create_user_command("ChapletGraph", open_graph, { force = true })

  local prefix = config.get("keymap_prefix")
  if prefix then
    vim.keymap.set("n", prefix .. "b", "<Cmd>Chaplet<CR>", {
      silent = true,
      desc = "Chaplet inbox",
    })
    vim.keymap.set("n", prefix .. "s", "<Cmd>ChapletGraph<CR>", {
      silent = true,
      desc = "Chaplet graph",
    })
  end

  return options
end

return M
