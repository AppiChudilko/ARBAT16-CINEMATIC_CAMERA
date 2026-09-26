# ARBAT16 Cinematic Camera 1.8.0

One resource now supports FiveM and RedM. The client and server detect the game automatically, select its native API, and show the matching weather, filter and transport controls. The folder `arbat16_camera`, command `/ar16_cam` and ACE permission `arbat16_camera.use` stay unchanged.

- FiveM: vehicle attachment, GTA V timecycles including Black & White, local weather/clock control, and optional shallow depth of field with focus and strength.
- RedM: existing horse/wagon attachment, native filters and `simple_weather` integration remain available.
- Shared free flight, stabilization, dense route recording, saved cameras, timeline, presets, grids and persistent workspaces.
- Separate verified native tables, dual-game runtime/storage/NUI checks and pinned upstream reference fixtures.

The same resource ZIP can be built with `python tools/build_release.py`. A repository source download contains the installable folder under `resource/arbat16_camera`. Keep dated backups and retain the resource name for existing server KVP data. Exported scenes use game-specific locations and weather and are not automatically converted between games.

Automated checks pass for both game paths. This does not replace live FiveM and RedM tests of rendering, capture and compatibility with other server resources. The existing repository screenshots were captured in RedM.

The ARBAT16 Source-Available License 1.0 (No Resale), official contacts and Inter OFL notices are unchanged.
