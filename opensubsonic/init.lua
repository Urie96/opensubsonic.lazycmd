local M = {}

local api = require 'opensubsonic.api'
local config = require 'opensubsonic.config'
local provider = require 'opensubsonic.provider'

local browser = nil

local function config_entries(err)
  return {
    {
      key = 'configure',
      kind = 'info',
      display = deck.style.line { deck.style.span('Configure OpenSubsonic via setup() or env vars'):fg 'yellow' },
    },
    {
      key = 'hint',
      kind = 'info',
      display = deck.style.line { deck.style.span(tostring(err)):fg 'yellow' },
    },
  }
end

local function ensure_browser()
  if browser then return browser end

  local ok, music_or_err = deck.plugin.load 'music'
  if not ok then error('failed to load music plugin: ' .. tostring(music_or_err)) end

  browser = ok.new(provider, {
    root = 'opensubsonic',
  })
  return browser
end

function M.setup(opt)
  config.setup(opt)
  browser = nil
  local _, setup_err = deck.plugin.load 'music'
  if setup_err then deck.log('warn', 'failed to setup music plugin from opensubsonic: {}', tostring(setup_err)) end
end

function M.list(path, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    cb(config_entries(err))
    return
  end

  local get_ok, b_or_err = pcall(ensure_browser)
  if not get_ok then
    cb(config_entries(b_or_err))
    return
  end

  b_or_err:list(path, cb)
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

  local get_ok, b_or_err = pcall(ensure_browser)
  if get_ok then
    b_or_err:preview(entry, cb)
  else
    cb(tostring(b_or_err))
  end
end

return M
