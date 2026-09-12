local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.default_prog = { '/usr/bin/fish' }

config.colors = {
  background = '#1b120d',
  foreground = '#f3d7a0',
  cursor_bg = '#f6b73c',
  cursor_fg = '#1b120d',
  selection_bg = '#8f4b28',
  selection_fg = '#ffe4ad',
  scrollbar_thumb = '#c46a2b',

  ansi = {
    '#2a1a12', '#b5482d', '#c98725', '#d79a35',
    '#a6532f', '#b9653d', '#d8a15b', '#f0c982',
  },
  brights = {
    '#60402b', '#df6840', '#f0a62b', '#ffc95c',
    '#e47a3b', '#e18a5f', '#f0c27b', '#fff0c7',
  },

  tab_bar = {
    background = '#120b08',
    active_tab = {
      bg_color = '#c46a2b',
      fg_color = '#1b120d',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#3a2418',
      fg_color = '#c89a68',
    },
    inactive_tab_hover = {
      bg_color = '#6d3822',
      fg_color = '#f3d7a0',
    },
    new_tab = {
      bg_color = '#24150f',
      fg_color = '#d79a35',
    },
    new_tab_hover = {
      bg_color = '#8f4b28',
      fg_color = '#ffe4ad',
    },
  },
}

-- Session restore: autosave workspace state and restore it on startup.
-- Fully automatic, no keybindings: periodic saves every 30 seconds plus
-- saves on focus loss and on tab/pane structure changes. Restored panes
-- return to their saved working directory with scrollback; panes that were
-- running opencode relaunch it, resuming the exact session when a
-- pane-to-session snapshot is present and otherwise continuing the
-- folder's last session.
local resurrect = wezterm.plugin.require('https://github.com/StephenGemin/resurrect.wezterm')
local resurrect_state_dir = (os.getenv('XDG_STATE_HOME') or (wezterm.home_dir .. '/.local/state'))
  .. '/wezterm/resurrect/'
local session_map_path = resurrect_state_dir .. 'opencode-sessions.json'
local session_snapshot_path = resurrect_state_dir .. 'opencode-tab-snapshot.json'

resurrect.state_manager.set_max_nlines(2000)
resurrect.state_manager.periodic_save({ interval_seconds = 30, save_workspaces = true })
resurrect.state_manager.event_driven_save({ save_workspaces = true, save_on_focus_loss = true })

local last_save_text = 'autosave: pending'

local function read_json_file(path)
  local file = io.open(path, 'r')
  if not file then return nil end
  local content = file:read('*a')
  file:close()
  if not content or content == '' then return nil end
  local ok, value = pcall(wezterm.json_parse, content)
  if not ok then return nil end
  return value
end

local function base_name(path)
  if type(path) ~= 'string' then return nil end
  return path:match('([^/]+)$')
end

local function is_opencode_process(process)
  if type(process) ~= 'table' then return false end
  if base_name(process.name) == 'opencode' then return true end
  if base_name(process.executable) == 'opencode' then return true end
  local argv0 = type(process.argv) == 'table' and process.argv[1] or nil
  return base_name(argv0) == 'opencode'
end

local function valid_session_id(value)
  return type(value) == 'string' and value:match('^ses_[A-Za-z0-9]+$') ~= nil
end

