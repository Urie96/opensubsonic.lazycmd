local M = {}
local config = require 'opensubsonic.config'

local state = {
  cache_prefix = 'opensubsonic:',
  cache_version = 0,
  cache = {},
  config_key = nil,
}

local function urlencode(value)
  return tostring(value):gsub('\n', '\r\n'):gsub('([^%w%-_%.~])', function(char)
    return string.format('%%%02X', string.byte(char))
  end)
end

local function to_hex(s)
  return (tostring(s):gsub('.', function(char)
    return string.format('%02x', string.byte(char))
  end))
end

local function encode_query(params)
  local chunks = {}
  for key, value in pairs(params or {}) do
    if value ~= nil and value ~= '' then
      table.insert(chunks, urlencode(key) .. '=' .. urlencode(value))
    end
  end
  table.sort(chunks)
  return table.concat(chunks, '&')
end

local function normalize_list(value, field)
  if not value then return {} end
  if field and value[field] then return value[field] or {} end
  return value
end

local function current_cfg()
  return config.get()
end

local function config_key(cfg)
  return encode_query({
    url = cfg.base_url or '',
    username = cfg.username or '',
  })
end

local function ensure_cache_state()
  local cfg = current_cfg()
  local next_key = config_key(cfg)
  if state.config_key == next_key then return cfg end

  state.config_key = next_key
  state.cache_prefix = 'opensubsonic:' .. next_key .. ':'
  state.cache_version = 0
  state.cache = {}
  return cfg
end

local function ensure_configured()
  local cfg = ensure_cache_state()
  if not cfg.base_url or cfg.base_url == '' then return nil, 'missing OpenSubsonic url' end
  if cfg.api_key and cfg.api_key ~= '' then return true end
  if cfg.username and cfg.username ~= '' and cfg.password and cfg.password ~= '' then return true end
  return nil, 'missing authentication, set api_key or username/password'
end

local function auth_query()
  local cfg = ensure_cache_state()
  local params = {
    v = '1.16.1',
    c = 'lazycmd-opensubsonic',
    f = 'json',
  }

  if cfg.api_key and cfg.api_key ~= '' then
    params.apiKey = cfg.api_key
    return params
  end

  params.u = cfg.username
  params.p = 'enc:' .. to_hex(cfg.password or '')
  return params
end

local function make_cache_key(name, params)
  return state.cache_prefix .. state.cache_version .. ':' .. name .. ':' .. encode_query(params)
end

local function extract_payload(decoded)
  local envelope = decoded and decoded['subsonic-response']
  if not envelope then return nil, 'invalid OpenSubsonic response' end
  if envelope.status ~= 'ok' then
    local err = envelope.error or {}
    return nil, err.message or ('request failed (' .. tostring(err.code or 'unknown') .. ')')
  end
  return envelope
end

local function request_json(endpoint, params, cb)
  local ok, err = ensure_configured()
  if not ok then
    cb(nil, err)
    return
  end

  local cfg = ensure_cache_state()
  local url = cfg.base_url .. endpoint .. '?' .. encode_query(lc.tbl_extend({}, auth_query(), params or {}))
  lc.http.get(url, function(response)
    if not response.success then
      cb(nil, response.error or ('HTTP ' .. tostring(response.status)))
      return
    end

    local decode_ok, decoded = pcall(lc.json.decode, response.body or '')
    if not decode_ok then
      cb(nil, 'failed to decode OpenSubsonic response')
      return
    end

    local payload, payload_err = extract_payload(decoded)
    if not payload then
      cb(nil, payload_err)
      return
    end
    cb(payload)
  end)
end

local function get_cached_json(name, params, loader, cb)
  local key = make_cache_key(name, params)
  local cached = state.cache[key]
  if cached ~= nil then
    cb(cached)
    return
  end

  loader(function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    state.cache[key] = payload
    cb(payload)
  end)
end

function M.ensure_configured()
  return ensure_configured()
end

function M.invalidate_cache()
  state.cache_version = state.cache_version + 1
  state.cache = {}
end

function M.stream_url(song_id)
  local cfg = ensure_cache_state()
  local params = auth_query()
  params.id = song_id
  if cfg.stream_format and cfg.stream_format ~= '' then params.format = cfg.stream_format end
  if cfg.max_bitrate then params.maxBitRate = cfg.max_bitrate end
  return cfg.base_url .. '/stream?' .. encode_query(params)
end

