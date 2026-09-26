# Arbat16 Camera 1.8.0 — FiveM and RedM director resource

Standalone Lua cinematic camera with an English NUI editor. The game remains visible behind the transparent interface. The NUI starts hidden and opens only through the game client. There is no website, sample world, browser simulator, browser scene storage, external asset service or build step in this resource.

## Install and update

Extract **arbat16_camera** from `arbat16_camera-v1.8.0.zip` into your FiveM or RedM server's `resources` directory. **The same ZIP supports both games.** Game detection is automatic on the client and server; no platform setting is required. Keep the resource folder name unchanged. No framework, database, npm build or external font download is required for installation.

`server.cfg` should contain:

```cfg
add_ace group.admin arbat16_camera.use allow
ensure arbat16_camera
```

For a first install, run `refresh` and `ensure arbat16_camera` in the server console. After an update, use `restart arbat16_camera`. If ACE was just added to the file, run its `add_ace` line in the console or restart the server to read the configuration. Restarting the resource closes camera sessions: save or export unsaved scenes first.

Open with `/ar16_cam` in chat or `ar16_cam` in the client F8 console. Emergency cleanup: `ar16_camclose` in F8. The default permission, `arbat16_camera.use`, is checked when opening and on every library operation.

For access independent of admin-group membership, add `add_ace identifier.license:YOUR_LICENSE arbat16_camera.use allow` to `server.cfg`, substituting the player's actual license. Configuration edits are read on server startup; restarting only the resource does not reload `server.cfg`. ACE results are normalized explicitly: only boolean `true` or numeric `1` grants access.

If flight or playback does not move the camera, run `ar16_camdebug` in F8 while the camera is open. It prints camera ownership/rendering, input delivery, timeline and whether the keyframes actually contain different camera poses. Copy these lines when reporting a problem. The command only reads state.

Diagnostics are off by default. With `Diagnostics=true`, opening, flight and playback also record diagnostic snapshots automatically, including a delayed movement/playback sample. The server writes `camera-diagnostics.jsonl` inside this resource, capped at 256 KiB with complete old lines discarded when full. Reports include camera coordinates and runtime counters, but no license, account name or hardware identifiers. They are marked as client reports. Set `Diagnostics=false` to disable automatic recording. Keep diagnostic logs private when sharing the resource.

Before updating, keep a dated copy of your installed resource and back up the server's KVP data. ZIP files contain code, not saved player scenes. Retain your configuration and compare new options before replacing it. Stop the resource, replace its files, then start it again. Do not run the old and new copies simultaneously.

FXServer namespaces scene KVP by resource name. Any scenes saved under `frontier_camera` stay in its original KVP and are not automatically moved by this rename. Export their JSON using the archived old version and import it into Arbat16 Camera. Keep a KVP backup before changing resource names.

## First shot

1. Run `/ar16_cam`. In **Camera**, choose a stabilization level, then use **Tab** or **Move Camera** to enter flight mode.
2. Move with **W A S D**, go down/up with **Q / E**, and turn with the mouse. Flight uses native game input and releases the editor cursor. **Shift** accelerates; **Alt** or **Ctrl** slows movement. On older clients without native raw-key input, the NUI fallback uses mouse capture or right-button drag.
3. Press **F / Add Point** to remember a point on the route, move and add another. Alternatively, press **R / Record Route**, fly the shot and press **R** again to create one recorded clip.
4. Return to editing with **Tab**. Select a keyframe to edit it; double-click it to move the camera to that pose.
5. Press **Space / Play Route** to play the route. **H** hides the controls and keeps the camera visible.
6. Use **Save Scene / Ctrl+S** to name the route. **F1 / Help** explains the controls at any time.

## Simple controls and smooth flight

The inspector starts on **Camera** with a short first-shot guide, stabilization, composition guides and lens controls. **Look** holds presets, filters and framing. **Saved** contains named viewpoints and the scene library. **Advanced** contains detailed route editing, environment, motion effects and generated moves. Selecting a timeline point makes its editing controls available. The timeline and main actions remain accessible while switching tabs.