-- Ordered list of { cwd, session } matching restore order. Rebuilt after
-- every workspace save by zipping the just-written state (preorder:
-- node, right, bottom) with the live mux panes in the same order.
-- The pairwise zip stops at the first cwd mismatch so skewed saves degrade
-- to plain restores instead of attaching wrong sessions.
local function rebuild_session_snapshot(state_path)
  local ok = pcall(function()
    local state = read_json_file(state_path)
    if type(state) ~= 'table' or type(state.workspace) ~= 'string'
      or type(state.window_states) ~= 'table' then
      return
    end

    local saved = {}
    local function walk(node)
      if type(node) ~= 'table' then return end
      table.insert(saved, node.cwd)
      walk(node.right)
      walk(node.bottom)
    end
    for _, window_state in ipairs(state.window_states) do
      if type(window_state.tabs) == 'table' then
        for _, tab_state in ipairs(window_state.tabs) do
          walk(tab_state.pane_tree)
        end
      end
    end
    if #saved == 0 then return end

    local live = {}
    for _, mux_win in ipairs(wezterm.mux.all_windows()) do
      if mux_win:get_workspace() == state.workspace then
        for _, mux_tab in ipairs(mux_win:tabs()) do
          for _, mux_pane in ipairs(mux_tab:panes()) do
            local cwd_obj = mux_pane:get_current_working_dir()
            table.insert(live, {
              id = tostring(mux_pane:pane_id()),
              cwd = cwd_obj and cwd_obj.file_path or nil,
            })
          end
        end
      end
    end

    local map = read_json_file(session_map_path) or {}

    local snapshot = {}
    for i = 1, math.min(#saved, #live) do
      if saved[i] == nil or saved[i] ~= live[i].cwd then break end
      local session = nil
      local entry = map[live[i].id]
      if type(entry) == 'table' and valid_session_id(entry.session)
        and entry.directory == live[i].cwd then
        session = entry.session
      end
      table.insert(snapshot, { cwd = live[i].cwd, session = session })
    end

    local file = io.open(session_snapshot_path, 'w')
    if file then
      file:write(wezterm.json_encode(snapshot))
      file:close()
    end

    -- Drop map entries for dead panes so stale ids can never false-match
    -- after a restart reuses low pane ids (the map is wiped on fresh boot anyway).
    local live_ids = {}
    for _, p in ipairs(live) do live_ids[p.id] = true end
    local fresh = {}
    for id, entry in pairs(map) do
      if live_ids[id] then fresh[id] = entry end
    end
    local prune = io.open(session_map_path, 'w')
    if prune then
      prune:write(wezterm.json_encode(fresh))
      prune:close()
    end
  end)
  if not ok then
    wezterm.log_warn('session snapshot rebuild failed')
  end
end

wezterm.on('resurrect.file_io.write_state.finished', function(file_path)
  rebuild_session_snapshot(file_path)
  last_save_text = 'autosave: ' .. os.date('%H:%M:%S')
end)

wezterm.on('update-status', function(window)
  window:set_right_status(last_save_text)
end)

local restore_snapshot = {}
local restore_index = 0

local function on_pane_restore(pane_tree)
  restore_index = restore_index + 1
  if is_opencode_process(pane_tree.process) and pane_tree.pane then
    local entry = restore_snapshot[restore_index]
    if type(entry) == 'table' and entry.cwd == pane_tree.cwd
      and valid_session_id(entry.session) then
      pane_tree.pane:send_text('opencode --session ' .. entry.session .. '\r\n')
    else
      pane_tree.pane:send_text('opencode --continue\r\n')
    end
  else
    resurrect.tab_state.default_on_pane_restore(pane_tree)
  end
end

wezterm.on('gui-startup', function()
  local ok = pcall(function()
    if #wezterm.mux.all_windows() == 0 then
      -- Fresh mux: pane ids restart at zero, so last lifetime's map would
      -- false-match. The snapshot taken at save time already holds sessions.
      os.remove(session_map_path)
    end

    local name = 'default'
    local current = io.open(resurrect_state_dir .. 'current_state', 'r')
    if current then
      local saved_name = current:read('*line')
      local saved_type = current:read('*line')
      current:close()
      if saved_type ~= nil and saved_type ~= 'workspace' then return end
      if type(saved_name) == 'string' and saved_name:match('^[%w_%-]+$') then
        name = saved_name
      end
    end

    local probe = io.open(resurrect_state_dir .. 'workspace/' .. name .. '.json', 'r')
    if not probe then return end
    probe:close()

    local state = resurrect.state_manager.load_state(name, 'workspace')
    if type(state) ~= 'table' or type(state.window_states) ~= 'table'
      or #state.window_states == 0 then
      return
    end

    local snapshot = read_json_file(session_snapshot_path)
    restore_snapshot = type(snapshot) == 'table' and snapshot or {}
    restore_index = 0

    resurrect.workspace_state.restore_workspace(state, {
      spawn_in_workspace = true,
      relative = true,
      restore_text = true,
      on_pane_restore = on_pane_restore,
    })
    wezterm.mux.set_active_workspace(name)
  end)
  if not ok then
    wezterm.log_error('session restore on gui-startup failed')
  end
end)

return config
