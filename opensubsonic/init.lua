local M = {}
local config = require 'opensubsonic.config'
local api = require 'opensubsonic.api'
local mpv = require 'opensubsonic.mpv'

local state = {
  page_entries = {},
  player_reload_pending = false,
}

local function path_key(path) return table.concat(path or {}, '\1') end
local function join_path(path) return table.concat(path or {}, '/') end

local song_preview
local refresh_current_page_entries
local set_song_starred_local
local create_playlist_from_input
local player_keymap
local song_keymap
local playlist_keymap
local search_keymap

local function remember_entries(path, entries) state.page_entries[path_key(path)] = entries or {} end

local function current_song_entries()
  local path = lc.api.get_current_path()
  local entries = state.page_entries[path_key(path)] or {}
  local out = {}
  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song then table.insert(out, entry.song) end
  end
  return out, entries
end

local function show_error(err)
  lc.notify(lc.style.line {
    lc.style.span('OpenSubsonic: '):fg 'red',
    lc.style.span(tostring(err)):fg 'red',
  })
end

local function show_info(msg)
  lc.notify(lc.style.line {
    lc.style.span('OpenSubsonic: '):fg 'cyan',
    lc.style.span(tostring(msg)):fg 'white',
  })
end

local function dim(s) return lc.style.span(tostring(s or '')):fg 'blue' end
local function accent(s) return lc.style.span(tostring(s or '')):fg 'cyan' end
local function warm(s) return lc.style.span(tostring(s or '')):fg 'yellow' end
local function okc(s) return lc.style.span(tostring(s or '')):fg 'green' end
local function mag(s) return lc.style.span(tostring(s or '')):fg 'magenta' end
local function titlec(s) return lc.style.span(tostring(s or '')):fg 'white' end

local function aligned_line(line) return { line = line, align = true } end

local function kv_line(label, value, label_color)
  local label_span = lc.style.span(tostring(label or ''))
  if label_color == 'accent' then
    label_span = label_span:fg 'cyan'
  elseif label_color == 'warm' then
    label_span = label_span:fg 'yellow'
  elseif label_color == 'mag' then
    label_span = label_span:fg 'magenta'
  else
    label_span = label_span:fg 'blue'
  end

  return aligned_line(lc.style.line {
    label_span,
    dim ': ',
    titlec(value or '-'),
  })
end

local function preview_lines(lines)
  local out, aligned = {}, {}
  for _, line in ipairs(lines or {}) do
    local item = line
    local should_align = false

    if type(line) == 'table' and line.line ~= nil then
      item = line.line
      should_align = line.align == true
    elseif type(line) == 'string' or type(line) == 'number' or type(line) == 'boolean' or line == nil then
      item = lc.style.line { lc.style.span(tostring(line or '')) }
    end

    table.insert(out, item)
    if should_align then table.insert(aligned, item) end
  end
  if #aligned > 0 then lc.style.align_columns(aligned) end
  return lc.style.text(out)
end

local function format_duration(seconds)
  local n = tonumber(seconds)
  if not n or n <= 0 then return '--:--' end
  local h = math.floor(n / 3600)
  local m = math.floor((n % 3600) / 60)
  local s = n % 60
  if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
  return string.format('%d:%02d', m, s)
end

local function format_time(value)
  if not value or value == '' then return '-' end
  local ok, ts = pcall(lc.time.parse, tostring(value))
  if not ok or not ts then return tostring(value) end
  local fmt_ok, formatted = pcall(lc.time.format, ts, 'compact')
  if not fmt_ok or not formatted or formatted == '' then return tostring(value) end
  return formatted
end

local function format_song_display(song)
  local title = song.title or song.name or song.id or 'Unknown'
  local artist = song.artist or song.displayArtist or 'Unknown artist'
  local starred = song.starred ~= nil and song.starred ~= ''
  return lc.style.line {
    starred and warm '★' or dim ' ',
    dim ' ',
    titlec(title),
    dim '  [',
    accent(artist),
    dim ']',
  }
end

