local State = {}

local _counters = {
   search_calls = 0,
   searches_started = 0,
   search_results_found = 0,
   fallback_calls = 0,
   fallback_results_found = 0,
   stage_exhaustions = 0,
   failed_searches = 0,
   search_failures = 0,
   total_candidates_examined = 0,
   max_candidates_examined = 0,
   heavy_searches = 0,
   restock_allowed = 0,
   restock_blocked = 0,
   restock_max_errands_calls = 0,
   restock_current_limit = 0,
   restock_available_workers = 0,
}
local _last_search_summary_at = 0
local _loaded_overrides = {}
local _issue_counts = {}

local function _counter(name)
   _counters[name] = _counters[name] or 0
   return _counters[name]
end

function State.increment(name, amount)
   _counters[name] = _counter(name) + (amount or 1)
end

function State.add(name, amount)
   State.increment(name, amount)
end

function State.set(name, value)
   _counters[name] = value
end

function State.set_max(name, value)
   local current = _counter(name)
   if value > current then
      _counters[name] = value
   end
end

function State.get_snapshot()
   local snapshot = {}
   for name, value in pairs(_counters) do
      snapshot[name] = value
   end
   snapshot.loaded_overrides = State.get_loaded_overrides()
   return snapshot
end

function State.register_override(name)
   if not name or _loaded_overrides[name] then
      return
   end

   _loaded_overrides[name] = true
end

function State.get_loaded_overrides()
   local result = {}

   for name in pairs(_loaded_overrides) do
      result[#result + 1] = name
   end

   table.sort(result)
   return result
end

function State.log_patch_state(settings, patch_points)
   local SmartLocalAiLogger = require 'lib.logger'
   if not settings.log_patch_state then
      return
   end

   local patch_summary = patch_points and table.concat(patch_points, ', ') or 'none'
   local loaded_overrides = table.concat(State.get_loaded_overrides(), ', ')
   SmartLocalAiLogger.info(
      'state profile=%s local=%s expanded=%s fallback=%s max_items=%s restock_mode=%s restock_range=%s-%s patches=%s overrides=%s',
      tostring(settings.search_profile),
      tostring(settings.local_radius),
      tostring(settings.expanded_radius),
      tostring(settings.global_fallback),
      tostring(settings.max_items_to_examine),
      tostring(settings.restock_mode),
      tostring(settings.min_concurrent_restock_errands),
      tostring(settings.max_concurrent_restock_errands),
      patch_summary,
      loaded_overrides ~= '' and loaded_overrides or 'none'
   )
end

function State.note_issue(kind, payload)
   local SmartLocalAiLogger = require 'lib.logger'
   local action = payload and payload.action or 'unknown'
   local description = payload and payload.description or 'unknown'
   local reason = payload and payload.reason or 'unknown'
   local key = table.concat({ tostring(kind), tostring(action), tostring(description), tostring(reason) }, '|')

   _issue_counts[key] = (_issue_counts[key] or 0) + 1
   local count = _issue_counts[key]

   if count == 1 or count % 5 == 0 then
      local issue_payload = {}
      if payload then
         for name, value in pairs(payload) do
            issue_payload[name] = value
         end
      end
      issue_payload.count = count
      SmartLocalAiLogger.issue(issue_payload)
   end
end

function State.maybe_log_search_summary(settings)
   local SmartLocalAiLogger = require 'lib.logger'
   if not settings.log_search_stats then
      return
   end

   local searches_started = _counter('search_calls')
   local interval = tonumber(settings.search_log_interval) or 50
   if searches_started == 0 or searches_started % interval ~= 0 or searches_started == _last_search_summary_at then
      return
   end

   _last_search_summary_at = searches_started
   local avg_candidates = 0
   if searches_started > 0 then
      avg_candidates = math.floor(_counter('total_candidates_examined') / searches_started)
   end
   SmartLocalAiLogger.info(
      'search summary searches=%s found=%s fallback=%s exhausted=%s failed=%s avg_candidates=%s max_candidates=%s',
      tostring(searches_started),
      tostring(_counter('search_results_found')),
      tostring(_counter('fallback_calls')),
      tostring(_counter('stage_exhaustions')),
      tostring(_counter('failed_searches')),
      tostring(avg_candidates),
      tostring(_counter('max_candidates_examined'))
   )
end

return State
