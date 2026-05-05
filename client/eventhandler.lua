---@param soundData SoundDataWithEntity | SoundDataWithLocation
RegisterNetEvent("zyke_sounds:PlaySound", function(soundData)
    PlaySoundData(soundData)
end)

---@param passed {event: string, data: any}
---@param callback fun(response: any)
RegisterNUICallback("Eventhandler", function(passed, callback)
    local event = passed.event
    local data = passed.data

    if (event == "SoundMetadata") then
        if (type(data) == "table" and data.reportEvents == true) then
            TriggerServerEvent("zyke_sounds:SoundMetadata", data)
        end

        return callback("ok")
    elseif (event == "SoundEnded") then
        if (type(data) ~= "table") then return callback("ok") end
        if (type(data.soundId) ~= "string") then return callback("ok") end

        local activeSound = Cache.activeSounds[data.soundId]

        if (not activeSound or activeSound.iteration == data.iteration) then
            Cache.activeSounds[data.soundId] = nil
        end

        if (data.reportEvents == true) then
            TriggerServerEvent("zyke_sounds:SoundEnded", data)
        end

        return callback("ok")
    elseif (event == "CloseMenu") then
        SetNuiFocus(false, false)

        return callback("ok")
    elseif (event == "GetStrings") then return callback(Translations)
    elseif (event == "GetSoundsList") then return callback(GetSoundsList())
    elseif (event == "SetSoundVolume") then
        SetSoundVolume(data.name, data.volume)

        return callback("ok")
    elseif (event == "GetPresets") then return callback(GetPresets())
    end
end)

---@param soundId string
---@param fade? number
---@param forceFull? boolean
RegisterNetEvent("zyke_sounds:StopSound", function(soundId, fade, forceFull)
    StopSound(soundId, fade, forceFull)
end)

local seenStateBagSounds = {}
local activeStateBagSounds = {}
local activeEntityStateKey = "zyke_sounds:active"

-- seenStateBagSounds dedupes short emit-slot one-shots so scope replays do not
-- replay old cough/open/beep sounds.
-- activeStateBagSounds remembers which tracked entity sounds were last present
-- for each state bag, so missing ids can be stopped locally.

---@param soundId string
local function forgetStateBagSound(soundId)
    local ttlMs = math.max(1000, tonumber(Config.Settings.oneShotStateBagTtlMs) or 10000)

    -- Expires the state bag sound dedupe entry.
    CreateThread(function()
        Wait(ttlMs + 1000)
        seenStateBagSounds[soundId] = nil
    end)
end

---@param payload table
---@param serverTime integer
---@return boolean
local function isStateBagSoundExpired(payload, serverTime)
    return type(payload.expiresAt) == "number" and serverTime > payload.expiresAt
end

---@param bagName string
---@return integer?
local function resolveStateBagEntity(bagName)
    local entity = GetEntityFromStateBagName(bagName)
    local attempts = 0

    if (not entity or entity == 0 or not DoesEntityExist(entity)) then
        local player = GetPlayerFromStateBagName(bagName)

        if (type(player) == "number" and player ~= -1) then
            entity = GetPlayerPed(player)
        end
    end

    while ((not entity or entity == 0 or not DoesEntityExist(entity)) and attempts < 20) do
        attempts = attempts + 1
        Wait(50)
        entity = GetEntityFromStateBagName(bagName)

        if (not entity or entity == 0 or not DoesEntityExist(entity)) then
            local player = GetPlayerFromStateBagName(bagName)

            if (type(player) == "number" and player ~= -1) then
                entity = GetPlayerPed(player)
            end
        end
    end

    if (
        not entity
        or entity == 0
        or not DoesEntityExist(entity)
    ) then
        return nil
    end

    return entity
end

-- Plays a short entity sound received through a replicated state bag payload.
---@param bagName string
---@param payload table
local function handleStateBagEntitySound(bagName, payload)
    if (
        type(payload) ~= "table"
        or type(payload.soundId) ~= "string"
        or type(payload.soundName) ~= "string"
        or type(payload.seq) ~= "number"
        or seenStateBagSounds[payload.soundId]
    ) then
        return
    end

    local serverTime = tonumber(GlobalState["OsTime"])
    if (serverTime and isStateBagSoundExpired(payload, serverTime)) then return end

    -- Dedupe per sound id because state bag handlers can replay during scope changes.
    seenStateBagSounds[payload.soundId] = true
    forgetStateBagSound(payload.soundId)

    -- Resolves the state bag entity before playing the one-shot sound.
    CreateThread(function()
        local entity = resolveStateBagEntity(bagName)
        if (not entity) then return end

        serverTime = tonumber(GlobalState["OsTime"])
        if (isStateBagSoundExpired(payload, serverTime)) then return end

        local entityNetId = NetworkGetNetworkIdFromEntity(entity)
        if (not entityNetId or entityNetId == 0) then return end

        PlaySoundData({
            soundId = payload.soundId,
            soundType = "entity",
            soundName = payload.soundName,
            maxVolume = tonumber(payload.maxVolume) or 0.3,
            maxDistance = tonumber(payload.maxDistance) or 10.0,
            entityNetId = entityNetId,
            looped = false,
            invoker = payload.invoker,
            iteration = payload.seq,
            offsetMs = 0,
            reportEvents = false
        })
    end)
