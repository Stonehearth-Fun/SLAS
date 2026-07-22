local Settings = {}

local DEFAULT_SETTINGS = {
   search_profile = 'BALANCED',
   diagnostics_enabled = true,
   diagnostics_player_id = 'player_1',
   diagnostics_log_interval_seconds = 60,
   diagnostics_log_file_name = 'slas_diagnostics.log',
   diagnostics_session_log_file_prefix = 'slas_save_session',
   diagnostics_log_search_flow = true,
   diagnostics_log_heavy_searches = true,
   diagnostics_heavy_search_candidate_threshold = 300,
   diagnostics_log_failed_searches = true,
   diagnostics_log_fallbacks = true,
   local_radius = 32,
   expanded_radius = 64,
   global_fallback = true,
   max_items_to_examine = 140,
   debug_enabled = false,
   log_loaded_overrides = true,
   log_search_stats = false,
   log_patch_state = true,
   search_log_interval = 50,
   enable_for_hauling = true,
   enable_for_fetching = true,
   enable_for_restocking = false,
   restock_mode = 'disabled',
   disable_restock_errands = true,
   enable_restock_throttle = true,
   max_concurrent_restock_errands = 0,
   restock_workers_per_errand = 12,
   min_concurrent_restock_errands = 0,
}

local PROFILE_SETTINGS = {
   SAFE = {
      local_radius = 24,
      expanded_radius = 48,
      max_items_to_examine = 80,
      global_fallback = true,
   },
   BALANCED = {
      local_radius = 32,
      expanded_radius = 64,
      max_items_to_examine = 140,
      global_fallback = true,
   },
   AGGRESSIVE = {
      local_radius = 48,
      expanded_radius = 96,
      max_items_to_examine = 220,
      global_fallback = true,
   },
}

local _cached_settings = nil

local function _get_nested(raw_settings, path, fallback)
   local value = raw_settings

   for _, key in ipairs(path) do
      if type(value) ~= 'table' then
         value = nil
         break
      end

      value = value[key]
      if value == nil then
         break
      end
   end

   if value == nil then
      return fallback
   end

   return value
end

local function _copy_keys(destination, source)
   if not source then
      return
   end

   for key, value in pairs(source) do
      destination[key] = value
   end
end

local function _normalize_restock_mode(settings, raw_settings)
   local restock_mode = settings.restock_mode
   if restock_mode == nil then
      if settings.disable_restock_errands then
         restock_mode = 'disabled'
      elseif settings.enable_restock_throttle == false then
         restock_mode = 'vanilla'
      else
         restock_mode = 'throttle'
      end
   end

   if restock_mode ~= 'disabled' and restock_mode ~= 'throttle' and restock_mode ~= 'vanilla' then
      restock_mode = DEFAULT_SETTINGS.restock_mode
   end

   settings.restock_mode = restock_mode
   settings.disable_restock_errands = restock_mode == 'disabled'
   settings.enable_restock_throttle = restock_mode == 'throttle'
end

