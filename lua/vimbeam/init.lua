-- File: lua/vimbeam/init.lua
-- Main entry point for vimbeam Neovim plugin
-- Works with Node.js helper for Automerge collaboration

local M = {}

-- Plugin state
M.state = {
  connected = false,
  doc_id = nil,
  user_id = nil,
  job_id = nil,
  bufnr = nil,
  cursor_ns = nil,  -- namespace for remote cursors
  remote_cursors = {},  -- track remote cursor extmarks
  remote_selections = {},  -- track remote selection extmarks
  last_sent_tick = 0,  -- track last changedtick sent to helper
  ignore_changes = false,
  after_connect = nil, -- deferred action to run after helper connects
  cursor_highlights = {}, -- memoized highlight groups keyed by user
  autocmd_group = nil,  -- augroup for buffer autocmds (cleanup on detach)
  -- NEW: Storm-specific state
  mode = nil,  -- 'automerge' or 'storm'
  project_id = nil,  -- Storm project ID
  storm_connected = false,
  chat_bufnr = nil,  -- Storm chat display buffer
  file_selections = {},  -- Storm file In/Out tracking {filename -> {input=bool, output=bool}}
  active_queries = {},  -- Storm pending queries {queryID -> {...}}
  other_users = {},  -- Presence tracking {clientID -> {name, color}}
}

-- Configuration defaults
M.config = {
  sync_url = 'ws://localhost:1234',
  awareness_url = 'ws://localhost:1235',
  node_helper_path = nil, -- Will be auto-detected
  user_name = nil,
  user_color = nil,
  debug = false,
  storm_url = nil,  -- e.g., 'http://localhost:8080'
}

