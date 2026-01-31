-- File: nvim/lua/collab-editor/buffer.lua
-- Buffer change tracking and remote edit application
-- Handles the tricky parts: detecting local changes, applying remote changes without loops

local M = {}

local protocol = require('collab-editor.protocol')

-- Track which buffers are attached
local attached_buffers = {} -- bufnr -> { uri, ignore_changes }

-- Attach to a buffer to track changes
-- @param bufnr number: Buffer number
-- @param uri string: Document URI
function M.attach(bufnr, uri)
    if attached_buffers[bufnr] then
        return -- Already attached
    end

    attached_buffers[bufnr] = {
        uri = uri,
        ignore_changes = false,
    }

    -- Use nvim_buf_attach with on_bytes for precise change detection
    vim.api.nvim_buf_attach(bufnr, false, {
        on_bytes = function(_, buf, changedtick,
                           start_row, start_col, byte_offset,
                           old_end_row, old_end_col, old_byte_len,
                           new_end_row, new_end_col, new_byte_len)

            -- Check if we should ignore this change (it's from a remote edit)
            local state = attached_buffers[buf]
            if not state or state.ignore_changes then
                return
            end

            -- Compute the delta and send to server
            M.on_bytes_change(buf, state.uri,
                start_row, start_col,
                old_end_row, old_end_col,
                new_end_row, new_end_col)
        end,

        on_detach = function(_, buf)
            attached_buffers[buf] = nil
        end,
    })

    -- Also track cursor movements for awareness
    vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
        buffer = bufnr,
        callback = function()
            M.on_cursor_moved(bufnr, uri)
        end,
    })
end

-- Detach from a buffer
-- @param bufnr number: Buffer number
function M.detach(bufnr)
    -- Note: nvim_buf_attach doesn't have a direct detach, but returning true
    -- from on_bytes/on_lines detaches. We just clear our state.
    attached_buffers[bufnr] = nil
end

