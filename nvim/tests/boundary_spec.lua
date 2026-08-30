local source = debug.getinfo(1, "S").source:sub(2)
local spec_path = vim.fn.fnamemodify(source, ":p")
local spec_dir = vim.fn.fnamemodify(spec_path, ":h")
local plugin_root = vim.fn.fnamemodify(spec_dir, ":h")
local lua_root = plugin_root .. "/lua"

local spawn_patterns = {
  "vim%.system",
  "jobstart",
  "io%.popen",
  "os%.execute",
  "vim%.fn%.system",
}

local function relative_path(path)
  return path:sub(#plugin_root + 2)
end

describe("chaplet process boundary", function()
  it("keeps bd.lua as the sole Lua spawn site", function()
    local files = vim.fn.globpath(lua_root, "**/*.lua", false, true)
    assert.is_true(#files > 0, "boundary scan found no Lua files under " .. lua_root)

    local violations = {}
    local bd_matched = false

    for _, file in ipairs(files) do
      local absolute = vim.fn.fnamemodify(file, ":p")
      local relative = relative_path(absolute)
      local is_bd = relative == "lua/chaplet/bd.lua"

      for line_number, line in ipairs(vim.fn.readfile(absolute)) do
        for _, pattern in ipairs(spawn_patterns) do
          if line:find(pattern) then
            if is_bd then
              bd_matched = true
            else
              table.insert(
                violations,
                string.format("%s:%d matches %s", relative, line_number, pattern)
              )
            end
          end
        end
      end
    end

    assert.is_true(
      bd_matched,
      "boundary scan did not find a spawn pattern in lua/chaplet/bd.lua"
    )
    assert.equals(0, #violations, table.concat(violations, "\n"))
  end)
end)
