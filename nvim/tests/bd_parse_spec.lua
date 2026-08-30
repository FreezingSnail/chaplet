local bd = require("chaplet.bd")
local config = require("chaplet.config")

local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = vim.fn.fnamemodify(source, ":h")
local fake_bd = vim.fn.fnamemodify(test_dir .. "/../../test/fake-bd", ":p")

describe("chaplet.bd parsing", function()
  before_each(function()
    config.setup({ bd_program = fake_bd })
  end)

  it("exports the elisp field order", function()
    assert.same({
      "id",
      "title",
      "description",
      "status",
      "priority",
      "issue_type",
      "owner",
      "labels",
      "dependencies",
      "defer_until",
      "design",
      "acceptance",
      "created_at",
      "updated_at",
      "parent",
    }, bd.FIELDS)
  end)

  it("parses empty, null, objects, and arrays", function()
    assert.is_nil(bd._parse("  \n\t "))
    assert.is_nil(bd._parse(" null\n"))
    assert.same({ { id = "bd-1" } }, bd._parse(' {"id":"bd-1"} '))
    assert.same({ { id = "bd-1" }, { id = "bd-2" } }, bd._parse('[{"id":"bd-1"},{"id":"bd-2"}]'))
  end)

  it("scrubs JSON null values recursively", function()
    local scrubbed = bd._scrub(vim.json.decode('{"top":null,"nested":{"value":null}}'))

    assert.is_nil(scrubbed.top)
    assert.is_nil(scrubbed.nested.value)
  end)

  it("normalizes fake-bd payloads and scrubs null defer_until", function()
    local payload = bd._parse(bd.invoke({ "list" }).stdout)
    local bead = bd._normalize(payload[1])

    assert.equals("bd-1", bead.id)
    assert.is_nil(bead.defer_until)
    assert.equals("", bead.acceptance)
    assert.is_nil(bead.extra)
  end)

  it("uses acceptance_criteria only when acceptance is absent", function()
    local fallback = bd._normalize({ acceptance_criteria = "fallback" })
    local explicit = bd._normalize({ acceptance = "explicit", acceptance_criteria = "fallback" })
    local fake_payload = bd._parse(bd.invoke({ "show", "bd-1" }).stdout)
    local fake_fallback = bd._normalize(fake_payload[1])

    assert.equals("fallback", fallback.acceptance)
    assert.equals("explicit", explicit.acceptance)
    assert.equals("acc1", fake_fallback.acceptance)
  end)

  it("flattens dependency objects while preserving plain identifiers", function()
    local dependencies = bd._normalize_deps({
      { issue_id = "bd-2", depends_on_id = "bd-1", type = "blocks", metadata = "{}" },
      "bd-0",
    })

    assert.same({ "bd-1", "bd-0" }, dependencies)
    assert.same({ "bd-1" }, bd._normalize({
      dependencies = { { issue_id = "bd-2", depends_on_id = "bd-1", type = "blocks", metadata = "{}" } },
    }).dependencies)
    assert.is_nil(bd._normalize_deps(nil))
  end)

  it("drops unknown keys and leaves every missing field absent", function()
    local bead = bd._normalize({ id = "bd-1", unknown = "drop" })
    local key = next(bead)

    assert.equals("id", key)
    assert.is_nil(next(bead, key))
    assert.is_nil(bead.unknown)
  end)
end)