-- Handle on_bytes change event
-- This is called after each edit operation
function M.on_bytes_change(bufnr, uri, start_row, start_col, old_end_row, old_end_col, new_end_row, new_end_col)
    local init = require('collab-editor')

    -- Get the new text that was inserted
    -- The change replaced text from (start_row, start_col) to (start_row + old_end_row, old_end_col)
    -- with new text ending at (start_row + new_end_row, new_end_col)

    local replacement = ''

    if new_end_row > 0 or new_end_col > 0 then
        -- There's new text - get it from the buffer
        local end_row = start_row + new_end_row
        local end_col = new_end_col

        -- Get lines that contain the new text
        local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)

        if #lines > 0 then
            if #lines == 1 then
                -- Single line change
                replacement = string.sub(lines[1], start_col + 1, start_col + end_col)
            else
                -- Multi-line change
                local parts = {}
                -- First line from start_col to end
                table.insert(parts, string.sub(lines[1], start_col + 1))
                -- Middle lines (complete)
                for i = 2, #lines - 1 do
                    table.insert(parts, lines[i])
                end
                -- Last line from start to end_col
                if #lines > 1 then
                    table.insert(parts, string.sub(lines[#lines], 1, end_col))
                end
                replacement = table.concat(parts, '\n')
            end
        end
    end

    -- Convert to Unicode character positions
    -- Note: nvim_buf_attach gives us byte positions, but the protocol uses character positions
    local start_char = M.byte_to_char(bufnr, start_row, start_col)
    local old_end_char = old_end_col -- This is relative, might need adjustment
    
    -- Calculate the actual end position of the deleted text
    local del_end_row = start_row + old_end_row
    local del_end_col = old_end_col
    if old_end_row == 0 then
        del_end_col = start_col + old_end_col
    end
    local del_end_char = M.byte_to_char(bufnr, del_end_row, del_end_col)

    -- Create delta
    local delta = protocol.make_simple_delta(
        start_row, start_char,
        del_end_row, del_end_char,
        replacement
    )

    -- Get daemon revision and send edit
    local revision = init.get_daemon_revision(uri)
    protocol.send_edit(uri, revision, delta)

    -- Increment editor revision
    init.increment_editor_revision(uri)
end

-- Convert byte position to character position (for Unicode support)
-- @param bufnr number: Buffer number
-- @param row number: 0-indexed row
-- @param byte_col number: Byte column
-- @return number: Character column
function M.byte_to_char(bufnr, row, byte_col)
    -- Get the line
    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
    if #lines == 0 then
        return byte_col -- Empty or invalid line
    end

    local line = lines[1]
    if byte_col >= #line then
        -- Position is at or past end of line
        return vim.fn.strchars(line)
    end

    -- Count characters up to byte position
    local substr = string.sub(line, 1, byte_col)
    return vim.fn.strchars(substr)
end

-- Convert character position to byte position
-- @param bufnr number: Buffer number
-- @param row number: 0-indexed row
-- @param char_col number: Character column
-- @return number: Byte column
function M.char_to_byte(bufnr, row, char_col)
    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
    if #lines == 0 then
        return char_col
    end

    local line = lines[1]
    -- Use strcharpart to get substring by character count, then get its byte length
    local substr = vim.fn.strcharpart(line, 0, char_col)
    return #substr
end

-- Handle cursor movement
function M.on_cursor_moved(bufnr, uri)
    local pos = vim.api.nvim_win_get_cursor(0) -- {row, col} 1-indexed row, 0-indexed col
    local row = pos[1] - 1 -- Convert to 0-indexed
    local col = pos[2]

    -- Convert byte column to character column
    local char_col = M.byte_to_char(bufnr, row, col)

    -- Get visual selection if in visual mode
    local mode = vim.fn.mode()
    local ranges = {}

    if mode == 'v' or mode == 'V' or mode == '' then
        -- Visual mode - get selection
        local start_pos = vim.fn.getpos('v')
        local end_pos = vim.fn.getpos('.')

        local start_row = start_pos[2] - 1
        local start_col = M.byte_to_char(bufnr, start_row, start_pos[3] - 1)
        local end_row = end_pos[2] - 1
        local end_col = M.byte_to_char(bufnr, end_row, end_pos[3] - 1)

        -- Ensure start is before end
        if start_row > end_row or (start_row == end_row and start_col > end_col) then
            start_row, end_row = end_row, start_row
            start_col, end_col = end_col, start_col
        end

        table.insert(ranges, protocol.make_range(start_row, start_col, end_row, end_col))
    else
        -- Normal mode - just cursor position
        table.insert(ranges, protocol.make_range(row, char_col, row, char_col))
    end

    -- Send cursor update (debounced - TODO: add debouncing)
    protocol.send_cursor(uri, ranges)
end

-- Apply a remote edit to a buffer
-- @param bufnr number: Buffer number
-- @param delta table: Array of edit objects
function M.apply_remote_edit(bufnr, delta)
    if not delta or #delta == 0 then
        return
    end

    local state = attached_buffers[bufnr]
    if not state then
        return
    end

    -- Set flag to ignore changes while we apply this edit
    state.ignore_changes = true

    -- Apply edits in reverse order to preserve positions
    -- (Later positions first, so earlier positions remain valid)
    local sorted_delta = vim.deepcopy(delta)
    table.sort(sorted_delta, function(a, b)
        if a.range.start.line ~= b.range.start.line then
            return a.range.start.line > b.range.start.line
        end
        return a.range.start.character > b.range.start.character
    end)

    for _, edit in ipairs(sorted_delta) do
        M.apply_single_edit(bufnr, edit)
    end

    -- Re-enable change tracking
    -- Use vim.schedule to ensure all buffer updates are complete
    vim.schedule(function()
        if attached_buffers[bufnr] then
            attached_buffers[bufnr].ignore_changes = false
        end
    end)
end

-- Apply a single edit to a buffer
-- @param bufnr number: Buffer number
-- @param edit table: {range: {start: pos, end: pos}, replacement: string}
function M.apply_single_edit(bufnr, edit)
    local start_row = edit.range.start.line
    local start_char = edit.range.start.character
    local end_row = edit.range['end'].line
    local end_char = edit.range['end'].character

    -- Convert character positions to byte positions
    local start_col = M.char_to_byte(bufnr, start_row, start_char)
    local end_col = M.char_to_byte(bufnr, end_row, end_char)

    -- Split replacement into lines
    local replacement_lines = vim.split(edit.replacement, '\n', { plain = true })

    -- Use nvim_buf_set_text for precise editing
    vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, replacement_lines)
end

-- Check if buffer is attached
function M.is_attached(bufnr)
    return attached_buffers[bufnr] ~= nil
end

-- Get URI for attached buffer
function M.get_uri(bufnr)
    local state = attached_buffers[bufnr]
    return state and state.uri or nil
end

return M
