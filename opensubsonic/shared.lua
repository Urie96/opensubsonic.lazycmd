local M = {}

M.state = {
  player_reload_pending = false,
}

function M.join_path(path) return table.concat(path or {}, '/') end

function M.current_song_entries()
  local entries = lc.api.get_entries() or {}
  local songs = {}
  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song then table.insert(songs, entry.song) end
  end
  return songs, entries
end

function M.show_error(err)
  lc.notify(lc.style.line {
    lc.style.span('OpenSubsonic: '):fg 'red',
    lc.style.span(tostring(err)):fg 'red',
  })
end

function M.show_info(msg)
  lc.notify(lc.style.line {
    lc.style.span('OpenSubsonic: '):fg 'cyan',
    lc.style.span(tostring(msg)):fg 'white',
  })
end

function M.dim(s) return lc.style.span(tostring(s or '')):fg 'blue' end
function M.accent(s) return lc.style.span(tostring(s or '')):fg 'cyan' end
function M.warm(s) return lc.style.span(tostring(s or '')):fg 'yellow' end
function M.okc(s) return lc.style.span(tostring(s or '')):fg 'green' end
function M.mag(s) return lc.style.span(tostring(s or '')):fg 'magenta' end
function M.titlec(s) return lc.style.span(tostring(s or '')):fg 'white' end
function M.liked_icon() return lc.style.span(' '):fg 'red' end

local function aligned_line(line) return { line = line, align = true } end

function M.kv_line(label, value, label_color)
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
    M.dim ': ',
    M.titlec(value or '-'),
  })
end

function M.preview_lines(lines)
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

function M.format_duration(seconds)
  local n = tonumber(seconds)
  if not n or n <= 0 then return '--:--' end
  local h = math.floor(n / 3600)
  local m = math.floor((n % 3600) / 60)
  local s = n % 60
  if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
  return string.format('%d:%02d', m, s)
end

function M.format_time(value)
  if not value or value == '' then return '-' end
  local ok, ts = pcall(lc.time.parse, tostring(value))
  if not ok or not ts then return tostring(value) end
  local fmt_ok, formatted = pcall(lc.time.format, ts, 'compact')
  if not fmt_ok or not formatted or formatted == '' then return tostring(value) end
  return formatted
end

function M.format_song_display(song)
  local title = song.title or song.name or song.id or 'Unknown'
  local artist = song.artist or song.displayArtist or 'Unknown artist'
  local starred = song.starred ~= nil and song.starred ~= ''
  return lc.style.line {
    starred and M.liked_icon() or M.dim '  ',
    M.titlec(title),
    M.dim '  [',
    M.accent(artist),
    M.dim ']',
  }
end

function M.format_album_display(album)
  local artist = album.artist or album.displayArtist or 'Unknown artist'
  local count = tonumber(album.songCount or 0)
  return lc.style.line {
    M.warm(album.name or album.id),
    M.dim '  ·  ',
    M.mag(artist),
    M.dim '  ·  ',
    M.okc(count),
    M.dim ' tracks',
  }
end

function M.format_artist_display(artist)
  return lc.style.line {
    M.mag(artist.name or artist.id),
    M.dim '  ·  ',
    M.okc(tonumber(artist.albumCount or 0)),
    M.dim ' albums',
  }
end

function M.format_playlist_display(playlist)
  return lc.style.line {
    M.accent(playlist.name or playlist.id),
    M.dim '  ·  ',
    M.okc(tonumber(playlist.songCount or 0)),
    M.dim ' songs  ·  ',
    M.warm(playlist.owner or 'unknown'),
  }
end

function M.format_player_entry(item)
  local meta = item._meta or {}
  local current = item.current or item.playing
  local title = meta.title or item.title or item.filename or ('#' .. tostring(item.id or '?'))
  local artist = meta.artist or ''
  local player = item._player or {}
  local marker = M.dim '  '
  if current then marker = (player.pause == true) and M.warm '⏸ ' or M.okc '▶ ' end
  local starred = meta.starred ~= nil and meta.starred ~= ''

  return lc.style.line {
    marker,
    starred and M.liked_icon() or M.dim '  ',
    M.titlec(title),
    artist ~= '' and M.dim '  [' or '',
    artist ~= '' and M.accent(artist) or '',
    artist ~= '' and M.dim ']' or '',
  }
end

function M.playlist_preview(entry)
  local playlist = entry.playlist or {}
  return M.preview_lines {
    lc.style.line { M.accent(playlist.name or 'Playlist') },
    '',
    M.kv_line('Owner', playlist.owner or '-', 'warm'),
    M.kv_line('Songs', tostring(playlist.songCount or 0), 'accent'),
    M.kv_line('Duration', M.format_duration(playlist.duration), 'accent'),
    M.kv_line('Created', M.format_time(playlist.created)),
    M.kv_line('Changed', M.format_time(playlist.changed)),
    M.kv_line('Public', tostring(playlist.public == true), 'mag'),
  }
end

function M.artist_preview(entry)
  local artist = entry.artist or {}
  return M.preview_lines {
    lc.style.line { M.mag(artist.name or 'Artist') },
    '',
    M.kv_line('Albums', tostring(artist.albumCount or 0), 'accent'),
    M.kv_line('MusicBrainz', tostring(artist.musicBrainzId or '-')),
    M.kv_line('Roles', table.concat(artist.roles or {}, ', ')),
  }
end

function M.album_preview(entry)
  local album = entry.album or {}
  return M.preview_lines {
    lc.style.line { M.warm(album.name or 'Album') },
    '',
    M.kv_line('Artist', tostring(album.artist or album.displayArtist or '-'), 'accent'),
    M.kv_line('Year', tostring(album.year or '-'), 'warm'),
    M.kv_line('Tracks', tostring(album.songCount or 0), 'accent'),
    M.kv_line('Duration', M.format_duration(album.duration), 'accent'),
    M.kv_line('Genre', tostring(album.genre or '-'), 'mag'),
    M.kv_line('Created', M.format_time(album.created)),
  }
end

function M.song_preview(entry)
  local song = entry.song or {}
  return M.preview_lines {
    lc.style.line { M.titlec(song.title or 'Song') },
    '',
    M.kv_line('Artist', tostring(song.artist or song.displayArtist or '-'), 'accent'),
    M.kv_line('Album', tostring(song.album or '-'), 'warm'),
    M.kv_line('Track', tostring(song.track or '-'), 'accent'),
    M.kv_line('Disc', tostring(song.discNumber or '-'), 'accent'),
    M.kv_line('Duration', M.format_duration(song.duration), 'accent'),
    M.kv_line('Bitrate', tostring(song.bitRate or '-') .. ' kbps', 'mag'),
    M.kv_line('Type', tostring(song.contentType or song.suffix or '-')),
    M.kv_line('Starred', tostring(song.starred ~= nil and song.starred ~= ''), 'accent'),
  }
end

function M.refresh_current_page_entries()
  local entries = lc.api.get_entries() or {}
  lc.api.set_entries(nil, entries)
  local hovered = lc.api.get_hovered()
  if hovered and type(hovered.preview) == 'function' then
    local hovered_path = lc.api.get_hovered_path()
    hovered:preview(function(preview) lc.api.set_preview(hovered_path, preview) end)
  end
end

return M
