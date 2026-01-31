-- File: nvim/lua/collab-editor/init.lua
-- Main entry point for collab-editor Neovim plugin
-- Works with Automerge-based collaboration server

local M = {}

local protocol = require('collab-editor.protocol')
local buffer = require('collab-editor.buffer')
local cursors = require('collab-editor.cursors')

-- Plugin state
M.state = {
    connected = false,
    room = nil,
    server_url = nil,
    job_id = nil,
    open_documents = {}, -- uri -> { bufnr, editor_revision, daemon_revision }
}

-- Configuration defaults
M.config = {
    server_url = nil, -- Required: ws://your-server:port/ws
    go_helper_path = nil, -- Will be auto-detected
    cursor_update_interval = 100, -- ms
    show_remote_cursors = true,
    debug = false,
}

-- Setup function called by user in their init.lua
function M.setup(opts)
    opts = opts or {}
    M.config = vim.tbl_deep_extend('force', M.config, opts)

    -- Auto-detect go-helper binary if not specified
    if not M.config.go_helper_path then
        -- Try to find it relative to this plugin
        local source = debug.getinfo(1).source
        if source:sub(1, 1) == '@' then
            local plugin_path = source:sub(2):gsub('/lua/collab%-editor/init%.lua$', '')
            M.config.go_helper_path = plugin_path .. '/go-helper/go-helper'
        end
    end

    -- Setup commands
    M.setup_commands()

    if M.config.debug then
        vim.notify('[collab-editor] Plugin loaded', vim.log.levels.DEBUG)
    end
end

-- Setup user commands
function M.setup_commands()
    vim.api.nvim_create_user_command('CollabConnect', function(opts)
        local args = vim.split(opts.args, ' ')
        local server = args[1] or M.config.server_url
        local room = args[2]
        M.connect(server, room)
    end, {
        nargs = '*',
        desc = 'Connect to collaboration server: CollabConnect [server_url] [room]'
    })

    vim.api.nvim_create_user_command('CollabDisconnect', function()
        M.disconnect()
    end, { desc = 'Disconnect from collaboration server' })

    vim.api.nvim_create_user_command('CollabJoin', function(opts)
        M.join_room(opts.args)
    end, {
        nargs = '?',
        desc = 'Join a collaboration room: CollabJoin [room_id]'
    })

    vim.api.nvim_create_user_command('CollabLeave', function()
        M.leave_room()
    end, { desc = 'Leave current collaboration room' })

    vim.api.nvim_create_user_command('CollabOpen', function()
        M.open_current_buffer()
    end, { desc = 'Open current buffer for collaboration' })

    vim.api.nvim_create_user_command('CollabClose', function()
        M.close_current_buffer()
    end, { desc = 'Close current buffer from collaboration' })

    vim.api.nvim_create_user_command('CollabInfo', function()
        M.show_info()
    end, { desc = 'Show collaboration status' })
end

-- Connect to collaboration server
function M.connect(server_url, room)
    if M.state.connected then
        vim.notify('[collab-editor] Already connected. Disconnect first.', vim.log.levels.WARN)
        return false
    end

    server_url = server_url or M.config.server_url
    if not server_url then
        vim.notify('[collab-editor] Server URL required. Use :CollabConnect <url> <room>', vim.log.levels.ERROR)
        return false
    end

    room = room or vim.fn.input('Room ID: ')
    if room == '' then
        vim.notify('[collab-editor] Room ID required', vim.log.levels.ERROR)
        return false
    end

    -- Check if go-helper exists
    local helper_path = M.config.go_helper_path
    if vim.fn.executable(helper_path) == 0 then
        vim.notify('[collab-editor] go-helper not found at: ' .. helper_path, vim.log.levels.ERROR)
        vim.notify('[collab-editor] Build it with: cd nvim/go-helper && go build', vim.log.levels.INFO)
        return false
    end

    -- Start go-helper process
    local cmd = {
        helper_path,
        '--server', server_url,
        '--room', room,
    }

    M.state.job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data, _)
            M.on_stdout(data)
        end,
        on_stderr = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= '' then
                    vim.notify('[collab-editor] Error: ' .. line, vim.log.levels.ERROR)
                end
            end
        end,
        on_exit = function(_, code, _)
            M.on_disconnect(code)
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if M.state.job_id <= 0 then
        vim.notify('[collab-editor] Failed to start go-helper', vim.log.levels.ERROR)
        M.state.job_id = nil
        return false
    end

    M.state.server_url = server_url
    M.state.room = room

    return true
end

-- Disconnect from server
function M.disconnect()
    if not M.state.connected and not M.state.job_id then
        vim.notify('[collab-editor] Not connected', vim.log.levels.WARN)
        return
    end

    -- Close all open documents
    for uri, doc in pairs(M.state.open_documents) do
        buffer.detach(doc.bufnr)
        protocol.send_close(uri)
    end
    M.state.open_documents = {}

    -- Send disconnect and stop job
    if M.state.job_id then
        protocol.send_disconnect()
        vim.fn.jobstop(M.state.job_id)
    end

    M.state.connected = false
    M.state.job_id = nil
    M.state.room = nil

    cursors.cleanup()

    vim.notify('[collab-editor] Disconnected', vim.log.levels.INFO)
end

-- Join a room (alias for connect)
function M.join_room(room)
    M.connect(M.config.server_url, room)
end

-- Leave room (alias for disconnect)
function M.leave_room()
    M.disconnect()
end

