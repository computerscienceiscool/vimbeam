# Repository Guidelines

## Project Structure & Module Organization
- `lua/viduct/` contains the Neovim plugin Lua modules.
- `node-helper/` contains the Node.js bridge to Automerge for document sync.
- `plugin/` contains the Vim plugin loader script.
- `docs/` contains documentation (protocol specs, etc.).
- `TODO/` tracks work items; `TODO/TODO.md` is the index (sorted by priority).
- Local state like `.grok/` is ignored; do not commit generated state or binaries.

## Build, Test, and Development Commands
- `cd node-helper && npm install` installs Node.js dependencies.
- Test the plugin by loading it in Neovim with a plugin manager or manually adding to runtimepath.
- Node helper can be tested standalone: `node node-helper/index.js`

## Coding Style & Naming Conventions
- Lua code follows standard Neovim plugin conventions.
- Use `vim.api.*` and `vim.fn.*` for Neovim API calls.
- Node.js code uses ES modules (`"type": "module"` in package.json).
- Prefer small, focused edits; avoid rearranging files without a clear need.
- Use `git mv` for renames to preserve history.

## Testing Guidelines
- Test plugin functionality manually in Neovim with a running sync server.
- Keep tests deterministic; mock external dependencies where possible.

## TODO Tracking
- Preferred: track work in `TODO/` with an index at `TODO/TODO.md`; number using letter-prefixed IDs (see below); don't renumber; sort by priority.
- TODO IDs use `LNNN` format (letter prefix + 3 digits), e.g. `S015`, `J016`.
  - Prefixes correspond to who creates the TODO: `S` = Steve, `J` = JJ.
  - To determine your prefix: run `git config user.name` and use the first letter (uppercase).
  - Example: `git config user.name` returns "JJ" → use `J` prefix; returns "Steve" → use `S` prefix.
- Transition rule: if an existing TODO is referenced without a letter (e.g., `015`), treat it as `S015` (default is Steve).
- Keep integer parts globally unique during transition: avoid creating both `J001` and `S001` in the same repo until all existing TODOs are renamed.
- When bulk-renaming existing TODO files to add prefixes, use `git mv` (not `mv`/`rm`) and do the renames in one commit without mixing other work.
- Mark completion with checkboxes (e.g., `- [ ] J005 - ...` → `- [x] J005 - ...`).
- Legacy: root `TODO.md` exists for historical reference; update `TODO/TODO.md` going forward.

## Commit & Pull Request Guidelines
- Commit subjects are short, imperative, and capitalized (e.g., "Fix cursor sync").
- In commit bodies, summarize the diff with a section per changed file using bullets.
- When staging, list files explicitly (avoid `git add .` / `git add -A`).
- PRs include a concise summary, the test commands run, and linked issues; add before/after notes when behavior changes.

## Agent-Specific Instructions (Codex CLI)
- Check `~/.codex/AGENTS.md` periodically for updated local conventions.
- Use `notify-send` when requesting user attention and when a task is complete.
