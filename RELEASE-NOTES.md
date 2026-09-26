# ARBAT16 Cinematic Camera 1.8.0

One resource now supports FiveM and RedM. The client and server detect the game automatically, select its native API, and show the matching weather, filter and transport controls. The folder `arbat16_camera`, command `/ar16_cam` and ACE permission `arbat16_camera.use` stay unchanged.

- FiveM: vehicle attachment, GTA V timecycles including Black & White, local weather/clock control, and optional shallow depth of field with focus and strength.
- RedM: existing horse/wagon attachment, native filters and `simple_weather` integration remain available.
- Shared free flight, stabilization, dense route recording, saved cameras, timeline, presets, grids and persistent workspaces.
- Separate verified native tables, dual-game runtime/storage/NUI checks and pinned upstream reference fixtures.

## Install or update

Download **arbat16_camera-v1.8.0.zip** from the assets below and extract its **arbat16_camera** folder into your FiveM or RedM server's `resources` directory. The same ZIP detects either game automatically.

```cfg
add_ace group.admin arbat16_camera.use allow
ensure arbat16_camera
```

Open with **/ar16_cam**. Existing installations can use `restart arbat16_camera` after replacing files; new ACE entries require reloading the server configuration. Save your work before restarting the resource. No framework, database or build step is required.

Keep dated backups and retain the resource name for existing server KVP data. Resource ZIPs contain code, not saved player scenes. Exported scenes use game-specific locations and weather and are not automatically converted between games.

The adjacent `.zip.sha256` file verifies the download; the manifest lists individual file checksums. Developers can reproduce the ZIP with `python tools/build_release.py`.

## Validation

Automated checks pass for both game paths. This does not replace live FiveM and RedM tests of rendering, capture and compatibility with other server resources. The existing repository screenshots were captured in RedM.

The ARBAT16 Source-Available License 1.0 (No Resale), official contacts and Inter OFL notices are unchanged.

[arbat16.com](https://arbat16.com) · [Discord](https://dscrd.in/arbat16)
