local M = {}

M.SPECS = {
  { key = "<CR>", label = "open" },
  { key = "v", label = "view switch" },
  { key = "s", label = "graph" },
  { key = "?", label = "actions" },
  { key = "q", label = "quit" },
  { key = "<LeftMouse>", label = "open" },
}

local cache = {}

local function normalize_key(key)
  key = tostring(key)
  if key == "\r" or key == "\n" or key == "^M" then
    return "<CR>"
  end
  key = key:gsub("^<[Cc][Rr]>$", "<CR>")
  key = key:gsub("^<[Ll]eft[Mm]ouse>$", "<LeftMouse>")
  return key
end

local function apply(bufnr)
  local rendered = cache[bufnr]
  if rendered == nil then
    return
  end

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[winid].winbar = rendered.winbar
    vim.wo[winid].statusline = rendered.statusline
  end
end

function M.bound(bufnr, specs)
  local mapped = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    mapped[normalize_key(mapping.lhs)] = true
  end

  local entries = {}
  for _, spec in ipairs(specs or M.SPECS) do
    if mapped[normalize_key(spec.key)] then
      entries[#entries + 1] = spec
    end
  end
  return entries
end

function M.entries(bufnr, specs, extra)
  local entries = M.bound(bufnr, specs)
  for _, spec in ipairs(extra or {}) do
    entries[#entries + 1] = spec
  end
  return entries
end

function M.render(entries)
  if entries == nil or #entries == 0 then
    return ""
  end

  local rendered = {}
  for _, entry in ipairs(entries) do
    rendered[#rendered + 1] = string.format("[%s] %s", entry.key, entry.label)
  end
  return " " .. table.concat(rendered, " ")
end

function M.counts(view, beads)
  local open = 0
  local blocked = 0
  beads = beads or {}
  for _, bead in ipairs(beads) do
    if bead.status == "open" then
      open = open + 1
    elseif bead.status == "blocked" then
      blocked = blocked + 1
    end
  end
  return string.format(
    "chaplet %s · %d beads · %d open · %d blocked",
    tostring(view or ""),
    #beads,
    open,
    blocked
  )
end

function M.install(bufnr, specs, extra)
  local existing = cache[bufnr]
  cache[bufnr] = {
    winbar = M.render(M.entries(bufnr, specs, extra)),
    statusline = existing and existing.statusline or "",
    specs = specs or M.SPECS,
    extra = extra or {},
  }
  apply(bufnr)

  if existing == nil then
    vim.api.nvim_create_autocmd("BufWinEnter", {
      buffer = bufnr,
      callback = function()
        apply(bufnr)
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      callback = function()
        cache[bufnr] = nil
      end,
    })
  end
end

function M.update(bufnr, view, beads)
  local installed = cache[bufnr]
  if installed == nil then
    return
  end

  installed.winbar = M.render(M.entries(bufnr, installed.specs, installed.extra))
  installed.statusline = M.counts(view, beads)
  apply(bufnr)
end

function M.rendered(bufnr)
  local rendered = cache[bufnr]
  if rendered == nil then
    return nil
  end
  return {
    winbar = rendered.winbar,
    statusline = rendered.statusline,
  }
end

return M