Flight stabilization smooths your mouse movement left/right and up/down, plus movement in all directions, including Q/E. Choose **Off**, **Light**, **Medium** or **Strong** under Camera, or press **J** to cycle them. Medium is a useful starting point; Strong responds more slowly and settles more gently after releasing movement. Off keeps direct input. Old workspaces start with Off, and your selection is remembered with your workspace.

Stabilization operates on the actual flying camera before route recording samples it. It does not apply a second smoothing pass during playback. Leaving flight, opening Help, losing game input focus, pausing or closing clears residual movement. The separate Sway/Handheld effect deliberately adds motion; turn that effect off when you want a steady, stabilized shot.

The inspector keeps short prompts visible. Click the circled information button beside a setting for its explanation; Escape or the close button dismisses it without exiting the camera. Help retains the complete first-shot guide. The flight guide lists active shortcuts, and action buttons also have brief pointer/focus hints. **F1** returns control to the editor before opening Help during native flight. Shortcuts do not run while typing in fields or using dialogs. **Record Route** saves a movement clip; it does not record a video file.

## Composition guides

In **Camera → Composition**, enable **Show guides** or press **G**. Choose **Rule of thirds (3 × 3)**, **Golden ratio**, **Diagonals**, **Fine grid (4 × 4)**, **Centre cross** or **Safe areas**. Selecting a grid also shows it. Safe areas mark centred 90% action and 80% title regions as composition references.

Set opacity from **10–100%**, with a slider or an exact number. White lines with a dark outline stay readable over different scenes. Guides fit the format selected in **Look → Frame Ratio**, including square and cinematic crops, and resize with the viewport. They are visible in flight; **H / Hide UI** hides guides along with the editor for clean external video capture. Black framing masks remain visible.

Your selected grid, opacity and on/off state are workspace preferences. They survive closing, reopening and reconnecting; older workspaces keep their previous thirds-grid on/off choice. These guides do not alter scene geometry or your camera route.

## Controls

| Input | Action |
| --- | --- |
| Tab / Move Camera | Switch flight and editor cursor; fields and dialogs keep normal Tab navigation |
| W A S D | Forward, left, backward and right during flight |
| Q / E | Down / up |
| Mouse / right-button drag | Turn camera |
| Left / right Shift | Fast flight, 4× by default |
| Alt / Ctrl | Slow flight |
| F | Add a route point (keyframe) |
| R | Start / stop recording the camera route |
| J | Cycle Off / Light / Medium / Strong stabilization |
| G | Show / hide the selected composition guides |
| F1 | Open the first-shot guide and shortcuts |
| Space | Play / pause the route |
| H | Hide / show editor and guides |
| Escape | Close dialog, leave mouse capture or exit editor |
| Ctrl+Z / Ctrl+Shift+Z | Undo / redo, up to 50 edits within a 16 MiB history budget |
| Ctrl+C / Ctrl+V / Ctrl+A | Copy / paste / select all keyframes |
| Ctrl+S | Save scene |
| Left / right arrow | Step 1/30 second |
| Delete | Delete selected keyframes |
| Shift+click | Toggle additional keyframe selection |
| Drag timeline keyframe | Reorder |

Scene shortcuts are suppressed while typing in a field. **Update from Camera** replaces the selected keyframe's pose and lens while retaining its timing, easing and tangents.

## Director workspace and saved cameras

The current camera position, timeline, scene, view settings, camera bank and custom presets save automatically to the server under your player license. Changes are checkpointed roughly every two seconds while moving, shortly after edits, and on close. The workspace indicator shows saving, saved or an error; a failed save keeps the in-memory session available and retries. A sudden disconnect restores the most recent acknowledged checkpoint, which may precede the final movement by a few seconds.