-- Open current buffer for collaboration
function M.open_current_buffer()
    if not M.state.connected then
        vim.notify('[collab-editor] Not connected to server', vim.log.levels.ERROR)
        return false
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if filepath == '' then
        vim.notify('[collab-editor] Buffer must have a filename', vim.log.levels.ERROR)
        return false
    end

    -- Create URI from filepath
    local uri = 'file://' .. filepath

    if M.state.open_documents[uri] then
        vim.notify('[collab-editor] Buffer already open for collaboration', vim.log.levels.WARN)
        return false
    end

    -- Get buffer content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')

    -- Register document
    M.state.open_documents[uri] = {
        bufnr = bufnr,
        editor_revision = 0,
        daemon_revision = 0,
    }

    -- Send open request
    protocol.send_open(uri, content)

    -- Attach buffer for change tracking
    buffer.attach(bufnr, uri)

    vim.notify('[collab-editor] Opened buffer for collaboration: ' .. filepath, vim.log.levels.INFO)
    return true
end

-- Close current buffer from collaboration
function M.close_current_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    local uri = 'file://' .. filepath

    local doc = M.state.open_documents[uri]
    if not doc then
        vim.notify('[collab-editor] Buffer not open for collaboration', vim.log.levels.WARN)
        return
    end

    -- Detach buffer
    buffer.detach(bufnr)

    -- Send close request
    protocol.send_close(uri)

    -- Remove from tracking
    M.state.open_documents[uri] = nil

    vim.notify('[collab-editor] Closed buffer from collaboration', vim.log.levels.INFO)
end

-- Show connection info
function M.show_info()
    if not M.state.connected then
        vim.notify('[collab-editor] Not connected', vim.log.levels.INFO)
        return
    end

    local doc_count = vim.tbl_count(M.state.open_documents)
    vim.notify(string.format(
        '[collab-editor] Connected to %s, Room: %s, Open documents: %d',
        M.state.server_url or 'unknown',
        M.state.room or 'unknown',
        doc_count
    ), vim.log.levels.INFO)
end

-- Handle stdout from go-helper
function M.on_stdout(data)
    for _, line in ipairs(data) do
        if line ~= '' then
            local ok, msg = pcall(vim.fn.json_decode, line)
            if ok then
                M.handle_message(msg)
            elseif M.config.debug then
                vim.notify('[collab-editor] Invalid JSON: ' .. line, vim.log.levels.DEBUG)
            end
        end
    end
end

-- Handle message from go-helper
function M.handle_message(msg)
    if msg.method then
        -- Notification from server
        if msg.method == 'connected' then
            M.state.connected = true
            vim.notify('[collab-editor] Connected to room: ' .. (M.state.room or '?'), vim.log.levels.INFO)

        elseif msg.method == 'disconnected' then
            M.state.connected = false
            local reason = msg.params and msg.params.reason or 'unknown'
            vim.notify('[collab-editor] Disconnected: ' .. reason, vim.log.levels.WARN)

        elseif msg.method == 'edit' then
            -- Remote edit from another user
            M.handle_remote_edit(msg.params)

        elseif msg.method == 'cursor' then
            -- Remote cursor update
            if M.config.show_remote_cursors then
                cursors.update(msg.params)
            end

        elseif msg.method == 'server_message' then
            -- Raw server message (for debugging)
            if M.config.debug then
                vim.notify('[collab-editor] Server: ' .. vim.inspect(msg.params), vim.log.levels.DEBUG)
            end

        else
            if M.config.debug then
                vim.notify('[collab-editor] Unknown method: ' .. msg.method, vim.log.levels.DEBUG)
            end
        end

    elseif msg.error then
        -- Error response
        vim.notify('[collab-editor] Error: ' .. msg.error.message, vim.log.levels.ERROR)
    end
end

-- Handle remote edit from another user
function M.handle_remote_edit(params)
    if not params or not params.uri then
        return
    end

    local doc = M.state.open_documents[params.uri]
    if not doc then
        return -- Document not open
    end

    -- Check revision
    if params.revision ~= doc.editor_revision then
        -- Our state has diverged, ignore this edit (server will retry)
        if M.config.debug then
            vim.notify(string.format(
                '[collab-editor] Ignoring edit: expected revision %d, got %d',
                doc.editor_revision, params.revision
            ), vim.log.levels.DEBUG)
        end
        return
    end

    -- Apply the edit to buffer
    buffer.apply_remote_edit(doc.bufnr, params.delta)

    -- Increment daemon revision
    doc.daemon_revision = doc.daemon_revision + 1
end

-- Handle disconnect
function M.on_disconnect(exit_code)
    M.state.connected = false
    M.state.job_id = nil

    if exit_code ~= 0 then
        vim.notify('[collab-editor] Connection lost (exit code: ' .. exit_code .. ')', vim.log.levels.WARN)
    end

    cursors.cleanup()
end

-- Get document state (used by buffer module)
function M.get_document(uri)
    return M.state.open_documents[uri]
end

-- Increment editor revision (called after local edit)
function M.increment_editor_revision(uri)
    local doc = M.state.open_documents[uri]
    if doc then
        doc.editor_revision = doc.editor_revision + 1
    end
end

-- Get daemon revision (needed for sending edits)
function M.get_daemon_revision(uri)
    local doc = M.state.open_documents[uri]
    return doc and doc.daemon_revision or 0
end

-- Get job_id for sending messages
function M.get_job_id()
    return M.state.job_id
end

return M
