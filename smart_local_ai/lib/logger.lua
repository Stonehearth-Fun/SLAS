local SmartLocalAiSettings = require 'lib.settings'
local SmartLocalAiSessionLog = require 'lib.session_log'

local Logger = {}

local log = radiant.log.create_logger('smart_local_ai')

local function _stringify(value)
   if value == nil then
      return 'nil'
   end

   if type(value) == 'boolean' then
      return value and 'true' or 'false'
   end

   return tostring(value)
end

local function _format_payload(payload, ordered_keys)
   local parts = {}
   local used = {}
   local extra_parts = {}

   if ordered_keys then
      for _, key in ipairs(ordered_keys) do
         if payload[key] ~= nil then
            parts[#parts + 1] = key .. '=' .. _stringify(payload[key])
            used[key] = true
         end
      end
   end

   for key, value in pairs(payload) do
      if not used[key] then
         extra_parts[#extra_parts + 1] = key .. '=' .. _stringify(value)
      end
   end

   table.sort(extra_parts)
   for _, part in ipairs(extra_parts) do
      parts[#parts + 1] = part
   end

   return table.concat(parts, ' ')
end

local function _safe_format(message, ...)
   local ok, formatted = pcall(string.format, message, ...)
   if ok then
      return formatted
   end

   return tostring(message)
end

function Logger.info(message, ...)
   log:info(message, ...)
   SmartLocalAiSessionLog.write('INFO', _safe_format(message, ...))
end

function Logger.warn(message, ...)
   log:warning(message, ...)
   SmartLocalAiSessionLog.write('WARN', _safe_format(message, ...))
end

function Logger.error(message, ...)
   log:error(message, ...)
   SmartLocalAiSessionLog.write('ERROR', _safe_format(message, ...))
end

function Logger.override_active(name)
   local SmartLocalAiState = require 'lib.state'
   SmartLocalAiState.register_override(name)
   local settings = SmartLocalAiSettings.get()
   if settings.log_loaded_overrides then
      log:info('[SLAS] override active: %s', tostring(name))
   end
end

function Logger.summary(payload)
   local formatted = _format_payload(payload, {
      'time',
      'game_day',
      'settlers',
      'items_total',
      'storage_entities',
      'search_calls',
      'fallback_calls',
      'failed_searches',
      'restock_allowed',
      'restock_blocked',
      'restock_current_limit',
      'avg_candidates',
      'max_candidates',
      'profile',
      'overrides',
   })
   log:info('[SLAS:SUMMARY] %s', formatted)
   SmartLocalAiSessionLog.write_structured('INFO', 'SUMMARY', payload, 'summary')
end

function Logger.heavy_search(payload)
   local formatted = _format_payload(payload, {
      'time',
      'action',
      'description',
      'stage',
      'candidates',
      'total_candidates',
      'result',
      'reason',
   })
   log:info('[SLAS:HEAVY_SEARCH] %s', formatted)
   SmartLocalAiSessionLog.write_structured('INFO', 'HEAVY_SEARCH', payload, 'heavy_search')
end

function Logger.failed_search(payload)
   local formatted = _format_payload(payload, {
      'time',
      'action',
      'description',
      'stage',
      'candidates',
      'total_candidates',
      'fallback',
      'result',
      'reason',
   })
   log:warning('[SLAS:FAILED_SEARCH] %s', formatted)
   SmartLocalAiSessionLog.write_structured('WARN', 'FAILED_SEARCH', payload, 'failed_search')
end

function Logger.fallback(payload)
   local formatted = _format_payload(payload, {
      'time',
      'action',
      'description',
      'stage',
      'candidates',
      'total_candidates',
      'reason',
   })
   log:info('[SLAS:FALLBACK] %s', formatted)
   SmartLocalAiSessionLog.write_structured('INFO', 'FALLBACK', payload, 'fallback')
end

function Logger.issue(payload)
   local formatted = _format_payload(payload, {
      'time',
      'action',
      'description',
      'reason',
      'stage',
      'entity',
      'count',
   })
   log:warning('[SLAS:ISSUE] %s', formatted)
   SmartLocalAiSessionLog.write_structured('WARN', 'ISSUE', payload, 'issue')
end

function Logger.search_flow(payload)
   local formatted = _format_payload(payload, {
      'time',
      'action',
      'description',
      'event',
      'stage',
      'candidates',
      'total_candidates',
      'result',
      'reason',
   })
   log:info('[SLAS:SEARCH_FLOW] %s', formatted)
   SmartLocalAiSessionLog.write_structured('INFO', 'SEARCH_FLOW', payload, 'search_flow')
end

return Logger
