"""Cross-check both native tables against the independently downloaded NativeDB fixtures."""
from pathlib import Path
import json
import sys
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / 'resource' / 'arbat16_camera'
sys.path.insert(0, str(ROOT / 'tools'))
from fetch_native_references import ensure_references
ensure_references()

for game, framework in (('gta5', 'fivem'), ('rdr3', 'redm')):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().framework = framework
    lua.execute('function GetGameName() return framework end')
    for name in ('shared/core.lua', 'client/natives.lua'):
        lua.execute((RESOURCE / name).read_text(encoding='utf-8-sig'))
    assert lua.globals().FC.Core.game == game
    assert lua.globals().FC.Natives.game == game
    database = json.loads((ROOT / 'references' / f'{game}-natives.json').read_text(encoding='utf-8-sig'))
    hashes = {int(h, 16): definition for namespace in database.values() for h, definition in namespace.items()}
    count = 0
    for name, spec in lua.globals().FC.Natives.spec.items():
        if spec.builtin:
            declaration = (ROOT / 'references' / 'IsEntityPositionFrozen.md').read_text()
            assert game == 'gta5' and name == 'IS_ENTITY_POSITION_FROZEN'
            assert spec.builtin == 'IsEntityPositionFrozen' and spec.arity == 1 and spec.return_type == 'BOOL'
            assert 'bool IS_ENTITY_POSITION_FROZEN(Entity entity);' in declaration and 'game: gta5' in declaration
            lua.execute('''
                IsEntityPositionFrozen=function(entity) assert(entity==42); return false end
                assert(FC.Natives.call('IS_ENTITY_POSITION_FROZEN',42)==false)
                IsEntityPositionFrozen=function(entity) assert(entity==42); return true end
                assert(FC.Natives.call('IS_ENTITY_POSITION_FROZEN',42)==true)
            ''')
        else:
            definition = hashes[spec.hash & 0xFFFFFFFFFFFFFFFF]
            assert definition['name'] == name, (game, name, definition['name'])
            assert spec.arity == len(definition['params']), (game, name, 'arity')
            assert spec.return_type == definition['return_type'], (game, name, 'return type')
            floats = [i + 1 for i, param in enumerate(definition['params']) if param['type'] == 'float']
            actual = list(spec.float_args.values()) if spec.float_args else []
            assert actual == floats, (game, name, 'float ABI', actual, floats)
        count += 1
    print(f'{game}: {count} native hash/name/arity/return/float contracts verified independently.')

manifest = (RESOURCE / 'fxmanifest.lua').read_text(encoding='utf-8-sig')
assert "games { 'gta5', 'rdr3' }" in manifest
assert 'rdr3_warning' in manifest
print('One manifest enables both game APIs; framework detection selects only the matching table.')
