local Entity = _radiant.om.Entity
local FindBestLocalReachableEntityByType = radiant.class()
local SmartLocalAiLogger = require 'lib.logger'
local SmartLocalAiSettings = require 'lib.settings'
local SmartLocalAiState = require 'lib.state'

FindBestLocalReachableEntityByType.name = 'find best local reachable entity by type'
FindBestLocalReachableEntityByType.does = 'smart_local_ai:find_best_local_reachable_entity_by_type'
FindBestLocalReachableEntityByType.args = {
   filter_fn = 'function',
   rating_fn = {
      type = 'function',
      default = stonehearth.ai.NIL,
   },
   description = 'string',
   ignore_leases = {
      default = false,
      type = 'boolean'
   },
   max_items_to_examine = {
      default = 200,
      type = 'number'
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
FindBestLocalReachableEntityByType.think_output = {
   item = Entity,
   rating = 'number',
}
FindBestLocalReachableEntityByType.priority = {0, 1}

local log = radiant.log.create_logger('smart_local_ai')
SmartLocalAiLogger.override_active('find_best_local_reachable_entity_by_type')

local function _build_stages(settings)
   if not settings.enable_for_hauling and not settings.enable_for_fetching then
      return {
         { label = 'fallback', max_distance = nil }
      }
   end

   local stages = {}
   local local_radius = tonumber(settings.local_radius)
   local expanded_radius = tonumber(settings.expanded_radius)

   if local_radius and local_radius > 0 then
      table.insert(stages, {
         label = 'local',
         max_distance = local_radius,
      })
   end

   if expanded_radius and expanded_radius > 0 and expanded_radius ~= local_radius then
      table.insert(stages, {
         label = 'expanded',
         max_distance = expanded_radius,
      })
   end

   if settings.global_fallback or #stages == 0 then
      table.insert(stages, {
         label = 'fallback',
         max_distance = nil,
      })
   end

   return stages
end

function FindBestLocalReachableEntityByType:start_thinking(ai, entity, args)
   assert(args.filter_fn)

   self._ai = ai
   self._description = args.description
   self._log = log
   self._ready = false
   self._result = nil
   self._started = false
   self._location = ai.CURRENT.location
   self._items_examined = 0
   self._stage_items_examined = 0
   self._settings = SmartLocalAiSettings.get()
   self._stages = _build_stages(self._settings)
   self._stage_index = 0
   self._if = nil
   self._delay_start_timer = nil
   self._best_item = nil
   self._best_rating = 0
   self._max_items_to_examine = tonumber(self._settings.max_items_to_examine) or args.max_items_to_examine

   if not self._location then
      ai:set_debug_progress('entity has no location')
      SmartLocalAiState.increment('search_failures')
      SmartLocalAiState.note_issue('search', {
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_best_local_reachable_entity_by_type',
         description = self._description,
         reason = 'no_location',
         entity = entity,
      })
      return
   end

   SmartLocalAiState.increment('search_calls')
   SmartLocalAiState.increment('searches_started')
   if self._settings.diagnostics_log_search_flow then
      SmartLocalAiLogger.search_flow({
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_best_local_reachable_entity_by_type',
         description = self._description,
         event = 'start',
         stage = 'pending',
         result = 'search_started',
      })
   end
   SmartLocalAiState.maybe_log_search_summary(self._settings)
   self:_start_next_stage(entity, args)
end

function FindBestLocalReachableEntityByType:_start_next_stage(entity, args)
   self._stage_index = self._stage_index + 1
   local stage = self._stages[self._stage_index]

   if not stage then
      self._ai:set_debug_progress('exhausted with no results')
      local previous_stage = self._stages[self._stage_index - 1]
      if previous_stage and previous_stage.label == 'fallback' then
         SmartLocalAiState.increment('fallback_calls')
      end
      SmartLocalAiState.increment('failed_searches')
      SmartLocalAiState.increment('search_failures')
      if self._settings.diagnostics_log_failed_searches then
         SmartLocalAiLogger.failed_search({
            time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
            action = 'find_best_local_reachable_entity_by_type',
            description = self._description,
            stage = previous_stage and previous_stage.label or 'none',
            candidates = self._stage_items_examined,
            total_candidates = self._items_examined,
            fallback = previous_stage and previous_stage.label == 'fallback',
            result = 'not_found',
            reason = 'all_stages_exhausted',
         })
      end
      SmartLocalAiState.note_issue('search', {
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_best_local_reachable_entity_by_type',
         description = self._description,
         stage = previous_stage and previous_stage.label or 'none',
         candidates = self._stage_items_examined,
         total_candidates = self._items_examined,
         reason = 'all_stages_exhausted',
         entity = entity,
      })
      SmartLocalAiState.maybe_log_search_summary(self._settings)
      return
   end

   self._best_item = nil
   self._best_rating = 0
   self._stage_items_examined = 0

   if self._settings.debug_enabled then
      self._log:debug('%s starting %s search (%s)', tostring(entity), stage.label, tostring(stage.max_distance))
   end
   if self._settings.diagnostics_log_search_flow then
      SmartLocalAiLogger.search_flow({
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_best_local_reachable_entity_by_type',
         description = self._description,
         event = 'stage_start',
         stage = stage.label,
         total_candidates = self._items_examined,
         result = 'searching',
      })
   end

   local exhausted = function()
      self:_destroy_item_finder()

      if self._best_item then
         self:_set_result(self._best_item, self._best_rating, args)
      else
         if self._settings.diagnostics_log_search_flow then
            SmartLocalAiLogger.search_flow({
               time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
               action = 'find_best_local_reachable_entity_by_type',
               description = self._description,
               event = 'stage_end',
               stage = stage.label,
               candidates = self._stage_items_examined,
               total_candidates = self._items_examined,
               result = 'stage_exhausted',
               reason = 'no_match_in_stage',
            })
         end
         self:_start_next_stage(entity, args)
      end
   end

   local consider = function(item)
      if not self._ai.CURRENT or self._ai.CURRENT.self_reserved[item:get_id()] then
         return false
      end

      self._items_examined = self._items_examined + 1
      self._stage_items_examined = self._stage_items_examined + 1
      SmartLocalAiState.add('total_candidates_examined', 1)
      SmartLocalAiState.set_max('max_candidates_examined', self._stage_items_examined)
      if self._stage_items_examined > self._max_items_to_examine then
         SmartLocalAiState.increment('stage_exhaustions')
         if stage.label == 'fallback' then
            SmartLocalAiState.increment('fallback_calls')
         end
         if self._settings.diagnostics_log_heavy_searches
               and self._stage_items_examined >= self._settings.diagnostics_heavy_search_candidate_threshold then
            SmartLocalAiState.increment('heavy_searches')
            SmartLocalAiLogger.heavy_search({
               time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
               action = 'find_best_local_reachable_entity_by_type',
               description = self._description,
               stage = stage.label,
               candidates = self._stage_items_examined,
               total_candidates = self._items_examined,
               result = 'stage_exhausted',
               reason = 'candidate_budget',
            })
         end
         if self._settings.debug_enabled then
            self._log:debug('%s exhausted %s stage after %s candidates (%s total)', tostring(entity), stage.label, self._stage_items_examined, self._items_examined)
         end
         exhausted()
         return true
      end

      local rating = args.rating_fn and math.min(1.0, args.rating_fn(item, entity)) or 1
      if not self._best_item or rating > self._best_rating then
         self._best_item = item
         self._best_rating = rating
         if rating == 1.0 then
            self:_set_result(item, rating, args)
            return true
         end
      end

      return false
   end

   self._delay_start_timer = radiant.on_game_loop_once('SmartLocalAI start local reachable search', function()
         local options = {
            description = string.format('%s (%s)', self._description, stage.label),
            ignore_leases = args.ignore_leases,
            exhausted_cb = exhausted,
            reappraise_cb = consider,
            owner_player_id = args.owner_player_id,
            should_sort = false,
         }

         if stage.max_distance then
            options.max_distance = stage.max_distance
         end

         self._if = entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
               self._location,
               args.filter_fn,
               consider,
               options)
      end)
end

function FindBestLocalReachableEntityByType:start(ai, entity, args)
   if not radiant.entities.exists(self._result) or not args.filter_fn(self._result) then
      ai:abort(string.format('destination %s is no longer valid at start. filter description: %s', tostring(self._result), tostring(self._description)))
   end

   if not radiant.entities.exists_in_world(self._result) then
      ai:abort(string.format('destination %s is no longer in world.', tostring(self._result)))
   end

   self._started = true
end

function FindBestLocalReachableEntityByType:stop_thinking(ai, entity, args)
   if self._delay_start_timer then
      self._delay_start_timer:destroy()
      self._delay_start_timer = nil
   end

   self:_destroy_item_finder()
end

function FindBestLocalReachableEntityByType:_destroy_item_finder()
   if self._if then
      self._if:destroy()
      self._if = nil
   end
end

function FindBestLocalReachableEntityByType:stop(ai, entity, args)
   self:stop_thinking(ai, entity, args)
end

function FindBestLocalReachableEntityByType:_set_result(item, rating, args)
   if self._started then
      return
   end

   self:_destroy_item_finder()
   self._result = item
   self._ready = true
   self._ai:set_think_output({ item = item, rating = rating })
   if args.rating_fn then
      self._ai:set_utility(rating)
   end

   SmartLocalAiState.increment('search_results_found')
   local stage = self._stages[self._stage_index]
   if self._settings.diagnostics_log_search_flow then
      SmartLocalAiLogger.search_flow({
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_best_local_reachable_entity_by_type',
         description = self._description,
         event = 'result',
         stage = stage and stage.label or 'unknown',
         candidates = self._stage_items_examined,
         total_candidates = self._items_examined,
         result = 'found',
      })
   end
   if stage and stage.label == 'fallback' then
      SmartLocalAiState.increment('fallback_calls')
      SmartLocalAiState.increment('fallback_results_found')
      if self._settings.diagnostics_log_fallbacks then
         SmartLocalAiLogger.fallback({
            time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
            action = 'find_best_local_reachable_entity_by_type',
            description = self._description,
            stage = stage.label,
            candidates = self._stage_items_examined,
            total_candidates = self._items_examined,
            reason = 'global_fallback_result',
         })
      end
   end
   if self._settings.diagnostics_log_heavy_searches
         and self._stage_items_examined >= self._settings.diagnostics_heavy_search_candidate_threshold then
      SmartLocalAiState.increment('heavy_searches')
      SmartLocalAiLogger.heavy_search({
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_best_local_reachable_entity_by_type',
         description = self._description,
         stage = stage and stage.label or 'unknown',
         candidates = self._stage_items_examined,
         total_candidates = self._items_examined,
         result = 'found',
         reason = 'heavy_search_threshold',
      })
   end
   SmartLocalAiState.maybe_log_search_summary(self._settings)

   if self._settings.debug_enabled then
      self._log:debug('selected %s rating=%s after %s candidates in %s stage (%s total)', tostring(item), tostring(rating), self._stage_items_examined, tostring(self._stages[self._stage_index] and self._stages[self._stage_index].label), self._items_examined)
   end
end

return FindBestLocalReachableEntityByType
