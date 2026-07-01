# Smart Local AI Search

`Smart Local AI Search` is a Stonehearth mod for the ACE environment focused on improving AI search behavior before expensive global candidate scans become the default path.

The main idea is simple:
- try nearby valid targets first
- expand the search radius if needed
- fall back to normal Stonehearth or ACE behavior when no local result is available

This keeps the mod compatibility-first. It is meant to work alongside existing performance mods, not replace them.

## What The Mod Does

- prefers nearby reachable items and resources over distant ones
- uses staged search with local, expanded, and fallback passes
- keeps safe fallback behavior so hearthlings do not get permanently stuck
- exposes basic tuning through `smart_local_ai/data/settings.json`
- includes optional debug logging

## What The Mod Does Not Do

- it does not replace the full inventory service
- it does not replace the full storage service
- it does not try to solve every performance issue in Stonehearth at once
- it does not aim to replace ACE or existing cache-oriented performance mods

## Current Scope

The current implementation is focused on:
- nearby item pickup and related reachable-entity searches
- fetch-style searches with staged local-to-global behavior
- limiting or disabling restock errands to reduce unnecessary workload

## Compatibility

- target game: `Stonehearth`
- required mod environment: `ACE`
- dependencies: `stonehearth`, `stonehearth_ace`, `radiant`

## Settings

Current settings live in `smart_local_ai/data/settings.json`.

Example:

```json
{
  "local_radius": 32,
  "expanded_radius": 64,
  "global_fallback": true,
  "debug_enabled": false,
  "enable_for_hauling": true,
  "enable_for_fetching": true,
  "enable_for_restocking": false,
  "disable_restock_errands": true,
  "enable_restock_throttle": true,
  "max_concurrent_restock_errands": 0,
  "restock_workers_per_errand": 12,
  "min_concurrent_restock_errands": 0
}
```

## Debug Logging

Set `debug_enabled` to `true` in the settings file to enable extra logging for staged searches and selected results.

## Known Limitations

- the mod currently targets a narrow set of AI search paths rather than the whole game
- integration points are still being expanded and validated against ACE behavior
- more comparison work is still needed against other performance-oriented mods
