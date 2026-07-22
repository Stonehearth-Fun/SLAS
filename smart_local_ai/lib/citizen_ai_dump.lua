local CitizenAiDump = class()

local log = radiant.log.create_logger('smart_local_ai_citizen_dump')
local _io = rawget(_G, 'io')
local _os = rawget(_G, 'os')

local DUMP_FOLDER = 'logs'
local DUMP_DELAY_MS = 2000
local MANIFEST_FILE = '_slas_manifest.txt'
local PROBE_FILE = '_slas_probe.txt'
local _candidate_directories = {
   'smart_local_ai/logs',
   './smart_local_ai/logs',
   'mods/smart_local_ai/logs',
   './mods/smart_local_ai/logs',
   '../mods/smart_local_ai/logs',
   '../../mods/smart_local_ai/logs',
   '../../../mods/smart_local_ai/logs',
   '../../../../mods/smart_local_ai/logs',
}

local function _safe_tostring(value)
   if value == nil then
      return 'nil'
   end

   local ok, result = pcall(tostring, value)
   return ok and result or '<unprintable>'
end

local function _sanitize_filename(value)
   local text = _safe_tostring(value)
   text = text:gsub('[\\/:*?"<>|]', '_')
   text = text:gsub('%s+', ' ')
   text = text:gsub('^%s+', '')
   text = text:gsub('%s+$', '')
   if text == '' then
      text = 'unknown'
   end
   return text
end

local function _get_time_now()
   if stonehearth and stonehearth.calendar and stonehearth.calendar.get_elapsed_time then
      return stonehearth.calendar:get_elapsed_time()
   end
end

local function _get_game_day()
   if stonehearth and stonehearth.calendar and stonehearth.calendar.get_elapsed_days then
      return stonehearth.calendar:get_elapsed_days()
   end
end

local function _get_job_name(entity)
   local job = entity:get_component('stonehearth:job')
   if not job then
      return 'no_job'
   end

   local job_data = job:get_job_data()
   if job_data and job_data.display_name then
      return job_data.display_name
   end

   return job:get_job_uri() or 'unknown_job'
end

local function _get_job_level(entity)
   local job = entity:get_component('stonehearth:job')
   if not job or not job.get_current_job_level then
      return nil
   end

   return job:get_current_job_level()
end

local function _get_citizen_name(entity)
   return radiant.entities.get_custom_name(entity) or radiant.entities.get_display_name(entity) or tostring(entity)
end

