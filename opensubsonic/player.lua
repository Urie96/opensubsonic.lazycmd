local M = {}

local mpv = require 'opensubsonic.mpv'
local actions = require 'opensubsonic.actions'
local cfg = require 'opensubsonic.config'
local shared = require 'opensubsonic.shared'

local function player_preview(entry)
  local item = entry.player_item or {}
  local meta = item._meta or {}
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

local function player_keymap()
  local keymap = cfg.get().keymap
  return {
    [keymap.play_now] = { callback = actions.player_jump_to_entry, desc = 'jump to this song' },
    [keymap.toggle_star] = { callback = actions.toggle_song_star_entry, desc = 'toggle star' },
    [keymap.player_pause] = { callback = actions.player_toggle_pause, desc = 'pause or resume player' },
    [keymap.player_next] = { callback = actions.player_next, desc = 'next song' },
    [keymap.player_prev] = { callback = actions.player_prev, desc = 'previous song' },
    [keymap.player_resume] = { callback = actions.player_play, desc = 'resume player' },
    [keymap.player_volume_up] = { callback = function() actions.adjust_player_volume(5) end, desc = 'volume up' },
    [keymap.player_volume_down] = { callback = function() actions.adjust_player_volume(-5) end, desc = 'volume down' },
  }
end

local function attach_player_song_meta(entries)
  local mt = {}
  mt.__index = mt
  mt.keymap = player_keymap()
  mt.preview = player_preview

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

function M.list(path, cb)
  mpv.get_player_state(function(player, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for index, item in ipairs(player.playlist or {}) do
      item._player = player
      table.insert(entries, {
        key = tostring(index - 1),
        kind = 'player_song',
        player = player,
        player_item = item,
        playlist_index = index - 1,
        display = shared.format_player_entry(item),
      })
    end

    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          keymap = player_keymap(),
          preview = player_preview,
          player = player,
          display = lc.style.line {
            shared.dim(player.running and 'mpv queue is empty' or 'mpv is not running'),
          },
        },
      }
    else
      attach_player_song_meta(entries)
    end

    cb(entries)
  end)
end

return M
