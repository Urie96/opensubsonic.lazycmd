local M = {}

local api = require 'opensubsonic.api'
local mpv = require 'opensubsonic.mpv'
local shared = require 'opensubsonic.shared'

local function hovered_entry() return lc.api.page_get_hovered() end

function M.open_search_input()
  lc.input {
    prompt = 'Search music',
    placeholder = 'keyword',
    on_submit = function(input)
      local query = tostring(input or ''):trim()
      if query == '' then
        lc.api.go_to { 'search' }
        return
      end
      lc.api.go_to { 'search', query }
    end,
  }
end

local function reload_if_player_visible()
  if lc.api.get_current_path()[1] == 'player' then lc.cmd 'reload' end
end

function M.play_song_entry()
  local target = hovered_entry()
  if not target or target.kind ~= 'song' or not target.song then
    lc.cmd 'enter'
    return
  end

  local _, entries = shared.current_song_entries()
  local start = 1
  for index, entry in ipairs(entries or {}) do
    if entry.kind == 'song' and entry.song and tostring(entry.song.id) == tostring(target.song.id) then
      start = index
      break
    end
  end

  local queue = {}
  for index = start, #entries do
    local entry = entries[index]
    if entry and entry.kind == 'song' and entry.song then table.insert(queue, entry.song) end
  end

  for _, song in ipairs(queue) do
    mpv.remember_song(song, api.stream_url)
  end

  mpv.play_tracks(queue, api.stream_url, function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    shared.show_info 'Sent tracks to mpv queue'
    reload_if_player_visible()
  end)
end

function M.append_song_entry()
  local target = hovered_entry()
  if not target or target.kind ~= 'song' or not target.song then return end
  mpv.remember_song(target.song, api.stream_url)
  mpv.append_tracks({ target.song }, api.stream_url, function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    shared.show_info 'Song appended to mpv queue'
    reload_if_player_visible()
  end)
end

function M.append_playlist_entry()
  local target = lc.api.page_get_hovered()
  if not target or target.kind ~= 'playlist' or not target.playlist or not target.playlist.id then return end
  api.list_playlist_songs(target.playlist.id, function(playlist, err)
    if err then
      shared.show_error(err)
      return
    end

    local tracks = playlist.entry or {}
    for _, song in ipairs(tracks) do
      mpv.remember_song(song, api.stream_url)
    end

    mpv.append_tracks(tracks, api.stream_url, function(_, append_err)
      if append_err then
        shared.show_error(append_err)
        return
      end
      shared.show_info 'Playlist appended to mpv queue'
      reload_if_player_visible()
    end)
  end)
end

function M.set_song_starred_local(song_id, starred)
  local entries = lc.api.page_get_entries() or {}
  mpv.set_song_starred(song_id, starred)
  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song and tostring(entry.song.id) == tostring(song_id) then
      entry.song.starred = starred and lc.time.format(lc.time.now()) or nil
      entry.display = shared.format_song_display(entry.song)
    elseif entry.kind == 'player_song' then
      local item = entry.player_item or {}
      local meta = item._meta or {}
      local item_id = meta.id or item.id
      if tostring(item_id) == tostring(song_id) then
        meta.starred = starred and lc.time.format(lc.time.now()) or nil
        item._meta = meta
        entry.player_item = item
        entry.display = shared.format_player_entry(item)
      end
    end
  end
  lc.api.page_set_entries(entries)
  shared.refresh_current_page_entries()
end

function M.toggle_song_star_entry()
  local target = hovered_entry()
  if not target then return false end

  local song = nil
  if target.kind == 'song' and target.song then
    song = target.song
  elseif target.kind == 'player_song' then
    local item = target.player_item or {}
    local meta = item._meta or {}
    local song_id = meta.id or item.id
    if song_id then song = {
      id = song_id,
      starred = meta.starred,
    } end
  end

  if not song or not song.id then return false end
  local was_starred = song.starred and song.starred ~= ''

  M.set_song_starred_local(song.id, not was_starred)

  if was_starred then
    api.unstar_song(song.id, function(_, err)
      if err then
        M.set_song_starred_local(song.id, true)
        shared.show_error(err)
      end
    end)
    return true
  end

  api.star_song(song.id, function(_, err)
    if err then
      M.set_song_starred_local(song.id, false)
      shared.show_error(err)
    end
  end)
  return true
end

