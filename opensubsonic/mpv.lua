local M = {}
local config = require 'opensubsonic.config'

local state = {
  mpv_starting = false,
  mpv_pid = nil,
  mpv_waiters = {},
  queue_meta = {},
  sock = nil,
  sock_path = nil,
  next_request_id = 0,
  pending_requests = {},
  player_event_cb = nil,
  player_observing = false,
}

local function current_cfg() return config.get() end
local socket_send

local function socket_exists()
  local cfg = current_cfg()
  return lc.fs.stat(cfg.mpv_socket).exists
end

local function finish_waiters(ok, err)
  local waiters = state.mpv_waiters
  state.mpv_waiters = {}
  state.mpv_starting = false
  if not ok then state.mpv_pid = nil end
  for _, waiter in ipairs(waiters) do
    waiter(ok, err)
  end
end

local function wrap_once(cb)
  local done = false
  return function(...)
    if done then return end
    done = true
    cb(...)
  end
end

local function fail_pending_requests(err)
  local pending = state.pending_requests
  state.pending_requests = {}
  for _, cb in pairs(pending) do
    cb(nil, err or 'mpv socket closed')
  end
end

local function close_socket(err)
  local sock = state.sock
  state.sock = nil
  state.sock_path = nil
  state.player_observing = false
  if sock then pcall(function() sock:close() end) end
  fail_pending_requests(err)
end

local function emit_player_event(event)
  if state.player_event_cb then state.player_event_cb(event) end
end

local function handle_socket_line(line)
  local ok, decoded = pcall(lc.json.decode, line or '')
  if not ok or type(decoded) ~= 'table' then return end

  if decoded.event then
    if decoded.event == 'property-change' then emit_player_event(decoded) end
    if decoded.event == 'shutdown' then
      emit_player_event(decoded)
      close_socket 'mpv socket closed'
    end
    return
  end

  local request_id = decoded.request_id
  if request_id == nil then return end

  local cb = state.pending_requests[request_id]
  state.pending_requests[request_id] = nil
  if cb then cb(decoded) end
end

local function ensure_socket()
  local cfg = current_cfg()
  if state.sock and state.sock_path == cfg.mpv_socket then return state.sock end

  if state.sock then close_socket 'mpv socket reset' end

  local sock = lc.socket.connect('unix:' .. cfg.mpv_socket)
  sock:on_line(function(line) handle_socket_line(line) end)
  state.sock = sock
  state.sock_path = cfg.mpv_socket
  return sock
end

local function ensure_player_observers()
  if state.player_observing then return end
  state.player_observing = true

  socket_send { command = { 'observe_property', 1, 'pause' } }
  socket_send { command = { 'observe_property', 2, 'playlist' } }
  socket_send { command = { 'observe_property', 3, 'playlist-pos' } }
  socket_send { command = { 'observe_property', 4, 'idle-active' } }
  socket_send { command = { 'observe_property', 5, 'volume' } }
end

socket_send = function(payload, cb)
  if not socket_exists() then
    if cb then cb(nil, 'mpv not running') end
    return
  end

  local sock
  local ok, result = pcall(ensure_socket)
  if ok then
    sock = result
  else
    close_socket(result)
    if cb then cb(nil, tostring(result)) end
    return
  end

  if cb then cb = wrap_once(cb) end

  local request_id = state.next_request_id + 1
  state.next_request_id = request_id
  payload.request_id = request_id

  if cb then state.pending_requests[request_id] = cb end

  local write_ok, write_err = pcall(function() sock:write(lc.json.encode(payload)) end)
  if write_ok then return end

  state.pending_requests[request_id] = nil
  close_socket(write_err)
  if cb then cb(nil, tostring(write_err)) end
end

local function mpv_request_no_spawn(command, cb)
  if not socket_exists() then
    close_socket 'mpv not running'
    cb(nil, 'mpv not running')
    return
  end

  ensure_player_observers()

  socket_send({ command = command }, function(response, err)
    if err or not response then
      cb(nil, err)
      return
    end

    if response.error and response.error ~= 'success' then
      cb(nil, response.error)
      return
    end
    cb(response)
  end)
end

function M.on_player_event(cb) state.player_event_cb = cb end

local function probe_mpv(cb)
  mpv_request_no_spawn({ 'get_property', 'pause' }, function(response, err)
    if response then
      cb(true)
      return
    end
    local cfg = current_cfg()
    close_socket(err)
    if socket_exists() then lc.fs.remove(cfg.mpv_socket) end
    cb(nil, err)
  end)
end

local function wait_for_socket(attempt)
  if attempt > 40 then
    finish_waiters(nil, 'mpv socket did not become ready')
    return
  end

  probe_mpv(function(ok)
    if ok then
      finish_waiters(true)
      return
    end

    lc.defer_fn(function() wait_for_socket(attempt + 1) end, 100)
  end)
end

