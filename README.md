# Technical Task: Stonehearth ACE Smart Local AI Search Mod

## Goal

Create a Stonehearth mod for ACE that improves AI performance and behavior by limiting item/resource search scope before expensive inventory/storage/filter operations are triggered.

The mod should NOT replace the existing ACE performance mod. It should complement it.

Main idea:
- Existing performance mods optimize cache/filter/storage operations after a large candidate list exists.
- This mod should reduce the candidate list earlier by preferring local nearby items/resources first.

## Target Game

- Stonehearth
- ACE mod environment
- Lua-based Stonehearth modding system
- Standard Stonehearth `manifest.json` structure

Stonehearth mods use a `manifest.json` with an `info` section, including `namespace`, `name`, and API `version`, currently `3`. Actions can be Lua scripts registered in the manifest and injected into AI packs. Use the Stonehearth modding guide structure for manifest, aliases, mixintos, overrides, and AI actions.

## Mod Name

Suggested folder/namespace:

```text
smart_local_ai
```

Suggested display name:

```text
Smart Local AI
```

## Core Concept

When hearthlings search for items/resources to pick up, haul, restock, or fetch, the mod should prefer nearby valid candidates instead of scanning or accepting candidates from the whole map immediately.

The logic should work in stages:

1. Search local radius first.
2. If nothing is found, expand radius.
3. If still nothing is found, fall back to vanilla/ACE behavior.

This prevents breaking gameplay while reducing unnecessary global searches.

## MVP Scope

Implement the first version only for item/resource pickup or hauling-related behavior.

Do not rewrite the entire inventory service or storage service in the first version.

Priority target:
- hauling loose items
- picking up resources
- fetching resources for jobs if safely accessible

## Required Behavior

### 1. Radius-based candidate filtering

Add configurable radius values:

```lua
local_radius = 32
expanded_radius = 64
global_fallback = true
```

Expected behavior:

- First attempt: only consider items within `local_radius` from the hearthling.
- Second attempt: only consider items within `expanded_radius`.
- Final fallback: use original vanilla/ACE search behavior if enabled.

### 2. Distance-based utility penalty

If multiple valid items are found, closer items should be preferred.

Suggested logic:

```text
distance <= local_radius      -> high utility
distance <= expanded_radius   -> medium utility
distance > expanded_radius    -> low utility or fallback only
```

Do not hard-block distant items unless fallback is disabled.

### 3. Safe fallback

The mod must never leave hearthlings permanently unable to find resources.

If local search fails, fallback to vanilla/ACE behavior.

### 4. Compatibility-first design

Avoid overriding core services unless absolutely necessary.

Preferred approach:
- add custom Lua AI action(s)
- inject them through AI packs/mixintos
- wrap or extend existing behavior where possible

Avoid:
- full replacement of `inventory_service`
- full replacement of `storage_service`
- global monkey-patching without safety checks

### 5. Debug logging

Add optional debug logging.

Config:

```lua
debug_enabled = false
```

When enabled, log:
- hearthling entity id/name
- search stage: local / expanded / fallback
- number of candidates found
- chosen item
- distance to item
- fallback usage

### 6. Settings file

Create a simple config file, for example:

```text
smart_local_ai/data/settings.json
```

Example:

```json
{
  "local_radius": 32,
  "expanded_radius": 64,
  "global_fallback": true,
  "debug_enabled": false,
  "enable_for_hauling": true,
  "enable_for_fetching": false,
  "enable_for_restocking": false
}
```

## Suggested File Structure

```text
smart_local_ai/
├─ manifest.json
├─ data/
│  └─ settings.json
├─ ai/
│  ├─ actions/
│  │  └─ smart_find_local_item_action.lua
│  └─ ai_pack/
│     └─ smart_local_ai_pack.json
├─ mixintos/
│  └─ hearthling_ai_pack_mixinto.json
└─ README.md
```

## manifest.json Requirements

Create a valid Stonehearth manifest.

Minimum:

```json
{
  "info": {
    "name": "Smart Local AI",
    "namespace": "smart_local_ai",
    "version": 3
  },
  "aliases": {
    "smart_find_local_item_action": "file(ai/actions/smart_find_local_item_action.lua)",
    "smart_local_ai_pack": "file(ai/ai_pack/smart_local_ai_pack.json)",
    "settings": "file(data/settings.json)"
  },
  "mixintos": {
  }
}
```

Add correct mixintos only after identifying the correct ACE/Stonehearth AI pack path.

## Implementation Notes

### Important

Before coding, inspect existing Stonehearth/ACE files related to:
- hauling
- pickup item actions
- finding items
- inventory service
- storage service
- AI packs for hearthlings/workers

Find the safest injection point.

Do not assume exact file names. Search the game/mod files first.

### Pseudocode

```lua
function find_local_item(ai, entity, args)
   local settings = load_settings()

   local origin = radiant.entities.get_world_grid_location(entity)

   local candidates = get_candidate_items(args)

   local local_candidates = filter_by_radius(candidates, origin, settings.local_radius)

   if #local_candidates > 0 then
      return choose_nearest_or_best(local_candidates)
   end

   local expanded_candidates = filter_by_radius(candidates, origin, settings.expanded_radius)

   if #expanded_candidates > 0 then
      return choose_nearest_or_best(expanded_candidates)
   end

   if settings.global_fallback then
      return original_behavior(args)
   end

   return nil
end
```

### Distance Function

Use Stonehearth/Radiant helper functions if available.

If not, calculate simple grid distance from world coordinates.

### Candidate Validation

Do not select invalid items.

Candidate must be:
- existing entity
- reachable if reachability data is available
- not reserved by another hearthling
- not already in storage if action requires loose item
- matching requested material/category/filter
- not hidden/destroyed
- allowed by ACE filters

## Acceptance Criteria

The mod is successful if:

1. Game loads without errors.
2. Mod appears in Mods menu.
3. Hearthlings still haul/pick up items normally.
4. Local nearby items are preferred over distant items.
5. If no nearby items exist, hearthlings can still use distant items through fallback.
6. Debug mode logs search stage and selected item.
7. No permanent AI deadlock occurs.
8. The mod does not require disabling ACE.
9. The mod does not replace the existing ACE performance mod.
10. The code is organized and commented enough for a beginner modder to understand.

## Testing Scenario

Create a test town with:

1. Hearthling near a pile of wood.
2. Another pile of wood far away.
3. A storage zone nearby.
4. A storage zone far away.
5. Enable debug mode.

Expected:
- Hearthling chooses nearby pile first.
- If nearby pile is removed, hearthling eventually uses far pile.
- Debug shows local search first, then expanded/fallback only if needed.

Second test:

- Create many loose items in a mine or far area.
- Confirm hearthlings do not constantly prefer far-away items when equivalent nearby items exist.

## README Requirements

README should explain:

- What the mod does.
- What it does not do.
- Compatibility with ACE.
- Difference from existing performance/cache mods.
- How to change radius settings.
- How to enable debug logging.
- Known limitations.

## Important Design Principle

This mod should reduce bad candidate selection before expensive filter/cache/service work happens.

It should not try to optimize everything at once.

Start small, safe, and compatible.
