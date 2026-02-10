# viduct

A Neovim plugin that allows Neovim users to collaborate in real time with other Neovim users and web users via [Automerge](https://automerge.org/) CRDTs.

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

For the awareness server, use [@collab-editor/awareness](https://github.com/computerscienceiscool/collab-awareness):

```bash
npx @collab-editor/awareness --port 1235
```

See [docs/PROTOCOL.md](docs/PROTOCOL.md) for details on running your own servers.

## Installation

### lazy.nvim

```lua
{
  'computerscienceiscool/viduct',
  build = 'cd node-helper && npm install',
  config = function()
    require('viduct').setup({
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
  'computerscienceiscool/viduct',
  run = 'cd node-helper && npm install',
  config = function()
    require('viduct').setup({
      sync_url = 'ws://localhost:1234',
      awareness_url = 'ws://localhost:1235',
    })
  end,
}
```

### vim-plug

```vim
Plug 'computerscienceiscool/viduct', { 'do': 'cd node-helper && npm install' }
```

Then in your `init.lua`:

```lua
require('viduct').setup({
  sync_url = 'ws://localhost:1234',
  awareness_url = 'ws://localhost:1235',
})
```

### Manual

```bash
git clone https://github.com/computerscienceiscool/viduct.git ~/.local/share/nvim/site/pack/plugins/start/viduct
cd ~/.local/share/nvim/site/pack/plugins/start/viduct/node-helper
npm install
```

Then in your `init.lua`:

```lua
require('viduct').setup()
```

## Configuration

```lua
require('viduct').setup({
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
| `:DuctConnect [sync_url] [awareness_url]` | Connect to the collaboration server (uses defaults if no URLs provided) |
| `:DuctDisconnect` | Disconnect from the server |
| `:DuctCreate` | Create a new collaborative document |
| `:DuctOpen <doc_id>` | Open an existing document by ID |
| `:DuctClose` | Close the current collaborative document |
| `:DuctInfo` | Show connection status |
| `:DuctUserName <name>` | Set your display name |
| `:DuctUserColor [color]` | Set cursor color (by name or hex, or show picker) |
| `:DuctQuick <doc_id>` | Connect and open a document in one step |

## Usage

1. Start your Automerge sync server
2. Connect to the server: `:DuctConnect`
3. Create a new document: `:DuctCreate`
4. Share the document ID with collaborators
5. Others can join with: `:DuctOpen <doc_id>`

## Color Options

Use `:DuctUserColor` with no argument to show a color picker, or specify a color:

- By name: `:DuctUserColor Green`
- By hex: `:DuctUserColor #4ECDC4`

Available color names: Red, Orange, Yellow, Green, Teal, Blue, Purple, Pink, and more.

## Architecture

The plugin consists of two parts:

1. **Lua plugin** (`lua/viduct/`) - Neovim interface, buffer management, cursor display
2. **Node.js helper** (`node-helper/`) - Automerge document sync and presence via WebSocket

The Node.js helper uses [@collab-editor/awareness](https://github.com/computerscienceiscool/collab-awareness) for cursor/presence synchronization, enabling real-time collaboration with browser users running [collab-editor](https://github.com/computerscienceiscool/collab-editor).

Communication between Lua and Node.js happens via JSON messages over stdin/stdout. See [docs/PROTOCOL.md](docs/PROTOCOL.md) for details.

```
viduct/
├── lua/
│   └── viduct/
│       └── init.lua          # Main plugin module
├── node-helper/
│   ├── index.js              # Automerge bridge
│   ├── package.json
│   └── package-lock.json
├── plugin/
│   └── viduct.vim     # Vim plugin loader
├── docs/
│   └── PROTOCOL.md           # JSON protocol spec
├── AGENTS.md
└── README.md
```

## License

MIT
