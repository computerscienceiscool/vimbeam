# Collaborative Editing System

Three repos work together to provide real-time collaborative editing between a browser and Neovim.

## Repos

### collab-awareness (`~/lab/collab-awareness`)

Shared library providing cursor/presence synchronization. Contains three parts:

- **Server** (`server/index.js`) — A WebSocket broadcast relay on port 1235. Stateless: forwards every message to all other connected clients. No document routing; filtering is client-side.
- **Browser client** (`client/browser.js`) — `AwarenessClient` class for browser environments. Manages local state (user name, color, cursor position, typing), broadcasts via WebSocket, and filters incoming messages by `documentId`. Also exports `CursorWidget`, `remoteCursorPlugin` (CodeMirror 6 extension), `createUserList`, and `createTypingIndicator`.
- **Node client** (`client/node.js`) — `AwarenessClientNode` class for Node.js. Same protocol as the browser client but uses the `ws` package. Filters incoming messages by `documentId`.

### collab-web-editor (`~/lab/collab-web-editor`)

Browser-based collaborative editor. CodeMirror 6 frontend with Automerge CRDT backend.

- Connects to the Automerge sync server (port 1234) for document sync
- Connects to the awareness server (port 1235) for cursor/presence
- Uses `@collab-editor/awareness` as a `file:` dependency (`../collab-awareness`)
- Sends cursor position on `selectionchange`, `mouseup`, `keyup` events
- Renders remote cursors via `remoteCursorPlugin` CodeMirror extension

### viduct (`~/lab/viduct`)

Neovim plugin for collaborative editing. Two layers:

- **Lua plugin** (`lua/viduct/init.lua`) — Neovim commands (`:DuctConnect`, `:DuctOpen`, etc.), buffer management, cursor tracking via `CursorMoved`/`CursorMovedI` autocmds, remote cursor rendering via extmarks.
- **Node helper** (`node-helper/index.js`) — Child process spawned by the Lua plugin. Speaks Automerge sync protocol to the sync server and JSON over stdin/stdout to Neovim. Uses `@collab-editor/awareness/node` (from `../collab-awareness`) for cursor presence.

## Data Flow

```
                    Automerge Sync Server (port 1234)
                   /                                \
                  / document sync (CBOR/binary)      \
                 /                                    \
  collab-web-editor                              viduct node-helper
  (browser)                                      (Node.js child process)
                 \                                    /
                  \ cursor/presence (JSON)            /
                   \                                 /
                    Awareness Server (port 1235)

                                                viduct node-helper
                                                    |
                                                    | JSON over stdin/stdout
                                                    |
                                                Neovim (Lua plugin)
```

**Text sync:** Both clients connect to the Automerge sync server. Edits are CRDT-merged automatically. The browser uses IndexedDB for local storage; viduct uses the filesystem (`~/.local/share/viduct/automerge-data`).

**Cursor sync:** Both clients connect to the awareness server. Each broadcasts `{ type: "awareness", clientID, documentId, state: { user, selection, typing } }`. The server relays to all other clients. Clients filter by `documentId` to ignore messages from other documents.

## How to Start

### Quick start (from collab-web-editor)

```bash
cd ~/lab/collab-web-editor
make start DOC=<document-id>    # starts all 3 servers + opens browser
```

This starts:
- Automerge sync server on port 1234
- Awareness server on port 1235 (runs `../collab-awareness/server/index.js`)
- Vite dev server on port 8080

### Individual servers

```bash
# Sync server
cd ~/lab/collab-web-editor
make sync

# Awareness server
cd ~/lab/collab-web-editor
make awareness
# or directly:
cd ~/lab/collab-awareness && node server/index.js

# Web editor
cd ~/lab/collab-web-editor
make web
```

### Neovim (viduct)

With servers running:

```vim
:DuctConnect                          " connect to defaults (ws://localhost:1234, ws://localhost:1235)
:DuctCreate                           " create a new document
:DuctOpen <document-id>               " open existing document
```

Or with custom URLs:

```vim
:DuctConnect ws://host:1234 ws://host:1235
```

### Stop everything

```bash
cd ~/lab/collab-web-editor
make stop                             " stops sync, awareness, and web servers
```

In Neovim: `:DuctDisconnect`

### Check status

```bash
cd ~/lab/collab-web-editor
make status
```

## Ports

| Service            | Default Port | Config                          |
|--------------------|-------------|---------------------------------|
| Automerge sync     | 1234        | `SYNC_PORT` env / Makefile var  |
| Awareness          | 1235        | `AWARENESS_PORT` env / Makefile var |
| Vite dev server    | 8080        | `VITE_PORT` env / Makefile var  |

Both viduct and collab-web-editor default to 1234/1235. Override in viduct via `:DuctConnect <sync_url> <awareness_url>` or in `setup()` config.
