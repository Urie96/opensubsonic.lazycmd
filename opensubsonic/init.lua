local M = {}

local api = require 'opensubsonic.api'
local actions = require 'opensubsonic.actions'
local config = require 'opensubsonic.config'
local metas = require 'opensubsonic.metas'
local root = require 'opensubsonic.root'
local shared = require 'opensubsonic.shared'

local function config_entries(err)
  return metas.attach_all {
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
end

function M.setup(opt)
  config.setup(opt)
  actions.setup()
end

function M.list(path, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    local entries = config_entries(err)
    cb(entries)
    return
  end

  root.list(path, cb)
end

function M.preview(entry, cb)
  if not entry then
    cb ''
    return
  end

  if type(entry.preview) == 'function' then
    entry:preview(cb)
    return
  end

  cb(shared.preview_lines { shared.join_path(lc.api.get_hovered_path() or {}) })
end

return M
