local source = debug.getinfo(1, "S").source:sub(2)
local nvim_dir = vim.fn.fnamemodify(source, ":h:h")

local function plenary_path()
  if vim.env.CHAPLET_PLENARY and vim.fn.isdirectory(vim.env.CHAPLET_PLENARY) == 1 then
    return vim.env.CHAPLET_PLENARY
  end

  local lazy = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
  if vim.fn.isdirectory(lazy) == 1 then
    return lazy
  end

  local paths = vim.fn.glob("~/.local/share/nvim/site/pack/*/start/plenary.nvim", false, true)
  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
  end
end

local plenary = plenary_path()
if plenary then
  vim.opt.rtp:prepend(plenary)
end
vim.opt.rtp:prepend(nvim_dir)
vim.opt.swapfile = false
