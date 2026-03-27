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
    [keymap.append_to_player] = actions.append_playlist_entry,
    [keymap.delete] = actions.delete_playlist_entry,
    [keymap.new] = actions.create_playlist_from_input,
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
            [keymap.new] = actions.create_playlist_from_input,
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
    [keymap.play_now] = actions.play_song_entry,
    [keymap.append_to_player] = actions.append_song_entry,
    [keymap.toggle_star] = actions.toggle_song_star_entry,
    [keymap.add_to_playlist] = actions.add_song_entry_to_playlist,
    [keymap.delete] = actions.remove_song_entry_from_playlist,
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
  if #path == 1 then
    list_playlists(path, cb)
    return
  end

  if #path == 2 then
    list_playlist_songs(path[2], cb)
    return
  end

  cb {}
end

return M
