local SessionLog = {}

local log = radiant.log.create_logger('smart_local_ai_session')
local SmartLocalAiSettings = require 'lib.settings'
local _os = rawget(_G, 'os')
local _io = rawget(_G, 'io')

local _active_handle = nil
local _active_path = nil
local _session_started = false
local _sequence = 0

local _candidate_directories = {
   'smart_local_ai/logs',
   'mods/smart_local_ai/logs',
   '../mods/smart_local_ai/logs',
}

local function _safe_tostring(value)
   if value == nil then
      return 'nil'
   end

   if type(value) == 'boolean' then
      return value and 'true' or 'false'
   end

   return tostring(value)
end

local function _format_payload(payload)
   if type(payload) ~= 'table' then
      return _safe_tostring(payload)
   end

   local keys = {}
   for key in pairs(payload) do
      keys[#keys + 1] = key
   end
   table.sort(keys)

   local parts = {}
   for _, key in ipairs(keys) do
      parts[#parts + 1] = key .. '=' .. _safe_tostring(payload[key])
   end

   return table.concat(parts, ' ')
end

local function _build_stamp()
   if _os and _os.date then
      local ok, stamp = pcall(_os.date, '%Y%m%d_%H%M%S')
      if ok and stamp then
         return stamp
      end
   end

   if radiant and radiant.gamestate and radiant.gamestate.now then
      local ok, now = pcall(radiant.gamestate.now)
      if ok and now then
         return tostring(now)
      end
   end

   _sequence = _sequence + 1
   return string.format('session_%03d', _sequence)
end

local function _close_handle()
   if _active_handle then
      pcall(function()
         _active_handle:flush()
         _active_handle:close()
      end)
   end

   _active_handle = nil
end

local function _open_handle(file_name)
   if not _io or not _io.open then
      return nil, 'io.open unavailable'
   end

   for _, directory in ipairs(_candidate_directories) do
      local path = string.format('%s/%s', directory, file_name)
      local ok, handle = pcall(_io.open, path, 'a')
      if ok and handle then
         return handle, path
      end
   end

   return nil, 'no writable smart_local_ai/logs path found'
end

local function _write_session_line(line)
   if not _active_handle then
      return false
   end

   local ok = pcall(function()
      _active_handle:write(line .. '\n')
      _active_handle:flush()
   end)

   if not ok then
      _close_handle()
      _active_path = nil
   end

   return ok
end

function SessionLog.start_session(reason, payload)
   _close_handle()

   local settings = SmartLocalAiSettings.get()
   local prefix = settings.diagnostics_session_log_file_prefix or 'slas_save_session'
   local file_name = string.format('%s_%s.log', prefix, _build_stamp())
   local handle, path_or_error = _open_handle(file_name)

   _active_handle = handle
   _active_path = handle and path_or_error or nil
   _session_started = true

   if _active_path then
      log:info('[SLAS:SESSION_FILE] %s', _active_path)
   else
      log:warning('[SLAS:SESSION_FILE] fallback to shared log only: %s', tostring(path_or_error))
   end

   SessionLog.write_structured('INFO', 'SESSION_START', payload or {}, reason or 'save session started')
   return _active_path
end

function SessionLog.stop_session(reason, payload)
   if not _session_started then
      return
   end

   SessionLog.write_structured('INFO', 'SESSION_END', payload or {}, reason or 'save session stopped')
   _close_handle()
   _active_path = nil
   _session_started = false
end

function SessionLog.write(level, line)
   if not _session_started then
      return false
   end

   return _write_session_line(string.format('[%s] %s', tostring(level or 'INFO'), tostring(line or '')))
end

function SessionLog.write_structured(level, tag, payload, message)
   local parts = {
      string.format('[SLAS:%s]', tostring(tag or 'EVENT')),
      tostring(message or 'event'),
   }

   local payload_text = _format_payload(payload)
   if payload_text ~= '' then
      parts[#parts + 1] = payload_text
   end

   return SessionLog.write(level, table.concat(parts, ' '))
end

function SessionLog.get_active_path()
   return _active_path
end

return SessionLog
