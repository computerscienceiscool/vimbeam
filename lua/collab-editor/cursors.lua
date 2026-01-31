-- File: nvim/lua/collab-editor/cursors.lua
-- Remote cursor display using extmarks

local M = {}

-- Namespace for cursor extmarks
local namespace = nil

-- Track remote cursors: user_id -> { uri, ranges, name, extmark_ids }
local remote_cursors = {}

-- Colors for different users (will cycle through these)
local cursor_colors = {
    '#FF6B6B', -- Red
    '#4ECDC4', -- Teal
    '#FFE66D', -- Yellow
    '#95E1D3', -- Mint
    '#F38181', -- Coral
    '#AA96DA', -- Purple
    '#FCBAD3', -- Pink
    '#A8D8EA', -- Light blue
}

-- User ID to color index mapping
local user_color_map = {}
local next_color_index = 1

-- Initialize cursor display
function M.setup()
    if namespace then
        return -- Already setup
    end

    namespace = vim.api.nvim_create_namespace('collab-editor-cursors')

    -- Define highlight groups for cursor colors
    for i, color in ipairs(cursor_colors) do
        vim.api.nvim_set_hl(0, 'CollabCursor' .. i, {
            bg = color,
            fg = '#000000',
        })
        vim.api.nvim_set_hl(0, 'CollabCursorLabel' .. i, {
            fg = color,
            bold = true,
        })
    end
end

-- Cleanup cursor display
function M.cleanup()
    -- Clear all extmarks
    if namespace then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) then
                pcall(vim.api.nvim_buf_clear_namespace, buf, namespace, 0, -1)
            end
        end
    end

    remote_cursors = {}
    user_color_map = {}
    next_color_index = 1
end

-- Get color index for a user (assigns new color if needed)
local function get_user_color(user_id)
    if not user_color_map[user_id] then
        user_color_map[user_id] = next_color_index
        next_color_index = (next_color_index % #cursor_colors) + 1
    end
    return user_color_map[user_id]
end

-- Find buffer for a URI
local function find_buffer_for_uri(uri)
    -- Convert URI to filepath
    local filepath = uri:gsub('^file://', '')

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
            local buf_name = vim.api.nvim_buf_get_name(bufnr)
            if buf_name == filepath then
                return bufnr
            end
        end
    end

    return nil
end

-- Update remote cursor position
-- @param params table: { userid, name, uri, ranges }
function M.update(params)
    if not namespace then
        M.setup()
    end

    local user_id = params.userid
    local name = params.name or user_id
    local uri = params.uri
    local ranges = params.ranges or {}

    -- Find the buffer for this URI
    local bufnr = find_buffer_for_uri(uri)
    if not bufnr then
        return -- Buffer not open
    end

    -- Clear previous cursors for this user
    M.clear_user(user_id, bufnr)

    -- Store cursor info
    remote_cursors[user_id] = {
        uri = uri,
        ranges = ranges,
        name = name,
        bufnr = bufnr,
        extmark_ids = {},
    }

    -- Get color for this user
    local color_index = get_user_color(user_id)
    local cursor_hl = 'CollabCursor' .. color_index
    local label_hl = 'CollabCursorLabel' .. color_index

    -- Create extmarks for each cursor/selection
    for _, range in ipairs(ranges) do
        local start_row = range.start.line
        local start_col = range.start.character
        local end_row = range['end'].line
        local end_col = range['end'].character

        -- Convert character positions to byte positions
        local buffer_mod = require('collab-editor.buffer')
        start_col = buffer_mod.char_to_byte(bufnr, start_row, start_col)
        end_col = buffer_mod.char_to_byte(bufnr, end_row, end_col)

        -- Ensure positions are valid
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if start_row >= line_count then
            start_row = line_count - 1
        end
        if end_row >= line_count then
            end_row = line_count - 1
        end

        local start_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1] or ''
        local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ''

        if start_col > #start_line then
            start_col = #start_line
        end
        if end_col > #end_line then
            end_col = #end_line
        end

        -- Create extmark
        local opts = {
            end_row = end_row,
            end_col = end_col,
            hl_group = cursor_hl,
            hl_mode = 'combine',
            priority = 100,
        }

        -- Add virtual text with username at the cursor position
        if start_row == end_row and start_col == end_col then
            -- Single cursor (no selection) - show as virtual text
            opts.virt_text = {{' ' .. name .. ' ', label_hl}}
            opts.virt_text_pos = 'overlay'
        else
            -- Selection - show username at end
            opts.virt_text = {{name, label_hl}}
            opts.virt_text_pos = 'eol'
        end

        local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, start_row, start_col, opts)
        if ok then
            table.insert(remote_cursors[user_id].extmark_ids, extmark_id)
        end
    end
end

-- Clear cursors for a specific user
-- @param user_id string: User ID
-- @param bufnr number|nil: Specific buffer, or nil for all buffers
function M.clear_user(user_id, bufnr)
    local cursor_info = remote_cursors[user_id]
    if not cursor_info then
        return
    end

    local target_bufnr = bufnr or cursor_info.bufnr
    if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
        for _, extmark_id in ipairs(cursor_info.extmark_ids or {}) do
            pcall(vim.api.nvim_buf_del_extmark, target_bufnr, namespace, extmark_id)
        end
    end

    if not bufnr then
        remote_cursors[user_id] = nil
    else
        cursor_info.extmark_ids = {}
    end
end

-- Remove a user entirely (when they disconnect)
-- @param user_id string: User ID
function M.remove_user(user_id)
    M.clear_user(user_id)
    remote_cursors[user_id] = nil
    user_color_map[user_id] = nil
end

-- Get list of connected users
function M.get_users()
    local users = {}
    for user_id, info in pairs(remote_cursors) do
        table.insert(users, {
            id = user_id,
            name = info.name,
            uri = info.uri,
        })
    end
    return users
end

return M