local function format_album_display(album)
  local artist = album.artist or album.displayArtist or 'Unknown artist'
  local count = tonumber(album.songCount or 0)
  return lc.style.line {
    warm(album.name or album.id),
    dim '  ·  ',
    mag(artist),
    dim '  ·  ',
    okc(count),
    dim ' tracks',
  }
end

local function format_artist_display(artist)
  return lc.style.line {
    mag(artist.name or artist.id),
    dim '  ·  ',
    okc(tonumber(artist.albumCount or 0)),
    dim ' albums',
  }
end

local function format_playlist_display(playlist)
  return lc.style.line {
    accent(playlist.name or playlist.id),
    dim '  ·  ',
    okc(tonumber(playlist.songCount or 0)),
    dim ' songs  ·  ',
    warm(playlist.owner or 'unknown'),
  }
end

local function format_player_entry(item)
  local meta = item._meta or {}
  local current = item.current or item.playing
  local title = meta.title or item.title or item.filename or ('#' .. tostring(item.id or '?'))
  local artist = meta.artist or ''
  local player = item._player or {}
  local marker = dim '  '
  if current then
    marker = (player.pause == true) and warm '⏸ ' or okc '▶ '
  end
  local starred = meta.starred ~= nil and meta.starred ~= ''

  return lc.style.line {
    marker,
    starred and warm '★' or dim ' ',
    dim ' ',
    titlec(title),
    artist ~= '' and dim '  [' or '',
    artist ~= '' and accent(artist) or '',
    artist ~= '' and dim ']' or '',
  }
end

local function root_entries()
  return {
    {
      key = 'playlist',
      kind = 'section',
      title = 'Playlists',
      display = lc.style.line { accent '󰲹', dim '  ', accent 'Playlist' },
      keymap = {
        n = function()
          lc.api.go_to { 'playlist' }
          lc.defer_fn(create_playlist_from_input, 0)
        end,
      },
    },
    {
      key = 'artist',
      kind = 'section',
      title = 'Artists',
      display = lc.style.line { mag '󰎂', dim '  ', mag 'Artist' },
    },
    {
      key = 'album',
      kind = 'section',
      title = 'Albums',
      display = lc.style.line { warm '󰀥', dim '  ', warm 'Album' },
    },
    {
      key = 'player',
      kind = 'section',
      title = 'Player Queue',
      display = lc.style.line { okc '󰐊', dim '  ', okc 'Player' },
    },
    {
      key = 'random',
      kind = 'section',
      title = 'Random Songs',
      display = lc.style.line { okc '', dim '  ', okc 'Random' },
    },
    {
      key = 'starred',
      kind = 'section',
      title = 'Starred Songs',
      display = lc.style.line { accent '', dim '  ', accent 'Starred' },
    },
    {
      key = 'search',
      kind = 'section',
      title = 'Search',
      display = lc.style.line { titlec '󰍉', dim '  ', titlec 'Search' },
      keymap = search_keymap(),
    },
  }
end

local function open_search_input()
  lc.input {
    prompt = 'Search music',
    placeholder = 'keyword',
    on_submit = function(input)
      local query = tostring(input or ''):trim()
      if query == '' then
        lc.api.go_to { 'search' }
        return
      end
      lc.api.go_to { 'search', query }
    end,
  }
end

local function list_playlists(path, cb)
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
        display = format_playlist_display(playlist),
        keymap = playlist_keymap({
          key = playlist.id,
          kind = 'playlist',
          playlist = playlist,
        }),
      })
    end
    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          display = lc.style.line { dim 'No playlists yet. Press n to create one.' },
          keymap = {
            n = create_playlist_from_input,
          },
        },
      }
    end
    remember_entries(path, entries)
    cb(entries)
  end)
end

local function list_playlist_songs(path, playlist_id, cb)
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
        display = format_song_display(song),
        keymap = song_keymap({
          key = song.id,
          kind = 'song',
          song = song,
          parent = playlist,
          source = 'playlist',
        }),
      })
    end
    remember_entries(path, entries)
    cb(entries)
  end)
end

