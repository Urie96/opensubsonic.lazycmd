local M = {}

local api = require 'opensubsonic.api'
local shared = require 'opensubsonic.shared'
local actions = require 'opensubsonic.actions'
local cfg = require 'opensubsonic.config'

local function attach_playlist_meta(entries)
  local keymap = cfg.get().keymap

  local mt = {}
  mt.__index = mt
  mt.keymap = {
    [keymap.append_to_player] = { callback = actions.append_playlist_entry, desc = 'append playlist to player' },
    [keymap.delete] = { callback = actions.delete_playlist_entry, desc = 'delete playlist' },
    [keymap.new] = { callback = actions.create_playlist_from_input, desc = 'new playlist' },
  }
  mt.preview = shared.playlist_preview

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

local function list_playlists(path, cb)
  local keymap = cfg.get().keymap

  api.list_playlists(function(playlists, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, playlist in ipairs(playlists) do
      table.insert(entries, {
        key = playlist.id,
        kind = 'playlist',
        playlist = playlist,
        display = shared.format_playlist_display(playlist),
      })
    end

    if #entries > 0 then
      attach_playlist_meta(entries)
    else
      entries = {
        {
          key = 'empty',
          kind = 'info',
          keymap = {
            [keymap.new] = { callback = actions.create_playlist_from_input, desc = 'new playlist' },
          },
          display = lc.style.line { shared.dim 'No playlists yet.' },
        },
      }
    end

    cb(entries)
  end)
end

local function attach_playlist_song_meta(entries)
  local keymap = cfg.get().keymap

  local mt = {}
  mt.__index = mt
  mt.keymap = {
    [keymap.play_now] = { callback = actions.play_song_entry, desc = 'play now' },
    [keymap.append_to_player] = { callback = actions.append_song_entry, desc = 'append to player' },
    [keymap.toggle_star] = { callback = actions.toggle_song_star_entry, desc = 'toggle star' },
    [keymap.add_to_playlist] = { callback = actions.add_song_entry_to_playlist, desc = 'add to playlist' },
    [keymap.delete] = { callback = actions.remove_song_entry_from_playlist, desc = 'remove from playlist' },
  }
  mt.preview = shared.song_preview

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

local function list_playlist_songs(playlist_id, cb)
  api.list_playlist_songs(playlist_id, function(playlist, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, song in ipairs(playlist.entry or {}) do
      table.insert(entries, {
        key = song.id,
        kind = 'song',
        song = song,
        parent = playlist,
        source = 'playlist',
        display = shared.format_song_display(song),
      })
    end

    attach_playlist_song_meta(entries)
    cb(entries)
  end)
end

function M.list(path, cb)
  if #path == 2 then
    list_playlists(path, cb)
    return
  end

  if #path == 3 then
    list_playlist_songs(path[3], cb)
    return
  end

  cb {}
end

return M
