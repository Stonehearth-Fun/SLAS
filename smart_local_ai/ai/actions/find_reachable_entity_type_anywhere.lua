local FindReachableEntityTypeAnywhere = radiant.class()
local SmartLocalAiLogger = require 'lib.logger'
local SmartLocalAiSettings = require 'lib.settings'
local SmartLocalAiState = require 'lib.state'

FindReachableEntityTypeAnywhere.name = 'find reachable entity type anywhere'
FindReachableEntityTypeAnywhere.does = 'stonehearth:find_reachable_entity_type_anywhere'
FindReachableEntityTypeAnywhere.args = {
   filter_fn = 'function',
   description = 'string',
   ignore_leases = {
      default = false,
      type = 'boolean',
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   material = 'string',
}

FindReachableEntityTypeAnywhere.version = 2
FindReachableEntityTypeAnywhere.priority = 1

local NO_MATERIAL = stonehearth.constants.construction.NO_MATERIAL
local log = radiant.log.create_logger('smart_local_ai')
SmartLocalAiLogger.override_active('find_reachable_entity_type_anywhere')

local function _build_search_stages(settings)
   if not settings.enable_for_fetching then
      return {
         { kind = 'ground', label = 'ground', max_distance = nil },
         { kind = 'storage', label = 'storage', max_distance = nil },
      }
   end

   local stages = {}
   local local_radius = tonumber(settings.local_radius)
   local expanded_radius = tonumber(settings.expanded_radius)
   local radii = {}

   if local_radius and local_radius > 0 then
      table.insert(radii, { label = 'local', max_distance = local_radius })
   end

   if expanded_radius and expanded_radius > 0 and expanded_radius ~= local_radius then
      table.insert(radii, { label = 'expanded', max_distance = expanded_radius })
   end

   if settings.global_fallback or #radii == 0 then
      table.insert(radii, { label = 'fallback', max_distance = nil })
   end

   for _, stage in ipairs(radii) do
      table.insert(stages, {
         kind = 'ground',
         label = stage.label .. ' ground',
         max_distance = stage.max_distance,
      })
      table.insert(stages, {
         kind = 'storage',
         label = stage.label .. ' storage',
         max_distance = stage.max_distance,
      })
   end

   return stages
end

local function make_storage_filter_fn(args_filter_fn)
   return function(entity)
      local storage = entity:get('stonehearth:storage')
      if not storage then
         return false
      end

      if entity:get('stonehearth:stockpile') then
         return false
      end

      if not storage:is_public() then
         return false
      end

      return storage:storage_contains_filter_fn(args_filter_fn)
   end
end

function FindReachableEntityTypeAnywhere:start_thinking(ai, entity, args)
   self._ai = ai
   self._description = args.description
   self._filter_fn = args.filter_fn
   self._log = log
   self._location = ai.CURRENT.location
   self._settings = SmartLocalAiSettings.get()
   self._stages = _build_search_stages(self._settings)
   self._stage_index = 0
   self._active_search = nil
   self._items_examined = 0
   self._stage_items_examined = 0
   self._max_items_to_examine = tonumber(self._settings.max_items_to_examine) or 0
   SmartLocalAiState.increment('search_calls')
   SmartLocalAiState.increment('searches_started')
   if self._settings.diagnostics_log_search_flow then
      SmartLocalAiLogger.search_flow({
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_reachable_entity_type_anywhere',
         description = self._description,
         event = 'start',
         stage = 'pending',
         result = 'search_started',
      })
   end

   if not self._location or args.material == NO_MATERIAL then
      SmartLocalAiState.note_issue('search', {
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_reachable_entity_type_anywhere',
         description = self._description,
         reason = not self._location and 'no_location' or 'no_material',
         entity = entity,
      })
      ai:set_think_output({})
      return
   end

   local carried_item = ai.CURRENT.carrying
   if carried_item then
      if self._filter_fn(carried_item) then
         ai:set_think_output({})
         return
      else
         local iconic_form = carried_item:get('stonehearth:iconic_form')
         if iconic_form and self._filter_fn(iconic_form:get_root_entity()) then
            ai:set_think_output({})
            return
         end
      end
   end

   local backpack = entity:get('stonehearth:storage')
   if backpack then
      for _, item in pairs(backpack:get_items()) do
         if self._filter_fn(item) then
            ai:set_think_output({})
            return
         else
            local iconic_form = item:get('stonehearth:iconic_form')
            if iconic_form and self._filter_fn(iconic_form:get_root_entity()) then
               ai:set_think_output({})
               return
            end
         end
      end
   end

   self:_start_next_stage(entity, args)
end

function FindReachableEntityTypeAnywhere:_start_next_stage(entity, args)
   self._stage_index = self._stage_index + 1
   local stage = self._stages[self._stage_index]
   if not stage then
      SmartLocalAiState.increment('failed_searches')
      SmartLocalAiState.increment('search_failures')
      if self._settings.diagnostics_log_failed_searches then
         SmartLocalAiLogger.failed_search({
            time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
            action = 'find_reachable_entity_type_anywhere',
            description = self._description,
            stage = self._stages[self._stage_index - 1] and self._stages[self._stage_index - 1].label or 'none',
            candidates = self._stage_items_examined,
            total_candidates = self._items_examined,
            fallback = self._stages[self._stage_index - 1] and string.find(self._stages[self._stage_index - 1].label, 'fallback', 1, true) ~= nil,
            result = 'not_found',
            reason = 'all_stages_exhausted',
         })
      end
      SmartLocalAiState.note_issue('search', {
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_reachable_entity_type_anywhere',
         description = self._description,
         stage = self._stages[self._stage_index - 1] and self._stages[self._stage_index - 1].label or 'none',
         candidates = self._stage_items_examined,
         total_candidates = self._items_examined,
         reason = 'all_stages_exhausted',
         entity = entity,
      })
      self._ai:reject('smart local search exhausted')
      return
   end

   self._stage_items_examined = 0

   if self._settings.debug_enabled then
      self._log:debug('%s starting %s (%s)', tostring(entity), stage.label, tostring(stage.max_distance))
   end
   if self._settings.diagnostics_log_search_flow then
      SmartLocalAiLogger.search_flow({
         time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
         action = 'find_reachable_entity_type_anywhere',
         description = self._description,
         event = 'stage_start',
         stage = stage.label,
         total_candidates = self._items_examined,
         result = 'searching',
      })
   end

   local exhausted_cb = function()
      if self._active_search then
         self._active_search:destroy()
         self._active_search = nil
      end
      if self._settings.diagnostics_log_search_flow then
         SmartLocalAiLogger.search_flow({
            time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
            action = 'find_reachable_entity_type_anywhere',
            description = self._description,
            event = 'stage_end',
            stage = stage.label,
            candidates = self._stage_items_examined,
            total_candidates = self._items_examined,
            result = 'stage_exhausted',
            reason = 'no_match_in_stage',
         })
      end
      if stage.label == 'fallback ground' or stage.label == 'fallback storage' then
         SmartLocalAiState.increment('fallback_calls')
      end
      self:_start_next_stage(entity, args)
   end

   if stage.kind == 'ground' then
      local found_cb = function(item)
         self._items_examined = self._items_examined + 1
         self._stage_items_examined = self._stage_items_examined + 1
         SmartLocalAiState.add('total_candidates_examined', 1)
         SmartLocalAiState.set_max('max_candidates_examined', self._stage_items_examined)

         local item_id = item:get_id()
         if self._ai.CURRENT.self_reserved[item_id] then
            return false
         end

         if not stonehearth.ai:can_acquire_ai_lease(item, entity) then
            return false
         end

         SmartLocalAiState.increment('search_results_found')
         if self._settings.diagnostics_log_search_flow then
            SmartLocalAiLogger.search_flow({
               time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
               action = 'find_reachable_entity_type_anywhere',
               description = self._description,
               event = 'result',
               stage = stage.label,
               candidates = self._stage_items_examined,
               total_candidates = self._items_examined,
               result = 'found',
            })
         end
         if string.find(stage.label, 'fallback', 1, true) then
            SmartLocalAiState.increment('fallback_calls')
            SmartLocalAiState.increment('fallback_results_found')
            if self._settings.diagnostics_log_fallbacks then
               SmartLocalAiLogger.fallback({
                  time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
                  action = 'find_reachable_entity_type_anywhere',
                  description = self._description,
                  stage = stage.label,
                  candidates = self._stage_items_examined,
                  total_candidates = self._items_examined,
                  reason = 'fallback_result',
               })
            end
         end
         if self._settings.diagnostics_log_heavy_searches
               and self._stage_items_examined >= self._settings.diagnostics_heavy_search_candidate_threshold then
            SmartLocalAiState.increment('heavy_searches')
            SmartLocalAiLogger.heavy_search({
               time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
               action = 'find_reachable_entity_type_anywhere',
               description = self._description,
               stage = stage.label,
               candidates = self._stage_items_examined,
               total_candidates = self._items_examined,
               result = 'found',
               reason = 'heavy_search_threshold',
            })
         end
         self._ai:set_think_output({})
         return true
      end

      local options = {
         description = self._description .. ' (' .. stage.label .. ')',
         owner_player_id = args.owner_player_id,
         exhausted_cb = exhausted_cb,
      }
      if stage.max_distance then
         options.max_distance = stage.max_distance
      end

      self._active_search = entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
            self._location,
            args.filter_fn,
            found_cb,
            options)
   else
      local storage_filter_fn = stonehearth.ai:filter_from_key(
            'stonehearth:find_reachable_entity_type_anywhere',
            args.filter_fn,
            make_storage_filter_fn(args.filter_fn))

      local found_cb = function(storage)
         self._items_examined = self._items_examined + 1
         self._stage_items_examined = self._stage_items_examined + 1
         SmartLocalAiState.add('total_candidates_examined', 1)
         SmartLocalAiState.set_max('max_candidates_examined', self._stage_items_examined)

         SmartLocalAiState.increment('search_results_found')
         if self._settings.diagnostics_log_search_flow then
            SmartLocalAiLogger.search_flow({
               time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
               action = 'find_reachable_entity_type_anywhere',
               description = self._description,
               event = 'result',
               stage = stage.label,
               candidates = self._stage_items_examined,
               total_candidates = self._items_examined,
               result = 'found',
            })
         end
         if string.find(stage.label, 'fallback', 1, true) then
            SmartLocalAiState.increment('fallback_calls')
            SmartLocalAiState.increment('fallback_results_found')
            if self._settings.diagnostics_log_fallbacks then
               SmartLocalAiLogger.fallback({
                  time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
                  action = 'find_reachable_entity_type_anywhere',
                  description = self._description,
                  stage = stage.label,
                  candidates = self._stage_items_examined,
                  total_candidates = self._items_examined,
                  reason = 'fallback_result',
               })
            end
         end
         if self._settings.diagnostics_log_heavy_searches
               and self._stage_items_examined >= self._settings.diagnostics_heavy_search_candidate_threshold then
            SmartLocalAiState.increment('heavy_searches')
            SmartLocalAiLogger.heavy_search({
               time = stonehearth.calendar and stonehearth.calendar.get_elapsed_time and stonehearth.calendar:get_elapsed_time() or nil,
               action = 'find_reachable_entity_type_anywhere',
               description = self._description,
               stage = stage.label,
               candidates = self._stage_items_examined,
               total_candidates = self._items_examined,
               result = 'found',
               reason = 'heavy_search_threshold',
            })
         end
         self._ai:set_think_output({})
         return true
      end

      local options = {
         description = self._description .. ' (' .. stage.label .. ')',
         owner_player_id = args.owner_player_id,
         exhausted_cb = exhausted_cb,
      }
      if stage.max_distance then
         options.max_distance = stage.max_distance
      end

      self._active_search = entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
            self._location,
            storage_filter_fn,
            found_cb,
            options)
   end
end

function FindReachableEntityTypeAnywhere:stop_thinking(ai, entity, args)
   self:_destroy_itemfinder()
end

function FindReachableEntityTypeAnywhere:stop(ai, entity, args)
   self:_destroy_itemfinder()
end

function FindReachableEntityTypeAnywhere:_destroy_itemfinder()
   if self._active_search then
      self._active_search:destroy()
      self._active_search = nil
   end
end

return FindReachableEntityTypeAnywhere