end

---@param bagName string
---@param payloads table | nil
local function handleActiveEntitySounds(bagName, payloads)
    CreateThread(function()
        local currentSounds = {}
        local entity
        local entityNetId
        local hasPlayablePayload = false
        local shouldSyncPrevious = true

        if (type(payloads) == "table" and next(payloads) ~= nil) then
            for _, payload in pairs(payloads) do
                if (type(payload) == "table" and payload.stopped == true and type(payload.soundId) == "string") then
                    StopSound(payload.soundId, tonumber(payload.fade) or 0, payload.forceFull == true)
                elseif (
                    type(payload) == "table"
                    and type(payload.soundId) == "string"
                    and type(payload.soundName) == "string"
                    and type(payload.iteration) == "number"
                ) then
                    hasPlayablePayload = true
                end
            end

            if (hasPlayablePayload) then
                entity = resolveStateBagEntity(bagName)

                if (entity) then
                    entityNetId = NetworkGetNetworkIdFromEntity(entity)
                else
                    shouldSyncPrevious = false
                end
            end
        end

        if (entityNetId and entityNetId ~= 0) then
            for _, payload in pairs(payloads) do
                if (
                    type(payload) == "table"
                    and type(payload.soundId) == "string"
                    and type(payload.soundName) == "string"
                    and type(payload.iteration) == "number"
                ) then
                    currentSounds[payload.soundId] = true
                    local ownerServerId = tonumber(payload.ownerServerId)

                    PlaySoundData({
                        soundId = payload.soundId,
                        soundType = "entity",
                        soundName = payload.soundName,
                        maxVolume = tonumber(payload.maxVolume) or 0.3,
                        maxDistance = tonumber(payload.maxDistance) or 10.0,
                        entityNetId = entityNetId,
                        looped = payload.looped == true,
                        invoker = payload.invoker,
                        iteration = payload.iteration,
                        offsetMs = tonumber(payload.offsetMs) or 0,
                        reportEvents = ownerServerId == nil or ownerServerId == GetPlayerServerId(PlayerId()),
                        stateBagManaged = true,
                        stateBagName = bagName
                    })
                end
            end
        end

        local previousSounds = activeStateBagSounds[bagName] or {}

        if (shouldSyncPrevious) then
            for soundId in pairs(previousSounds) do
                if (not currentSounds[soundId]) then
                    StopSound(soundId)
                end
            end

            activeStateBagSounds[bagName] = next(currentSounds) and currentSounds or nil
        end
    end)
end

local stateBagEmitSlots = math.max(1, math.floor(tonumber(Config.Settings.stateBagEmitSlots) or 4))

-- Each slot is a separate state key so rapid one-shots are not collapsed.
for slot = 0, stateBagEmitSlots - 1 do
    ---@param bagName string
    ---@param stateKey string
    ---@param value any
    AddStateBagChangeHandler(("zyke_sounds:emit:%d"):format(slot), nil, function(bagName, stateKey, value)
        handleStateBagEntitySound(bagName, value)
    end)
end

AddStateBagChangeHandler(activeEntityStateKey, nil, function(bagName, stateKey, value)
    handleActiveEntitySounds(bagName, value)
end)

-- Requests the server snapshot for location sounds the player should hear.
local function requestSoundSnapshot()
    TriggerServerEvent("zyke_sounds:RequestSnapshot")
end

-- Requests the initial location sound snapshot after the client starts.
CreateThread(function()
    Wait(500)
    requestSoundSnapshot()
end)

---@param resource string
AddEventHandler("onClientResourceStart", function(resource)
    if (resource ~= GetCurrentResourceName()) then return end

    -- Requests a fresh snapshot after this resource restarts.
    CreateThread(function()
        Wait(500)
        requestSoundSnapshot()
    end)
end)

-- Refreshes sound state after the player spawns.
AddEventHandler("playerSpawned", function()
    requestSoundSnapshot()
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    local soundIds = {}
    local presetNames = {}

    for soundId, soundData in pairs(Cache.activeSounds) do
        if (soundData.invoker == resource) then
            soundIds[#soundIds + 1] = soundId
        end
    end

    for name, preset in pairs(Cache.presets) do
        if (preset.invoker == resource) then
            presetNames[#presetNames + 1] = name
        end
    end

    for i = 1, #soundIds do
        StopSound(soundIds[i])
    end

    for i = 1, #presetNames do
        Cache.presets[presetNames[i]] = nil
    end
end)