local function list_artists(path, cb)
  api.list_artists(function(artists, err)
    if err then
      cb(nil, err)
      return
    end
    local entries = {}
    for _, artist in ipairs(artists) do
      table.insert(entries, {
        key = artist.id,
        kind = 'artist',
        artist = artist,
        display = format_artist_display(artist),
      })
    end
    remember_entries(path, entries)
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
        display = format_album_display(album),
      })
    end
    remember_entries(path, entries)
    cb(entries)
  end)
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
        display = format_album_display(album),
      })
    end
    remember_entries(path, entries)
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
        display = format_song_display(song),
        keymap = song_keymap({
          key = song.id,
          kind = 'song',
          song = song,
          parent = album,
          source = 'album',
        }),
      })
    end
    remember_entries(path, entries)
    cb(entries)
  end)
end

local function list_player_queue(path, cb)
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
        display = format_player_entry(item),
        keymap = player_keymap({
          key = tostring(index - 1),
          kind = 'player_song',
          player = player,
          player_item = item,
          playlist_index = index - 1,
        }),
      })
    end

    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          player = player,
          display = lc.style.line {
            dim(player.running and 'mpv queue is empty' or 'mpv is not running'),
          },
          keymap = player_keymap(),
        },
      }
    end

    remember_entries(path, entries)
    cb(entries)
  end)
end

local function list_random_songs(path, cb)
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
        display = format_song_display(song),
        keymap = song_keymap({
          key = song.id,
          kind = 'song',
          song = song,
          source = 'random',
        }),
      })
    end

    remember_entries(path, entries)
    cb(entries)
  end)
end

local function list_starred_songs(path, cb)
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
        display = format_song_display(song),
        keymap = song_keymap({
          key = song.id,
          kind = 'song',
          song = song,
          source = 'starred',
        }),
      })
    end

    remember_entries(path, entries)
    cb(entries)
  end)
end

local function list_search_root(path, cb)
  local entries = {
    {
      key = 'prompt',
      kind = 'info',
      display = lc.style.line {
        titlec 'Press s to search music',
        dim '  ·  uses search3',
      },
      keymap = search_keymap(),
    },
  }
  remember_entries(path, entries)
  cb(entries)
end

local function format_search_kind_display(kind, count)
  local color = kind == 'artist' and mag or (kind == 'album' and warm or accent)
  return lc.style.line {
    color(kind),
    dim '  ·  ',
    okc(count),
    dim(kind == 'song' and ' songs' or (' ' .. kind .. (count == 1 and '' or 's'))),
  }
end

