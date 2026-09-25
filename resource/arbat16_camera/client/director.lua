-- The game has one timecycle slot. Only clear it while it still holds our index.
-- A different resource taking ownership is not overwritten by per-frame updates.
FC.DirectorRuntime = {}
local R, D, N = FC.DirectorRuntime, FC.Director, FC.Natives
local filters = {}
for _, item in ipairs(D.filters) do filters[item.id] = item end
local ownedIndex, ownedPostfx, selectedFilter, selectedStrength, warned
local function attempt(fn)
    local ok, err = pcall(fn)
    if not ok and not warned then
        warned = true
        print('[arbat16_camera] Director filter could not be applied: '..tostring(err))
    end
    return ok
end
local function clearOwned()
    if ownedIndex ~= nil then
        if N.call('GET_TIMECYCLE_MODIFIER_INDEX') == ownedIndex then N.call('CLEAR_TIMECYCLE_MODIFIER') end
        ownedIndex = nil
    end
end
local function stopOwnedPostfx()
    if ownedPostfx then
        -- No STOP_ALL: other resources may have unrelated photo or gameplay FX.
        N.call('ANIMPOSTFX_STOP',ownedPostfx)
        ownedPostfx=nil
    end
end
function R.apply(director)
    local look = director and director.look or D.defaults().look
    if look.filter == selectedFilter and look.strength == selectedStrength then return true end
    local ok = attempt(function()
        if look.filter == 'none' or look.strength <= 0 then clearOwned();stopOwnedPostfx()
        else
            local filter = assert(filters[look.filter], 'Unknown director filter')
            if filter.postfx then
                clearOwned()
                if ownedPostfx and ownedPostfx~=filter.postfx then stopOwnedPostfx() end
                if not ownedPostfx and not N.call('ANIMPOSTFX_IS_RUNNING',filter.postfx) then
                    -- Reserve cleanup ownership before starting, even if the
                    -- native throws after changing its game-side state.
                    ownedPostfx=filter.postfx
                    N.call('ANIMPOSTFX_PLAY',ownedPostfx)
                end
                -- A pre-existing copy of this effect belongs to its caller;
                -- neither its strength nor its lifecycle is changed here.
                if ownedPostfx then N.call('_ANIMPOSTFX_SET_STRENGTH',ownedPostfx,look.strength) end
            else
                stopOwnedPostfx()
                local modifier=assert(filter.modifier,'Unknown director timecycle')
                -- Changing a look is an explicit user action; it may take the slot.
                if selectedFilter ~= look.filter or ownedIndex == nil or N.call('GET_TIMECYCLE_MODIFIER_INDEX') ~= ownedIndex then
                    N.call('SET_TIMECYCLE_MODIFIER', modifier)
                    local index = N.call('GET_TIMECYCLE_MODIFIER_INDEX')
                    ownedIndex = type(index) == 'number' and index >= 0 and index or nil
                end
                if ownedIndex ~= nil then N.call('SET_TIMECYCLE_MODIFIER_STRENGTH', look.strength) end
            end
        end
    end)
    -- Avoid retrying a failing native every frame; a changed selection retries.
    selectedFilter, selectedStrength = look.filter, look.strength
    return ok
end
function R.cleanup()
    local ok = attempt(clearOwned)
    local postfxOk=attempt(stopOwnedPostfx)
    ownedIndex, ownedPostfx, selectedFilter, selectedStrength = nil, nil, nil, nil
    return ok and postfxOk
end
function R.pose(base, director, elapsed) return D.motionPose(base,director,elapsed) end
return R
