# Publishing notes for the maintainer

These instructions prepare the official GitHub release and the package you upload to Tebex. They do not publish a product, choose a price or create purchase, payment or refund terms.

## Release identity

- Repository: [AppiChudilko/ARBAT16-REDM_CINEMATIC_CAMERA](https://github.com/AppiChudilko/ARBAT16-REDM_CINEMATIC_CAMERA).
- Release version: `1.7.1`, with matching `v1.7.1` tag, manifest, README and product description.
- Installed folder: `arbat16_camera`.
- Default command: `/ar16_cam`.
- License: **ARBAT16 Source-Available License 1.0 (No Resale)**.

The publisher is ARBAT16, identified here by the GitHub account AppiChudilko. No legal entity, registration number, address or governing jurisdiction has been invented.

## Prepare the package

1. Finish the release checks, then perform a target-server smoke test of flight, a saved-camera recall, route recording and playback, Black & White, composition guides, and workspace restoration. Automated tests are not evidence of live game appearance or compatibility.
2. Run `python tools/build_release.py` from the repository root to build the release ZIP from the resource source, with a single `arbat16_camera` folder containing `fxmanifest.lua`. Keep dated copies of the previous installation and new release. Never include runtime diagnostics, server configuration, credentials, player KVP data, caches, development dependencies or unrelated workspace files.
3. Include `LICENSE.txt`, `THIRD_PARTY_NOTICES.md`, `web/fonts/OFL-Inter.txt`, the README and the documentation with the deliverable. Inspect the ZIP contents and record its SHA-256 hash. The bundled Inter notice must remain intact.
4. Extract the ZIP into a clean temporary folder and verify the layout. Check that documentation uses `/ar16_cam` and that the manifest reports `1.7.1`. Keep the installation resource name stable so ordinary updates continue using existing KVP storage.

Saved scenes and workspaces live in server resource KVP storage, outside a normal resource ZIP. An archive of the code does not back up player libraries. Export scenes or back up server KVP separately before migration.

## GitHub release

Publish the resource source under `resource/arbat16_camera`, with a copy of `LICENSE.txt` at the repository root and the complete notices inside the resource. Add the README, changelog and relevant documentation. Exclude private local paths, diagnostics and generated development files from the public copy.

Create the `v1.7.1` tag and release against the intended commit, attach the inspected ZIP and its checksum, and describe actual changes and any unverified game behavior. Check the repository links before sharing them. If updating an existing release, preserve previous version artifacts rather than silently replacing their contents.

Do not select MIT, Apache, GPL or another standard license in a repository wizard. The project uses its actual custom license file. Describe it as **source-available, no resale**. A GitHub license badge is not a substitute for the controlling text.

## Tebex upload

Use [TEBEX-DESCRIPTION.md](TEBEX-DESCRIPTION.md) as the product copy after confirming that it matches the released build. Upload the inspected ZIP yourself through your store's product workflow. Set your own price, delivery options and customer-facing purchase details in the store; this document supplies none of those terms.

Capture and upload genuine screenshots from the released resource running in RedM. A useful set shows the full editor, saved cameras and timeline, Black & White at a representative strength, composition guides, and a clean framed shot. Show actual functionality and keep capture resolution or performance claims tied to what you tested. Do not present design mockups as game screenshots. Add screenshots to the store and repository only when the real files are available; the public product description contains no placeholder image links.

Preview the store description, download the attachment from the customer delivery path and verify its hash or contents, then confirm that the installation steps and license files remain accessible. Do not claim official approval, universal server compatibility, built-in video export or advanced depth-of-field blur.

## Author notes on the license

The license was drafted with an AI assistant, not a lawyer. This custom template is not legal advice. It expresses the requested use, modification and free-sharing permissions with a no-resale condition; it does not establish the publisher's ownership of third-party contributions or replace mandatory consumer rights. Confirm rights in any supplied design code or future contributions before including them in a release.

This is a resource copyright license, not a store agreement or a jurisdiction-specific compliance audit. Platform terms, store disclosures and mandatory purchaser rights remain separate. The license deliberately selects no governing law or court. It allows commercial-server use and monetized output, reserves official commercial distribution to ARBAT16, and requires a written exception for recipient resale. No broad source-disclosure obligation was added.

GitHub documents placing a `LICENSE.txt` file at the repository root and explains that public source remains subject to its licensing terms. Its license detection compares against known texts, so a custom license may not receive a standard badge. [GitHub: Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

Inter is a separate component under SIL OFL 1.1. That license permits bundling with software under its own conditions, requires preservation of its notices and license, and keeps the font under OFL. The resource's custom restriction must not replace or narrow that grant. [SIL: Official OFL text](https://openfontlicense.org/open-font-license-official-text/).
