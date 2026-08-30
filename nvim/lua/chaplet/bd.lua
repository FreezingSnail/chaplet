local config = require("chaplet.config")

local M = {}

local function capability()
  return vim.system ~= nil
end

local function absolute(path)
  path = vim.fn.fnamemodify(path, ":p")
  if path == "/" then
    return path
  end
  return path:gsub("/+$", "")
end

local function valid_args(args)
  local is_list = vim.islist or vim.tbl_islist
  if type(args) ~= "table" or not is_list(args) then
    return false
  end

  for _, arg in ipairs(args) do
    if type(arg) ~= "string" then
      return false
    end
  end

  return true
end

function M.program()
  return config.get("bd_program")
end

function M.root()
  local directory = vim.fn.expand("%:p:h")
  if directory == "" then
    directory = vim.fn.getcwd()
  end
  directory = absolute(directory)

  local git_root
  while true do
    if vim.fn.isdirectory(directory .. "/.beads") == 1 then
      return directory
    end
    if not git_root and vim.fn.isdirectory(directory .. "/.git") == 1 then
      git_root = directory
    end

    local parent = absolute(vim.fn.fnamemodify(directory, ":h"))
    if parent == directory then
      break
    end
    directory = parent
  end

  return git_root or absolute(vim.fn.getcwd())
end

function M.invoke(args)
  if not valid_args(args) then
    error("chaplet: incomplete bd command (missing argument): " .. vim.inspect(args))
  end

  local argv = { M.program(), "-C", M.root() }
  vim.list_extend(argv, args)
  M._last_argv = vim.deepcopy(argv)

  if vim.fn.executable(M.program()) == 0 then
    return { code = 127, stdout = "" }
  end

  if capability() then
    local result = vim.system(argv, { text = true }):wait()
    return { code = result.code, stdout = result.stdout or "" }
  end

  return { code = vim.v.shell_error, stdout = vim.fn.system(argv) }
end

return M
