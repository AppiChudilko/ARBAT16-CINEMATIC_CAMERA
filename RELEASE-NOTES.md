# ARBAT16 Cinematic Camera 1.7.0

## Install

Download **arbat16_camera-v1.7.0.zip**, extract the single `arbat16_camera` folder into your RedM `resources`, grant `arbat16_camera.use` and start it with `ensure arbat16_camera`. Open with **/ar16_cam**. The adjacent `.sha256` file verifies the ZIP.

## Included

- Free-flight camera with adjustable stabilization, speed and lens controls.
- Saved camera angles, a scene library, route editing, dense movement recording and persistent workspaces.
- Cinematic presets, adjustable Black & White / Photo Mode Noir, frame masks and six composition guides.
- Translucent monochrome UI, 4K scaling, short prompts and clickable explanations.
- Complete editable source and the ARBAT16 Source-Available License 1.0 (No Resale), with Inter's separate OFL notice.

## Changes from 1.6.0

The command family now uses `ar16_cam`, including `ar16_camclose`, `ar16_camdebug` and `ar16_camresetview`. Black & White starts at full strength and can be blended down. Automatic diagnostics are off by default. Back up your configuration and server KVP before updating; the resource folder name remains unchanged.

## License

Use and modification for any lawful purpose, including commercial servers and monetized videos, are permitted. Free redistribution must retain the license and notices. Recipients may not sell or resell the resource or derivatives, including paid bundles. See LICENSE.txt for full terms and exceptions.

## Validation and limits

Offline Lua, storage, native-contract, runtime, model and NUI tests passed. The native Noir name and call signatures were checked against RDR3 references; its appearance has not yet been checked in a live RedM session. Test on your target server before recording production work. Route recording saves movement, not video, and filters currently apply to the whole scene.
