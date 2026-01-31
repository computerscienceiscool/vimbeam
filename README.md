# vimbeam

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

See [docs/PROTOCOL.md](docs/PROTOCOL.md) for details on running your own servers.

## Installation

### lazy.nvim

```lua
{
  'computerscienceiscool/vimbeam',
  build = 'cd node-helper && npm install',
  config = function()
    require('vimbeam').setup({
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
  'computerscienceiscool/vimbeam',
  run = 'cd node-helper && npm install',
  config = function()
    require('vimbeam').setup({
      sync_url = 'ws://localhost:1234',
      awareness_url = 'ws://localhost:1235',
    })
  end,
}
```

### vim-plug

```vim
Plug 'computerscienceiscool/vimbeam', { 'do': 'cd node-helper && npm install' }
```

Then in your `init.lua`:

```lua
require('vimbeam').setup({
  sync_url = 'ws://localhost:1234',
  awareness_url = 'ws://localhost:1235',
})
```

### Manual

```bash
git clone https://github.com/computerscienceiscool/vimbeam.git ~/.local/share/nvim/site/pack/plugins/start/vimbeam
cd ~/.local/share/nvim/site/pack/plugins/start/vimbeam/node-helper
npm install
```

Then in your `init.lua`:

```lua
require('vimbeam').setup()
```

## Configuration

```lua
require('vimbeam').setup({
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
| `:BeamConnect` | Connect to the collaboration server |
| `:BeamDisconnect` | Disconnect from the server |
| `:BeamCreate` | Create a new collaborative document |
| `:BeamOpen <doc_id>` | Open an existing document by ID |
| `:BeamClose` | Close the current collaborative document |
| `:BeamInfo` | Show connection status |
| `:BeamUserName <name>` | Set your display name |
| `:BeamUserColor [color]` | Set cursor color (by name or hex, or show picker) |
| `:BeamQuick <doc_id>` | Connect and open a document in one step |

## Usage

1. Start your Automerge sync server
2. Connect to the server: `:BeamConnect`
3. Create a new document: `:BeamCreate`
4. Share the document ID with collaborators
5. Others can join with: `:BeamOpen <doc_id>`

## Color Options

Use `:BeamUserColor` with no argument to show a color picker, or specify a color:

- By name: `:BeamUserColor Green`
- By hex: `:BeamUserColor #4ECDC4`

Available color names: Red, Orange, Yellow, Green, Teal, Blue, Purple, Pink, and more.

## Architecture

The plugin consists of two parts:

1. **Lua plugin** (`lua/vimbeam/`) - Neovim interface, buffer management, cursor display
2. **Node.js helper** (`node-helper/`) - Automerge document sync via WebSocket

Communication between Lua and Node.js happens via JSON messages over stdin/stdout. See [docs/PROTOCOL.md](docs/PROTOCOL.md) for details.

```
vimbeam/
├── lua/
│   └── vimbeam/
│       └── init.lua          # Main plugin module
├── node-helper/
│   ├── index.js              # Automerge bridge
│   ├── package.json
│   └── package-lock.json
├── plugin/
│   └── vimbeam.vim     # Vim plugin loader
├── docs/
│   └── PROTOCOL.md           # JSON protocol spec
├── AGENTS.md
└── README.md
```

## License

MIT