function M.list_playlists(cb)
  get_cached_json('playlists', {}, function(done)
    request_json('/getPlaylists', {}, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cb(normalize_list(payload.playlists, 'playlist'))
  end)
end

function M.create_playlist(name, cb)
  request_json('/createPlaylist', { name = name }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    state.cache = {}
    state.cache_version = state.cache_version + 1
    cb(payload or true)
  end)
end

function M.delete_playlist(playlist_id, cb)
  request_json('/deletePlaylist', { id = playlist_id }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    state.cache = {}
    state.cache_version = state.cache_version + 1
    cb(payload or true)
  end)
end

function M.list_playlist_songs(playlist_id, cb)
  get_cached_json('playlist', { id = playlist_id }, function(done)
    request_json('/getPlaylist', { id = playlist_id }, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local playlist = payload.playlist or {}
    cb(playlist)
  end)
end

function M.list_artists(cb)
  get_cached_json('artists', {}, function(done)
    request_json('/getArtists', {}, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local artists = {}
    for _, idx in ipairs(normalize_list(payload.artists, 'index')) do
      for _, artist in ipairs(idx.artist or {}) do
        table.insert(artists, artist)
      end
    end
    table.sort(artists, function(a, b)
      return tostring(a.name or ''):lower() < tostring(b.name or ''):lower()
    end)
    cb(artists)
  end)
end

function M.list_artist_albums(artist_id, cb)
  get_cached_json('artist', { id = artist_id }, function(done)
    request_json('/getArtist', { id = artist_id }, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local artist = payload.artist or {}
    local albums = artist.album or {}
    table.sort(albums, function(a, b)
      local ay = tonumber(a.year or 0)
      local by = tonumber(b.year or 0)
      if ay == by then return tostring(a.name or ''):lower() < tostring(b.name or ''):lower() end
      return ay < by
    end)
    cb(artist, albums)
  end)
end

function M.list_albums(cb)
  local cfg = ensure_cache_state()
  local params = {
    type = cfg.album_list_type,
    size = cfg.album_list_size,
  }

  get_cached_json('albums', params, function(done)
    request_json('/getAlbumList2', params, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cb(normalize_list(payload.albumList2, 'album'))
  end)
end

function M.list_random_songs(cb)
  local cfg = ensure_cache_state()
  request_json('/getRandomSongs', { size = cfg.random_song_count or 100 }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    cb(normalize_list(payload.randomSongs, 'song'))
  end)
end

function M.list_starred_songs(cb)
  get_cached_json('starred2', {}, function(done)
    request_json('/getStarred2', {}, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local starred = payload.starred2 or {}
    cb(normalize_list(starred, 'song'))
  end)
end

function M.star_song(song_id, cb)
  request_json('/star', { id = song_id }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    state.cache = {}
    state.cache_version = state.cache_version + 1
    cb(payload or true)
  end)
end

function M.unstar_song(song_id, cb)
  request_json('/unstar', { id = song_id }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    state.cache = {}
    state.cache_version = state.cache_version + 1
    cb(payload or true)
  end)
end

function M.add_song_to_playlist(playlist_id, song_id, cb)
  request_json('/updatePlaylist', {
    playlistId = playlist_id,
    songIdToAdd = song_id,
  }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    state.cache = {}
    state.cache_version = state.cache_version + 1
    cb(payload or true)
  end)
end

function M.remove_song_from_playlist(playlist_id, song_index, cb)
  request_json('/updatePlaylist', {
    playlistId = playlist_id,
    songIndexToRemove = song_index,
  }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    state.cache = {}
    state.cache_version = state.cache_version + 1
    cb(payload or true)
  end)
end

function M.list_album_songs(album_id, cb)
  get_cached_json('album', { id = album_id }, function(done)
    request_json('/getAlbum', { id = album_id }, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local album = payload.album or {}
    local songs = album.song or {}
    table.sort(songs, function(a, b)
      local ad = tonumber(a.discNumber or 0)
      local bd = tonumber(b.discNumber or 0)
      if ad ~= bd then return ad < bd end
      local at = tonumber(a.track or 0)
      local bt = tonumber(b.track or 0)
      if at ~= bt then return at < bt end
      return tostring(a.title or ''):lower() < tostring(b.title or ''):lower()
    end)
    cb(album, songs)
  end)
end

function M.search(query, cb)
  local cfg = ensure_cache_state()
  local params = {
    query = tostring(query or ''),
    artistCount = cfg.search_artist_count or 20,
    albumCount = cfg.search_album_count or 20,
    songCount = cfg.search_song_count or 100,
    artistOffset = 0,
    albumOffset = 0,
    songOffset = 0,
  }

  get_cached_json('search3', params, function(done)
    request_json('/search3', params, done)
  end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local result = payload.searchResult3 or {}
    cb({
      artist = normalize_list(result, 'artist'),
      album = normalize_list(result, 'album'),
      song = normalize_list(result, 'song'),
    })
  end)
end

return M
