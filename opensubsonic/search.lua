local M = {}

local api = require 'opensubsonic.api'
local actions = require 'opensubsonic.actions'
local cfg = require 'opensubsonic.config'
local shared = require 'opensubsonic.shared'

local function search_root_preview()
  return shared.preview_lines {
    lc.style.line { shared.titlec 'Search music' },
    '',
    lc.style.line { shared.dim 'Results are loaded from search3 and grouped into Song, Album and Artist.' },
  }
end

local function search_groups_preview(entry)
  local query = entry.query or lc.api.get_current_path()[2] or ''
  return shared.preview_lines {
    lc.style.line { shared.titlec 'Search results' },
    '',
    shared.kv_line('Query', query, 'accent'),
    shared.kv_line('Groups', 'Song / Album / Artist', 'warm'),
  }
end

local function search_group_preview(entry)
  local query = entry.query or lc.api.get_current_path()[2] or ''
  local kind = entry.search_kind or lc.api.get_current_path()[3] or 'song'
  local color = kind == 'artist' and 'mag' or (kind == 'album' and 'warm' or 'accent')
  local title = kind:gsub('^%l', string.upper)
  return shared.preview_lines {
    lc.style.line { shared.titlec 'Search group' },
    '',
    shared.kv_line('Query', query, 'accent'),
    shared.kv_line('Type', title, color),
    shared.kv_line('Count', tostring(entry.count or 0), 'accent'),
    '',
    lc.style.line { shared.dim 'Enter to open this list. In song results, Enter plays from the current song.' },
  }
end

local function attach_search_group_meta(entries)
  local keymap = cfg.get().keymap

  local mt = {}
  mt.__index = mt
  mt.keymap = {
    [keymap.toggle_star] = { callback = actions.open_search_input, desc = 'search again' },
  }
  mt.preview = search_group_preview

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

local function attach_search_artist_meta(entries)
  local keymap = cfg.get().keymap

  local mt = {}
  mt.__index = function(_, key)
    if key == 'preview' then return shared.artist_preview end
    if key == 'keymap' then return {
      [keymap.toggle_star] = { callback = actions.open_search_input, desc = 'search again' },
    } end
  end

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

local function attach_search_album_meta(entries)
  local keymap = cfg.get().keymap

  local mt = {}
  mt.__index = function(_, key)
    if key == 'preview' then return shared.album_preview end
    if key == 'keymap' then return {
      [keymap.toggle_star] = { callback = actions.open_search_input, desc = 'search again' },
    } end
  end

  for i, entry in ipairs(entries or {}) do
    entries[i] = setmetatable(entry, mt)
  end
end

local function attach_search_song_meta(entries)
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

local function format_search_kind_display(kind, count)
  local color = kind == 'artist' and shared.mag or (kind == 'album' and shared.warm or shared.accent)
  local title = kind:gsub('^%l', string.upper)
  return lc.style.line {
    color(title),
    shared.dim '  ·  ',
    shared.okc(count),
    shared.dim(' ' .. title .. (count == 1 and '' or 's')),
  }
end

local function list_search_root(path, cb)
  local keymap = cfg.get().keymap

  local entries = {
    {
          key = 'prompt',
          kind = 'info',
          keymap = {
        [keymap.search] = { callback = actions.open_search_input, desc = 'search' },
          },
      preview = search_root_preview,
      display = shared.titlec(('Press %s to search music'):format(keymap.search)),
    },
  }
  cb(entries)
end

local function list_search_groups(path, query, cb)
  api.search(query, function(result, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {
      {
        key = 'song',
        kind = 'search_group',
        query = query,
        search_kind = 'song',
        count = #(result.song or {}),
        display = format_search_kind_display('song', #(result.song or {})),
      },
      {
        key = 'album',
        kind = 'search_group',
        query = query,
        search_kind = 'album',
        count = #(result.album or {}),
        display = format_search_kind_display('album', #(result.album or {})),
      },
      {
        key = 'artist',
        kind = 'search_group',
        query = query,
        search_kind = 'artist',
        count = #(result.artist or {}),
        display = format_search_kind_display('artist', #(result.artist or {})),
      },
    }

    attach_search_group_meta(entries)
    cb(entries)
  end)
end

local function list_search_items(path, query, search_kind, cb)
  api.search(query, function(result, err)
    if err then
      cb(nil, err)
      return
    end

    local items = result[search_kind] or {}
    local entries = {}
    if search_kind == 'artist' then
      for _, item in ipairs(items) do
        table.insert(entries, {
          key = item.id,
          kind = 'artist',
          artist = item,
          source = 'search',
          query = query,
          display = shared.format_artist_display(item),
        })
      end
      attach_search_artist_meta(entries)
    elseif search_kind == 'album' then
      for _, item in ipairs(items) do
        table.insert(entries, {
          key = item.id,
          kind = 'album',
          album = item,
          source = 'search',
          query = query,
          display = shared.format_album_display(item),
        })
      end
      attach_search_album_meta(entries)
    else
      for _, item in ipairs(items) do
        table.insert(entries, {
          key = item.id,
          kind = 'song',
          song = item,
          source = 'search',
          query = query,
          display = shared.format_song_display(item),
        })
      end
      attach_search_song_meta(entries)
    end

    if #entries == 0 then
      local keymap = cfg.get().keymap
      entries = {
        {
          key = 'empty',
          kind = 'info',
          keymap = {
            [keymap.toggle_star] = { callback = actions.open_search_input, desc = 'search again' },
          },
          preview = search_groups_preview,
          query = query,
          search_kind = search_kind,
          display = lc.style.line { shared.dim('No ' .. search_kind:gsub('^%l', string.upper) .. ' matched this query') },
        },
      }
    end

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
        source = 'search',
        display = shared.format_song_display(song),
      })
    end

    attach_search_song_meta(entries)
    cb(entries)
  end)
end

local function list_artist_albums(path, artist_id, cb)
  api.list_artist_albums(artist_id, function(artist, albums, err)
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
        parent = artist,
        source = 'search',
        display = shared.format_album_display(album),
      })
    end

    attach_search_album_meta(entries)
    cb(entries)
  end)
end

function M.list(path, cb)
  if #path == 1 then
    list_search_root(path, cb)
    return
  end

  if #path == 2 then
    list_search_groups(path, path[2], cb)
    return
  end

  if #path == 3 then
    list_search_items(path, path[2], path[3], cb)
    return
  end

  if path[3] == 'album' and #path == 4 then
    list_album_songs(path, path[4], cb)
    return
  end

  if path[3] == 'artist' and #path == 4 then
    list_artist_albums(path, path[4], cb)
    return
  end

  if path[3] == 'artist' and #path == 5 then
    list_album_songs(path, path[5], cb)
    return
  end

  cb {}
end

return M