Closing with the command or Escape releases the player. Reopening `/ar16_cam`, reconnecting, or restarting the resource restores the last saved camera and scene with playback paused. **Clean View / H** keeps the current camera and playback visible while hiding the editor; framing remains visible. Live entity handles are not restored: attached paths are saved at their current world position, so you can attach them to a new entity later.

**Saved Cameras** stores up to 100 named viewpoints. Save the current view, select a camera and use Go to Camera, Update or Delete. Each camera stores its position, rotation, lens, environment and director look. Numbered markers and viewfinder outlines show the cameras in the world: click to select one, double-click to go to it. The Show Cameras switch hides these markers independently of the route; playback and Clean View hide them automatically.

Use **Add to Route** or drag a saved camera onto the timeline to insert a three-second hold shot. Drop onto another clip to insert before it, or onto empty track space to append. Drag timeline clips to reorder, select one to change its duration. Adding a shot keeps its lens and environment; the timeline uses the scene's common look. Recalling a camera restores its individual look. **Scene Library** separately stores named routes and their director settings.

The configured distance limit still applies. If a restored camera is too far from your player, move closer or use `/ar16_camresetview` after the initial open attempt. This resets only the active viewpoint to the player; it keeps saved cameras, presets and the scene.

If the server cannot read the existing workspace, automatic saving is disabled to protect it. The recovery control explicitly discards that unreadable autosave before saving the current session; it does not delete named scenes in Scene Library. Resource version ZIPs do not include player KVP data: back up the server's KVP database separately.

## Looks, framing and motion

Every slider has a paired numeric field, including FOV, roll, flight speed, filter strength, framing opacity, motion controls and timeline seconds. Playback speed accepts exact values from 0.1 to 8. Empty or invalid fields do not silently write zero.

**Presets** includes Natural, Cinema Scope / Western Scope, Urban / Frontier, Quiet Portrait, Handheld and Dream Sequence. Apply one as a starting point, adjust the lens, filter, framing and motion, then save your own named preset (up to 40). Applying a preset pauses playback so its live lens settings remain visible. Timeline keyframes retain their authored lenses; capture or update a keyframe to use the new lens there.

**Look & Framing** offers eight choices including Original and Black & White. FiveM uses GTA V timecycles (including `blackNwhite`); RedM uses its own timecycles and the Photo Mode Noir effect. The catalog switches automatically. Filter strength is adjustable; choose 100% for a fully monochrome look. Formats are Native, 2.39:1, 2.35:1, 1.85:1, 16:9, 4:3 and square, with adjustable mask opacity. These masks do not change capture resolution. Other resources can take ownership of the game's timecycle slot; cleanup only releases effects owned by this resource. Filters apply to the whole scene and cannot yet be automated per timeline point.

**Camera Motion** offers Sway and Handheld movement with amplitude, frequency and roll controls. This is an additive effect: the saved base viewpoint and path are not changed. Set motion to None to return to the exact base camera.

**Create Camera Move** appends an editable Dolly, Truck, Crane, Pan or Orbit starting at the current camera. Set travel distance or angle and total duration, optionally Return to start, then use Play. Enable the existing Loop control to repeat the route. A return move's duration includes both directions. Generated frames can be moved, retimed, saved and followed by manual keyframes or REC. Orbit uses a pivot in front of the current camera; distance is the orbit radius.

