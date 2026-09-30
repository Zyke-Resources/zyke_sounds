local volumeUpdateInterval = math.max(10, tonumber(Config.Settings.volumeUpdateInterval) or 100)
local isUpdatingVolume = false
local spatialSettings = Config.Settings.spatialAudio or {}
local occlusionSettings = spatialSettings.occlusion or {}
local vehicleSettings = spatialSettings.vehicle or {}
-- Low-pass cutoff in Hz that leaves a sound untouched
local openLowpass = 22000.0

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

---@param a vector3
---@param b vector3
---@return number
local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

---@param soundData SoundDataWithLocation | SoundDataWithEntity
---@return vector3? position
---@return integer? entity
local function getSoundSourcePosition(soundData)
    if (soundData.soundType == "location") then return soundData.location end
    if (not soundData.entityNetId or not NetworkDoesNetworkIdExist(soundData.entityNetId)) then return nil end

    local entity = NetworkGetEntityFromNetworkId(soundData.entityNetId)
    if (not entity or entity == 0 or not DoesEntityExist(entity)) then return nil end

    return GetEntityCoords(entity), entity
end

-- Rays per check at most, one plus each ignored entity it may pass through
local maxOcclusionRays = 4

-- Only world geometry counts, so the vehicle or ped carrying the sound never muffles it.
-- Ignored entities cost another ray only when one is actually in the way, carrying on from where it was hit
---@param from vector3
---@param to vector3
---@param entity? integer
---@param ignored? table<integer, true> @ Entities this sound passes through
---@return boolean occluded
local function isSoundOccluded(from, to, entity, ignored)
    to = vector3(to.x, to.y, to.z + 0.3)
    local direction = norm(to - from)
    local skip = entity or 0

    for _ = 1, maxOcclusionRays do
        local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1, skip, 7)
        local _, hit, hitPos, _, hitEntity = GetShapeTestResult(handle)
        if (hit ~= 1) then return false end
        if (hitEntity ~= entity and not (ignored and ignored[hitEntity])) then return true end

        -- The probe skips one entity, so the next one starts past this hit instead of at the camera
        skip = hitEntity
        from = hitPos + direction * 0.01
    end

    -- Everything hit so far was ignored
    return false
end

-- Vehicle classes without a cabin: motorcycles, cycles and boats
local openVehicleClasses = {[8] = true, [13] = true, [14] = true}

-- Open vehicles and lowered convertible roofs let sounds through untouched
---@param vehicle integer
---@return boolean
local function isVehicleClosed(vehicle)
    if (openVehicleClasses[GetVehicleClass(vehicle)]) then return false end
    if (IsVehicleAConvertible(vehicle, false) and GetConvertibleRoofState(vehicle) ~= 0) then return false end

    return true
end

-- Only peds count, sounds on the vehicle itself (engine bay, flatbed hydraulics) are outside the cabin
---@param entity? integer
---@param vehicle integer
---@return boolean
local function isInsideVehicle(entity, vehicle)
    if (not entity or not IsEntityAPed(entity)) then return false end

    return GetVehiclePedIsIn(entity, false) == vehicle
end

-- Direction from the camera to the sound in Web Audio's listener space (+X right, +Y up, -Z ahead),
-- plus how muffled it is. nil keeps the sound centred, as for sounds on the player's own ped.
-- Left/right panning can not tell ahead from behind, so sounds behind are muffled like a head shadow
---@param soundData SoundDataWithLocation | SoundDataWithEntity
---@param volume number
---@return NUISpatialData? spatial
local function getSoundSpatial(soundData, volume)
    if (spatialSettings.enabled ~= true) then return nil end

    local ped = PlayerPedId()
    local sourcePos, entity = getSoundSourcePosition(soundData)
    if (not sourcePos or entity == ped) then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local sharesVehicle = vehicle ~= 0 and isInsideVehicle(entity, vehicle)

    local camPos = GetFinalRenderedCamCoord()
    local offset = sourcePos - camPos
    local distance = #offset
    if (distance < 0.5) then return nil end

    local camRot = GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(camRot.x), math.rad(camRot.z)
    local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local up = vector3(right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x)
    local direction = offset / distance

    ---@type NUISpatialData
    local spatial = {
        x = dot(direction, right),
        y = dot(direction, up),
        z = -dot(direction, forward),
        gain = 1.0,
    }

    local rearLowpass = tonumber(spatialSettings.rearLowpass)
    if (rearLowpass and spatial.z > 0.0) then
        -- Eases from open straight to the side down to rearLowpass directly behind
        spatial.lowpass = openLowpass * (math.max(100.0, rearLowpass) / openLowpass) ^ spatial.z
    end

    -- Inside a vehicle the cabin muffles everything outside it evenly, so the ray is skipped.
    -- Sounds within the same vehicle skip the ray too, as it would hit the vehicle itself
    local muffle
    local ignore = soundData.occlusionIgnore and Cache.occlusionIgnores[soundData.occlusionIgnore]
    if (vehicle ~= 0 and not sharesVehicle and vehicleSettings.enabled == true and isVehicleClosed(vehicle)) then
        muffle = vehicleSettings
    elseif (not sharesVehicle and occlusionSettings.enabled == true and volume > 0.0 and isSoundOccluded(camPos, sourcePos, entity, ignore and ignore.entities)) then
        -- Silent sounds skip the ray, it is the only costly part
        muffle = occlusionSettings
    end

    if (muffle) then
        spatial.gain = math.max(0.0, math.min(1.0, tonumber(muffle.volume) or 0.6))
        spatial.lowpass = math.min(spatial.lowpass or openLowpass, math.max(100.0, tonumber(muffle.lowpass) or 1000.0))
    end

    return spatial
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
        spatial = getSoundSpatial(soundData, volume),
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
            volume = volume or 0.0,
            spatial = getSoundSpatial(soundData, volume or 0.0)
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