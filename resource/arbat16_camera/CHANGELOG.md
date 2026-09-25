# Arbat16 Camera changelog

## 1.7.1 — 2026-09-25

- Added the official ARBAT16 website and Discord link to the license and documentation.
- No camera behavior or permissions changed; the no-resale terms remain the same.

## 1.7.0 — 2026-09-25

- Changed the open/close command to `/ar16_cam`, including diagnostic, emergency close and saved-view reset commands and all current documentation.
- Added native Black & White / Photo Mode Noir with adjustable strength. The effect applies to the game image and is restored through scene and preset settings.
- Prepared a public source repository and installable resource ZIP, with installation instructions, checksum, release notes and an English Tebex description.
- Added the ARBAT16 No-Resale License: use and modification, including commercial server use and monetized output, are allowed; selling or reselling the resource or derivatives is prohibited for recipients. Inter retains its separate SIL OFL 1.1 license.
- Disabled automatic diagnostic files by default in the distributed configuration; operators can enable them when troubleshooting. Existing saved scenes remain compatible.


## 1.6.0 — 2026-09-25

- Added Camera → Composition with six guides: thirds, golden ratio, diagonals, 4 × 4, centre cross and 90%/80% safe areas. Grid choice, 10–100% opacity and visibility persist in the workspace; older settings migrate without losing the enabled flag.
- Added G to show/hide the last grid in both native flight and the editor, retaining focus/pause/held-key guards. Guides fit the selected frame ratio at any viewport size and disappear with Hide UI.
- Replaced long inspector paragraphs with short prompts and clickable information buttons. Explanations support keyboard access, Escape/close focus return and automatic dismissal when changing view or entering flight. Full instructions remain in Help.
- Kept monochrome, transparent NUI styling and all existing camera/recording behavior. No new game natives or external assets.


## 1.5.2 — 2026-09-25

- Fixed native flight ignoring left/right Shift when only their individual raw-key codes are reported. Generic and side-specific Shift, Ctrl and Alt now normalize into modifier families before held-key guards.
- Verified 4× Shift acceleration, normal speed after release, both-side handling, 0.2× Ctrl/Alt travel and all four stabilization levels. Focus/pause guards still require a complete modifier release before accepting stale held input.

## 1.5.1 — 2026-09-25

- Restyled the existing director interface using the supplied design code: rounded floating surfaces, pill controls, restrained dividers and locally bundled Inter typography.
- Applied a strictly monochrome palette to every editor control, recorded clip, world camera marker, path guide and feedback state. White accents, labels and shapes distinguish active states.
- Added translucent dark panels while preserving a fully transparent game viewport and opaque text. No backdrop blur, fullscreen tint or pulsing indicators.
- Kept a 14px minimum text size on compact windows, with larger 4K scaling and adjusted control rows. Corrected the saved-camera viewfinder SVG to fill the viewport.
- Retained camera behavior, the four inspector tabs, keyboard shortcuts, exact numeric inputs and responsive 4K scaling. Saved scenes and workspaces remain compatible.

## 1.5.0 — 2026-09-25

- Added Off, Light, Medium and Strong free-flight stabilization for mouse yaw/pitch and movement on every axis, including vertical travel. Stabilized positions are used by route recording.
- Added frame-rate-independent smoothing with controlled acceleration/deceleration, safe resets on focus/pause/lifecycle changes and direct-input compatibility when Off.
- Remembered stabilization in each director workspace; older workspaces keep direct input until the user enables it. Visual presets do not change the flight preference.
- Simplified the editor into Camera, Look, Saved and Advanced views, with clearer primary action labels, a short first-shot guide and contextual help.
- Added J to cycle stabilization, R to start/stop route recording and F1 for Help in native flight and the editor, with typing and repeat guards. Flight shortcuts work while movement modifiers are held.
- Replaced sparse REC keyframes with timestamped recordings targeting 30 samples per second. Each recording is one timeline clip; stationary intervals, rendered stabilization and additive motion are preserved without a second playback smoothing pass.
- Added recorded clip retiming, endpoint capture, in-progress autosave, safe stop/save/close handling and world-space baking of attached recordings. A take holds up to 9,001 samples / five minutes; a scene holds up to 18,002 samples.
- Added numbered saved-camera markers with world-projected viewfinder outlines, independent visibility, click selection and double-click recall. Saved cameras can be dragged onto the timeline as timed hold shots; clips can be reordered.
- Raised scene storage/import to 4 MiB and workspace storage to 8 MiB, with bounded validation and latent bulk transport. Undo/redo retains up to 50 states within a shared 16 MiB serialized history budget.
- Added math, runtime, persistence and DOM regressions. Final smoothing feel and the revised interface require an in-game check; automated tests do not replace that check.

