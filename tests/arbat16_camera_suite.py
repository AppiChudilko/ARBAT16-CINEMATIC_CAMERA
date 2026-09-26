"""Run the resource's offline release checks from any working directory."""
from pathlib import Path
import re
import os
import shutil
import subprocess
import sys
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / 'resource' / 'arbat16_camera'

for path in RESOURCE.rglob('*.lua'):
    LuaRuntime().execute('assert(load(...))', path.read_text(encoding='utf-8-sig'))
print('Lua syntax: all resource files compile', flush=True)

for game in ('rdr3', 'gta5'):
    print(f'Testing {game} model, storage and runtime', flush=True)
    for name in ('arbat16_camera_core_spec.lua', 'arbat16_camera_director_spec.lua', 'arbat16_camera_take_spec.lua', 'arbat16_camera_flight_spec.lua', 'arbat16_camera_server_spec.lua'):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().arg = lua.table_from([str(RESOURCE / 'server' / 'main.lua')])
        lua.globals().TEST_GAME = game
        if name.endswith('_server_spec.lua'):
            lua.execute("function GetGameName() return 'fxserver' end; function GetConvar(name,default) return name=='gamename' and TEST_GAME or default end")
        else:
            lua.execute("function GetGameName() return TEST_GAME=='gta5' and 'fivem' or 'redm' end")
        previous = Path.cwd()
        try:
            os.chdir(ROOT)
            lua.execute((ROOT / 'tests' / name).read_text(encoding='utf-8-sig'))
        finally:
            os.chdir(previous)
    subprocess.run([sys.executable, str(ROOT / 'tests' / 'arbat16_camera_runtime_spec.py'), game], check=True)

subprocess.run([sys.executable, str(ROOT / 'tests' / 'arbat16_camera_platform_spec.py')], check=True)
node = shutil.which('node')
if not node:
    raise RuntimeError('Node.js is required for the NUI checks.')
for name in ('app.js', 'model.js', 'director.js'):
    subprocess.run([node, '--check', str(RESOURCE / 'web' / name)], check=True)
subprocess.run([node, '--test', str(ROOT / 'tests' / 'arbat16_camera_model.test.cjs')], check=True)
for game in ('gta5', 'rdr3'):
    subprocess.run([node, '--test', str(ROOT / 'tests' / 'arbat16_camera_nui.test.cjs')],
                   env={**os.environ, 'CAMERA_GAME': game}, check=True)

html = (RESOURCE / 'web/index.html').read_text(encoding='utf-8-sig')
css = (RESOURCE / 'web/style.css').read_text(encoding='utf-8-sig')
app = (RESOURCE / 'web/app.js').read_text(encoding='utf-8-sig')
assert '<html lang="en">' in html
assert re.search(r'<main\b[^>]*\bid="editor"[^>]*\bhidden\b', html)
assert re.search(r'html\s*,\s*body\s*\{[^}]*background\s*:\s*transparent', css)
for text in (html, css, app):
    for removed in ('preview-world', 'demoFrame', 'function simulate(', 'localStorage', 'mountain far', 'frontier-camera-preview'):
        assert removed not in text, f'Browser simulation remains: {removed}'
for path in RESOURCE.rglob('*'):
    if path.suffix in {'.lua', '.js', '.html', '.css'}:
        assert not re.search('[\u0400-\u04ff]', path.read_text(encoding='utf-8-sig')), f'Non-English production string: {path}'
assert 'GetParentResourceName' in app
for source in re.findall(r'(?:src|href)="([^"]+)"', html):
    if source.startswith(('http:', 'https:')):
        raise AssertionError('External NUI asset: ' + source)
    assert (RESOURCE / 'web' / source).is_file(), source
print('NUI packaging: English, transparent, hidden at startup, no browser simulator or external assets', flush=True)
print('All offline release checks passed for FiveM and RedM. Live client checks remain required.', flush=True)
