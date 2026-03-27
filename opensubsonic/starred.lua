local M = {}

local api = require 'opensubsonic.api'
local actions = require 'opensubsonic.actions'
local cfg = require 'opensubsonic.config'
local shared = require 'opensubsonic.shared'

local function starred_preview()
  return shared.preview_lines {
    lc.style.line { shared.accent 'Starred songs' },
  }
end

local function attach_starred_song_meta(entries)
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

function M.list(path, cb)
  api.list_starred_songs(function(songs, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, song in ipairs(songs or {}) do
      table.insert(entries, {
        key = song.id,
        kind = 'song',
        song = song,
        source = 'starred',
        display = shared.format_song_display(song),
      })
    end

    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          preview = starred_preview,
          display = lc.style.line { shared.dim 'No starred songs.' },
        },
      }
    else
      attach_starred_song_meta(entries)
    end

    cb(entries)
  end)
end

return M