## 1.4.0 — 2026-09-24

- Added server-persisted director workspaces: current camera, scene, timeline, view settings, 100 saved cameras and 40 custom presets. Reopening and reconnecting restore the last saved workspace with playback paused.
- Added a camera bank with recall/update/delete, six cinematic presets and custom preset management.
- Added six verified native game filters with strength, seven framing choices with opacity, and additive sway/handheld motion.
- Added editable dolly/truck/crane/pan/orbit generation, optional return motion and existing loop playback. Generated clips append without replacing authored frames.
- Added numeric entry beside sliders and exact playback-speed entry. Kept the transparent, responsive graphite editor and clean view.
- Saved attached routes now bake their current world transform consistently for named scenes and autosave. Capturing or recording after a generated final zero-duration frame remains valid.
- Protected unreadable autosaves from replacement, isolated save failures, and added explicit workspace and distance recovery controls.
- Added workspace lifecycle, storage isolation, director validation, motion, filter ownership and NUI regression checks. Live game rendering of new looks and motion remains unverified.

## 1.3.0 — 2026-09-24

- Moved flight keyboard and mouse input to RedM's native input path. The game receives focus during flight; Tab restores the editor cursor. Older clients retain the NUI input fallback.
- Added automatic camera/input/playback diagnostics, stored in a bounded server-side `camera-diagnostics.jsonl` file. Reports are client observations, not trusted server state.
- Reworked styling into a flat graphite editor with restrained slate-blue selections; controls, layout, transparent viewport and resolution scaling are retained.
- Added native-input and DOM/transport regression checks. DOM checks run without a browser or game window.

## 1.2.1 — 2026-09-24

- Normalize server ACE results explicitly: boolean true and numeric 1 allow access; false, 0 and unexpected values deny it.
- Added regression coverage for numeric ACE results on camera opening and scene-library requests.
- Configured a direct camera-only ACE for the verified local server owner, with a dated server.cfg backup.

## 1.2.0 — 2026-09-24

- Added automatic 4K/ultrawide scaling, compact layouts, scrollable properties and a separate properties toggle; the game viewport remains transparent.
- Fixed projected path SVG sizing to cover the full viewport.
- Protected flight entry from stale Lua state messages, including messages arriving after a callback acknowledgement.
- Added monotonic runtime state sequencing and the read-only camera diagnostic command. Invalid camera handles are rejected before focus/freeze.
- Renamed the resource to `arbat16_camera` and introduced resource-specific camera commands.
- Updated the editor branding, Lua event names, default ACE permission, scene export filename, documentation and test paths.
- Added deployment migration for the old resource folder and startup entries, preserving dated archives and the old KVP data.
- Documented JSON transfer for scenes saved under the old resource name.

## 1.1.0 — 2026-09-24

- Removed the browser demo: backdrop, generated terrain, sample keyframes, browser storage and simulated responses.
- Transparent NUI starts hidden and opens only from RedM. No full-screen background is shipped.
- Translated controls, tooltips, dialogs, validation errors and client/server notifications to English. User-created scene content is preserved.
- Removed the nonfunctional DOF blur switch; retained the implemented focus-distance control.
- Hardened NUI lifecycle, failed-edit feedback, input handling and asynchronous scene operations.
- Fixed recording intervals and protection of existing authored frame durations, failed seeks and stale storage replies.
- Kept older libraries accessible after configured storage limits are lowered.
- Added complete-folder deployment with verification, version ZIPs and retained prior folders.
- Added English documentation and repeatable offline release checks.

## 1.0.0 — 2026-09-24

Initial standalone Lua/RedM camera editor: free flight, keyframes, spline/Bezier routes, transitions, local environment, entity attachment, recording and server scene libraries. Interface inspired by the public Luman Camera reference; code written independently.

Initial validation: 774 Lua assertions, 23 server check groups, 9 JavaScript tests, mocked runtime/native contracts and a browser demonstration. The browser demo was removed from the resource in 1.1.0.

## Version archive policy

Every deployment creates dated archives of the installed resource and new release. Use tools/deploy_arbat16_camera.ps1. Increment fxmanifest.lua semantic version, update this changelog, and run targeted checks. Keep old archives outside resources; never overwrite them. Saved KVP scenes require separate server-data backups or JSON export.
