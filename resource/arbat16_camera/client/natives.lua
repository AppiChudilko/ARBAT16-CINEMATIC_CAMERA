-- RDR3 signatures verified against alloc8or/rdr3-nativedb-data on 2026-09-24.
-- No GTA-only natives or undocumented DOF pointer buffers.
FC = FC or {}
FC.Natives = {spec = {
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
}}
function FC.Natives.call(name, ...)
    local spec = assert(FC.Natives.spec[name], "Unknown RedM native: " .. tostring(name))
    assert(select("#", ...) == spec.arity, "Native arity mismatch: " .. name)
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