local function _append_line(lines, text)
   lines[#lines + 1] = text
end

local function _join_path(directory, file_name)
   return string.format('%s/%s', directory, file_name)
end

local function _read_file(path)
   if not _io or not _io.open then
      return nil
   end

   local ok, handle = pcall(_io.open, path, 'r')
   if not ok or not handle then
      return nil
   end

   local read_ok, content = pcall(function()
      local data = handle:read('*a')
      handle:close()
      return data
   end)

   if not read_ok then
      pcall(handle.close, handle)
      return nil
   end

   return content
end

local function _write_file(path, text)
   if not _io or not _io.open then
      return false
   end

   local ok, handle = pcall(_io.open, path, 'w')
   if not ok or not handle then
      return false
   end

   local write_ok = pcall(function()
      handle:write(text or '')
      handle:flush()
      handle:close()
   end)

   if not write_ok then
      pcall(handle.close, handle)
   end

   return write_ok
end

local function _delete_file(path)
   if _os and _os.remove then
      pcall(_os.remove, path)
   end
end

local function _resolve_output_directory()
   for _, directory in ipairs(_candidate_directories) do
      local probe_path = _join_path(directory, PROBE_FILE)
      if _write_file(probe_path, 'slas probe') then
         return directory
      end
   end

   return nil
end

local function _read_manifest(directory)
   local content = _read_file(_join_path(directory, MANIFEST_FILE))
   if not content or content == '' then
      return {}
   end

   local files = {}
   for line in content:gmatch('[^\r\n]+') do
      if line ~= '' then
         files[#files + 1] = line
      end
   end
   return files
end

local function _write_manifest(directory, files)
   _write_file(_join_path(directory, MANIFEST_FILE), table.concat(files, '\n'))
end

local function _format_header(entity)
   return {
      citizen_name = _get_citizen_name(entity),
      citizen_id = entity:get_id(),
      citizen_uri = entity:get_uri(),
      job_name = _get_job_name(entity),
      job_level = _get_job_level(entity),
      game_day = _get_game_day(),
      game_time = _get_time_now(),
      position = radiant.entities.get_world_grid_location(entity),
   }
end

local function _format_node_line(node_data)
   local parts = {}
   parts[#parts + 1] = _safe_tostring(node_data.id or '')
   parts[#parts + 1] = '-'
   parts[#parts + 1] = '<' .. _safe_tostring(node_data.does or node_data.name or 'unknown') .. '>'

   if node_data.state then
      parts[#parts + 1] = 'state=' .. _safe_tostring(node_data.state)
   end

   if node_data.name and node_data.name ~= node_data.does then
      parts[#parts + 1] = 'name=' .. _safe_tostring(node_data.name)
   end

   if node_data.utility then
      parts[#parts + 1] = 'u=' .. _safe_tostring(node_data.utility)
   end

   if node_data.progress then
      parts[#parts + 1] = 'progress=' .. _safe_tostring(node_data.progress)
   end

   if node_data.args then
      parts[#parts + 1] = 'args=' .. _safe_tostring(node_data.args)
   end

   return table.concat(parts, ' ')
end

local function _append_debug_tree(lines, node, indent)
   if not node then
      return
   end

   local node_data = node.get and node:get() or node
   if not node_data then
      return
   end

   _append_line(lines, string.rep(' ', indent) .. _format_node_line(node_data))

   local children = node_data.children
   if not children then
      return
   end

   for _, child in ipairs(children) do
      _append_debug_tree(lines, child, indent + 2)
   end
end

local function _build_dump_text(entity)
   local lines = {}
   local header = _format_header(entity)

   _append_line(lines, 'SLAS Citizen AI Dump')
   _append_line(lines, 'citizen_name=' .. _safe_tostring(header.citizen_name))
   _append_line(lines, 'citizen_id=' .. _safe_tostring(header.citizen_id))
   _append_line(lines, 'citizen_uri=' .. _safe_tostring(header.citizen_uri))
   _append_line(lines, 'job_name=' .. _safe_tostring(header.job_name))
   _append_line(lines, 'job_level=' .. _safe_tostring(header.job_level))
   _append_line(lines, 'game_day=' .. _safe_tostring(header.game_day))
   _append_line(lines, 'game_time=' .. _safe_tostring(header.game_time))
   _append_line(lines, 'position=' .. _safe_tostring(header.position))
   _append_line(lines, '')

   local ai_component = entity:get_component('stonehearth:ai')
   if not ai_component then
      _append_line(lines, 'AI component missing')
      return table.concat(lines, '\n')
   end

   local active_activities = ai_component:get_active_activities() or {}
   local activity_names = {}
   for activity_name in pairs(active_activities) do
      activity_names[#activity_names + 1] = activity_name
   end
   table.sort(activity_names)

   _append_line(lines, 'active_activities=' .. (#activity_names > 0 and table.concat(activity_names, ', ') or 'none'))
   _append_line(lines, '')
   _append_line(lines, 'AI Tree:')

   local ok, debug_info = pcall(ai_component.get_debug_info, ai_component)
   if ok and debug_info and debug_info.debug_info and debug_info.debug_info.get then
      local root = debug_info.debug_info:get()
      if root and root.execution_frame then
         _append_debug_tree(lines, root.execution_frame, 0)
      else
         _append_line(lines, '<no execution frame>')
      end
   else
      _append_line(lines, '<failed to read debug info>')
   end

   return table.concat(lines, '\n')
end

local function _clear_previous_logs()
   local directory = _resolve_output_directory()
   if directory then
      local existing_files = _read_manifest(directory)
      for _, file_name in ipairs(existing_files) do
         _delete_file(_join_path(directory, file_name))
      end
      _delete_file(_join_path(directory, MANIFEST_FILE))
      _write_file(_join_path(directory, PROBE_FILE), 'slas probe')
      return directory
   end

   return nil
end

local function _get_player_citizens(player_id)
   if not stonehearth or not stonehearth.population or not stonehearth.population.get_population then
      return {}
   end

   local ok, population = pcall(stonehearth.population.get_population, stonehearth.population, player_id)
   if not ok or not population or not population.get_citizens then
      return {}
   end

   local ok_citizens, citizens = pcall(population.get_citizens, population)
   if not ok_citizens or not citizens then
      return {}
   end

   local result = {}
   for _, citizen in citizens:each() do
      result[#result + 1] = citizen
   end

   table.sort(result, function(a, b)
      return _get_citizen_name(a) < _get_citizen_name(b)
   end)

   return result
end

function CitizenAiDump:dump_all_citizens(player_id)
   local directory = _clear_previous_logs()

   local citizens = _get_player_citizens(player_id)
   local written_files = {}

   for _, citizen in ipairs(citizens) do
      local citizen_name = _get_citizen_name(citizen)
      local job_name = _get_job_name(citizen)
      local file_name = string.format('%s+%s.log', _sanitize_filename(citizen_name), _sanitize_filename(job_name))
      local text = _build_dump_text(citizen)
      local wrote_to_fs = false

      if directory then
         wrote_to_fs = _write_file(_join_path(directory, file_name), text)
      end

      if not wrote_to_fs then
         radiant.mods.write_object(DUMP_FOLDER .. '/' .. file_name, {
            file_name = file_name,
            citizen_name = citizen_name,
            job_name = job_name,
            text = text,
         })
      end

      written_files[#written_files + 1] = file_name
   end

   if directory then
      _write_manifest(directory, written_files)
   else
      radiant.mods.write_object(DUMP_FOLDER .. '/_manifest', {
         generated_at = _get_time_now(),
         player_id = player_id,
         files = written_files,
      })
   end

   log:info('[SLAS] wrote %s citizen AI dumps for player %s output_dir=%s', tostring(#citizens), tostring(player_id), tostring(directory or 'mod_storage'))
end

function CitizenAiDump:schedule_dump(player_id)
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end

   self._timer = radiant.set_realtime_timer('slas citizen ai dump', DUMP_DELAY_MS, function()
      self._timer = nil
      self:dump_all_citizens(player_id)
   end)
end

return CitizenAiDump
