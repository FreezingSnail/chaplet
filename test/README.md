# Shared test doubles

`fake-bd` and `fake-dot` are read from source below. This documents their current behavior.

## `fake-bd`

Invocation is `fake-bd -C <root> <subcommand> [args...]`.

Read subcommands emit canned output and exit successfully:

- `list`, `query`, `show`, and `comments` emit canned JSON.
- `graph` emits canned DOT.

Write subcommands exit successfully without changing the canned data:

- `create`, `comment`, `undefer`, `defer`, `update`, and `label`.

Any other subcommand exits with status 1.

When `CHAPLET_FAKE_BD_STATE` names a file, stateful behavior is enabled:

- `undefer <id>` appends `APPROVED <id>`.
- `comment <id> <text>` appends `COMMENT <id> <text>`.
- `query` filters approved ids out of the inbox response.

The shared state-file path used by the tests is `test/.fake-bd-state`; it is already gitignored.

## `fake-dot`

`fake-dot` consumes standard input and prints a fixed empty SVG, then exits successfully.

## Binding rule

Exactly one copy of each double lives here. Every plugin resolves its doubles from the repository root. If a plugin needs new `bd` behavior, extend this file so the other plugin's suite re-runs against the change.