local function _normalize_settings(raw_settings)
   raw_settings = raw_settings or {}

   local settings = {}
   _copy_keys(settings, DEFAULT_SETTINGS)

   local profile_name = tostring(raw_settings.search_profile or DEFAULT_SETTINGS.search_profile):upper()
   if not PROFILE_SETTINGS[profile_name] then
      profile_name = DEFAULT_SETTINGS.search_profile
   end

   settings.search_profile = profile_name
   _copy_keys(settings, PROFILE_SETTINGS[profile_name])
   _copy_keys(settings, raw_settings)

   settings.diagnostics_enabled = _get_nested(raw_settings, { 'diagnostics', 'enabled' }, settings.diagnostics_enabled)
   settings.diagnostics_player_id = _get_nested(raw_settings, { 'diagnostics', 'player_id' }, settings.diagnostics_player_id)
   settings.diagnostics_log_interval_seconds = _get_nested(raw_settings, { 'diagnostics', 'log_interval_seconds' }, settings.diagnostics_log_interval_seconds)
   settings.diagnostics_log_file_name = _get_nested(raw_settings, { 'diagnostics', 'log_file_name' }, settings.diagnostics_log_file_name)
   settings.diagnostics_session_log_file_prefix = _get_nested(raw_settings, { 'diagnostics', 'session_log_file_prefix' }, settings.diagnostics_session_log_file_prefix)
   settings.diagnostics_log_search_flow = _get_nested(raw_settings, { 'diagnostics', 'log_search_flow' }, settings.diagnostics_log_search_flow)
   settings.diagnostics_log_heavy_searches = _get_nested(raw_settings, { 'diagnostics', 'log_heavy_searches' }, settings.diagnostics_log_heavy_searches)
   settings.diagnostics_heavy_search_candidate_threshold = _get_nested(raw_settings, { 'diagnostics', 'heavy_search_candidate_threshold' }, settings.diagnostics_heavy_search_candidate_threshold)
   settings.diagnostics_log_failed_searches = _get_nested(raw_settings, { 'diagnostics', 'log_failed_searches' }, settings.diagnostics_log_failed_searches)
   settings.diagnostics_log_fallbacks = _get_nested(raw_settings, { 'diagnostics', 'log_fallbacks' }, settings.diagnostics_log_fallbacks)

   settings.local_radius = _get_nested(raw_settings, { 'local_search', 'local_radius' }, settings.local_radius)
   settings.expanded_radius = _get_nested(raw_settings, { 'local_search', 'expanded_radius' }, settings.expanded_radius)
   settings.global_fallback = _get_nested(raw_settings, { 'local_search', 'global_fallback' }, settings.global_fallback)
   settings.max_items_to_examine = _get_nested(raw_settings, { 'local_search', 'max_items_per_stage' }, settings.max_items_to_examine)
   settings.enable_for_hauling = _get_nested(raw_settings, { 'local_search', 'enable_for_hauling' }, settings.enable_for_hauling)
   settings.enable_for_fetching = _get_nested(raw_settings, { 'local_search', 'enable_for_fetching' }, settings.enable_for_fetching)
   settings.enable_for_restocking = _get_nested(raw_settings, { 'local_search', 'enable_for_restocking' }, settings.enable_for_restocking)

   settings.restock_mode = _get_nested(raw_settings, { 'restock', 'mode' }, settings.restock_mode)
   settings.disable_restock_errands = _get_nested(raw_settings, { 'restock', 'disable_restock_errands' }, settings.disable_restock_errands)
   settings.enable_restock_throttle = _get_nested(raw_settings, { 'restock', 'throttle_enabled' }, settings.enable_restock_throttle)
   settings.max_concurrent_restock_errands = _get_nested(raw_settings, { 'restock', 'max_concurrent_restock_errands' }, settings.max_concurrent_restock_errands)
   settings.restock_workers_per_errand = _get_nested(raw_settings, { 'restock', 'workers_per_errand' }, settings.restock_workers_per_errand)
   settings.min_concurrent_restock_errands = _get_nested(raw_settings, { 'restock', 'min_concurrent_restock_errands' }, settings.min_concurrent_restock_errands)

   settings.debug_enabled = _get_nested(raw_settings, { 'debug', 'enabled' }, settings.debug_enabled)
   settings.log_loaded_overrides = _get_nested(raw_settings, { 'debug', 'log_loaded_overrides' }, settings.log_loaded_overrides)
   settings.log_patch_state = _get_nested(raw_settings, { 'debug', 'log_settings_on_start' }, settings.log_patch_state)

   _normalize_restock_mode(settings, raw_settings)

   settings.local_radius = tonumber(settings.local_radius) or DEFAULT_SETTINGS.local_radius
   settings.expanded_radius = tonumber(settings.expanded_radius) or DEFAULT_SETTINGS.expanded_radius
   settings.max_items_to_examine = tonumber(settings.max_items_to_examine) or DEFAULT_SETTINGS.max_items_to_examine
   settings.diagnostics_log_interval_seconds = tonumber(settings.diagnostics_log_interval_seconds)
      or DEFAULT_SETTINGS.diagnostics_log_interval_seconds
   settings.diagnostics_heavy_search_candidate_threshold = tonumber(settings.diagnostics_heavy_search_candidate_threshold)
      or DEFAULT_SETTINGS.diagnostics_heavy_search_candidate_threshold
   settings.max_concurrent_restock_errands = tonumber(settings.max_concurrent_restock_errands)
      or DEFAULT_SETTINGS.max_concurrent_restock_errands
   settings.restock_workers_per_errand = tonumber(settings.restock_workers_per_errand)
      or DEFAULT_SETTINGS.restock_workers_per_errand
   settings.min_concurrent_restock_errands = tonumber(settings.min_concurrent_restock_errands)
      or DEFAULT_SETTINGS.min_concurrent_restock_errands
   settings.search_log_interval = tonumber(settings.search_log_interval) or DEFAULT_SETTINGS.search_log_interval
   settings.global_fallback = settings.global_fallback ~= false
   settings.diagnostics_enabled = settings.diagnostics_enabled and true or false
   settings.diagnostics_log_search_flow = settings.diagnostics_log_search_flow ~= false
   settings.debug_enabled = settings.debug_enabled and true or false
   settings.log_loaded_overrides = settings.log_loaded_overrides ~= false
   settings.log_search_stats = settings.log_search_stats and true or false
   settings.log_patch_state = settings.log_patch_state ~= false
   settings.diagnostics_log_heavy_searches = settings.diagnostics_log_heavy_searches ~= false
   settings.diagnostics_log_failed_searches = settings.diagnostics_log_failed_searches ~= false
   settings.diagnostics_log_fallbacks = settings.diagnostics_log_fallbacks ~= false
   settings.enable_for_hauling = settings.enable_for_hauling ~= false
   settings.enable_for_fetching = settings.enable_for_fetching ~= false
   settings.enable_for_restocking = settings.enable_for_restocking and true or false

   return settings
end

function Settings.reload()
   local raw_settings = radiant.resources.load_json('smart_local_ai:data:settings', true, false) or {}
   _cached_settings = _normalize_settings(raw_settings)
   return _cached_settings
end

function Settings.get()
   if not _cached_settings then
      return Settings.reload()
   end

   return _cached_settings
end

function Settings.get_profile_settings(profile_name)
   return PROFILE_SETTINGS[profile_name]
end

return Settings
