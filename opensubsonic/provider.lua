local M = {}

local api = require 'opensubsonic.api'

M.name = 'opensubsonic'
M.title = 'OpenSubsonic'

local function normalize_track(song, extra)
  song = song or {}
  local out = {
    type = 'track',
    id = tostring(song.id or ''),
    title = song.title or song.name or tostring(song.id or 'Unknown'),
    artist = song.artist or song.displayArtist or 'Unknown artist',
    album = song.album or '',
    duration = tonumber(song.duration or 0),
    liked = song.starred ~= nil and song.starred ~= '',
    track_no = tonumber(song.track or 0),
    disc_no = tonumber(song.discNumber or 0),
    bitrate = tonumber(song.bitRate or 0),
    content_type = song.contentType or song.suffix,
    source = M.name,
    raw = song,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function normalize_playlist(playlist, extra)
  playlist = playlist or {}
  local out = {
    type = 'playlist',
    id = tostring(playlist.id or ''),
    name = playlist.name or tostring(playlist.id or 'Playlist'),
    owner = playlist.owner,
    track_count = tonumber(playlist.songCount or 0),
    duration = tonumber(playlist.duration or 0),
    description = playlist.comment or playlist.description,
    public = playlist.public,
    created_at = playlist.created,
    updated_at = playlist.changed,
    source = M.name,
    raw = playlist,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function normalize_artist(artist, extra)
  artist = artist or {}
  local out = {
    type = 'artist',
    id = tostring(artist.id or ''),
    name = artist.name or tostring(artist.id or 'Artist'),
    album_count = tonumber(artist.albumCount or 0),
    source = M.name,
    raw = artist,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function normalize_album(album, extra)
  album = album or {}
  local out = {
    type = 'album',
    id = tostring(album.id or ''),
    name = album.name or tostring(album.id or 'Album'),
    artist = album.artist or album.displayArtist,
    year = tonumber(album.year or 0),
    track_count = tonumber(album.songCount or 0),
    duration = tonumber(album.duration or 0),
    genre = album.genre,
    source = M.name,
    raw = album,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function map_items(items, mapper, extra)
  local out = {}
  for _, item in ipairs(items or {}) do
    table.insert(out, mapper(item, extra))
  end
  return out
end

function M.get_play_url(track, cb)
  cb(api.stream_url(track.id))
end

function M.get_playlists(cb)
  api.list_playlists(function(playlists, err)
    if err then return cb(nil, err) end
    cb(map_items(playlists, normalize_playlist))
  end)
end

function M.get_playlist_tracks(playlist_id, cb)
  api.list_playlist_songs(playlist_id, function(playlist, err)
    if err then return cb(nil, err) end
    cb(map_items(playlist.entry or {}, normalize_track, {
      parent = normalize_playlist(playlist),
      list_source = 'playlist',
    }))
  end)
end

function M.get_artists(cb)
  api.list_artists(function(artists, err)
    if err then return cb(nil, err) end
    cb(map_items(artists, normalize_artist))
  end)
end

function M.get_artist_albums(artist_id, cb)
  api.list_artist_albums(artist_id, function(artist, albums, err)
    if err then return cb(nil, err) end
    cb(map_items(albums, normalize_album, {
      parent = normalize_artist(artist),
      list_source = 'artist',
    }))
  end)
end

function M.get_albums(cb)
  api.list_albums(function(albums, err)
    if err then return cb(nil, err) end
    cb(map_items(albums, normalize_album))
  end)
end

function M.get_album_tracks(album_id, cb)
  api.list_album_songs(album_id, function(album, songs, err)
    if err then return cb(nil, err) end
    cb(map_items(songs, normalize_track, {
      parent = normalize_album(album),
      list_source = 'album',
    }))
  end)
end

function M.get_recommend_tracks(cb)
  api.list_random_songs(function(songs, err)
    if err then return cb(nil, err) end
    cb(map_items(songs, normalize_track, {
      list_source = 'random',
      source_title = 'Random',
    }))
  end)
end

function M.get_liked_tracks(cb)
  api.list_starred_songs(function(songs, err)
    if err then return cb(nil, err) end
    cb(map_items(songs, normalize_track, {
      list_source = 'starred',
      source_title = 'Starred',
    }))
  end)
end

function M.search(query, cb)
  api.search(query, function(result, err)
    if err then return cb(nil, err) end
    cb {
      tracks = map_items((result or {}).song, normalize_track, { list_source = 'search', query = query }),
      albums = map_items((result or {}).album, normalize_album, { list_source = 'search', query = query }),
      artists = map_items((result or {}).artist, normalize_artist, { list_source = 'search', query = query }),
      playlists = {},
    }
  end)
end

function M.set_track_liked(track, liked, cb)
  if liked then
    api.star_song(track.id, function(payload, err) cb(payload or true, err) end)
  else
    api.unstar_song(track.id, function(payload, err) cb(payload or true, err) end)
  end
end

function M.add_track_to_playlist(track, playlist_id, cb)
  api.add_song_to_playlist(playlist_id, track.id, function(payload, err) cb(payload or true, err) end)
end

function M.remove_track_from_playlist(track, context, cb)
  local index = context and context.index
  local playlist_id = context and context.playlist_id
  if index == nil then return cb(nil, 'missing playlist item index') end
  if not playlist_id or playlist_id == '' then return cb(nil, 'missing playlist id') end
  api.remove_song_from_playlist(playlist_id, index, function(payload, err) cb(payload or true, err) end)
end

function M.create_playlist(name, cb)
  api.create_playlist(name, function(payload, err) cb(payload or true, err) end)
end

function M.delete_playlist(playlist, cb)
  api.delete_playlist(playlist.id, function(payload, err) cb(payload or true, err) end)
end

return M
