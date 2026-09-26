"""Fetch development-only native references pinned by commit and SHA-256."""
from pathlib import Path
import hashlib
import json
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REFERENCE_ROOT = ROOT / 'references'
FILES = {'gta5-natives.json', 'rdr3-natives.json', 'GetGameName.md', 'IsEntityPositionFrozen.md'}


def ensure_references():
    manifest = json.loads((REFERENCE_ROOT / 'sources.json').read_text(encoding='utf-8'))
    references = manifest['references']
    if set(references) != FILES:
        raise RuntimeError('Unexpected native-reference manifest entries')
    for name, reference in references.items():
        source, expected = reference['source'], reference['sha256']
        if not re.fullmatch(r'https://raw\.githubusercontent\.com/(?:alloc8or/(?:gta5|rdr3)-nativedb-data|citizenfx/fivem)/[0-9a-f]{40}/[A-Za-z0-9_./-]+', source):
            raise RuntimeError(f'Unpinned reference URL: {name}')
        if not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise RuntimeError(f'Invalid reference digest: {name}')
        destination = REFERENCE_ROOT / name
        if destination.is_file():
            data = destination.read_bytes()
        else:
            with urllib.request.urlopen(source, timeout=30) as response:
                data = response.read(8 * 1024 * 1024 + 1)
            if len(data) > 8 * 1024 * 1024:
                raise RuntimeError(f'Oversized native reference: {name}')
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f'Native reference checksum mismatch: {name}')
        if not destination.exists():
            destination.write_bytes(data)
            print(f'Cached verified reference: {name}')


if __name__ == '__main__':
    ensure_references()
    print('All four native references match their pinned checksums.')
