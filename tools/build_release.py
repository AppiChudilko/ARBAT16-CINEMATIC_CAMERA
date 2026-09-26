"""Build an allowlisted, deterministic resource ZIP without logs or development files."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / 'resource' / 'arbat16_camera'
FILES = (
    'fxmanifest.lua', 'config.lua', 'README.md', 'CHANGELOG.md',
    'LICENSE.txt', 'THIRD_PARTY_NOTICES.md', 'docs/LICENSE-FAQ.md',
    'client/main.lua', 'client/natives.lua', 'client/director.lua',
    'server/main.lua', 'shared/core.lua', 'shared/director.lua', 'shared/flight.lua',
    'web/index.html', 'web/style.css', 'web/app.js', 'web/model.js', 'web/director.js',
    'web/fonts/inter-latin.woff2', 'web/fonts/OFL-Inter.txt',
)


def keep_or_create(path, content):
    if path.exists():
        if path.read_bytes() != content:
            raise RuntimeError(f'Refusing to overwrite an existing different release: {path.name}')
    else:
        with path.open('xb') as output:
            output.write(content)


def build(output):
    manifest = (RESOURCE / 'fxmanifest.lua').read_text(encoding='utf-8-sig')
    assert "games { 'gta5', 'rdr3' }" in manifest, 'The release must support both games'
    assert 'rdr3_warning' in manifest, 'RedM manifest acknowledgement is required'
    version = re.search(r"(?m)^version\s+'(\d+\.\d+\.\d+)'", manifest).group(1)
    buffers = {}
    for relative in FILES:
        path = RESOURCE / relative
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(RESOURCE.resolve()):
            raise RuntimeError(f'Missing or unsafe package file: {relative}')
        data = path.read_bytes()
        if path.suffix.lower() in {'.lua', '.js', '.html', '.css', '.md', '.txt'}:
            content = data.decode('utf-8-sig').replace('\r\n', '\n').replace('\r', '\n')
            for pattern in (r'(?i)[A-Z]:[\\/]Users[\\/]', r'ar16_fcam', r'gh[pousr]_[A-Za-z0-9]{20,}',
                            r'github_pat_[A-Za-z0-9_]{20,}', r'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----',
                            r'https://(?:discord(?:app)?\.com)/api/webhooks/'):
                if re.search(pattern, content):
                    raise RuntimeError(f'Private data or retired command found in {relative}')
            data = content.encode('utf-8')
        buffers[relative] = data
    archive_buffer = io.BytesIO()
    with zipfile.ZipFile(archive_buffer, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, data in sorted(buffers.items()):
            entry = zipfile.ZipInfo('arbat16_camera/' + relative, date_time=(2020, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    payload = archive_buffer.getvalue()
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == {'arbat16_camera/' + name for name in FILES}
        for relative, data in buffers.items():
            assert archive.read('arbat16_camera/' + relative) == data
    output.mkdir(parents=True, exist_ok=True)
    name = f'arbat16_camera-v{version}.zip'
    digest = hashlib.sha256(payload).hexdigest()
    keep_or_create(output / name, payload)
    keep_or_create(output / f'{name}.sha256', f'{digest}  {name}\n'.encode())
    metadata = {'version': version, 'games': ['gta5', 'rdr3'], 'archive': name, 'sha256': digest, 'bytes': len(payload),
                'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(buffers.items())}}
    keep_or_create(output / f'arbat16_camera-v{version}-manifest.json',
                   (json.dumps(metadata, indent=2) + '\n').encode())
    print(f'Built {output / name}: {len(FILES)} verified files, {len(payload)} bytes')
    print(f'SHA-256: {digest}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    build(parser.parse_args().output.resolve())
