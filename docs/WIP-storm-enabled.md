# Integration Plan: Viduct Storm Mode

## Overview

Add Storm LLM chat capabilities to viduct while maintaining full compatibility with existing Automerge collaborative editing.

## Architecture: Three Independent Pieces

```
┌─────────────────────────────────────────────────────────────┐
│                         Neovim (Lua)                        │
│  - Commands (:StormConnect, :DuctConnect, etc.)             │
│  - Buffers (collaborative docs, chat display)               │
│  - State management (mode: 'automerge' | 'storm' | null)    │
└─────────────────┬───────────────────────────────────────────┘
                  │ JSON over stdin/stdout
                  │
┌─────────────────▼───────────────────────────────────────────┐
│                    Node Helper (index.js)                   │
│  - Message router                                           │
│  - Automerge repo + WebSocket (existing)                    │
│  - Storm WebSocket (new)                                    │
│  - Protocol translator                                      │
└─────────────────┬──────────────────┬────────────────────────┘
                  │                  │
     ┌────────────▼─────┐   ┌───────▼──────────┐
     │  Automerge Sync  │   │  Storm Server    │
     │  + Awareness     │   │  (port 8080)     │
     │  (port 1234/35)  │   │                  │
     └──────────────────┘   └──────────────────┘
```

## Core Principle: Mode Isolation

**The two modes NEVER interact:**
- Automerge mode = collaborative document editing
- Storm mode = LLM chat in a project
- Plugin state tracks which mode is active
- User explicitly switches between modes with commands
- Each mode has its own buffer, state, and WebSocket connections

## Connection Requirements

### Requirement 1: Dual Connection Support

Node helper must support **both connections simultaneously**:
- Automerge WebSocket remains connected when Storm is active
- Storm WebSocket remains connected when Automerge is active
- Each has independent state variables (repo/handle vs stormWs/stormProjectId)
- Disconnecting one mode does NOT disconnect the other

### Requirement 2: Message Routing

Node helper routes messages based on type:
- `type: 'connect'` → Automerge repo initialization
- `type: 'storm_connect'` → Storm WebSocket connection
- `type: 'edit'` → Automerge document update
- `type: 'storm_query'` → Storm query submission
- Messages from Automerge WebSocket → forward to Neovim with Automerge types
- Messages from Storm WebSocket → forward to Neovim with Storm types

### Requirement 3: Protocol Translation

Node helper translates between viduct and Storm protocols:

**Viduct → Storm:**
- `storm_connect` → open WebSocket to `/project/{projectID}/ws`
- `storm_query` → send `{type: "query", query: "...", llm: "...", inputFiles: [...], outFiles: [...]}`
- `storm_disconnect` → close Storm WebSocket

**Storm → Viduct:**
- `{type: "query", ...}` → forward as `{type: "storm_query", data: {...}}`
- `{type: "response", ...}` → forward as `{type: "storm_response", data: {...}}`
- `{type: "filesUpdated", ...}` → forward as `{type: "storm_files_updated", data: {...}}`

### Requirement 4: State Independence

Each mode maintains separate state in Neovim:

**Automerge state:**
- `doc_id` - current collaborative document
- `bufnr` - buffer with collaborative editing
- `remote_cursors` - cursor positions from other users

**Storm state:**
- `project_id` - current Storm project
- `chat_bufnr` - chat display buffer
- `other_users` - presence info from Storm

**Shared state:**
- `job_id` - the node helper process
- `connected` - whether helper is running
- `mode` - which mode is currently active ('automerge' | 'storm' | null)

## Prerequisites

### Before Starting Implementation:

1. **Storm server must be running** on port 8080
2. **Storm project must exist** - created via `storm project add test-project /path /path/chat.md`
3. **Automerge servers must be running** on ports 1234/1235 (if using Automerge mode)
4. **Node dependencies installed** in `node-helper/`

## Implementation Phases

### Phase 1: Debug Silent Failure
**Goal:** Get ANY response from Storm connection attempt

**Tasks:**
1. Enable debug logging in both Lua and node helper
2. Verify message reaches node helper from Lua
3. Verify node helper attempts WebSocket connection to Storm
4. Verify Storm server receives connection
5. Verify response makes it back to Neovim

**Success criteria:** See either "Connected to Storm: test-project" OR a meaningful error message

### Phase 2: Complete Storm Message Handlers
**Goal:** Handle all Storm message types

**Tasks:**
1. Add missing node helper message handlers (storm_disconnect, storm_list_projects, storm_open_project, storm_query)
2. Add missing Lua message handlers (storm_connected, storm_disconnected, storm_query, storm_response, etc.)
3. Implement Storm-specific Lua functions (disconnect_storm, list_storm_projects, etc.)

**Success criteria:** Can send and receive each message type without errors

### Phase 3: Chat Buffer UI
**Goal:** Display Storm chat in a buffer

**Tasks:**
1. Create/manage chat buffer
2. Append queries to buffer
3. Append responses to buffer
4. Handle markdown rendering

**Success criteria:** Can see query/response conversation in split window

### Phase 4: End-to-End Testing
**Goal:** Verify complete workflow

**Tasks:**
1. Connect to Storm project
2. Send query with input/output files
3. Receive and display response
4. Switch between projects
5. Disconnect cleanly
6. **Verify Automerge still works** - critical!

**Success criteria:** All Storm features work AND Automerge mode still functions normally

## Testing Strategy

### Test 1: Mode Independence
1. Start with Automerge: `:DuctConnect` → `:DuctCreate` → edit buffer
2. Switch to Storm: `:StormConnect test-project` → send query
3. Verify both buffers remain intact and functional
4. Disconnect Storm: `:StormDisconnect`
5. Verify Automerge editing still works
6. Disconnect Automerge: `:DuctDisconnect`
7. Reconnect to Automerge and verify no corruption

### Test 2: Storm Full Workflow
1. Connect: `:StormConnect test-project`
2. Verify chat buffer opens with header
3. Send query: `:StormQuery What files are in this project?`
4. Verify query appears in buffer
5. Wait for response
6. Verify response appears in buffer
7. List projects: `:StormProject`
8. Verify project picker appears
9. Switch project via picker
10. Verify new project context loads
11. Disconnect: `:StormDisconnect`
12. Verify clean shutdown

### Test 3: Error Handling
1. Try `:StormConnect` without `:DuctConnect` first → should error gracefully
2. Try `:StormConnect nonexistent-project` → should show meaningful error
3. Kill Storm server mid-query → should handle connection loss
4. Send query with invalid file paths → should error gracefully

## Risk Mitigation

### Risk 1: Breaking Automerge Mode
**Mitigation:** 
- Never touch existing Automerge message handlers
- Keep Storm state completely separate
- Test Automerge after every Storm change

### Risk 2: Protocol Mismatch
**Mitigation:**
- Document exact message formats from both sides
- Test each message type individually
- Use debug logging to inspect actual messages

### Risk 3: State Corruption
**Mitigation:**
- Clear Storm state on disconnect
- Never mix Automerge and Storm state variables
- Reset mode flag appropriately

## Success Criteria

✅ Can use Automerge mode exactly as before
✅ Can connect to Storm project and see confirmation
✅ Can send Storm query and receive response
✅ Chat buffer displays conversation history
✅ Can switch between Storm projects
✅ Can disconnect from Storm cleanly
✅ Debug logging helps troubleshoot issues
✅ Error messages are clear and actionable

## Rollback Plan

If Storm integration breaks Automerge:
1. Git revert to last working commit
2. Create separate branch for Storm work
3. Use feature flag to disable Storm features
4. Keep Storm code isolated in separate functions/sections