function M.add_song_entry_to_playlist()
  local target = hovered_entry()
  if not target or target.kind ~= 'song' or not target.song then return false end

  api.list_playlists(function(playlists, err)
    if err then
      shared.show_error(err)
      return
    end

    local options = {}
    for _, playlist in ipairs(playlists or {}) do
      table.insert(options, {
        value = playlist.id,
        display = shared.format_playlist_display(playlist),
      })
    end

    if #options == 0 then
      shared.show_info 'No playlists available'
      return
    end

    lc.select({
      prompt = 'Add song to playlist',
      options = options,
    }, function(choice)
      if not choice then return end

      api.add_song_to_playlist(choice, target.song.id, function(_, add_err)
        if add_err then
          shared.show_error(add_err)
          return
        end
        shared.show_info 'Song added to playlist'
      end)
    end)
  end)

  return true
end

function M.remove_song_entry_from_playlist(target)
  local path = lc.api.get_current_path()
  if path[1] ~= 'playlist' or #path ~= 2 or not target or target.kind ~= 'song' then return false end

  local entries = lc.api.page_get_entries() or {}
  local playlist_index = nil
  local song_count = 0
  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song then
      if target.song and tostring(entry.song.id) == tostring(target.song.id) and playlist_index == nil then
        playlist_index = song_count
      end
      song_count = song_count + 1
    end
  end

  if playlist_index == nil then
    shared.show_error 'failed to locate playlist item index'
    return true
  end

  api.remove_song_from_playlist(path[2], playlist_index, function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    shared.show_info 'Song removed from playlist'
    lc.cmd 'reload'
  end)

  return true
end

function M.delete_playlist_entry()
  local target = lc.api.page_get_hovered()
  if not target or target.kind ~= 'playlist' or not target.playlist then return false end

  local playlist = target.playlist or {}
  lc.confirm {
    title = 'Delete Playlist',
    prompt = 'Delete playlist "' .. tostring(playlist.name or playlist.id or '?') .. '"?',
    on_confirm = function()
      api.delete_playlist(playlist.id, function(_, err)
        if err then
          shared.show_error(err)
          return
        end
        shared.show_info 'Playlist deleted'
        lc.cmd 'reload'
      end)
    end,
  }

  return true
end

function M.create_playlist_from_input()
  local path = lc.api.get_current_path()
  if path[1] ~= 'playlist' or #path ~= 1 then return false end

  lc.input {
    prompt = 'New playlist',
    placeholder = 'playlist name',
    on_submit = function(input)
      local name = tostring(input or ''):trim()
      if name == '' then return end

      api.create_playlist(name, function(_, err)
        if err then
          shared.show_error(err)
          return
        end
        shared.show_info 'Playlist created'
        lc.cmd 'reload'
      end)
    end,
  }

  return true
end

function M.player_jump_to_entry(target)
  if not target or target.kind ~= 'player_song' then
    lc.cmd 'enter'
    return
  end

  mpv.player_jump(target.playlist_index, function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

function M.player_next()
  mpv.player_next(function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

function M.player_prev()
  mpv.player_prev(function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

function M.player_toggle_pause()
  mpv.player_toggle_pause(function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

function M.player_play()
  mpv.player_play(function(_, err)
    if err then
      shared.show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

function M.adjust_player_volume(delta)
  mpv.player_adjust_volume(delta, function(volume, err)
    if err then
      shared.show_error(err)
      return
    end
    if type(volume) == 'number' then
      shared.show_info(string.format('Volume %.0f%%', volume))
    else
      shared.show_info 'Volume updated'
    end
  end)
end

function M.schedule_player_reload()
  if shared.state.player_reload_pending then return end
  shared.state.player_reload_pending = true
  lc.defer_fn(function()
    shared.state.player_reload_pending = false
    if lc.api.get_current_path()[1] == 'player' then lc.cmd 'reload' end
  end, 50)
end

function M.setup()
  mpv.on_player_event(function(event)
    if not event then return end

    if event.event == 'shutdown' then
      M.schedule_player_reload()
      return
    end

    if event.event ~= 'property-change' then return end
    local name = tostring(event.name or '')
    if name == 'pause' or name == 'playlist' or name == 'playlist-pos' or name == 'idle-active' or name == 'volume' then
      M.schedule_player_reload()
    end
  end)

  lc.api.append_hook_pre_quit(function()
    local ok, err = mpv.quit_sync()
    if not ok and err then lc.log('warn', 'failed to quit mpv: {}', err) end
  end)
end

return M
