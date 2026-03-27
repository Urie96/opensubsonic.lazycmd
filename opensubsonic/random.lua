local M = {}

local api = require 'opensubsonic.api'
local actions = require 'opensubsonic.actions'
local cfg = require 'opensubsonic.config'
local shared = require 'opensubsonic.shared'

local function random_preview()
  return shared.preview_lines {
    lc.style.line { shared.okc 'Random songs' },
  }
end

local function attach_random_song_meta(entries)
  local keymap = cfg.get().keymap

  local mt = {}
  mt.__index = mt
  mt.keymap = {
    [keymap.play_now] = actions.play_song_entry,
    [keymap.append_to_player] = actions.append_song_entry,
    [keymap.toggle_star] = actions.toggle_song_star_entry,
    [keymap.add_to_playlist] = actions.add_song_entry_to_playlist,
  }
  mt.preview = shared.song_preview

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

function M.list(path, cb)
  api.list_random_songs(function(songs, err)
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
        source = 'random',
        display = shared.format_song_display(song),
      })
    end

    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          preview = random_preview,
          display = lc.style.line { shared.dim 'No random songs returned.' },
        },
      }
    else
      attach_random_song_meta(entries)
    end

    cb(entries)
  end)
end

return M