-- Per-user highlight groups: use browser hex if valid, otherwise deterministic palette; defines both GUI and cterm colors so boxes render.
local function user_highlight_groups(user_id, color)
  -- Normalize browser hex if present.
  local normalized = nil
  if type(color) == 'string' then
    local trimmed = color:match('^%s*(.-)%s*$')
    if trimmed and trimmed:match('^#%x%x%x%x%x%x$') then
      normalized = trimmed:lower()
    end
  end

  -- Deterministic fallback palette if the color is missing/invalid.
  local palette = { '#FF6B6B', '#4ECDC4', '#FFE66D', '#95E1D3', '#AA96DA', '#FCBAD3', '#A8D8EA', '#06d6a0' }
  local chosen = normalized
  if not chosen then
    local uid = tostring(user_id or 'user')
    local sum = 0
    for i = 1, #uid do
      sum = sum + string.byte(uid, i)
    end
    chosen = palette[(sum % #palette) + 1]
  end

  -- Map hex to a cterm approximation for non-truecolor terminals.
  local function hex_to_cterm(hex)
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    if not r or not g or not b then return nil end
    local function to_cube(v) return math.floor((v / 255) * 5 + 0.5) end
    return 16 + 36 * to_cube(r) + 6 * to_cube(g) + to_cube(b)
  end

  local safe_user = (user_id or 'user'):gsub('[^%w]', '_')
  local label_group = 'VimbeamCursorLabel_' .. safe_user
  local select_group = 'VimbeamCursorSel_' .. safe_user

  local function ensure_group(name, fg, bg)
    if M.state.cursor_highlights[name] == bg then
      return name
    end
    local attrs = { fg = fg, bg = bg, bold = true, default = false }
    local cterm = hex_to_cterm(bg)
    if cterm then
      attrs.ctermbg = cterm
      attrs.ctermfg = 0
      attrs.cterm = { bold = true }
    end
    local ok = pcall(vim.api.nvim_set_hl, 0, name, attrs)
    if not ok or vim.fn.hlexists(name) == 0 then
      return nil
    end
    M.state.cursor_highlights[name] = bg
    return name
  end

  local label = ensure_group(label_group, '#000000', chosen) or 'Search'
  local select = ensure_group(select_group, '#000000', chosen) or 'Visual'
  return label, select
end

-- Setup function called by user in their init.lua
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  -- Auto-detect node-helper path if not specified
  if not M.config.node_helper_path then
    local source = debug.getinfo(1).source
    if source:sub(1, 1) == '@' then
      local plugin_path = source:sub(2):gsub('/lua/vimbeam/init%.lua$', '')
      M.config.node_helper_path = plugin_path .. '/node-helper/index.js'
    end
  end

  M.setup_commands()

  if M.config.debug then
    vim.notify('[vimbeam] Plugin loaded', vim.log.levels.DEBUG)
  end
end

-- Show remote cursor in buffer using extmarks
function M.show_remote_cursor(user_id, name, color, anchor, head)
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return
  end

  local function shorten_label(label)
    if not label or label == '' then
      return nil
    end
    if #label > 20 then
      return label:sub(1, 17) .. "..."
    end
    return label
  end
  
  -- Create namespace if needed
  if not M.state.cursor_ns then
    M.state.cursor_ns = vim.api.nvim_create_namespace("vimbeam_cursors")
  end
  
  -- Clear previous cursor/selection for this user
  if M.state.remote_cursors[user_id] then
    pcall(vim.api.nvim_buf_del_extmark, M.state.bufnr, M.state.cursor_ns, M.state.remote_cursors[user_id])
    M.state.remote_cursors[user_id] = nil
  end
  if M.state.remote_selections and M.state.remote_selections[user_id] then
    pcall(vim.api.nvim_buf_del_extmark, M.state.bufnr, M.state.cursor_ns, M.state.remote_selections[user_id])
    M.state.remote_selections[user_id] = nil
  end
  
  -- Convert anchor (character offset) to row/col
  local lines = vim.api.nvim_buf_get_lines(M.state.bufnr, 0, -1, false)
  if #lines == 0 then
    lines = { '' }
  end

  local total_len = 0
  for i, line in ipairs(lines) do
    total_len = total_len + vim.fn.strchars(line)  -- Use character count, not bytes
    if i < #lines then
      total_len = total_len + 1
    end
  end

  local function clamp_offset(off)
    return math.max(0, math.min(tonumber(off) or 0, total_len))
  end

  local function offset_to_pos(off)
    local clamped = clamp_offset(off)
    local offset = 0
    local target_row = 0
    local target_col = 0

    for i, line in ipairs(lines) do
      local line_len = vim.fn.strchars(line) + 1  -- +1 for newline, use char count not bytes
      if offset + line_len > clamped then
        target_row = i - 1
        target_col = clamped - offset
        return target_row, target_col
      end
      offset = offset + line_len
    end

    local last_row = math.max(0, #lines - 1)
    local last_line = lines[#lines] or ""
    return last_row, math.min(clamped - offset, vim.fn.strchars(last_line))
  end

  -- Convert character column to byte column for extmarks
  local function char_to_byte_col(row, char_col)
    if char_col <= 0 then return 0 end
    local line = lines[row + 1] or ""  -- row is 0-indexed
    if char_col >= vim.fn.strchars(line) then return #line end
    -- Get substring by character count and return byte length
    local substr = vim.fn.strcharpart(line, 0, char_col)
    return #substr
  end

  -- Normalize remote offsets (JSON null becomes vim.NIL userdata); default to 0.
  local anchor_num = tonumber(anchor) or 0
  local head_num = tonumber(head)

  local cursor_row, cursor_char_col = offset_to_pos(anchor_num)
  local cursor_byte_col = char_to_byte_col(cursor_row, cursor_char_col)

  local label_hl, select_hl = user_highlight_groups(user_id, color)

  local selection_mark_id = nil
  if head_num ~= nil and head_num ~= anchor_num then
    local start_off = clamp_offset(math.min(anchor_num, head_num))
    local end_off = clamp_offset(math.max(anchor_num, head_num))
    local start_row, start_char_col = offset_to_pos(start_off)
    local end_row, end_char_col = offset_to_pos(end_off)
    -- Convert character columns to byte columns for extmarks
    local start_byte_col = char_to_byte_col(start_row, start_char_col)
    local end_byte_col = char_to_byte_col(end_row, end_char_col)

    selection_mark_id = vim.api.nvim_buf_set_extmark(M.state.bufnr, M.state.cursor_ns, start_row, start_byte_col, {
      end_line = end_row,
      end_col = end_byte_col,
      hl_group = select_hl,
      hl_mode = 'combine',
      priority = 200,
    })
  end

  -- Create extmark with virtual text and cursor highlight
  local display_name = shorten_label(name) or shorten_label(user_id) or "user"
  local cursor_line = lines[cursor_row + 1] or ""
  local cursor_end_col = math.min(cursor_byte_col + 1, #cursor_line)
  local mark_id = vim.api.nvim_buf_set_extmark(M.state.bufnr, M.state.cursor_ns, cursor_row, cursor_byte_col, {
    virt_text = {{ " " .. display_name .. " ", label_hl }},
    virt_text_pos = "overlay",
    hl_group = select_hl,
    end_col = cursor_end_col,
    hl_mode = 'combine',
    priority = 300,
  })
  
  M.state.remote_cursors[user_id] = mark_id
  if selection_mark_id then
    M.state.remote_selections[user_id] = selection_mark_id
  end
end


-- Setup user commands
function M.setup_commands()
  vim.api.nvim_create_user_command('BeamConnect', function()
    M.connect()
  end, { desc = 'Connect to collaboration server' })

  vim.api.nvim_create_user_command('BeamDisconnect', function()
    M.disconnect()
  end, { desc = 'Disconnect from collaboration server' })

  vim.api.nvim_create_user_command('BeamCreate', function()
    M.create_document()
  end, { desc = 'Create new collaborative document' })

  vim.api.nvim_create_user_command('BeamOpen', function(opts)
    M.open_document(opts.args)
  end, { nargs = 1, desc = 'Open collaborative document by ID' })

  vim.api.nvim_create_user_command('BeamClose', function()
    M.close_document()
  end, { desc = 'Close current collaborative document' })

  vim.api.nvim_create_user_command('BeamInfo', function()
    M.show_info()
  end, { desc = 'Show connection info' })

  vim.api.nvim_create_user_command('BeamUserName', function(opts)
    M.set_name(opts.args)
  end, { nargs = 1, desc = 'Set collaboration display name' })

  vim.api.nvim_create_user_command('BeamUserColor', function(opts)
    M.set_color_by_name(opts.args)
  end, { nargs = '?', desc = 'Set color by name (e.g., green, blue) or show picker if no arg' })

  -- Testing shortcut: connect (if needed) and open a doc in one step
  vim.api.nvim_create_user_command('BeamQuick', function(opts)
    M.quick_connect_open(opts.args)
  end, { nargs = 1, desc = 'TESTING: Connect and open doc in one step' })

    -- NEW: Storm-specific commands
  vim.api.nvim_create_user_command('StormConnect', function(opts)
    M.connect_storm(opts.args)
  end, { nargs = 1, desc = 'Connect to Storm server with project ID' })

  vim.api.nvim_create_user_command('StormProject', function(opts)
    if opts.args == '' then
      M.list_storm_projects()
    else
      M.open_storm_project(opts.args)
    end
  end, { nargs = '?', desc = 'List or open Storm project' })

  vim.api.nvim_create_user_command('StormDisconnect', function()
    M.disconnect_storm()
  end, { desc = 'Disconnect from Storm' })
end

-- Send JSON message to helper
function M.send(msg)
  if M.state.job_id then
    local json = vim.fn.json_encode(msg) .. '\n'
    vim.fn.chansend(M.state.job_id, json)
    if M.config.debug then
      vim.notify('[vimbeam] Sent: ' .. vim.fn.json_encode(msg), vim.log.levels.DEBUG)
    end
  end
end

function M.set_name(name)
  if not name or name == '' then
    vim.notify('[vimbeam] Name required', vim.log.levels.ERROR)
    return
  end
  M.config.user_name = name
  M.send({ type = 'set_name', name = name })
  if M.config.debug then
    vim.notify('[vimbeam] Set name to ' .. name, vim.log.levels.DEBUG)
  end
end

function M.set_color(color)
  if not color or color == '' then
    vim.notify('[vimbeam] Color required (e.g., #88cc88)', vim.log.levels.ERROR)
    return
  end
  M.config.user_color = color
  M.send({ type = 'set_color', color = color })
  if M.config.debug then
    vim.notify('[vimbeam] Set color to ' .. color, vim.log.levels.DEBUG)
  end
end

-- Extended color palette for user selection
-- Simple names (Red, Green, Blue, etc.) listed first for easy typing
M.color_palette = {
  -- Simple one-word colors
  { name = "Red",           hex = "#FF6B6B" },
  { name = "Orange",        hex = "#FFB703" },
  { name = "Yellow",        hex = "#FFE66D" },
  { name = "Green",         hex = "#06D6A0" },
  { name = "Teal",          hex = "#4ECDC4" },
  { name = "Blue",          hex = "#219EBC" },
  { name = "Purple",        hex = "#8338EC" },
  { name = "Pink",          hex = "#FF006E" },
  -- Descriptive variants
  { name = "Coral Red",     hex = "#E63946" },
  { name = "Sunset Orange", hex = "#F4A261" },
  { name = "Lime Green",    hex = "#2A9D8F" },
  { name = "Mint",          hex = "#95E1D3" },
  { name = "Ocean Blue",    hex = "#0077B6" },
  { name = "Sky Blue",      hex = "#8ECAE6" },
  { name = "Light Blue",    hex = "#A8D8EA" },
  { name = "Lavender",      hex = "#AA96DA" },
  { name = "Hot Pink",      hex = "#F72585" },
  { name = "Soft Pink",     hex = "#FCBAD3" },
}

-- Find color by name (case-insensitive)
function M.find_color_by_name(name)
  local lower_name = name:lower()
  for _, c in ipairs(M.color_palette) do
    if c.name:lower() == lower_name then
      return c
    end
  end
  return nil
end

-- Set color by name or show picker if no name given
function M.set_color_by_name(name)
  if not name or name == '' then
    M.show_color_picker()
    return
  end

  -- Check if it's a hex color
  if name:match('^#%x%x%x%x%x%x$') then
    M.set_color(name)
    vim.notify('[vimbeam] Color set to ' .. name, vim.log.levels.INFO)
    return
  end

  -- Try to find by name
  local color = M.find_color_by_name(name)
  if color then
    M.set_color(color.hex)
    vim.notify('[vimbeam] Color set to ' .. color.name .. ' (' .. color.hex .. ')', vim.log.levels.INFO)
  else
    vim.notify('[vimbeam] Unknown color: ' .. name .. '. Use :BeamUserColor to see options.', vim.log.levels.WARN)
  end
end

-- Show color picker using vim.ui.select
function M.show_color_picker()
  local items = {}
  local hex_lookup = {}
  for _, c in ipairs(M.color_palette) do
    local label = string.format("%s (%s)", c.name, c.hex)
    table.insert(items, label)
    hex_lookup[label] = c.hex
  end

  vim.ui.select(items, {
    prompt = "Select cursor color:",
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if choice then
      local hex = hex_lookup[choice]
      M.set_color(hex)
      vim.notify('[vimbeam] Color set to ' .. choice, vim.log.levels.INFO)
    end
  end)
end

function M.ensure_helper_running()
  if M.state.job_id and M.state.job_id > 0 then
    return true
  end

  local helper_path = M.config.node_helper_path
  if not helper_path or vim.fn.filereadable(helper_path) == 0 then
    vim.notify('[vimbeam] Node helper not found at: ' .. (helper_path or 'nil'), vim.log.levels.ERROR)
    return false
  end

  -- Start node helper process
  M.state.job_id = vim.fn.jobstart({ 'node', helper_path }, {
    on_stdout = function(_, data, _)
      M.on_stdout(data)
    end,
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= '' then
          if M.config.debug then
            vim.notify('[vimbeam] Helper: ' .. line, vim.log.levels.DEBUG)
          end
        end
      end
    end,
    on_exit = function(_, code, _)
      M.on_exit(code)
    end,
    stdout_buffered = false,
    stderr_buffered = false,
  })

  if M.state.job_id <= 0 then
    vim.notify('[vimbeam] Failed to start helper', vim.log.levels.ERROR)
    M.state.job_id = nil
    return false
  end

  return true
end

-- Connect to collaboration server
function M.connect()
  if M.state.connected then
    vim.notify('[vimbeam] Already connected', vim.log.levels.WARN)
    return
  end

  if not M.ensure_helper_running() then
    return
  end

  -- Send connect message
  M.send({
    type = 'connect',
    syncUrl = M.config.sync_url,
    awarenessUrl = M.config.awareness_url,
    name = M.config.user_name,
    color = M.config.user_color,
  })

  -- Apply configured identity after connect
  if M.config.user_name then
    M.set_name(M.config.user_name)
  end
  if M.config.user_color then
    M.set_color(M.config.user_color)
  end
end

function M.list_storm_projects()
  if not M.config.storm_url then
    vim.notify('[vimbeam] storm_url not configured', vim.log.levels.ERROR)
    return
  end
  vim.notify('[vimbeam] StormProject listing not implemented yet. Use :StormConnect <project-id>.', vim.log.levels.WARN)
end

function M.open_storm_project(project_id)
  if not project_id or project_id == '' then
    vim.notify('[vimbeam] Project ID required', vim.log.levels.ERROR)
    return
  end
  vim.notify('[vimbeam] StormProject open not implemented yet. Use :StormConnect ' .. project_id .. '.', vim.log.levels.WARN)
end

-- NEW: Storm connect
function M.connect_storm(project_id)
  if not project_id or project_id == '' then
    vim.notify('[vimbeam] Project ID required', vim.log.levels.ERROR)
    return
  end

  if M.state.storm_connected then
    vim.notify('[vimbeam] Storm already connected', vim.log.levels.WARN)
    return
  end

  if not M.config.storm_url then
    vim.notify('[vimbeam] storm_url not configured', vim.log.levels.ERROR)
    return
  end

  if not M.ensure_helper_running() then
    return
  end

  M.state.mode = 'storm'
  M.state.project_id = project_id

  -- Auto-detect user identity if not set
  if not M.config.user_name then
    local git_name = vim.fn.system('git config user.name 2>/dev/null'):gsub('%s+$', '')
    if git_name ~= '' then
      M.config.user_name = git_name
    else
      M.config.user_name = vim.env.USER or 'vim-user'
    end
  end

  if not M.config.user_color then
    math.randomseed(os.time())
    local idx = math.random(1, #M.color_palette)
    M.config.user_color = M.color_palette[idx].hex
  end

  -- Send Storm connect message
  M.send({
    type = 'storm_connect',
    stormUrl = M.config.storm_url,
    projectId = project_id,
    name = M.config.user_name,
    color = M.config.user_color,
  })
end

function M.disconnect_storm()
  if not M.state.job_id then
    vim.notify('[vimbeam] Not connected', vim.log.levels.WARN)
    return
  end

  M.send({ type = 'storm_disconnect' })
  M.state.storm_connected = false
  M.state.project_id = nil
  M.state.chat_bufnr = nil
  M.state.file_selections = {}
  M.state.active_queries = {}
  M.state.other_users = {}

  if not M.state.connected then
    vim.fn.jobstop(M.state.job_id)
    M.state.job_id = nil
  end

  vim.notify('[vimbeam] Storm disconnected', vim.log.levels.INFO)
end

-- Disconnect from server
function M.disconnect()
  if not M.state.job_id then
    vim.notify('[vimbeam] Not connected', vim.log.levels.WARN)
    return
  end

  M.send({ type = 'disconnect' })

  M.state.connected = false
  M.state.doc_id = nil
  M.state.user_id = nil
  M.state.after_connect = nil

  if M.state.bufnr then
    M.detach_buffer()
  end

  if not M.state.storm_connected then
    vim.fn.jobstop(M.state.job_id)
    M.state.job_id = nil
  end

  vim.notify('[vimbeam] Disconnected', vim.log.levels.INFO)
end

-- Create new document
function M.create_document()
  if not M.state.connected then
    vim.notify('[vimbeam] Not connected. Run :BeamConnect first', vim.log.levels.ERROR)
    return
  end

  M.send({ type = 'create' })
end

-- Open existing document
function M.open_document(doc_id)
  if not M.state.connected then
    vim.notify('[vimbeam] Not connected. Run :BeamConnect first', vim.log.levels.ERROR)
    return
  end

  if not doc_id or doc_id == '' then
    vim.notify('[vimbeam] Document ID required', vim.log.levels.ERROR)
    return
  end

  M.send({ type = 'open', docId = doc_id })
end

-- Close current document
function M.close_document()
  if not M.state.doc_id then
    vim.notify('[vimbeam] No document open', vim.log.levels.WARN)
    return
  end

  M.send({ type = 'close' })
  M.detach_buffer()
  M.state.doc_id = nil
end

-- Show connection info
function M.show_info()
  M.send({ type = 'info' })
  if M.config.debug then
    local parts = {
      'connected=' .. tostring(M.state.connected),
      'doc=' .. (M.state.doc_id or 'none'),
      'user=' .. (M.state.user_id or 'unknown'),
      'sync=' .. (M.config.sync_url or 'n/a'),
      'awareness=' .. (M.config.awareness_url or 'n/a'),
    }
    vim.notify('[vimbeam] ' .. table.concat(parts, ' | '), vim.log.levels.INFO)
  end
end

-- Handle stdout from helper
function M.on_stdout(data)
  for _, line in ipairs(data) do
    if line ~= '' then
      local ok, msg = pcall(vim.fn.json_decode, line)
      if ok then
        M.handle_message(msg)
      elseif M.config.debug then
        vim.notify('[vimbeam] Invalid JSON: ' .. line, vim.log.levels.DEBUG)
      end
    end
  end
end

-- Handle message from helper
function M.handle_message(msg)
  if M.config.debug then
    vim.notify('[vimbeam] Received: ' .. vim.fn.json_encode(msg), vim.log.levels.DEBUG)
  end

  if msg.type == 'connected' then
    M.state.connected = true
    M.state.user_id = msg.userId
    vim.notify('[vimbeam] Connected as ' .. msg.userId, vim.log.levels.INFO)
    if M.state.after_connect then
      local cb = M.state.after_connect
      M.state.after_connect = nil
      pcall(cb)
    end

  elseif msg.type == 'storm_connected' then
    M.state.storm_connected = true
    if msg.projectId then
      M.state.project_id = msg.projectId
    end
    vim.notify('[vimbeam] Storm connected: ' .. (M.state.project_id or 'unknown'), vim.log.levels.INFO)

  elseif msg.type == 'disconnected' then
    M.state.connected = false
    M.state.doc_id = nil
    vim.notify('[vimbeam] Disconnected', vim.log.levels.INFO)
    M.state.after_connect = nil

  elseif msg.type == 'storm_disconnected' then
    M.state.storm_connected = false
    M.state.project_id = nil
    M.state.chat_bufnr = nil
    M.state.file_selections = {}
    M.state.active_queries = {}
    M.state.other_users = {}
    if not M.state.connected and M.state.job_id then
      vim.fn.jobstop(M.state.job_id)
      M.state.job_id = nil
    end
    vim.notify('[vimbeam] Storm disconnected', vim.log.levels.INFO)

  elseif msg.type == 'created' then
    M.state.doc_id = msg.docId
    vim.notify('[vimbeam] Created document: ' .. msg.docId, vim.log.levels.INFO)
    M.attach_buffer('')

  elseif msg.type == 'opened' then
    M.state.doc_id = msg.docId
    vim.notify('[vimbeam] Opened document: ' .. msg.docId, vim.log.levels.INFO)
    M.attach_buffer(msg.content or '')

  elseif msg.type == 'changed' then
    M.apply_remote_change(msg.content or '')

  elseif msg.type == 'closed' then
    M.state.doc_id = nil
    M.detach_buffer()
    vim.notify('[vimbeam] Document closed', vim.log.levels.INFO)

  elseif msg.type == 'cursor' then
    -- Remote cursor update - display in buffer
    if msg.anchor ~= nil then
      M.show_remote_cursor(msg.userId, msg.name, msg.color, msg.anchor, msg.head)
    end
    if M.config.debug then
      vim.notify('[vimbeam] Cursor from ' .. (msg.name or msg.userId), vim.log.levels.DEBUG)
    end

  elseif msg.type == 'info' then
    local info = string.format(
      '[vimbeam] Connected: %s | Doc: %s | User: %s',
      tostring(msg.connected),
      msg.docId or 'none',
      msg.userName or 'unknown'
    )
    vim.notify(info, vim.log.levels.INFO)

  elseif msg.type == 'error' then
    vim.notify('[vimbeam] Error: ' .. (msg.message or 'unknown'), vim.log.levels.ERROR)
  end
end

-- Quick testing helper: connect (if needed) and open a doc
function M.quick_connect_open(doc_id)
  if not doc_id or doc_id == '' then
    vim.notify('[vimbeam] Document ID required', vim.log.levels.ERROR)
    return
  end

  local function open_after_connect()
    M.open_document(doc_id)
  end

  if M.state.connected then
    open_after_connect()
    return
  end

  M.state.after_connect = open_after_connect

  if not M.state.job_id then
    M.connect()
  else
    if M.config.debug then
      vim.notify('[vimbeam] Waiting for connect to finish...', vim.log.levels.DEBUG)
    end
  end
end

-- Attach to current buffer for collaboration
function M.attach_buffer(initial_content)
  local bufnr = vim.api.nvim_get_current_buf()
  M.state.bufnr = bufnr
  M.state.last_sent_tick = vim.api.nvim_buf_get_changedtick(bufnr)

  -- Clean up previous autocmds if any
  if M.state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, M.state.autocmd_group)
  end

  -- Create augroup for this buffer's autocmds (enables cleanup on detach)
  M.state.autocmd_group = vim.api.nvim_create_augroup('Vimbeam_' .. bufnr, { clear = true })

  -- Set buffer content
  M.state.ignore_changes = true
  local lines = vim.split(initial_content, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  M.state.ignore_changes = false

  -- Set buffer options
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].buftype = 'nofile'

  -- Send buffer content to helper (debounced by changedtick)
  local function send_buffer_if_changed(reason)
    if M.state.ignore_changes then
      if M.config.debug then
        vim.notify(string.format('[vimbeam] skip send (%s): ignoring changes', reason or 'unknown'), vim.log.levels.DEBUG)
      end
      return
    end
    if bufnr ~= M.state.bufnr then
      return
    end
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    if tick == M.state.last_sent_tick then
      if M.config.debug then
        vim.notify(string.format('[vimbeam] skip send (%s): tick unchanged (%d)', reason or 'unknown', tick), vim.log.levels.DEBUG)
      end
      return
    end
    M.state.last_sent_tick = tick

    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(buf_lines, '\n')
    if M.config.debug then
      vim.notify(string.format('[vimbeam] send (%s): tick %d len %d', reason or 'unknown', tick, #content), vim.log.levels.DEBUG)
    end
    M.send({ type = 'edit', content = content })
  end

  -- Attach to buffer changes using on_lines only (not on_bytes - avoid duplicates)
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf, _, _, _, _, _)
      if buf ~= bufnr then
        return
      end
      send_buffer_if_changed('on_lines')
    end,
    on_detach = function()
      if M.state.bufnr == bufnr then
        M.state.bufnr = nil
      end
    end,
  })

  -- Track cursor movements (in augroup for cleanup)
  vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    group = M.state.autocmd_group,
    buffer = bufnr,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1]  -- 1-indexed
      local col = cursor[2]  -- 0-indexed

      local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      if #all_lines == 0 then
        all_lines = { '' }
      end

      -- Convert byte column to character column
      local function byte_to_char_col(line, byte_col)
        if byte_col <= 0 then return 0 end
        if byte_col >= #line then return vim.fn.strchars(line) end
        -- Get substring up to byte position and count characters
        local substr = string.sub(line, 1, byte_col)
        return vim.fn.strchars(substr)
      end

      local function clamp_pos(lnum, byte_c)
        local lnum_clamped = math.max(1, math.min(lnum, #all_lines))
        local line = all_lines[lnum_clamped] or ""
        local byte_clamped = math.max(0, math.min(byte_c, #line))
        -- Convert byte column to character column
        local char_col = byte_to_char_col(line, byte_clamped)
        return lnum_clamped, char_col
      end

      local function offset_from_pos(lnum, byte_c)
        local lnum_clamped, char_col = clamp_pos(lnum, byte_c)
        local offset = 0
        for i = 1, lnum_clamped - 1 do
          offset = offset + vim.fn.strchars(all_lines[i]) + 1  -- Use char count, not bytes
        end
        return offset + char_col
      end

      local offset = offset_from_pos(row, col)

      local selection = nil
      local mode = vim.fn.mode(1)
      local visual_prefix = mode:sub(1, 1)
      if visual_prefix == 'v' or visual_prefix == 'V' or visual_prefix == '\22' then
        local anchor_pos = vim.fn.getpos('v')
        local anchor_row = anchor_pos[2]
        local anchor_col = math.max(0, (anchor_pos[3] or 1) - 1)

        selection = {
          anchor = offset_from_pos(anchor_row, anchor_col),
          head = offset,
        }
      end

      local message = { type = 'cursor', offset = offset }
      if selection then
        message.selection = selection
      end

      M.send(message)
    end,
  })

  if M.config.debug then
    vim.notify('[vimbeam] Attached to buffer ' .. bufnr, vim.log.levels.DEBUG)
  end
end

-- Detach from current buffer
function M.detach_buffer()
  -- Clean up autocmds
  if M.state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, M.state.autocmd_group)
    M.state.autocmd_group = nil
  end

  M.state.bufnr = nil
  M.state.remote_cursors = {}
  M.state.remote_selections = {}
  -- Note: nvim_buf_attach doesn't have a direct detach,
  -- but returning true from on_lines would detach
end

-- Apply remote change to buffer
function M.apply_remote_change(content)
  if not M.state.bufnr then
    return
  end

  local bufnr = M.state.bufnr

  -- Check if buffer still exists
  if not vim.api.nvim_buf_is_valid(bufnr) then
    M.state.bufnr = nil
    return
  end

  -- Get current content
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_content = table.concat(current_lines, '\n')

  -- Only update if different
  if content == current_content then
    return
  end

  -- Apply change
  M.state.ignore_changes = true

  -- Save cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)

  local lines = vim.split(content, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Restore cursor position (clamped to valid range)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local new_row = math.min(cursor[1], line_count)
  local new_line = vim.api.nvim_buf_get_lines(bufnr, new_row - 1, new_row, false)[1] or ''
  local new_col = math.min(cursor[2], #new_line)
  vim.api.nvim_win_set_cursor(0, { new_row, new_col })

  -- Use vim.schedule to reset ignore_changes after all buffer events have processed
  -- This prevents race conditions with queued change events
  vim.schedule(function()
    M.state.ignore_changes = false
  end)
end

-- Handle helper exit
function M.on_exit(code)
  M.state.job_id = nil
  M.state.connected = false
  M.state.doc_id = nil
  M.state.after_connect = nil
  M.state.storm_connected = false
  M.state.project_id = nil
  M.state.chat_bufnr = nil
  M.state.file_selections = {}
  M.state.active_queries = {}
  M.state.other_users = {}
  
  if code ~= 0 then
    vim.notify('[vimbeam] Helper exited with code ' .. code, vim.log.levels.WARN)
  end
end

return M
