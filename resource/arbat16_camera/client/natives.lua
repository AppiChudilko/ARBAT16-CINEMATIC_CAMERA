-- Verified native contracts: alloc8or GTA V / RDR3 NativeDB, 2026-09-25.
-- Keep separate game tables: identical names do not imply identical ABIs.
FC = FC or {}
local game = assert(FC.Core and FC.Core.game, 'Camera platform must load before natives')
local specs = {
gta5 = {
    CLEAR_FOCUS = {hash=0x31B73D1EA9F01DA2, arity=0, return_type='void'},
    CLEAR_OVERRIDE_WEATHER = {hash=0x338D2E3477711050, arity=0, return_type='void'},
    CLEAR_TIMECYCLE_MODIFIER = {hash=0x0F07E7745A236711, arity=0, return_type='void'},
    CLEAR_WEATHER_TYPE_NOW_PERSIST_NETWORK = {hash=0x0CF97F497FE7D048, arity=1, return_type='void'},
    CLEAR_WEATHER_TYPE_PERSIST = {hash=0xCCC39339BEF76CF5, arity=0, return_type='void'},
    CREATE_CAM = {hash=0xC3981DCE61D9E13F, arity=2, return_type='Cam'},
    DESTROY_CAM = {hash=0x865908C81A2C22E9, arity=2, return_type='void'},
    DISABLE_ALL_CONTROL_ACTIONS = {hash=0x5F4B6931816E599B, arity=1, return_type='void'},
    DOES_CAM_EXIST = {hash=0xA7A932170592B50E, arity=1, return_type='BOOL'},
    DOES_ENTITY_EXIST = {hash=0x7239B21A38F536BA, arity=1, return_type='BOOL'},
    FREEZE_ENTITY_POSITION = {hash=0x428CA6DBD1094446, arity=2, return_type='void'},
    GET_CAM_COORD = {hash=0xBAC038F7459AE5AE, arity=1, return_type='Vector3'},
    GET_CLOCK_HOURS = {hash=0x25223CA6B4D20B7F, arity=0, return_type='int'},
    GET_CLOCK_MINUTES = {hash=0x13D2B8ADD79640F2, arity=0, return_type='int'},
    GET_DISABLED_CONTROL_NORMAL = {hash=0x11E65974A982637C, arity=2, return_type='float'},
    GET_ENTITY_COORDS = {hash=0x3FEF770D40960D5A, arity=2, return_type='Vector3'},
    GET_ENTITY_MATRIX = {hash=0xECB2FC7235A7D137, arity=5, return_type='void'},
    GET_ENTITY_ROTATION = {hash=0xAFBD61CC738D9EB9, arity=2, return_type='Vector3'},
    GET_ENTITY_TYPE = {hash=0x8ACD366038D14505, arity=1, return_type='int'},
    GET_FINAL_RENDERED_CAM_COORD = {hash=0xA200EB1EE790F448, arity=0, return_type='Vector3'},
    GET_FINAL_RENDERED_CAM_FOV = {hash=0x80EC114669DAEFF4, arity=0, return_type='float'},
    GET_FINAL_RENDERED_CAM_ROT = {hash=0x5B4E4C817FCC2DFB, arity=1, return_type='Vector3'},
    GET_FRAME_TIME = {hash=0x15C40837039FFAF7, arity=0, return_type='float'},
    GET_GAME_TIMER = {hash=0x9CD27B0045628463, arity=0, return_type='int'},
    GET_GAMEPLAY_CAM_COORD = {hash=0x14D6F5678D8F1B37, arity=0, return_type='Vector3'},
    GET_GAMEPLAY_CAM_FOV = {hash=0x65019750A0324133, arity=0, return_type='float'},
    GET_GAMEPLAY_CAM_ROT = {hash=0x837765A25378F0BB, arity=1, return_type='Vector3'},
    GET_HASH_KEY = {hash=0xD24D37CC275948CC, arity=1, return_type='Hash'},
    GET_PREV_WEATHER_TYPE_HASH_NAME = {hash=0x564B884A05EC45A3, arity=0, return_type='Hash'},
    GET_RENDERING_CAM = {hash=0x5234F9F10919EABA, arity=0, return_type='Cam'},
    GET_SCREEN_COORD_FROM_WORLD_COORD = {hash=0x34E82F05DF2974F5, arity=5, return_type='BOOL', float_args={1,2,3}},
    GET_SHAPE_TEST_RESULT = {hash=0x3D87450E15D98694, arity=5, return_type='int'},
    GET_TIMECYCLE_MODIFIER_INDEX = {hash=0xFDF3D97C674AFB66, arity=0, return_type='int'},
    GET_VEHICLE_PED_IS_IN = {hash=0x9A9112A0FE9A4713, arity=2, return_type='Vehicle'},
    HIDE_HUD_AND_RADAR_THIS_FRAME = {hash=0x719FF505F097FD20, arity=0, return_type='void'},
    IS_CAM_ACTIVE = {hash=0xDFB2B516207D3534, arity=1, return_type='BOOL'},
    IS_CAM_RENDERING = {hash=0x02EC0AF5C5A49B7A, arity=1, return_type='BOOL'},
    IS_ENTITY_DEAD = {hash=0x5F9532F3B5CC2551, arity=2, return_type='BOOL'},
    IS_PAUSE_MENU_ACTIVE = {hash=0xB0034A223497FFCB, arity=0, return_type='BOOL'},
    NETWORK_CLEAR_CLOCK_TIME_OVERRIDE = {hash=0xD972DF67326F966E, arity=0, return_type='void'},
    NETWORK_OVERRIDE_CLOCK_TIME = {hash=0xE679E3E06E363892, arity=3, return_type='void'},
    PLAYER_ID = {hash=0x4F8644AF03D0E0D6, arity=0, return_type='Player'},
    PLAYER_PED_ID = {hash=0xD80958FC74E988A6, arity=0, return_type='Ped'},
    RENDER_SCRIPT_CAMS = {hash=0x07E5B515DB0636FC, arity=6, return_type='void'},
    SET_CAM_ACTIVE = {hash=0x026FB97D0A425F84, arity=2, return_type='void'},
    SET_CAM_COORD = {hash=0x4D41783FB745E42E, arity=4, return_type='void', float_args={2,3,4}},
    SET_CAM_DOF_STRENGTH = {hash=0x5EE29B4D7D5DF897, arity=2, return_type='void', float_args={2}},
    SET_CAM_FAR_DOF = {hash=0xEDD91296CD01AEE0, arity=2, return_type='void', float_args={2}},
    SET_CAM_FOV = {hash=0xB13C14F66A00D047, arity=2, return_type='void', float_args={2}},
    SET_CAM_NEAR_CLIP = {hash=0xC7848EFCCC545182, arity=2, return_type='void', float_args={2}},
    SET_CAM_NEAR_DOF = {hash=0x3FA4BF0A7AB7DE2C, arity=2, return_type='void', float_args={2}},
    SET_CAM_ROT = {hash=0x85973643155D0B07, arity=5, return_type='void', float_args={2,3,4}},
    SET_CAM_USE_SHALLOW_DOF_MODE = {hash=0x16A96863A17552BB, arity=2, return_type='void'},
    SET_CURR_WEATHER_STATE = {hash=0x578C752848ECFA0C, arity=3, return_type='void', float_args={3}},
    SET_FOCUS_POS_AND_VEL = {hash=0xBB7454BAFF08FE25, arity=6, return_type='void', float_args={1,2,3,4,5,6}},
    SET_TIMECYCLE_MODIFIER = {hash=0x2C933ABF17A1DF41, arity=1, return_type='void'},
    SET_TIMECYCLE_MODIFIER_STRENGTH = {hash=0x82E7FFCD5B2326B3, arity=1, return_type='void', float_args={1}},
    SET_USE_HI_DOF = {hash=0xA13B0222F3D94A94, arity=0, return_type='void'},
    SET_WEATHER_TYPE_NOW_PERSIST = {hash=0xED712CA327900C8A, arity=1, return_type='void'},
    START_SHAPE_TEST_LOS_PROBE = {hash=0x7EE9F5D83DD4F90E, arity=9, return_type='int', float_args={1,2,3,4,5,6}},
    -- https://github.com/citizenfx/fivem/blob/master/ext/native-decls/IsEntityPositionFrozen.md
    IS_ENTITY_POSITION_FROZEN = {builtin='IsEntityPositionFrozen', arity=1, return_type='BOOL'},
},
rdr3 = {
    ANIMPOSTFX_PLAY = {hash=0x4102732DF6B4005F, arity=1, return_type='void'},
    ANIMPOSTFX_STOP = {hash=0xB4FD7446BAB2F394, arity=1, return_type='void'},
    ANIMPOSTFX_IS_RUNNING = {hash=0x4A123E85D7C4CA0B, arity=1, return_type='BOOL'},
    _ANIMPOSTFX_SET_STRENGTH = {hash=0xCAB4DD2D5B2B7246, arity=2, return_type='void', float_args={2}},
    _GET_NEXT_WEATHER_TYPE_HASH_NAME = {hash=0x51021D36F62AAA83, arity=0, return_type='Hash'},
    _GET_PREV_WEATHER_TYPE_HASH_NAME = {hash=0x4BEB42AEBCA732E9, arity=0, return_type='Hash'},
    _IS_ENTITY_FROZEN = {hash=0x083D497D57B7400F, arity=1, return_type='BOOL'},
    _NETWORK_CLOCK_TIME_OVERRIDE = {hash=0x669E223E64B1903C, arity=5, return_type='void'},
    _SET_CAM_FOCUS_DISTANCE = {hash=0x11F32BB61B756732, arity=2, return_type='void', float_args={2}},
    _SET_WEATHER_TYPE_FROZEN = {hash=0xD74ACDF7DB8114AF, arity=1, return_type='void'},
    CLEAR_FOCUS = {hash=0x86CCAF7CE493EFBE, arity=0, return_type='void'},
    CLEAR_TIMECYCLE_MODIFIER = {hash=0x0E3F4AF2D63491FB, arity=0, return_type='void'},
    CLEAR_OVERRIDE_WEATHER = {hash=0x80A398F16FFE3CC3, arity=0, return_type='void'},
    CLEAR_WEATHER_TYPE_PERSIST = {hash=0xD85DFE5C131E4AE9, arity=0, return_type='void'},
    CREATE_CAM = {hash=0xE72CDBA7F0A02DD6, arity=2, return_type='Cam'},
    DESTROY_CAM = {hash=0x4E67E0B6D7FD5145, arity=2, return_type='void'},
    DISABLE_ALL_CONTROL_ACTIONS = {hash=0x5F4B6931816E599B, arity=1, return_type='void'},
    DOES_CAM_EXIST = {hash=0x153AD457764FD704, arity=1, return_type='BOOL'},
    DOES_ENTITY_EXIST = {hash=0xD42BD6EB2E0F1677, arity=1, return_type='BOOL'},
    FREEZE_ENTITY_POSITION = {hash=0x7D9EFB7AD6B19754, arity=2, return_type='void'},
    GET_CLOCK_HOURS = {hash=0xC82CF208C2B19199, arity=0, return_type='int'},
    GET_CLOCK_MINUTES = {hash=0x4E162231B823DBBF, arity=0, return_type='int'},
    GET_CAM_COORD = {hash=0x6B12F11C2A9F0344, arity=1, return_type='Vector3'},
    GET_ENTITY_COORDS = {hash=0xA86D5F069399F44D, arity=3, return_type='Vector3'},
    GET_ENTITY_MATRIX = {hash=0x3A9B1120AF13FBF2, arity=5, return_type='void'},
    GET_ENTITY_ROTATION = {hash=0xE09CAF86C32CB48F, arity=2, return_type='Vector3'},
    GET_ENTITY_TYPE = {hash=0x97F696ACA466B4E0, arity=1, return_type='int'},
    GET_FINAL_RENDERED_CAM_COORD = {hash=0x5352E025EC2B416F, arity=0, return_type='Vector3'},
    GET_FINAL_RENDERED_CAM_FOV = {hash=0x04AF77971E508F6A, arity=0, return_type='float'},
    GET_FINAL_RENDERED_CAM_ROT = {hash=0x602685BD85DD26CA, arity=1, return_type='Vector3'},
    GET_FRAME_TIME = {hash=0x5E72022914CE3C38, arity=0, return_type='float'},
    GET_DISABLED_CONTROL_NORMAL = {hash=0x11E65974A982637C, arity=2, return_type='float'},
    GET_GAME_TIMER = {hash=0x4F67E8ECA7D3F667, arity=0, return_type='int'},
    GET_TIMECYCLE_MODIFIER_INDEX = {hash=0xA705394293E2B3D3, arity=0, return_type='int'},
    GET_GAMEPLAY_CAM_COORD = {hash=0x595320200B98596E, arity=0, return_type='Vector3'},
    GET_GAMEPLAY_CAM_FOV = {hash=0xF6A96E5ACEEC6E50, arity=0, return_type='float'},
    GET_GAMEPLAY_CAM_ROT = {hash=0x0252D2B5582957A6, arity=1, return_type='Vector3'},
    GET_HASH_KEY = {hash=0xFD340785ADF8CFB7, arity=1, return_type='Hash'},
    GET_MOUNT = {hash=0xE7E11B8DCBED1058, arity=1, return_type='Ped'},
    GET_RENDERING_CAM = {hash=0x03A8931ECC8015D6, arity=0, return_type='Cam'},
    GET_SCREEN_COORD_FROM_WORLD_COORD = {hash=0xCB50D7AFCC8B0EC6, arity=5, return_type='BOOL', float_args={1,2,3}},
    GET_SHAPE_TEST_RESULT = {hash=0xEDE8AC7C5108FB1D, arity=5, return_type='int'},
    GET_VEHICLE_PED_IS_IN = {hash=0x9A9112A0FE9A4713, arity=2, return_type='Vehicle'},
    HIDE_HUD_AND_RADAR_THIS_FRAME = {hash=0x36CDD81627A6FCD2, arity=0, return_type='void'},
    IS_ENTITY_DEAD = {hash=0x7D5B1F88E7504BBA, arity=1, return_type='BOOL'},
    IS_CAM_ACTIVE = {hash=0x63EFCC7E1810B8E6, arity=1, return_type='BOOL'},
    IS_CAM_RENDERING = {hash=0x4415F8A6C536D39F, arity=1, return_type='BOOL'},
    IS_PAUSE_MENU_ACTIVE = {hash=0x535384D6067BA42E, arity=0, return_type='BOOL'},
    NETWORK_CLEAR_CLOCK_TIME_OVERRIDE = {hash=0xD972DF67326F966E, arity=0, return_type='void'},
    PLAYER_ID = {hash=0x217E9DC48139933D, arity=0, return_type='Player'},
    PLAYER_PED_ID = {hash=0x096275889B8E0EE0, arity=0, return_type='Ped'},
    RENDER_SCRIPT_CAMS = {hash=0x33281167E4942E4F, arity=6, return_type='void'},
    SET_CAM_ACTIVE = {hash=0x87295BCA613800C8, arity=2, return_type='void'},
    SET_CAM_COORD = {hash=0xF9EE7D419EE49DE6, arity=4, return_type='void', float_args={2,3,4}},
    SET_CAM_FOV = {hash=0x27666E5988D9D429, arity=2, return_type='void', float_args={2}},
    SET_CAM_NEAR_CLIP = {hash=0xA924028272A61364, arity=2, return_type='void', float_args={2}},
    SET_CAM_ROT = {hash=0x63DFA6810AD78719, arity=5, return_type='void', float_args={2,3,4}},
    SET_FOCUS_POS_AND_VEL = {hash=0x25F6EF88664540E2, arity=6, return_type='void', float_args={1,2,3,4,5,6}},
    SET_TIMECYCLE_MODIFIER = {hash=0xFA08722A5EA82DA7, arity=1, return_type='void'},
    SET_TIMECYCLE_MODIFIER_STRENGTH = {hash=0xFDB74C9CC54C3F37, arity=1, return_type='void', float_args={1}},
    SET_WEATHER_TYPE = {hash=0x59174F1AFE095B5A, arity=6, return_type='void', float_args={5}},
    START_SHAPE_TEST_LOS_PROBE = {hash=0x7EE9F5D83DD4F90E, arity=9, return_type='ScrHandle', float_args={1,2,3,4,5,6}},
}
}
FC.Natives = {game=game, spec=assert(specs[game], 'Unsupported camera platform: ' .. tostring(game))}
function FC.Natives.call(name, ...)
    local spec = assert(FC.Natives.spec[name], "Unknown " .. FC.Natives.game .. " native: " .. tostring(name))
    assert(select("#", ...) == spec.arity, "Native arity mismatch: " .. name)
    if spec.builtin then
        local native = _G[spec.builtin]
        assert(type(native)=='function', 'Missing Cfx native: ' .. spec.builtin)
        return native(...)
    end
    local args = table.pack(...)
    for _, index in ipairs(spec.float_args or {}) do args[index] = args[index] + 0.0 end
    if spec.return_type ~= "void" then
        args.n = args.n + 1; args[args.n] = Citizen.ReturnResultAnyway()
        args.n = args.n + 1
        if spec.return_type == "Vector3" then args[args.n] = Citizen.ResultAsVector()
        elseif spec.return_type == "float" then args[args.n] = Citizen.ResultAsFloat()
        else args[args.n] = Citizen.ResultAsInteger() end
    end
    if spec.return_type == "BOOL" then
        -- Preserve pointer outputs (screen projections) when normalizing BOOL.
        local result = table.pack(Citizen.InvokeNative(spec.hash, table.unpack(args, 1, args.n)))
        result[1] = result[1] ~= nil and result[1] ~= false and result[1] ~= 0
        return table.unpack(result, 1, result.n)
    end
    return Citizen.InvokeNative(spec.hash, table.unpack(args, 1, args.n))
end
