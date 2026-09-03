local bar = require("chaplet.bar")
local list = require("chaplet.list")

local function new_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

local function delete_buffer(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

describe("chaplet.bar", function()
  it("keeps candidate entries in display order", function()
    assert.same({
      { key = "<CR>", label = "open" },
      { key = "v", label = "view switch" },
      { key = "s", label = "graph" },
      { key = "?", label = "actions" },
      { key = "q", label = "quit" },
      { key = "<LeftMouse>", label = "open" },
    }, bar.SPECS)
  end)

  it("includes only mapped candidates and always includes extras", function()
    local bufnr = new_buffer()
    for _, key in ipairs({ "<CR>", "v", "?", "q", "<LeftMouse>" }) do
      vim.api.nvim_buf_set_keymap(bufnr, "n", key, "<Nop>", {})
    end

    assert.same({
      { key = "<CR>", label = "open" },
      { key = "v", label = "view switch" },
      { key = "?", label = "actions" },
      { key = "q", label = "quit" },
      { key = "<LeftMouse>", label = "open" },
    }, bar.bound(bufnr, bar.SPECS))
    assert.same({
      { key = "q", label = "quit" },
      { key = "mouse-1", label = "open" },
    }, bar.entries(bufnr, { { key = "q", label = "quit" } }, {
      { key = "mouse-1", label = "open" },
    }))

    delete_buffer(bufnr)
  end)

  it("renders exact reference text and an empty bar", function()
    assert.equals(" [<CR>] open [v] view switch [?] actions", bar.render({
      { key = "<CR>", label = "open" },
      { key = "v", label = "view switch" },
      { key = "?", label = "actions" },
    }))
    assert.equals("", bar.render({}))
    assert.equals("", bar.render(nil))
  end)

  it("counts the rendered bead set", function()
    assert.equals(
      "chaplet open · 4 beads · 2 open · 1 blocked",
      bar.counts("open", {
        { status = "open" },
        { status = "blocked" },
        { status = "open" },
        { status = "closed" },
      })
    )
    assert.equals("chaplet all · 0 beads · 0 open · 0 blocked", bar.counts("all", {}))
  end)

  it("installs idempotently and updates cached window strings", function()
    local bufnr = new_buffer()
    vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<Nop>", {})
    local specs = {
      { key = "q", label = "quit" },
      { key = "s", label = "graph" },
    }

    bar.install(bufnr, specs)
    local first = bar.rendered(bufnr)
    bar.install(bufnr, specs)
    assert.same(first, bar.rendered(bufnr))
    assert.equals(first.winbar, vim.wo[vim.api.nvim_get_current_win()].winbar)
    assert.equals(first.statusline, vim.wo[vim.api.nvim_get_current_win()].statusline)

    vim.api.nvim_buf_set_keymap(bufnr, "n", "s", "<Nop>", {})
    bar.update(bufnr, "blocked", { { status = "blocked" } })
    local updated = bar.rendered(bufnr)
    assert.equals(" [q] quit [s] graph", updated.winbar)
    assert.equals("chaplet blocked · 1 beads · 0 open · 1 blocked", updated.statusline)
    assert.equals(updated.winbar, vim.wo[vim.api.nvim_get_current_win()].winbar)
    assert.equals(updated.statusline, vim.wo[vim.api.nvim_get_current_win()].statusline)

    delete_buffer(bufnr)
  end)

  it("updates from list.render, including epic headers", function()
    local bufnr = list.buffer()
    list.render(bufnr, {
      { id = "epic", issue_type = "epic", status = "open", title = "Epic" },
      { id = "task", parent = "epic", status = "blocked", title = "Task" },
    })

    local rendered = bar.rendered(bufnr)
    assert.equals("chaplet inbox · 2 beads · 1 open · 1 blocked", rendered.statusline)
    assert.equals(" [<CR>] open [v] view switch [?] actions [q] quit [<LeftMouse>] open", rendered.winbar)

    delete_buffer(bufnr)
  end)
end)
