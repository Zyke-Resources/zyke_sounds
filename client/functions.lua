local volumeUpdateInterval = math.max(10, tonumber(Config.Settings.volumeUpdateInterval) or 100)
local isUpdatingVolume = false

---@param bagName? string
---@return integer?
local function getStateBagEntityNow(bagName)
    if (type(bagName) ~= "string") then return nil end

    local entity = GetEntityFromStateBagName(bagName)
    if (entity and entity ~= 0 and DoesEntityExist(entity)) then return entity end

    local player = GetPlayerFromStateBagName(bagName)
    if (type(player) == "number" and player ~= -1) then
        local ped = GetPlayerPed(player)

        if (ped and ped ~= 0 and DoesEntityExist(ped)) then return ped end
    end

    return nil
end

-- Updates active sound volumes while any sound is playing.
function UpdateSoundVolumeLoop()
    if (isUpdatingVolume) then return end

    isUpdatingVolume = true

    while (Z.table.getFirstDictionaryKey(Cache.activeSounds) ~= nil) do
        local soundIds = {}

        for soundId in pairs(Cache.activeSounds) do
            soundIds[#soundIds + 1] = soundId
        end

        for i = 1, #soundIds do
            UpdateSoundVolume(soundIds[i])
        end

        Wait(volumeUpdateInterval)
    end

    isUpdatingVolume = false
end

---@param playerPos vector3
---@param soundData SoundDataWithLocation | SoundDataWithEntity
---@return number?
function GetSoundVolume(playerPos, soundData)
    local multiplier = GetVolumeMultiplier(soundData.soundName)

    if (soundData.soundType == "location") then
        local distance = #(playerPos - soundData.location)
        local maxDistance = tonumber(soundData.maxDistance) or 0

        if (Config.Settings.debug and Cache.activeSounds[soundData.soundId]) then
            Cache.activeSounds[soundData.soundId].pos = soundData.location
        end

        if (maxDistance <= 0 or distance > maxDistance) then return 0.0 end

        return math.min(1.0, soundData.maxVolume * (1.0 - (distance / maxDistance)) * multiplier)
    elseif (soundData.soundType == "entity") then
        if (
            (not soundData.entityNetId or not NetworkDoesNetworkIdExist(soundData.entityNetId))
            and soundData.stateBagName
        ) then
            local entity = getStateBagEntityNow(soundData.stateBagName)

            if (entity) then
                soundData.entityNetId = NetworkGetNetworkIdFromEntity(entity)
            end
        end

        if (not soundData.entityNetId or not NetworkDoesNetworkIdExist(soundData.entityNetId)) then return 0.0 end

        local entity = NetworkGetEntityFromNetworkId(soundData.entityNetId)
        local entityPosition = GetEntityCoords(entity)

        if (Config.Settings.debug and Cache.activeSounds[soundData.soundId]) then
            Cache.activeSounds[soundData.soundId].pos = entityPosition
        end

        local distance = #(playerPos - entityPosition)
        local maxDistance = tonumber(soundData.maxDistance) or 0

        if (maxDistance <= 0 or distance > maxDistance) then return 0.0 end

        return math.min(1.0, soundData.maxVolume * (1.0 - (distance / maxDistance)) * multiplier)
    end
end

---@param soundData SoundDataWithLocation | SoundDataWithEntity
---@return boolean
function PlaySoundData(soundData)
    if (
        type(soundData) ~= "table"
        or type(soundData.soundId) ~= "string"
        or type(soundData.soundName) ~= "string"
    ) then
        return false
    end

    local playerPos = GetEntityCoords(PlayerPedId())
    local volume = GetSoundVolume(playerPos, soundData)
    if (not volume) then return false end

    local existingSound = Cache.activeSounds[soundData.soundId]
    local shouldStartAudio = (
        not existingSound
        or existingSound.soundName ~= soundData.soundName
        or existingSound.iteration ~= soundData.iteration
    )

    Cache.activeSounds[soundData.soundId] = soundData

    if (not shouldStartAudio) then
        UpdateSoundVolume(soundData.soundId)
        UpdateSoundVolumeLoop()

        return true
    end

    ---@type NUISoundData
    local nuiSoundData = {
        soundId = soundData.soundId,
        soundName = soundData.soundName,
        volume = volume,
        looped = soundData.looped == true,
        iteration = soundData.iteration,
        offsetMs = soundData.offsetMs or 0,
        reportEvents = soundData.reportEvents == true
    }

    SendNUIMessage({
        event = "PlaySound",
        data = nuiSoundData
    })

    UpdateSoundVolumeLoop()

    return true
end

---@param soundId string
function UpdateSoundVolume(soundId)
    local soundData = Cache.activeSounds[soundId]
    if (not soundData) then return end

    local playerPos = GetEntityCoords(PlayerPedId())
    local volume = GetSoundVolume(playerPos, soundData)
    local now = GetGameTimer()

    if (soundData.soundType == "entity" and soundData.stateBagManaged == true) then
        if (not soundData.entityNetId or not NetworkDoesNetworkIdExist(soundData.entityNetId)) then
            soundData.missingEntitySince = soundData.missingEntitySince or now

            if (now - soundData.missingEntitySince >= math.max(500, tonumber(Config.Settings.stateBagEntityStaleMs) or 2500)) then
                StopSound(soundId)

                return
            end
        else
            soundData.missingEntitySince = nil
        end
    end

    SendNUIMessage({
        event = "UpdateSoundVolume",
        data = {
            soundId = soundId,
            volume = volume or 0.0
        }
    })
end

-- Plays a looped local preview sound until stopped.
---@param soundName string
---@param volume number @ 0.0-1.0
function BasicSoundPreview(soundName, volume)
    ---@type NUISoundData
    local soundData = {
        soundId = "BASIC_SOUND_PREVIEW",
        soundName = soundName,
        volume = volume,
        looped = true
    }

    SendNUIMessage({
        event = "PlaySound",
        data = soundData
    })
end

-- Stops the active local preview sound.
function StopBasicSoundPreview()
    SendNUIMessage({
        event = "StopSound",
        data = {soundId = "BASIC_SOUND_PREVIEW"}
    })
end

exports("BasicSoundPreview", BasicSoundPreview)
exports("StopBasicSoundPreview", StopBasicSoundPreview)

---@param soundId string
---@param fade? number
---@param forceFull? boolean
function StopSound(soundId, fade, forceFull)
    if (type(soundId) ~= "string") then return end

    Cache.activeSounds[soundId] = nil

    SendNUIMessage({
        event = "StopSound",
        data = {
            soundId = soundId,
            fade = fade,
            forceFull = forceFull
        }
    })
end