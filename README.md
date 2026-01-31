# collab-editor-neovim

A Neovim plugin for real-time collaborative editing using [Automerge](https://automerge.org/) CRDTs.

## Features

- Real-time collaborative text editing
- Remote cursor and selection display
- Works with any Automerge sync server
- Customizable user names and cursor colors

## Prerequisites

- Neovim 0.8+
- Node.js 18+
- A running Automerge sync server (for document sync)
- A running awareness server (for cursor sync)

## Server Setup

This plugin requires two WebSocket servers:

1. **Automerge Sync Server** - Handles document synchronization using the Automerge sync protocol
2. **Awareness Server** - Broadcasts cursor positions and user presence

You can use [automerge-repo-sync-server](https://github.com/automerge/automerge-repo-sync-server) for the sync server:

```bash
npx @automerge/automerge-repo-sync-server --port 1234
```

For the awareness server, you'll need a simple WebSocket broadcast server. A minimal example:

```bash
npx y-websocket --port 1235
```

Or run both from the companion [collab-editor](https://github.com/computerscienceiscool/collab-editor) project which includes pre-configured servers.

## Installation

### lazy.nvim

```lua
{
  'computerscienceiscool/collab-editor-neovim',
  build = 'cd node-helper && npm install',
  config = function()
    require('collab-editor').setup({
      sync_url = 'ws://localhost:1234',
      awareness_url = 'ws://localhost:1235',
      user_name = 'Your Name',
      user_color = '#4ECDC4',
    })
  end,
}
```

### packer.nvim

```lua
use {
  'computerscienceiscool/collab-editor-neovim',
  run = 'cd node-helper && npm install',
  config = function()
    require('collab-editor').setup({
      sync_url = 'ws://localhost:1234',
      awareness_url = 'ws://localhost:1235',
    })
  end,
}
```

### vim-plug

```vim
Plug 'computerscienceiscool/collab-editor-neovim', { 'do': 'cd node-helper && npm install' }
```

Then in your `init.lua`:

```lua
require('collab-editor').setup({
  sync_url = 'ws://localhost:1234',
  awareness_url = 'ws://localhost:1235',
})
```

### Manual

```bash
git clone https://github.com/computerscienceiscool/collab-editor-neovim.git ~/.local/share/nvim/site/pack/plugins/start/collab-editor-neovim
cd ~/.local/share/nvim/site/pack/plugins/start/collab-editor-neovim/node-helper
npm install
```

Then in your `init.lua`:

```lua
require('collab-editor').setup()
```

## Configuration

```lua
require('collab-editor').setup({
  -- Automerge sync server URL
  sync_url = 'ws://localhost:1234',

  -- Awareness server URL (for cursor sync)
  awareness_url = 'ws://localhost:1235',

  -- Path to node helper (auto-detected if nil)
  node_helper_path = nil,

  -- Your display name
  user_name = nil,

  -- Your cursor color (hex format)
  user_color = nil,

  -- Enable debug logging
  debug = false,
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:CollabConnect` | Connect to the collaboration server |
| `:CollabDisconnect` | Disconnect from the server |
| `:CollabCreate` | Create a new collaborative document |
| `:CollabOpen <doc_id>` | Open an existing document by ID |
| `:CollabClose` | Close the current collaborative document |
| `:CollabInfo` | Show connection status |
| `:CollabUserName <name>` | Set your display name |
| `:CollabUserColor [color]` | Set cursor color (by name or hex, or show picker) |
| `:CollabQuick <doc_id>` | Connect and open a document in one step |

## Usage

1. Start your Automerge sync server
2. Connect to the server: `:CollabConnect`
3. Create a new document: `:CollabCreate`
4. Share the document ID with collaborators
5. Others can join with: `:CollabOpen <doc_id>`

## Color Options

Use `:CollabUserColor` with no argument to show a color picker, or specify a color:

- By name: `:CollabUserColor Green`
- By hex: `:CollabUserColor #4ECDC4`

Available color names: Red, Orange, Yellow, Green, Teal, Blue, Purple, Pink, and more.

## Architecture

The plugin consists of two parts:

1. **Lua plugin** (`lua/collab-editor/`) - Neovim interface, buffer management, cursor display
2. **Node.js helper** (`node-helper/`) - Automerge document sync via WebSocket

Communication between Lua and Node.js happens via JSON messages over stdin/stdout. See [docs/PROTOCOL.md](docs/PROTOCOL.md) for details.

```
collab-editor-neovim/
├── lua/
│   └── collab-editor/
│       └── init.lua          # Main plugin module
├── node-helper/
│   ├── index.js              # Automerge bridge
│   ├── package.json
│   └── package-lock.json
├── plugin/
│   └── collab-editor.vim     # Vim plugin loader
├── docs/
│   └── PROTOCOL.md           # JSON protocol spec
├── AGENTS.md
└── README.md
```

## License

MIT
