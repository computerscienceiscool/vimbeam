# JSON Message Protocol

This document describes the JSON message protocol used for communication between the Neovim Lua plugin and the Node.js helper process.

Communication occurs over stdin/stdout with one JSON message per line.

## Overview

```
┌─────────────────┐         stdin (JSON)         ┌─────────────────┐
│                 │ ───────────────────────────► │                 │
│  Neovim Plugin  │                              │  Node.js Helper │
│  (Lua)          │ ◄─────────────────────────── │  (Automerge)    │
│                 │        stdout (JSON)         │                 │
└─────────────────┘                              └─────────────────┘
```

## Messages: Plugin → Helper

### connect

Establish connection to collaboration servers.

```json
{
  "type": "connect",
  "syncUrl": "ws://localhost:1234",
  "awarenessUrl": "ws://localhost:1235",
  "name": "Alice",
  "color": "#4ECDC4"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| syncUrl | string | yes | Automerge sync server WebSocket URL |
| awarenessUrl | string | no | Awareness server WebSocket URL for cursor sync |
| name | string | no | Initial display name |
| color | string | no | Initial cursor color (hex format) |

### disconnect

Close all connections and clean up.

```json
{
  "type": "disconnect"
}
```

### create

Create a new collaborative document.

```json
{
  "type": "create"
}
```

### open

Open an existing document by ID.

```json
{
  "type": "open",
  "docId": "3tFP3srLo4iHBPADoLtJ"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| docId | string | yes | Document ID (with or without `automerge:` prefix) |

### edit

Update document content.

```json
{
  "type": "edit",
  "content": "Hello, world!"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| content | string | yes | Full document content |

### close

Close the current document.

```json
{
  "type": "close"
}
```

### cursor

Update cursor/selection position.

```json
{
  "type": "cursor",
  "offset": 42,
  "selection": {
    "anchor": 42,
    "head": 50
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| offset | number | yes | Cursor position as character offset from document start |
| selection | object | no | Selection range (if text is selected) |
| selection.anchor | number | yes* | Selection start offset |
| selection.head | number | no | Selection end offset (defaults to anchor if omitted) |

### set_name

Change display name.

```json
{
  "type": "set_name",
  "name": "Bob"
}
```

### set_color

Change cursor color.

```json
{
  "type": "set_color",
  "color": "#FF6B6B"
}
```

### info

Request connection status.

```json
{
  "type": "info"
}
```

## Messages: Helper → Plugin

### connected

Connection established.

```json
{
  "type": "connected",
  "userId": "nvim-a1b2c3d4"
}
```

| Field | Type | Description |
|-------|------|-------------|
| userId | string | Unique identifier for this session |

### disconnected

Connection closed.

```json
{
  "type": "disconnected"
}
```

### created

New document created.

```json
{
  "type": "created",
  "docId": "automerge:3tFP3srLo4iHBPADoLtJ"
}
```

| Field | Type | Description |
|-------|------|-------------|
| docId | string | ID of the created document |

### opened

Document opened successfully.

```json
{
  "type": "opened",
  "docId": "3tFP3srLo4iHBPADoLtJ",
  "content": "Document content here..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| docId | string | ID of the opened document |
| content | string | Current document content |

### changed

Document content changed (remote edit received).

```json
{
  "type": "changed",
  "content": "Updated content..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| content | string | Full updated document content |

### closed

Document closed.

```json
{
  "type": "closed"
}
```

### cursor

Remote user cursor update.

```json
{
  "type": "cursor",
  "userId": "nvim-x1y2z3",
  "name": "Alice",
  "color": "#4ECDC4",
  "anchor": 100,
  "head": 150
}
```

| Field | Type | Description |
|-------|------|-------------|
| userId | string | Remote user's ID |
| name | string | Remote user's display name |
| color | string | Remote user's cursor color |
| anchor | number | Cursor/selection start offset (null if unavailable) |
| head | number | Selection end offset (null if no selection) |

### info

Connection status response.

```json
{
  "type": "info",
  "connected": true,
  "docId": "3tFP3srLo4iHBPADoLtJ",
  "userId": "nvim-a1b2c3d4",
  "userName": "Alice"
}
```

### error

Error occurred.

```json
{
  "type": "error",
  "message": "Not connected"
}
```

### name_set

Confirmation that name was updated.

```json
{
  "type": "name_set",
  "name": "Bob"
}
```

### color_set

Confirmation that color was updated.

```json
{
  "type": "color_set",
  "color": "#FF6B6B"
}
```

## Character Offsets

All cursor and selection positions use **character offsets** (not byte offsets) from the start of the document. This ensures correct behavior with Unicode/multibyte characters.

Example for document `"Hello, 世界!"`:
- `H` is at offset 0
- `,` is at offset 5
- `世` is at offset 7
- `!` is at offset 9

## Awareness Protocol

The awareness server uses a separate WebSocket connection for real-time cursor synchronization. Messages are JSON with this structure:

```json
{
  "type": "awareness",
  "clientID": "nvim-a1b2c3d4",
  "state": {
    "user": {
      "name": "Alice",
      "color": "#4ECDC4"
    },
    "typing": false,
    "selection": {
      "anchor": 42,
      "head": 50
    }
  },
  "documentId": "3tFP3srLo4iHBPADoLtJ"
}
```

The helper broadcasts awareness state periodically (every 5 seconds) and on cursor changes.
