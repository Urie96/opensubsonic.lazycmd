local M = {}

local actions = require 'opensubsonic.actions'
local shared = require 'opensubsonic.shared'

local function preview_method(renderer)
  return function(self, cb)
    cb(renderer(self))
  end
end

local section_mt = {
  __index = function(self, key)
    if key == 'preview' then return preview_method(shared.section_preview) end
    if key == 'keymap' then
      if self.key == 'playlist' then return actions.playlist_section_keymap end
      if self.key == 'search' then return actions.search_keymap end
    end
  end,
}

local playlist_mt = {
  __index = function(_, key)
    if key == 'preview' then return preview_method(shared.playlist_preview) end
    if key == 'keymap' then return actions.playlist_keymap end
  end,
}

local artist_mt = {
  __index = function(self, key)
    if key == 'preview' then return preview_method(shared.artist_preview) end
    if key == 'keymap' and self.source == 'search' then return actions.search_keymap end
  end,
}

local album_mt = {
  __index = function(self, key)
    if key == 'preview' then return preview_method(shared.album_preview) end
    if key == 'keymap' and self.source == 'search' then return actions.search_keymap end
  end,
}

local song_mt = {
  __index = function(_, key)
    if key == 'preview' then return preview_method(shared.song_preview) end
    if key == 'keymap' then return actions.song_keymap end
  end,
}

local search_group_mt = {
  __index = function(_, key)
    if key == 'preview' then return preview_method(shared.search_group_preview) end
    if key == 'keymap' then return actions.search_keymap end
  end,
}

local info_mt = {
  __index = function(self, key)
    if key == 'preview' then return preview_method(shared.info_preview) end
    if key == 'keymap' then
      if self.info_keymap == 'playlist' then return actions.playlist_keymap end
      if self.info_keymap == 'search' then return actions.search_keymap end
    end
  end,
}

local metatables = {
  section = section_mt,
  playlist = playlist_mt,
  artist = artist_mt,
  album = album_mt,
  song = song_mt,
  search_group = search_group_mt,
  info = info_mt,
}

function M.attach(entry)
  local mt = metatables[entry.kind]
  if mt then return setmetatable(entry, mt) end
  return entry
end

function M.attach_all(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    table.insert(out, M.attach(entry))
  end
  return out
end

return M
