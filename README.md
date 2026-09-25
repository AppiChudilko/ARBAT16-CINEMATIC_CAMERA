# ARBAT16 Cinematic Camera for RedM

A standalone in-game director for cinematic shots, saved camera angles and editable camera routes. Lua powers the camera; the English interface stays transparent over the game.

**Version 1.7.1 · Command `/ar16_cam` · Resource `arbat16_camera`**

[Download the ready-to-install ZIP](https://github.com/AppiChudilko/ARBAT16-REDM_CINEMATIC_CAMERA/releases/latest) · [Full user guide](resource/arbat16_camera/README.md) · [License](LICENSE.txt) · [Report a problem](https://github.com/AppiChudilko/ARBAT16-REDM_CINEMATIC_CAMERA/issues)

## Features

- Free flight with mouse control, adjustable speed and four stabilization levels.
- Saved camera angles, world-space camera markers and a scene library.
- A timeline for keyframes, recorded movement clips, hold shots, cuts and curved paths.
- Route recording at up to 30 samples per second, with real timestamps and stationary holds.
- Cinematic looks, custom presets and a native **Black & White** filter.
- Cinematic frame masks and six composition guides, including thirds and golden ratio.
- Local time and weather per keyframe, plus attachment to characters, mounts or vehicles.
- Autosaved workspace, numeric controls, keyboard shortcuts and click-to-read explanations.
- Monochrome, translucent interface that scales for 4K and ultrawide displays.

**Record Route records camera movement, not a video file.** Capture the final video separately. Filters currently apply to the whole scene, not individual timeline clips.

## Install

1. Download `arbat16_camera-v1.7.1.zip` from Releases.
2. Extract the `arbat16_camera` folder into your RedM server's `resources` directory.
3. Add the lines below to `server.cfg`. Ensure your account belongs to `group.admin`, or grant the ACE to your own identifier as explained in the user guide.
4. Start the resource and enter `/ar16_cam` in chat.

```cfg
add_ace group.admin arbat16_camera.use allow
ensure arbat16_camera
```

No framework or database is required. Keep the folder name `arbat16_camera`. On an existing installation, back up configuration and server KVP data before updating.

## Quick controls

| Key | Action |
| --- | --- |
| Tab | Switch flight/editor |
| WASD / Q / E | Move / down / up |
| Shift / Ctrl or Alt | Faster / slower |
| J | Change stabilization |
| R | Record / stop route |
| F / Space | Add point / play route |
| G / H | Toggle guides / hide UI |
| F1 | Help |

## Use and modification

You may use and modify the script for any lawful purpose, including commercial servers and monetized videos. You may distribute original or modified copies free of charge with the license and notices preserved. **You may not sell or resell the resource or its derivatives, including inside paid bundles.** Official distribution by ARBAT16 is separate from these recipient restrictions.

This is a custom source-available license, not MIT or an OSI open-source license. [Full terms](LICENSE.txt) · [License FAQ](resource/arbat16_camera/docs/LICENSE-FAQ.md) · [Third-party notices](resource/arbat16_camera/THIRD_PARTY_NOTICES.md)

## Development and packaging

The installable resource is under `resource/arbat16_camera`. Node.js 24, Python 3.13 and pnpm are required only for development:

```text
pnpm install --frozen-lockfile
python -m pip install -r requirements-dev.txt
python tests/arbat16_camera_suite.py
python tools/build_release.py
```

The ZIP contains one installable resource folder and its license documents. Logs, tests, build tools and dependency folders are excluded. SHA-256 checksums accompany releases.

[Changes](resource/arbat16_camera/CHANGELOG.md) · [Tebex product text](resource/arbat16_camera/docs/TEBEX-DESCRIPTION.md) · [Publishing notes](resource/arbat16_camera/docs/PUBLISHING.md)

Offline tests cover logic and NUI behavior. They do not replace an in-game smoke test on your RedM server; native effect appearance and compatibility with other camera/weather resources depend on that environment.

Official website: [arbat16.com](https://arbat16.com) · Discord: [dscrd.in/arbat16](https://dscrd.in/arbat16).
