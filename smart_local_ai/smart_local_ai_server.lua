local SmartLocalAiRestockDirectorPatch = require 'monkey_patches.smart_local_ai_restock_director'
local SmartLocalAiDiagnostics = require 'lib.diagnostics'
local SmartLocalAiCitizenAiDump = require 'lib.citizen_ai_dump'
local SmartLocalAiLogger = require 'lib.logger'
local SmartLocalAiSessionLog = require 'lib.session_log'
local SmartLocalAiSettings = require 'lib.settings'
local SmartLocalAiState = require 'lib.state'
local RestockDirector = radiant.mods.require('stonehearth.services.server.inventory.restock_director')
local settings = SmartLocalAiSettings.get()
local _runtime_started = false
local _citizen_ai_dump = SmartLocalAiCitizenAiDump()

SmartLocalAiRestockDirectorPatch._ace_old__get_max_errands = RestockDirector._get_max_errands
radiant.mixin(RestockDirector, SmartLocalAiRestockDirectorPatch)

local function _start_slas_runtime()
   if _runtime_started then
      return
   end

   _runtime_started = true
   SmartLocalAiSessionLog.start_session('save loaded', {
      profile = settings.search_profile,
      diagnostics = settings.diagnostics_enabled,
      restock_mode = settings.restock_mode,
      local_radius = settings.local_radius,
      expanded_radius = settings.expanded_radius,
      max_items_to_examine = settings.max_items_to_examine,
   })
   SmartLocalAiLogger.info(
      '[SLAS] settings loaded profile=%s diagnostics=%s restock_mode=%s local=%s expanded=%s max_items=%s',
      tostring(settings.search_profile),
      tostring(settings.diagnostics_enabled),
      tostring(settings.restock_mode),
      tostring(settings.local_radius),
      tostring(settings.expanded_radius),
      tostring(settings.max_items_to_examine)
   )
   SmartLocalAiState.log_patch_state(settings, {
      'restock_director',
      'pickup_item_type',
      'find_reachable_entity_type_anywhere',
      'find_reachable_storage_containing_best_entity_type',
      'fill_backpack_from_items',
      'drop_and_pickup_item_type',
      'rest_when_injured',
   })
   SmartLocalAiDiagnostics:get():start()
   _citizen_ai_dump:schedule_dump(settings.diagnostics_player_id or 'player_1')
   SmartLocalAiLogger.info('Smart Local AI server patch loaded: restock mode = %s', settings.restock_mode)
end

if radiant and radiant.events and radiant.events.listen_once then
   radiant.events.listen_once(radiant, 'radiant:game_loaded', _start_slas_runtime)
else
   _start_slas_runtime()
end
