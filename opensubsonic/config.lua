local M = {}

local cfg = {
  url = os.getenv 'OPENSUBSONIC_URL',
  username = os.getenv 'OPENSUBSONIC_USER',
  password = os.getenv 'OPENSUBSONIC_PASSWORD',
  api_key = os.getenv 'OPENSUBSONIC_API_KEY',
  album_list_type = 'newest',
  album_list_size = 200,
  random_song_count = 100,
  search_artist_count = 20,
  search_album_count = 20,
  search_song_count = 100,
  stream_format = 'raw',
  max_bitrate = nil,
  mpv_socket = '/tmp/lazycmd-opensubsonic-mpv.sock',
  mpv_args = {
    '--idle=yes',
    '--no-video',
    '--force-window=no',
    '--audio-display=no',
    '--really-quiet',
  },
}

local function trim(s)
  if s == nil then return nil end
  return tostring(s):match '^%s*(.-)%s*$'
end

local function normalize(next_cfg)
  local out = lc.tbl_extend({}, next_cfg or {})
  out.url = trim(out.url)
  out.username = trim(out.username)
  out.password = trim(out.password)
  out.api_key = trim(out.api_key)
  out.mpv_socket = trim(out.mpv_socket) or cfg.mpv_socket

  if out.url and out.url ~= '' then
    local base = out.url:gsub('/+$', '')
    out.base_url = base:match('/rest$') and base or (base .. '/rest')
  else
    out.base_url = nil
  end

  return out
end

function M.setup(opt)
  cfg = normalize(lc.tbl_extend(cfg, opt or {}))
end

function M.get()
  return cfg
end

return M
