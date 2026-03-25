local M = {}
local config = require 'opensubsonic.config'

local state = {
  mpv_starting = false,
  mpv_waiters = {},
  queue_meta = {},
}

local function current_cfg() return config.get() end

local function socket_exists()
  local cfg = current_cfg()
  return lc.fs.stat(cfg.mpv_socket).exists
end

local function finish_waiters(ok, err)
  local waiters = state.mpv_waiters
  state.mpv_waiters = {}
  state.mpv_starting = false
  for _, waiter in ipairs(waiters) do
    waiter(ok, err)
  end
end

local function socket_request_raw(message, cb)
  local cfg = current_cfg()
  lc.system.socket_request({
    path = cfg.mpv_socket,
    message = message,
  }, function(response)
    if not response.success then
      cb(nil, response.error or 'socket request failed')
      return
    end
    cb(response.body)
  end)
end

local function socket_request_raw_sync(message)
  local cfg = current_cfg()
  local response = lc.system.socket_request_sync {
    path = cfg.mpv_socket,
    message = message,
  }
  if not response.success then return nil, response.error or 'socket request failed' end
  return response.body
end

local function mpv_request_no_spawn(command, cb)
  if not socket_exists() then
    cb(nil, 'mpv not running')
    return
  end

  socket_request_raw(lc.json.encode { command = command }, function(body, err)
    if err then
      cb(nil, err)
      return
    end

    local ok, decoded = pcall(lc.json.decode, body or '')
    if not ok then
      cb(nil, 'failed to decode mpv response')
      return
    end

    if decoded.error and decoded.error ~= 'success' then
      cb(nil, decoded.error)
      return
    end
    cb(decoded)
  end)
end

local function probe_mpv(cb)
  mpv_request_no_spawn({ 'get_property', 'pause' }, function(response, err)
    if response then
      cb(true)
      return
    end
    local cfg = current_cfg()
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
      cb(true)
      return
    end

    table.insert(state.mpv_waiters, cb)
    if state.mpv_starting then return end

    state.mpv_starting = true
    if socket_exists() then lc.fs.remove(cfg.mpv_socket) end

    local cmd = { 'mpv' }
    local cfg = current_cfg()
    for _, arg in ipairs(cfg.mpv_args or {}) do
      table.insert(cmd, arg)
    end
    table.insert(cmd, '--input-ipc-server=' .. cfg.mpv_socket)
    lc.system.spawn(cmd)
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
    if tostring(meta.id) == tostring(song_id) then
      meta.starred = starred and lc.time.format(lc.time.now()) or nil
    end
  end
end

function M.play_tracks(tracks, stream_url_fn, cb) queue_tracks(tracks, true, stream_url_fn, cb) end

function M.append_tracks(tracks, stream_url_fn, cb) queue_tracks(tracks, false, stream_url_fn, cb) end

function M.player_next(cb) mpv_request({ 'playlist-next', 'force' }, cb) end

function M.player_prev(cb) mpv_request({ 'playlist-prev', 'force' }, cb) end

function M.player_toggle_pause(cb) mpv_request({ 'cycle', 'pause' }, cb) end

function M.player_play(cb) mpv_request({ 'set_property', 'pause', false }, cb) end

function M.player_jump(index, cb)
  mpv_request({ 'set_property', 'playlist-pos', index }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    M.player_play(cb)
  end)
end

function M.quit(cb)
  if not socket_exists() then
    if cb then cb(true) end
    return
  end

  mpv_request_no_spawn({ 'quit' }, function(_, err)
    if cb then
      if err and err ~= 'mpv not running' then
        cb(nil, err)
      else
        cb(true)
      end
    end
  end)
end

function M.quit_sync()
  if not socket_exists() then return true end
  local body, err = socket_request_raw_sync(lc.json.encode { command = { 'quit' } })
  if not body and err and err ~= 'mpv not running' then return nil, err end
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