local function ensure_mpv(cb)
  if not lc.system.executable 'mpv' then
    cb(nil, 'mpv not found in PATH')
    return
  end

  probe_mpv(function(ok)
    if ok then
      state.mpv_pid = nil
      cb(true)
      return
    end

    table.insert(state.mpv_waiters, cb)
    if state.mpv_starting then return end

    state.mpv_starting = true
    local cfg = current_cfg()
    close_socket 'mpv restarting'
    if socket_exists() then lc.fs.remove(cfg.mpv_socket) end

    local cmd = { 'mpv' }
    for _, arg in ipairs(cfg.mpv_args or {}) do
      table.insert(cmd, arg)
    end
    table.insert(cmd, '--input-ipc-server=' .. cfg.mpv_socket)
    local pid = lc.system.spawn(cmd)
    lc.notify(tostring(pid))
    state.mpv_pid = pid ~= 0 and pid or nil
    wait_for_socket(1)
  end)
end

local function mpv_request(command, cb)
  ensure_mpv(function(ok, err)
    if not ok then
      cb(nil, err)
      return
    end
    mpv_request_no_spawn(command, cb)
  end)
end

local function queue_tracks(tracks, replace, stream_url_fn, cb)
  if not tracks or #tracks == 0 then
    cb(true)
    return
  end

  ensure_mpv(function(ok, err)
    if not ok then
      cb(nil, err)
      return
    end

    local function step(index)
      if index > #tracks then
        mpv_request_no_spawn({ 'set_property', 'pause', false }, function(_, pause_err)
          if pause_err then
            cb(nil, pause_err)
            return
          end
          cb(true)
        end)
        return
      end

      local song = tracks[index]
      local mode = (replace and index == 1) and 'replace' or 'append-play'
      mpv_request_no_spawn({ 'loadfile', stream_url_fn(song.id), mode }, function(_, request_err)
        if request_err then
          cb(nil, request_err)
          return
        end
        step(index + 1)
      end)
    end

    step(1)
  end)
end

function M.remember_song(song, stream_url_fn)
  if not song or not song.id then return end
  local url = stream_url_fn(song.id)
  state.queue_meta[url] = {
    id = song.id,
    title = song.title or song.name or song.id,
    artist = song.artist or song.displayArtist or 'Unknown artist',
    album = song.album or '',
    duration = song.duration,
    starred = song.starred,
  }
end

function M.set_song_starred(song_id, starred)
  for _, meta in pairs(state.queue_meta) do
    if tostring(meta.id) == tostring(song_id) then meta.starred = starred and lc.time.format(lc.time.now()) or nil end
  end
end

function M.play_tracks(tracks, stream_url_fn, cb) queue_tracks(tracks, true, stream_url_fn, cb) end

function M.append_tracks(tracks, stream_url_fn, cb) queue_tracks(tracks, false, stream_url_fn, cb) end

function M.player_next(cb) mpv_request({ 'playlist-next', 'force' }, cb) end

function M.player_prev(cb) mpv_request({ 'playlist-prev', 'force' }, cb) end

function M.player_toggle_pause(cb) mpv_request({ 'cycle', 'pause' }, cb) end

function M.player_play(cb) mpv_request({ 'set_property', 'pause', false }, cb) end

function M.player_adjust_volume(delta, cb)
  mpv_request({ 'add', 'volume', delta }, function(_, err)
    if err then
      cb(nil, err)
      return
    end

    mpv_request_no_spawn({ 'get_property', 'volume' }, function(response, volume_err)
      if volume_err then
        cb(true)
        return
      end
      cb(response and response.data or true)
    end)
  end)
end

function M.player_jump(index, cb)
  mpv_request({ 'set_property', 'playlist-pos', index }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    M.player_play(cb)
  end)
end

function M.quit_sync()
  if not state.mpv_pid then return true end
  if state.mpv_pid then
    local ok, err = pcall(lc.system.kill, state.mpv_pid)
    if not ok then return nil, tostring(err) end
  end

  state.mpv_pid = nil
  close_socket 'mpv socket closed'
  return true
end

function M.get_player_state(cb)
  probe_mpv(function(ok)
    if not ok then
      cb {
        running = false,
        pause = true,
        playlist = {},
      }
      return
    end

    mpv_request_no_spawn({ 'get_property', 'playlist' }, function(playlist_resp, playlist_err)
      if playlist_err then
        cb(nil, playlist_err)
        return
      end

      mpv_request_no_spawn({ 'get_property', 'pause' }, function(pause_resp, pause_err)
        if pause_err then
          cb(nil, pause_err)
          return
        end

        local playlist = playlist_resp.data or {}
        for _, item in ipairs(playlist) do
          local meta = state.queue_meta[item.filename or '']
          if meta then item._meta = meta end
        end

        cb {
          running = true,
          pause = pause_resp.data == true,
          playlist = playlist,
        }
      end)
    end)
  end)
end

return M
