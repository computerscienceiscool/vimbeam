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
- Keep a `TODO/` directory and an index at `TODO/TODO.md`.
- Number TODOs with 3 digits (e.g., `005`); do not renumber—use the next available number.
- In `TODO/*`, include numbered checkbox subtasks (e.g., `- [ ] 005.1 describe subtask`).
- When completing a TODO, check it off in `TODO/TODO.md` (e.g., `- [x] 005 - ...`).

## Commit & Pull Request Guidelines
- Commit subjects are short, imperative, and capitalized (e.g., "Fix cursor sync").
- In commit bodies, summarize the diff with a section per changed file using bullets.
- When staging, list files explicitly (avoid `git add .` / `git add -A`).
- PRs include a concise summary, the test commands run, and linked issues; add before/after notes when behavior changes.

## Agent-Specific Instructions (Codex CLI)
- Check `~/.codex/AGENTS.md` periodically for updated local conventions.
- Use `notify-send` when requesting user attention and when a task is complete.
