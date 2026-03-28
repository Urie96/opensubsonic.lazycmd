local M = {}

local api = require 'opensubsonic.api'
local shared = require 'opensubsonic.shared'
local cfg = require 'opensubsonic.config'

local function hovered_entry() return lc.api.page_get_hovered() end

local function get_mpv()
  local ok, mod = pcall(require, 'mpv')
  if ok and mod then return mod end
  shared.show_error('mpv plugin is required: add { dir = "plugins/mpv.lazycmd" } to lc.config.plugins')
  return nil
end

local function reload_if_player_visible()
  local path = lc.api.get_current_path() or {}
  if path[1] == 'mpv' then lc.cmd 'reload' end
end

local function mpv_preview(entry)
  local item = entry.player_item or {}
  local meta = entry.mpv_meta or {}
  local player = entry.player or {}

  return shared.preview_lines {
    lc.style.line { shared.okc 'mpv queue' },
    '',
    shared.kv_line('State', player.pause and 'paused' or 'playing', player.pause and 'mag' or 'accent'),
    shared.kv_line('Current', tostring(item.current == true or item.playing == true), 'accent'),
    shared.kv_line('Title', meta.title or item.title or item.filename or '-'),
    shared.kv_line('Artist', meta.artist or '-'),
    shared.kv_line('Album', meta.album or '-'),
    shared.kv_line('Starred', tostring(meta.starred ~= nil and meta.starred ~= ''), 'accent'),
    shared.kv_line('Duration', shared.format_duration(meta.duration)),
  }
end

local function build_mpv_track(song)
  local keymap = cfg.get().keymap
  return {
    key = tostring(song.id),
    id = song.id,
    url = api.stream_url(song.id),
    title = song.title or song.name or song.id,
    artist = song.artist or song.displayArtist or 'Unknown artist',
    album = song.album or '',
    duration = song.duration,
    starred = song.starred,
    source = 'opensubsonic',
    display = function(item, player, meta)
      item._meta = meta
      item._player = player
      return shared.format_player_entry(item)
    end,
    preview = function(entry, cb)
      local preview = mpv_preview(entry)
      if cb then
        cb(preview)
        return
      end
      return preview
    end,
    keymap = {
      [keymap.toggle_star] = { callback = M.toggle_song_star_entry, desc = 'toggle star' },
    },
  }
end

function M.open_search_input()
  lc.input {
    prompt = 'Search music',
    placeholder = 'keyword',
    on_submit = function(input)
      local query = tostring(input or ''):trim()
      if query == '' then
        lc.api.go_to { 'opensubsonic', 'search' }
        return
      end
      lc.api.go_to { 'opensubsonic', 'search', query }
    end,
  }
end

function M.play_song_entry()
  local target = hovered_entry()
  if not target or target.kind ~= 'song' or not target.song then
    lc.cmd 'enter'
    return
  end

  local mpv = get_mpv()
  if not mpv then return false end

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
    if entry and entry.kind == 'song' and entry.song then
      table.insert(queue, build_mpv_track(entry.song))
    end
  end

  mpv.play_tracks(queue)
    :next(function()
      shared.show_info 'Sent tracks to mpv queue'
      reload_if_player_visible()
    end)
    :catch(function(err)
      shared.show_error(err)
    end)
end

function M.append_song_entry()
  local target = hovered_entry()
  if not target or target.kind ~= 'song' or not target.song then return false end

  local mpv = get_mpv()
  if not mpv then return false end

  mpv.append_tracks({ build_mpv_track(target.song) })
    :next(function()
      shared.show_info 'Song appended to mpv queue'
      reload_if_player_visible()
    end)
    :catch(function(err)
      shared.show_error(err)
    end)

  return true
end

function M.append_playlist_entry()
  local target = lc.api.page_get_hovered()
  if not target or target.kind ~= 'playlist' or not target.playlist or not target.playlist.id then return false end

  local mpv = get_mpv()
  if not mpv then return false end

  api.list_playlist_songs(target.playlist.id, function(playlist, err)
    if err then
      shared.show_error(err)
      return
    end

    local tracks = {}
    for _, song in ipairs(playlist.entry or {}) do
      table.insert(tracks, build_mpv_track(song))
    end

    mpv.append_tracks(tracks)
      :next(function()
        shared.show_info 'Playlist appended to mpv queue'
        reload_if_player_visible()
      end)
      :catch(function(append_err)
        shared.show_error(append_err)
      end)
  end)

  return true
end

function M.set_song_starred_local(song_id, starred)
  local entries = lc.api.page_get_entries() or {}
  local stamped = starred and lc.time.format(lc.time.now()) or nil
  local mpv = get_mpv()
  if mpv then mpv.update_track_fields(song_id, { starred = stamped }) end

  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song and tostring(entry.song.id) == tostring(song_id) then
      entry.song.starred = stamped
      entry.display = shared.format_song_display(entry.song)
    elseif entry.mpv_meta and tostring(entry.mpv_meta.id) == tostring(song_id) then
      entry.mpv_meta.starred = stamped
      local item = entry.player_item or {}
      item._meta = entry.mpv_meta
      entry.player_item = item
      if type(entry.display) ~= 'function' then entry.display = shared.format_player_entry(item) end
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
  elseif target.mpv_meta and target.mpv_meta.id then
    song = {
      id = target.mpv_meta.id,
      starred = target.mpv_meta.starred,
    }
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
  if path[2] ~= 'playlist' or #path ~= 3 or not target or target.kind ~= 'song' then return false end

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

  api.remove_song_from_playlist(path[3], playlist_index, function(_, err)
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
  if path[2] ~= 'playlist' or #path ~= 2 then return false end

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

function M.setup() end

return M
