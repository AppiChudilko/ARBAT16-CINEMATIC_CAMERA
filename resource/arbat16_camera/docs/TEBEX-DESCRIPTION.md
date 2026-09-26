# ARBAT16 Cinematic Camera for FiveM and RedM

Build camera shots and editable routes inside FiveM or RedM with a standalone Lua director resource. Fly the camera, save viewpoints, record movement and apply a cinematic look from an English interface that keeps the game visible behind it.

- **Version:** 1.8.0
- **Resource folder:** `arbat16_camera`
- **Open command:** `/ar16_cam`

## Camera and route tools

- Free flight with adjustable speed, FOV and roll, plus Off, Light, Medium and Strong stabilization.
- Up to 100 saved cameras with recall, update, world guides and timeline placement.
- Editable keyframes, cuts, holds, easing, splines and Bezier handles, with copy/paste, undo/redo, looping and exact numeric controls.
- Route recording targeting 30 samples per second. Each take becomes one editable timeline clip, including stationary pauses.
- Generated Dolly, Truck, Crane, Pan and Orbit moves, with an optional return to the starting position.
- Attachment to a player, mount, vehicle or aimed target, with optional rotation following.

## Look and composition

- Built-in cinematic presets and up to 40 custom presets.
- Adjustable game filters, including Black & White, plus the original game look.
- Native, 2.39:1, 2.35:1, 1.85:1, 16:9, 4:3 and square framing masks.
- Six composition guides: thirds, golden ratio, diagonals, 4 x 4 grid, centre cross and safe areas, with adjustable opacity.
- Sway and Handheld motion, local time and weather, and a clean view for external capture.

## Save and return

Your workspace remembers the last saved camera position, current scene, saved cameras, custom presets and viewing preferences. Reopening or reconnecting restores the saved workspace with playback paused. A separate personal scene library supports named saves and JSON import/export.

The interface scales for compact, ultrawide and 4K displays. Keyboard shortcuts, inline help and paired numeric fields keep frequent adjustments accessible.

## Requirements and limits

A running FiveM or RedM server and matching client are required. The same resource detects the game automatically; no manual platform switch is needed. The resource is standalone and uses server ACE permissions; no roleplay framework or database resource is required. Install the `arbat16_camera` folder, grant `arbat16_camera.use`, and add `ensure arbat16_camera` to the server configuration. Full steps are included in the README.

**Record Route records camera movement, not a video file.** Capture the final picture and audio with an external recording tool. Actual sampling depends on game frame rate. Framing masks do not change recording resolution.

A scene supports up to 200 points/clips and 60 minutes. One recorded take supports up to five minutes; the scene has a bounded recorded-sample limit. The default scene library holds 30 named scenes. Large saves take longer to transfer: wait for the workspace save indicator before disconnecting. A sudden disconnect can lose changes that have not reached the server.

Filter and focus appearance depend on game settings and other camera, timecycle or weather resources. FiveM supports optional shallow depth of field with focus and strength; RedM exposes focus distance. Unsupported controls are hidden automatically.

## Included and licensed

The package includes the Lua resource, local NUI assets, configuration, documentation and license notices. The archive contains editable source. The project originated with [ARBAT16 RedM Camera](https://github.com/AppiChudilko/ARBAT16-CINEMATIC_CAMERA).

Use and modification, including commercial-server use and monetized videos, are permitted under the included ARBAT16 source-available license. Free redistribution must retain the license and notices. Selling, reselling, renting or charging for copies of the script or derivatives, including paid bundles, requires separate written permission from ARBAT16. Bundled Inter uses SIL OFL 1.1.

This is an independent resource and is not an official Rockstar Games, Take-Two Interactive, Cfx.re or Tebex product.

Official website: [arbat16.com](https://arbat16.com) · Discord: [dscrd.in/arbat16](https://dscrd.in/arbat16).
