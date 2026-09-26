# Native reference cache

`sources.json` pins the upstream commit and SHA-256 for GTA V NativeDB, RDR3 NativeDB and two Cfx.re declarations used by the platform checks. Run `python tools/fetch_native_references.py` to populate this directory; the test suite also fetches missing references automatically. The first run requires access to raw.githubusercontent.com. Subsequent checks use the verified local cache and can run offline.

Downloaded upstream files retain their own upstream terms. They are ignored by Git and excluded from the resource ZIP. They are developer references, not runtime dependencies. Changing a pinned revision requires reviewing its data and updating its checksum deliberately.
