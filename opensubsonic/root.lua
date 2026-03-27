local M = {}

local actions = require 'opensubsonic.actions'
local cfg = require 'opensubsonic.config'
local shared = require 'opensubsonic.shared'

local sections = {
  {
    key = 'playlist',
    kind = 'section',
    title = 'Playlists',
    display = lc.style.line { shared.accent '󰲹', shared.dim '  ', shared.accent 'Playlist' },
    preview = function(self, cb) cb 'Browse playlists' end,
    list = function(...) require('opensubsonic.playlist').list(...) end,
  },
  {
    key = 'artist',
    kind = 'section',
    title = 'Artists',
    display = lc.style.line { shared.mag '󰎂', shared.dim '  ', shared.mag 'Artist' },
    list = function(...) require('opensubsonic.artist').list(...) end,
  },
  {
    key = 'album',
    kind = 'section',
    title = 'Albums',
    display = lc.style.line { shared.warm '󰀥', shared.dim '  ', shared.warm 'Album' },
    list = function(...) require('opensubsonic.album').list(...) end,
  },
  {
    key = 'player',
    kind = 'section',
    title = 'Player Queue',
    display = lc.style.line { shared.okc '󰐊', shared.dim '  ', shared.okc 'Player' },
    list = function(...) require('opensubsonic.player').list(...) end,
  },
  {
    key = 'random',
    kind = 'section',
    title = 'Random Songs',
    display = lc.style.line { shared.okc '', shared.dim '  ', shared.okc 'Random' },
    list = function(...) require('opensubsonic.random').list(...) end,
  },
  {
    key = 'starred',
    kind = 'section',
    title = 'Starred Songs',
    display = lc.style.line { shared.accent '', shared.dim '  ', shared.accent 'Starred' },
    list = function(...) require('opensubsonic.starred').list(...) end,
  },
  {
    key = 'search',
    kind = 'section',
    title = 'Search',
    display = lc.style.line { shared.titlec '󰍉', shared.dim '  ', shared.titlec 'Search' },
    keymap = {
      [cfg.get().keymap.play_now] = actions.open_search_input,
      [cfg.get().keymap.search] = actions.open_search_input,
    },
    preview = function(_, cb)
      cb(shared.preview_lines {
        lc.style.line { shared.titlec 'Search music' },
        '',
        lc.style.line { shared.dim 'Results are loaded from search3 and grouped into artist, album and song.' },
      })
    end,
    list = function(...) require('opensubsonic.search').list(...) end,
  },
}

function M.list(path, cb)
  if #path == 0 then cb(sections) end

  for _, section in ipairs(sections) do
    if section.key == path[1] then
      section.list(path, function(entries, list_err)
        if list_err then
          shared.show_error(list_err)
          cb {}
          return
        end
        cb(entries)
      end)
      break
    end
  end
end

return M