Game-specific calls are checked against [GTA V NativeDB](https://github.com/alloc8or/gta5-nativedb-data), [RDR3 NativeDB](https://github.com/alloc8or/rdr3-nativedb-data) and [Cfx.re native declarations](https://github.com/citizenfx/fivem/tree/master/ext/native-decls). Filter names come from [GTA V timecycles](https://github.com/DurtyFree/gta-v-data-dumps/blob/master/timecycleModifiers.json) and [RDR3 timecycles](https://github.com/femga/rdr3_discoveries/blob/master/graphics/timecycles/timecycles.lua). Their appearance depends on the game, weather and graphics settings.

## Screen sizes

The editor uses monochrome surfaces, rounded panels, capsule buttons, soft shadows and locally bundled Inter. The panel backgrounds are translucent; text and controls remain opaque. The game viewport stays transparent, with no fullscreen tint or backdrop blur. Status labels, selection outlines and clip patterns provide distinctions without color. This changes the editor's appearance, not the selected cinematic game filter.

Inter's license is included in `web/fonts/OFL-Inter.txt`. The font is served by the resource; the interface makes no external font requests.

The transparent interface scales automatically with viewport height, bounded by width. At 4K its controls and text are twice the 1080p size; ultrawide displays keep the height-based scale. Compact windows use wrapped controls and a scrollable properties panel. The **Toggle properties** button next to **Clean View** hides the inspector independently of the timeline. Resizing needs no restart and does not change camera projection coordinates.

Layout checks covered 360x640, 640x480, 800x600, 1280x720, 1920x1080, 2560x1440, 3440x1440 and 3840x2160. The responsive layout is retained from the RedM editor; live visual checks in both games are still required for this universal release.

## Camera and timeline

- Free camera, movement speed, FOV and roll.
- Linear paths, Catmull–Rom splines and cubic Bezier tangents. Edit tangents numerically or drag their viewport handles; **Auto tangents** restores the automatic spline.
- Six easing modes, cuts and hold-to-cut transitions.
- Multi-selection, batch positional offsets, copy/paste, reorder and undo/redo.
- Frame stepping, repeat and timeline speed from 0.1× to 8×.
- Timestamped route recording with **REC**, targeting 30 samples per second and storing each recording as one clip.
- Local weather and time per keyframe. Time follows the shortest path through midnight; weather switches between presets.
- Attach the route to the player, the current vehicle in FiveM, or the horse/vehicle in RedM; the aimed-target option supports an entity under the camera center. Optional rotation follows target orientation. Detaching bakes the current transform into the route.
- Server scene library, JSON import/export, HUD hiding, six composition guides and optional 2.39:1 letterbox.

A manual point's duration covers movement to the next point; the last duration is a stationary hold. A zero-duration non-final point must use a cut. Saved-camera shots hold their angle for their duration, then cut. Format limits: 200 points/clips, 600 seconds per clip and 60 minutes per scene.

**Recorded clips** preserve actual sample timestamps, including stationary intervals. The recording samples the rendered camera, including stabilization and Sway/Handheld; playback does not apply those effects again. Between samples it interpolates linearly, without path easing or splines. Sampling is limited by the game frame rate: a stalled game frame cannot supply the missing motion. The default aims for 30 Hz rather than mathematically lossless frame-by-frame capture.

One take is limited to five minutes / 9,001 samples, and the scene to 18,002 recorded samples. REC stops automatically at its limit. Stop, Play, Save and Close finalize the endpoint; autosave checkpoints the active take while recording. Attached recording follows the target, then becomes an independent world-space clip when stopped. Rename, copy, reorder, delete or change the clip duration to retime it; captured pose/lens controls are disabled because they belong to the recording. Double-click a recorded clip to seek to its start. Stop REC before adding a separate point or editing the timeline.

**REC records a camera route, not video.** Use OBS or another capture tool for the final picture and audio. **30 FPS** describes timeline stepping and timecode, not a game frame-rate limit. Timeline speed changes camera playback, not the global speed of players or the server world.

## Configuration and storage

Edit `config.lua`:

| Setting | Default | Purpose |
| --- | --- | --- |
| Command | `ar16_cam` | Open/close command |
| RequireAce / AcePermission | `true` / `arbat16_camera.use` | Server permission |
| Diagnostics | `false` | Automatic bounded camera/input reports |
| DefaultSpeed | `5.0` | Flight speed |
| FastMultiplier / SlowMultiplier | `4.0` / `0.2` | Flight modifiers |
| LookSensitivity | `0.12` | Mouse sensitivity |
| RecordInterval | `33` | REC target interval in milliseconds; maximum 30 Hz, bounded by game frames |
| MaxFrames / MaxScenes | `200` / `30` | New scene/library limits |
| MaxSceneBytes | `4194304` | Serialized scene byte limit, 4 MiB maximum |
| StorageCooldown | `600` | Library request interval, milliseconds |
| WorkspaceCooldown | `500` | Optional workspace request interval, minimum 500 milliseconds |
| FreezePlayer | `true` | Keep the player's body stationary |
| WeatherEnabled | `true` | Apply local environment |
| MaxDistance | `2000.0` | Distance from player, meters |

Libraries and director workspaces use separate server resource KVP keys for each stable player license. Workspaces are limited to 8 MiB. Names are display labels, never paths. Scene names allow up to 64 UTF-8 bytes, excluding slashes and control characters. Saving an existing name replaces that saved scene. Existing user names are preserved. Lowering configured limits does not prevent reading or deleting older valid scenes. Existing RedM workspaces remain compatible. FiveM and RedM use different worlds and weather catalogs: a scene export is intended for the same game, not automatic map conversion.

Large save/restore messages use [Cfx latent events](https://docs.fivem.net/docs/scripting-manual/working-with-events/triggering-events/) at 1 MiB/s when available, with 30-second request timeouts. Large recordings and slow networks can delay checkpoints; the workspace indicator confirms when the server has acknowledged a save.

Export JSON or back up server KVP data to preserve scenes: resource ZIPs contain code, not player libraries. Attachments last for the current session and are not persisted as entity handles; reattach a loaded route to a new target. Set `FreezePlayer=false` if the player's body needs to keep moving.

Closing, death, respawn, native failure or resource stop cleans up the owned camera, NUI focus, streaming focus and player freeze. Pre-existing frozen state is preserved; other resources' cameras are not destroyed. RedM retains `simple_weather` integration and authoritative resync on close. FiveM uses local weather/clock overrides and restores the prior weather while clearing the clock override on close. A continuously syncing external weather resource may overwrite local settings; coordinate that controller for filming or set `WeatherEnabled=false`. No framework-specific global weather changes are made. Use one camera editor at a time.

## Validation and current limits

Development tools are needed only to change or test the source: Node.js 24 and Python 3.13. From a repository checkout, run `pnpm install --frozen-lockfile`, `python -m pip install -r requirements-dev.txt`, then `python tests/arbat16_camera_suite.py`. This checks Lua syntax, interpolation, storage, both mocked game runtimes, the JavaScript model and NUI controls. Run `python tools/build_release.py` to produce an installable ZIP and SHA-256 checksum. Test dependencies are excluded from the downloadable resource.

FiveM exposes a depth-of-field toggle and blur strength, using GTA V shallow-DOF natives with a focus band around the chosen distance. RedM retains its documented focus-distance control; unsupported full DOF controls are hidden. Graphics settings and the scene affect the visible result.

Offline checks verify contracts, not actual rendering or server compatibility. This universal release still needs an in-game smoke test in **both FiveM and RedM**. Test flight/Shift, recording and playback, vehicle/horse attachment, saved workspace restoration, Black & White, weather/time and cleanup. For errors, check `[arbat16_camera]` in F8 and record the action that caused it.

## License

This is source-available software under the [ARBAT16 No-Resale License](LICENSE.txt). You may use and modify it for any lawful purpose, including commercial servers and monetized videos. You may share original or modified copies free of charge with the license and notices preserved. You may not sell, resell, rent or charge for access to the resource or a derivative, including through a paid bundle. Official sales by the rights holder are separate from these recipient restrictions.

See [License FAQ](docs/LICENSE-FAQ.md) for examples and [Third-party notices](THIRD_PARTY_NOTICES.md) for Inter's separate SIL Open Font License. This is not an MIT or OSI open-source license.

Questions and bug reports: [GitHub issues](https://github.com/AppiChudilko/ARBAT16-REDM_CINEMATIC_CAMERA/issues).

Official website: [arbat16.com](https://arbat16.com) · Discord: [dscrd.in/arbat16](https://dscrd.in/arbat16).