local function list_search_groups(path, query, cb)
  api.search(query, function(result, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {
      {
        key = 'artist',
        kind = 'search_group',
        query = query,
        search_kind = 'artist',
        count = #(result.artist or {}),
        display = format_search_kind_display('artist', #(result.artist or {})),
        keymap = search_keymap(),
      },
      {
        key = 'album',
        kind = 'search_group',
        query = query,
        search_kind = 'album',
        count = #(result.album or {}),
        display = format_search_kind_display('album', #(result.album or {})),
        keymap = search_keymap(),
      },
      {
        key = 'song',
        kind = 'search_group',
        query = query,
        search_kind = 'song',
        count = #(result.song or {}),
        display = format_search_kind_display('song', #(result.song or {})),
        keymap = search_keymap(),
      },
    }

    remember_entries(path, entries)
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
    for _, item in ipairs(items) do
      if search_kind == 'artist' then
        table.insert(entries, {
          key = item.id,
          kind = 'artist',
          artist = item,
          source = 'search',
          query = query,
          display = format_artist_display(item),
          keymap = search_keymap(),
        })
      elseif search_kind == 'album' then
        table.insert(entries, {
          key = item.id,
          kind = 'album',
          album = item,
          source = 'search',
          query = query,
          display = format_album_display(item),
          keymap = search_keymap(),
        })
      else
        table.insert(entries, {
          key = item.id,
          kind = 'song',
          song = item,
          source = 'search',
          query = query,
          display = format_song_display(item),
          keymap = song_keymap({
            key = item.id,
            kind = 'song',
            song = item,
            source = 'search',
            query = query,
          }),
        })
      end
    end

    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          query = query,
          search_kind = search_kind,
          display = lc.style.line { dim('No ' .. search_kind .. ' matched this query') },
          keymap = search_keymap(),
        },
      }
    end

    remember_entries(path, entries)
    cb(entries)
  end)
end

local function reload_if_player_visible()
  local path = lc.api.get_current_path()
  if path[1] == 'player' then lc.cmd 'reload' end
end

local function play_song_entry(target)
  if not target or target.kind ~= 'song' or not target.song then
    lc.cmd 'enter'
    return
  end

  local _, entries = current_song_entries()
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
    if entry and entry.kind == 'song' and entry.song then table.insert(queue, entry.song) end
  end

  for _, song in ipairs(queue) do
    mpv.remember_song(song, api.stream_url)
  end

  mpv.play_tracks(queue, api.stream_url, function(_, err)
    if err then
      show_error(err)
      return
    end
    show_info 'Sent tracks to mpv queue'
    reload_if_player_visible()
  end)
end

local function append_song_entry(target)
  if not target or target.kind ~= 'song' or not target.song then return end
  mpv.remember_song(target.song, api.stream_url)
  mpv.append_tracks({ target.song }, api.stream_url, function(_, err)
    if err then
      show_error(err)
      return
    end
    show_info 'Song appended to mpv queue'
    reload_if_player_visible()
  end)
end

local function append_playlist_entry(target)
  if not target or target.kind ~= 'playlist' or not target.playlist or not target.playlist.id then return end
  api.list_playlist_songs(target.playlist.id, function(playlist, err)
    if err then
      show_error(err)
      return
    end

    local tracks = playlist.entry or {}
    for _, song in ipairs(tracks) do
      mpv.remember_song(song, api.stream_url)
    end

    mpv.append_tracks(tracks, api.stream_url, function(_, append_err)
      if append_err then
        show_error(append_err)
        return
      end
      show_info 'Playlist appended to mpv queue'
      reload_if_player_visible()
    end)
  end)
end

local function toggle_song_star_entry(target)
  if not target then return false end

  local song = nil
  if target.kind == 'song' and target.song then
    song = target.song
  elseif target.kind == 'player_song' then
    local item = target.player_item or {}
    local meta = item._meta or {}
    local song_id = meta.id or item.id
    if song_id then
      song = {
        id = song_id,
        starred = meta.starred,
      }
    end
  end

  if not song or not song.id then return false end
  local was_starred = song.starred and song.starred ~= ''

  set_song_starred_local(song.id, not was_starred)

  if was_starred then
    api.unstar_song(song.id, function(_, err)
      if err then
        set_song_starred_local(song.id, true)
        show_error(err)
        return
      end
    end)
    return true
  end

  api.star_song(song.id, function(_, err)
    if err then
      set_song_starred_local(song.id, false)
      show_error(err)
      return
    end
  end)
  return true
end

local function add_song_entry_to_playlist(target)
  if not target or target.kind ~= 'song' or not target.song then return false end

  api.list_playlists(function(playlists, err)
    if err then
      show_error(err)
      return
    end

    local options = {}
    for _, playlist in ipairs(playlists or {}) do
      table.insert(options, {
        value = playlist.id,
        display = format_playlist_display(playlist),
      })
    end

    if #options == 0 then
      show_info 'No playlists available'
      return
    end

    lc.select({
      prompt = 'Add song to playlist',
      options = options,
    }, function(choice)
      if not choice then return end

      api.add_song_to_playlist(choice, target.song.id, function(_, add_err)
        if add_err then
          show_error(add_err)
          return
        end
        show_info 'Song added to playlist'
      end)
    end)
  end)

  return true
end

local function remove_song_entry_from_playlist(target)
  local path = lc.api.get_current_path()
  if path[1] ~= 'playlist' or #path ~= 2 or not target or target.kind ~= 'song' then return false end

  local entries = state.page_entries[path_key(path)] or {}
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
    show_error 'failed to locate playlist item index'
    return true
  end

  api.remove_song_from_playlist(path[2], playlist_index, function(_, err)
    if err then
      show_error(err)
      return
    end
    show_info 'Song removed from playlist'
    lc.cmd 'reload'
  end)

  return true
end

local function delete_playlist_entry(target)
  if not target or target.kind ~= 'playlist' or not target.playlist then return false end

  local playlist = target.playlist or {}
  lc.confirm {
    title = 'Delete Playlist',
    prompt = 'Delete playlist "' .. tostring(playlist.name or playlist.id or '?') .. '"?',
    on_confirm = function()
      api.delete_playlist(playlist.id, function(_, err)
        if err then
          show_error(err)
          return
        end
        show_info 'Playlist deleted'
        lc.cmd 'reload'
      end)
    end,
  }

  return true
end

create_playlist_from_input = function()
  local path = lc.api.get_current_path()
  if path[1] ~= 'playlist' or #path ~= 1 then return false end

  lc.input {
    prompt = 'New playlist',
    placeholder = 'playlist name',
    on_submit = function(input)
      local name = tostring(input or ''):trim()
      if name == '' then return end

      api.create_playlist(name, function(_, err)
        if err then
          show_error(err)
          return
        end
        show_info 'Playlist created'
        lc.cmd 'reload'
      end)
    end,
  }

  return true
end

local function player_jump_to_entry(target)
  if not target or target.kind ~= 'player_song' then
    lc.cmd 'enter'
    return
  end

  mpv.player_jump(target.playlist_index, function(_, err)
    if err then
      show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

local function player_next()
  mpv.player_next(function(_, err)
    if err then
      show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

local function player_prev()
  mpv.player_prev(function(_, err)
    if err then
      show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

local function player_toggle_pause()
  mpv.player_toggle_pause(function(_, err)
    if err then
      show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

local function player_play()
  mpv.player_play(function(_, err)
    if err then
      show_error(err)
      return
    end
    lc.cmd 'reload'
  end)
end

local function adjust_player_volume(delta)
  mpv.player_adjust_volume(delta, function(volume, err)
    if err then
      show_error(err)
      return
    end
    if type(volume) == 'number' then
      show_info(string.format('Volume %.0f%%', volume))
    else
      show_info 'Volume updated'
    end
    lc.cmd 'reload'
  end)
end

player_keymap = function(target)
  local keymap = {
    n = player_next,
    p = player_prev,
    ['<space>'] = player_toggle_pause,
    P = player_play,
    ['+'] = function() adjust_player_volume(5) end,
    ['-'] = function() adjust_player_volume(-5) end,
  }
  if target and target.kind == 'player_song' then
    keymap['<enter>'] = function() player_jump_to_entry(target) end
    keymap.s = function() toggle_song_star_entry(target) end
  end
  return keymap
end

song_keymap = function(target)
  local keymap = {
    ['<enter>'] = function() play_song_entry(target) end,
    a = function() append_song_entry(target) end,
    s = function() toggle_song_star_entry(target) end,
    A = function() add_song_entry_to_playlist(target) end,
  }
  if target and target.source == 'playlist' then
    keymap.dd = function() remove_song_entry_from_playlist(target) end
  end
  return keymap
end

playlist_keymap = function(target)
  return {
    A = function() append_playlist_entry(target) end,
    dd = function() delete_playlist_entry(target) end,
    n = create_playlist_from_input,
  }
end

search_keymap = function()
  return {
    s = open_search_input,
  }
end

local function queue_section_preview(entry)
  local lines = {
    lc.style.line { titlec(entry.title or entry.key) },
    '',
  }

  if entry.key == 'playlist' then
    table.insert(
      lines,
      lc.style.line {
        accent 'Enter to browse songs. Press n to create a playlist. Press A on a playlist to append all songs to mpv.',
      }
    )
  elseif entry.key == 'artist' then
    table.insert(
      lines,
      lc.style.line { mag 'Artists -> albums -> songs. Enter on a song replaces mpv queue from current song.' }
    )
  elseif entry.key == 'album' then
    table.insert(lines, lc.style.line { warm 'Album list source comes from getAlbumList2().' })
  elseif entry.key == 'player' then
    table.insert(lines, lc.style.line { okc 'Open the current mpv queue and playback state.' })
  elseif entry.key == 'random' then
    table.insert(lines, lc.style.line { okc 'Open a random song list from getRandomSongs().' })
  elseif entry.key == 'starred' then
    table.insert(lines, lc.style.line { accent 'Open the starred song list from getStarred2().' })
  elseif entry.key == 'search' then
    table.insert(
      lines,
      lc.style.line { titlec 'Enter the search page, then press s to search artists, albums and songs.' }
    )
  end

  table.insert(lines, '')
  table.insert(
    lines,
    lc.style.line {
      okc 'Keys: ',
      titlec 'Enter',
      dim ' play/enter, ',
      titlec 'a',
      dim ' append song, ',
      titlec 'A',
      dim ' append playlist, ',
      titlec 's',
      dim ' search songs',
    }
  )
  return preview_lines(lines)
end

local function search_root_preview()
  return preview_lines {
    lc.style.line { titlec 'Search music' },
    '',
    lc.style.line { dim 'Press s to open an input dialog, then submit a keyword.' },
    lc.style.line { dim 'Results are loaded from search3 and grouped into artist, album and song.' },
  }
end

local function random_preview()
  return preview_lines {
    lc.style.line { okc 'Random songs' },
    '',
    lc.style.line { dim 'Enter to browse a random song list loaded from getRandomSongs.' },
    lc.style.line { dim 'Press R to invalidate cache elsewhere; press Ctrl-r/reload here for a new random list.' },
  }
end

local function starred_preview()
  return preview_lines {
    lc.style.line { accent 'Starred songs' },
    '',
    lc.style.line { dim 'Enter to browse your starred song list loaded from getStarred2.' },
    lc.style.line { dim 'The list is cached until you press R.' },
  }
end

local function search_groups_preview(entry)
  local query = entry.query or lc.api.get_current_path()[2] or ''
  return preview_lines {
    lc.style.line { titlec 'Search results' },
    '',
    kv_line('Query', query, 'accent'),
    kv_line('Groups', 'artist / album / song', 'warm'),
    '',
    lc.style.line { dim 'Press Enter to open one group. Press s to search again.' },
  }
end

local function search_group_preview(entry)
  local query = entry.query or lc.api.get_current_path()[2] or ''
  local kind = entry.search_kind or lc.api.get_current_path()[3] or 'song'
  return preview_lines {
    lc.style.line { titlec 'Search group' },
    '',
    kv_line('Query', query, 'accent'),
    kv_line('Type', kind, kind == 'artist' and 'mag' or (kind == 'album' and 'warm' or 'accent')),
    kv_line('Count', tostring(entry.count or 0), 'accent'),
    '',
    lc.style.line { dim 'Enter to open this list. In song results, Enter plays from the current song.' },
  }
end

local function playlist_preview(entry)
  local playlist = entry.playlist or {}
  return preview_lines {
    lc.style.line { accent(playlist.name or 'Playlist') },
    '',
    kv_line('Owner', playlist.owner or '-', 'warm'),
    kv_line('Songs', tostring(playlist.songCount or 0), 'accent'),
    kv_line('Duration', format_duration(playlist.duration), 'accent'),
    kv_line('Created', format_time(playlist.created)),
    kv_line('Changed', format_time(playlist.changed)),
    kv_line('Public', tostring(playlist.public == true), 'mag'),
    '',
    lc.style.line { dim 'Press n to create a playlist. Press A to append one to mpv. Press dd to delete a playlist.' },
  }
end

local function artist_preview(entry)
  local artist = entry.artist or {}
  return preview_lines {
    lc.style.line { mag(artist.name or 'Artist') },
    '',
    kv_line('Albums', tostring(artist.albumCount or 0), 'accent'),
    kv_line('MusicBrainz', tostring(artist.musicBrainzId or '-')),
    kv_line('Roles', table.concat(artist.roles or {}, ', ')),
  }
end

local function album_preview(entry)
  local album = entry.album or {}
  return preview_lines {
    lc.style.line { warm(album.name or 'Album') },
    '',
    kv_line('Artist', tostring(album.artist or album.displayArtist or '-'), 'accent'),
    kv_line('Year', tostring(album.year or '-'), 'warm'),
    kv_line('Tracks', tostring(album.songCount or 0), 'accent'),
    kv_line('Duration', format_duration(album.duration), 'accent'),
    kv_line('Genre', tostring(album.genre or '-'), 'mag'),
    kv_line('Created', format_time(album.created)),
  }
end

song_preview = function(entry)
  local song = entry.song or {}
  return preview_lines {
    lc.style.line { titlec(song.title or 'Song') },
    '',
    kv_line('Artist', tostring(song.artist or song.displayArtist or '-'), 'accent'),
    kv_line('Album', tostring(song.album or '-'), 'warm'),
    kv_line('Track', tostring(song.track or '-'), 'accent'),
    kv_line('Disc', tostring(song.discNumber or '-'), 'accent'),
    kv_line('Duration', format_duration(song.duration), 'accent'),
    kv_line('Bitrate', tostring(song.bitRate or '-') .. ' kbps', 'mag'),
    kv_line('Type', tostring(song.contentType or song.suffix or '-')),
    kv_line('Starred', tostring(song.starred ~= nil and song.starred ~= ''), 'accent'),
    '',
    lc.style.line { okc 'Enter = replace mpv queue, a = append, s = toggle star, A = add to playlist.' },
    entry.source == 'playlist' and lc.style.line { dim 'dd = remove this song from the playlist.' } or '',
  }
end

refresh_current_page_entries = function()
  local path = lc.api.get_current_path()
  local entries = state.page_entries[path_key(path)] or {}
  lc.api.page_set_entries(entries)
  local hovered = lc.api.page_get_hovered()
  if hovered and hovered.kind == 'song' then lc.api.page_set_preview(song_preview(hovered)) end
end

set_song_starred_local = function(song_id, starred)
  local path = lc.api.get_current_path()
  local entries = state.page_entries[path_key(path)] or {}
  mpv.set_song_starred(song_id, starred)
  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song and tostring(entry.song.id) == tostring(song_id) then
      entry.song.starred = starred and lc.time.format(lc.time.now()) or nil
      entry.display = format_song_display(entry.song)
    elseif entry.kind == 'player_song' then
      local item = entry.player_item or {}
      local meta = item._meta or {}
      local item_id = meta.id or item.id
      if tostring(item_id) == tostring(song_id) then
        meta.starred = starred and lc.time.format(lc.time.now()) or nil
        item._meta = meta
        entry.player_item = item
        entry.display = format_player_entry(item)
      end
    end
  end
  remember_entries(path, entries)
  refresh_current_page_entries()
end

local function player_preview(entry)
  local item = entry.player_item or {}
  local meta = item._meta or {}
  local player = entry.player or {}

  return preview_lines {
    lc.style.line { okc 'mpv queue' },
    '',
    kv_line('State', player.pause and 'paused' or 'playing', player.pause and 'mag' or 'accent'),
    kv_line('Current', tostring(item.current == true or item.playing == true), 'accent'),
    kv_line('Title', meta.title or item.title or item.filename or '-'),
    kv_line('Artist', meta.artist or '-'),
    kv_line('Album', meta.album or '-'),
    kv_line('Starred', tostring(meta.starred ~= nil and meta.starred ~= ''), 'accent'),
    kv_line('Duration', format_duration(meta.duration)),
    '',
    lc.style.line { dim 'space = pause/play, n = next, p = previous, + = volume up, - = volume down, Enter = jump to selected' },
  }
end

local function schedule_player_reload()
  if state.player_reload_pending then return end
  state.player_reload_pending = true
  lc.defer_fn(function()
    state.player_reload_pending = false
    if lc.api.get_current_path()[1] == 'player' then lc.cmd 'reload' end
  end, 50)
end

function M.setup(opt)
  config.setup(opt)

  mpv.on_player_event(function(event)
    if not event then return end

    if event.event == 'shutdown' then
      schedule_player_reload()
      return
    end

    if event.event ~= 'property-change' then return end
    local name = tostring(event.name or '')
    if name == 'pause' or name == 'playlist' or name == 'playlist-pos' or name == 'idle-active' or name == 'volume' then
      schedule_player_reload()
    end
  end)

  lc.api.append_hook_pre_quit(function()
    local ok, err = mpv.quit_sync()
    if not ok and err then lc.log('warn', 'failed to quit mpv: {}', err) end
  end)

  lc.keymap.set('main', 'R', function()
    api.invalidate_cache()
    lc.notify 'OpenSubsonic cache invalidated'
    lc.cmd 'reload'
  end)
end

function M.list(path, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    cb {
      {
        key = 'configure',
        kind = 'info',
        display = lc.style.line { lc.style.span('Configure OpenSubsonic via setup() or env vars'):fg 'yellow' },
      },
      {
        key = 'hint',
        kind = 'info',
        display = lc.style.line { lc.style.span(tostring(err)):fg 'yellow' },
      },
    }
    return
  end

  if #path == 0 then
    local entries = root_entries()
    remember_entries(path, entries)
    cb(entries)
    return
  end

  if path[1] == 'playlist' and #path == 1 then
    list_playlists(path, function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'playlist' and #path == 2 then
    list_playlist_songs(path, path[2], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'artist' and #path == 1 then
    list_artists(path, function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'artist' and #path == 2 then
    list_artist_albums(path, path[2], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'artist' and #path == 3 then
    list_album_songs(path, path[3], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'album' and #path == 1 then
    list_albums(path, function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'album' and #path == 2 then
    list_album_songs(path, path[2], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'player' then
    list_player_queue(path, function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'random' and #path == 1 then
    list_random_songs(path, function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'starred' and #path == 1 then
    list_starred_songs(path, function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'search' and #path == 1 then
    list_search_root(path, function(entries) cb(entries) end)
    return
  end

  if path[1] == 'search' and #path == 2 then
    list_search_groups(path, path[2], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'search' and #path == 3 then
    list_search_items(path, path[2], path[3], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'search' and path[3] == 'album' and #path == 4 then
    list_album_songs(path, path[4], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'search' and path[3] == 'artist' and #path == 4 then
    list_artist_albums(path, path[4], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  if path[1] == 'search' and path[3] == 'artist' and #path == 5 then
    list_album_songs(path, path[5], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {}
        return
      end
      cb(entries)
    end)
    return
  end

  cb {}
end

function M.preview(entry, cb)
  if not entry then
    cb ''
    return
  end

  if entry.kind == 'section' then
    cb(queue_section_preview(entry))
    return
  end
  if entry.kind == 'playlist' then
    cb(playlist_preview(entry))
    return
  end
  if entry.kind == 'artist' then
    cb(artist_preview(entry))
    return
  end
  if entry.kind == 'album' then
    cb(album_preview(entry))
    return
  end
  if entry.kind == 'song' then
    cb(song_preview(entry))
    return
  end
  if entry.kind == 'search_group' then
    cb(search_group_preview(entry))
    return
  end
  if entry.kind == 'player_song' or lc.api.get_current_path()[1] == 'player' then
    cb(player_preview(entry))
    return
  end
  if lc.api.get_current_path()[1] == 'search' and #lc.api.get_current_path() == 1 then
    cb(search_root_preview())
    return
  end
  if lc.api.get_current_path()[1] == 'random' then
    cb(random_preview())
    return
  end
  if lc.api.get_current_path()[1] == 'starred' then
    cb(starred_preview())
    return
  end
  if lc.api.get_current_path()[1] == 'search' and #lc.api.get_current_path() == 2 then
    cb(search_groups_preview(entry))
    return
  end

  cb(preview_lines { join_path(lc.api.get_hovered_path() or {}) })
end

return M
