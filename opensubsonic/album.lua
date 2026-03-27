local M = {}

local api = require 'opensubsonic.api'
local actions = require 'opensubsonic.actions'
local cfg = require 'opensubsonic.config'
local shared = require 'opensubsonic.shared'

local function attach_album_meta(entries)
  local mt = {}
  mt.__index = mt
  mt.preview = shared.album_preview

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

local function attach_song_meta(entries)
  local keymap = cfg.get().keymap

  local mt = {}
  mt.__index = mt
  mt.keymap = {
    [keymap.play_now] = { callback = actions.play_song_entry, desc = 'play now' },
    [keymap.append_to_player] = { callback = actions.append_song_entry, desc = 'append to player' },
    [keymap.toggle_star] = { callback = actions.toggle_song_star_entry, desc = 'toggle star' },
    [keymap.add_to_playlist] = { callback = actions.add_song_entry_to_playlist, desc = 'add to playlist' },
  }
  mt.preview = shared.song_preview

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

local function list_albums(path, cb)
  api.list_albums(function(albums, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, album in ipairs(albums) do
      table.insert(entries, {
        key = album.id,
        kind = 'album',
        album = album,
        display = shared.format_album_display(album),
      })
    end

    attach_album_meta(entries)
    cb(entries)
  end)
end

local function list_album_songs(path, album_id, cb)
  api.list_album_songs(album_id, function(album, songs, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, song in ipairs(songs) do
      table.insert(entries, {
        key = song.id,
        kind = 'song',
        song = song,
        parent = album,
        source = 'album',
        display = shared.format_song_display(song),
      })
    end

    attach_song_meta(entries)
    cb(entries)
  end)
end

function M.list(path, cb)
  if #path == 2 then
    list_albums(path, cb)
    return
  end

  if #path == 3 then
    list_album_songs(path, path[3], cb)
    return
  end

  cb {}
end

return M
