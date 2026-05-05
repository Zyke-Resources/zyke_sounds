math.randomseed(os.time())

---@class CacheData
---@field activeSounds table<string, ServerSoundData>
---@field playerBuckets table<integer, integer>
---@field playerSounds table<integer, table<string, integer>>
---@field stateBagOneShots table<string, ServerStateBagOneShotData>
---@field soundDurations table<string, integer>
Cache = {
    -- Sound lifecycle registry keyed by sound id. Location sounds are fully server-managed from here.
    -- Entity sounds only stay here when they need lifecycle control, scheduling, or explicit StopSound support.
    activeSounds = {},

    -- Last routing bucket seen for each player. Used to refresh location sound visibility when a player changes bucket.
    playerBuckets = {},

    -- Location sounds currently sent to each player, stored as player id -> sound id -> iteration.
    -- Prevents duplicate location sends and identifies who needs a direct StopSound when a location sound leaves range.
    playerSounds = {},

    -- Temporary bookkeeping for fire-and-forget entity one-shots keyed by returned sound id.
    -- Points back to the emit statebag slot so StopSound(soundId) can clear/cancel the payload before its TTL expires.
    stateBagOneShots = {},

    -- Client-reported audio durations keyed by selected sound file.
    -- Used to schedule non-looped endings and calculate offsets for late receivers.
    soundDurations = {}
}

local soundIdCounter = 0
local stateBagEmitSeq = 0
local stateBagStopSeq = 0
local activeEntityStateKey = "zyke_sounds:active"
local soundsPath = GetResourcePath(GetCurrentResourceName()) .. "/nui/sounds/"

---@type table<string, boolean> @ File name, exists
local loadedSounds = {}

---@return string
function GetDefaultSoundId()
    soundIdCounter = soundIdCounter + 1

    return "sound-" .. soundIdCounter
end

---@param soundName string | string[]
---@return string | string[] | nil
local function copySoundName(soundName)
    if (type(soundName) ~= "table") then return soundName end

    local copiedSoundNames = {}

    for i = 1, #soundName do
        copiedSoundNames[i] = soundName[i]
    end

    return copiedSoundNames
end

---@param options? table
---@return table
local function copyOptions(options)
    local copiedOptions = {}

    if (type(options) ~= "table") then return copiedOptions end

    for key, value in pairs(options) do
        copiedOptions[key] = value
    end

    return copiedOptions
end

---@param tableData? table
---@return table
local function copyTable(tableData)
    local copiedTable = {}

    if (type(tableData) ~= "table") then return copiedTable end

    for key, value in pairs(tableData) do
        copiedTable[key] = value
    end

    return copiedTable
end

---@param soundName string | string[]
---@return string | string[] | nil
local function getValidSoundNames(soundName)
    if (type(soundName) == "string") then
        if (loadedSounds[soundName]) then return soundName end

        return nil
    end

    if (type(soundName) ~= "table") then return nil end

    local validSoundNames = {}
    local addedSoundNames = {}

    for i = 1, #soundName do
        local name = soundName[i]

        if (type(name) == "string" and loadedSounds[name] and not addedSoundNames[name]) then
            validSoundNames[#validSoundNames + 1] = name
            addedSoundNames[name] = true
        end
    end

    if (#validSoundNames == 0) then return nil end

    return validSoundNames
end

---@param soundName string | string[]
---@return string?
local function selectSoundName(soundName)
    if (type(soundName) == "table") then
        if (#soundName == 0) then return nil end

        return soundName[math.random(1, #soundName)]
    end

    if (type(soundName) ~= "string" or soundName == "") then return nil end

    return soundName
end

---@param playerId integer
---@return integer
local function getPlayerBucket(playerId)
    local bucket = GetPlayerRoutingBucket(playerId) or 0
    Cache.playerBuckets[playerId] = bucket

    return bucket
end

---@param playerId? integer | string
---@return integer?
local function getPlayerPedEntity(playerId)
    playerId = tonumber(playerId)
    if (not playerId or not GetPlayerName(playerId)) then return nil end

    local ped = GetPlayerPed(playerId)
    if (not ped or ped == 0 or not DoesEntityExist(ped)) then return nil end

    return ped
end

---@param entity? integer
---@return integer?
local function getPlayerIdFromPed(entity)
    if (type(entity) ~= "number" or entity == 0 or not DoesEntityExist(entity)) then return nil end

    local players = GetPlayers()

    for i = 1, #players do
        local playerId = tonumber(players[i])

        if (playerId and GetPlayerPed(playerId) == entity) then
            return playerId
        end
    end

    return nil
end

---@param entity? integer
---@param entityNetId? integer
---@param playerId? integer
---@return integer?
local function getEntityNetId(entity, entityNetId, playerId)
    if (type(entityNetId) == "number" and entityNetId > 0) then return entityNetId end
    entity = entity or getPlayerPedEntity(playerId)
    if (type(entity) ~= "number" or entity == 0 or not DoesEntityExist(entity)) then return nil end

    return NetworkGetNetworkIdFromEntity(entity)
end

---@param entityNetId? integer
---@return integer?
local function getEntityFromNetId(entityNetId)
    if (type(entityNetId) ~= "number" or entityNetId <= 0) then return nil end

    local entity = NetworkGetEntityFromNetworkId(entityNetId)
    if (not entity or entity == 0 or not DoesEntityExist(entity)) then return nil end

    return entity
end

---@param entity? integer
---@return integer?
local function getValidEntity(entity)
    if (type(entity) == "number" and entity ~= 0 and DoesEntityExist(entity)) then return entity end

    return nil
end

---@param soundData table
---@return integer?
local function getSoundEntity(soundData)
    return getPlayerPedEntity(soundData.playerId)
        or getValidEntity(soundData.entity)
        or getEntityFromNetId(soundData.entityNetId)
end

---@param soundData table
---@param entity? integer
---@return integer?
local function getSoundOwnerPlayerId(soundData, entity)
    local playerId = tonumber(soundData.playerId)
    if (playerId and GetPlayerName(playerId)) then return playerId end

    return getPlayerIdFromPed(entity or getValidEntity(soundData.entity) or getEntityFromNetId(soundData.entityNetId))
end

---@param soundData table
---@param entity? integer
---@return table? state
---@return integer? playerId
---@return integer? stateEntity
local function getEntitySoundState(soundData, entity)
    local playerId = getSoundOwnerPlayerId(soundData, entity)
    if (playerId) then
        return Player(playerId).state, playerId, nil
    end

    entity = getValidEntity(entity) or getSoundEntity(soundData) or getValidEntity(soundData.activeStateBagEntity)
    if (not entity) then return nil, nil, nil end

    return Entity(entity).state, nil, entity
end

---@param playerId integer
---@return vector3?
local function getPlayerPosition(playerId)
    local ped = GetPlayerPed(playerId)
    if (not ped or ped == 0 or not DoesEntityExist(ped)) then return nil end

    return GetEntityCoords(ped)
end

---@param soundData ServerSoundData
---@return vector3?
local function getSoundPosition(soundData)
    if (soundData.soundType ~= "location") then return nil end

    return soundData.location
end

---@param soundData ServerSoundData
---@param playerId integer
---@return boolean
local function isSoundInRangeOfPlayer(soundData, playerId)
    local maxDistance = tonumber(soundData.maxDistance) or 0
    if (maxDistance <= 0) then return false end

    local soundPosition = getSoundPosition(soundData)
    local playerPosition = getPlayerPosition(playerId)
    if (not soundPosition or not playerPosition) then return false end

    return #(playerPosition - soundPosition) <= maxDistance
end

---@param soundData ServerSoundData
---@return boolean
local function isSoundPlaying(soundData)
    return soundData.soundName ~= nil and soundData.waitingUntil == nil
end

---@param soundData ServerSoundData
---@param playerId integer
---@return boolean
local function isSoundVisibleToPlayer(soundData, playerId)
    if (soundData.soundType ~= "location") then return false end
    if (not soundData.global and getPlayerBucket(playerId) ~= soundData.routingBucket) then return false end

    return isSoundInRangeOfPlayer(soundData, playerId)
end

---@param soundData ServerSoundData
---@return table? @ Client sound payload
local function getClientSoundData(soundData)
    if (not isSoundPlaying(soundData)) then return nil end

    local offsetMs = math.max(0, GetGameTimer() - soundData.startedAt)
    local durationMs = Cache.soundDurations[soundData.soundName]

    if (soundData.looped ~= true and durationMs and offsetMs >= durationMs) then return nil end

    return {
        soundId = soundData.soundId,
        soundType = soundData.soundType,
        soundName = soundData.soundName,
        maxVolume = soundData.maxVolume,
        maxDistance = soundData.maxDistance,
        location = soundData.location,
        entityNetId = soundData.entityNetId,
        looped = soundData.looped == true,
        invoker = soundData.invoker,
        iteration = soundData.iteration,
        offsetMs = offsetMs,
        ownerServerId = tonumber(soundData.playerId),
        reportEvents = false
    }
end

---@param soundData ServerSoundData
---@return boolean
local function isEntitySound(soundData)
    return soundData.soundType == "entity"
end

---@param soundData ServerSoundData
local function setActiveEntityStateBagSound(soundData)
    if (not isEntitySound(soundData)) then return end

    local entity = getSoundEntity(soundData)
    local state, playerId, stateEntity = getEntitySoundState(soundData, entity)
    if (not state) then return end

    if (entity) then
        local entityNetId = getEntityNetId(entity)
        if (entityNetId and soundData.entityNetId ~= entityNetId) then
            soundData.entityNetId = entityNetId
        end
    end

    local payload = getClientSoundData(soundData)
    if (not payload) then return end

    payload.reportEvents = false
    payload.stateBagManaged = true
    payload.ownerServerId = playerId or tonumber(soundData.playerId)

    local activeSounds = copyTable(state[activeEntityStateKey])

    activeSounds[soundData.soundId] = payload
    state:set(activeEntityStateKey, activeSounds, true)

    soundData.activeStateBagPlayerId = playerId
    soundData.activeStateBagEntity = stateEntity or entity
end

---@return integer
local function getStateBagStopTtlMs()
    local ttlMs = math.floor(tonumber(Config.Settings.stateBagStopTtlMs) or 2000)

    return math.max(250, ttlMs)
end

---@param soundData? ServerSoundData
---@param fade? number
---@param forceFull? boolean
---@param emitStop? boolean
local function clearActiveEntityStateBagSound(soundData, fade, forceFull, emitStop)
    if (not soundData or not isEntitySound(soundData)) then return end

    local entity = getSoundEntity(soundData) or soundData.activeStateBagEntity
    local state = nil

    if (soundData.activeStateBagPlayerId and GetPlayerName(soundData.activeStateBagPlayerId)) then
        state = Player(soundData.activeStateBagPlayerId).state
    else
        state = select(1, getEntitySoundState(soundData, entity))
    end

    if (not state) then return end

    local activeSounds = copyTable(state[activeEntityStateKey])

    if (not activeSounds[soundData.soundId]) then return end

    if (emitStop) then
        stateBagStopSeq = stateBagStopSeq + 1

        local stopSeq = stateBagStopSeq
        local ttlMs = getStateBagStopTtlMs()

        activeSounds[soundData.soundId] = {
            soundId = soundData.soundId,
            stopped = true,
            stopSeq = stopSeq,
            fade = fade,
            forceFull = forceFull == true,
            expiresAt = os.time() + math.ceil(ttlMs / 1000)
        }

        state:set(activeEntityStateKey, activeSounds, true)

        CreateThread(function()
            Wait(ttlMs)

            local currentActiveSounds = copyTable(state[activeEntityStateKey])
            local currentPayload = currentActiveSounds[soundData.soundId]

            if (type(currentPayload) == "table" and currentPayload.stopped == true and currentPayload.stopSeq == stopSeq) then
                currentActiveSounds[soundData.soundId] = nil

                if (next(currentActiveSounds) == nil) then
                    currentActiveSounds = nil
                end

                state:set(activeEntityStateKey, currentActiveSounds, true)
            end
        end)

        return
    end

    activeSounds[soundData.soundId] = nil

    if (next(activeSounds) == nil) then
        activeSounds = nil
    end

    state:set(activeEntityStateKey, activeSounds, true)
end

---@param soundData ServerSoundData
---@return boolean
local function shouldSelectReporter(soundData)
    return soundData.looped ~= true and Cache.soundDurations[soundData.soundName] == nil
end

-- Assigns one visible player to report duration and end events for unknown location one-shots.
---@param soundData ServerSoundData
---@param playerId integer
---@return boolean
local function shouldPlayerReportSound(soundData, playerId)
    if (not shouldSelectReporter(soundData)) then return false end

    if (not soundData.reporterPlayerId) then
        soundData.reporterPlayerId = playerId
    end

    return soundData.reporterPlayerId == playerId
end

---@param playerId integer
---@param soundData ServerSoundData
local function sendSoundToPlayer(playerId, soundData)
    local payload = getClientSoundData(soundData)
    if (not payload) then return end

    payload.reportEvents = shouldPlayerReportSound(soundData, playerId)

    TriggerClientEvent("zyke_sounds:PlaySound", playerId, payload)

    Cache.playerSounds[playerId] = Cache.playerSounds[playerId] or {}
    Cache.playerSounds[playerId][soundData.soundId] = soundData.iteration
end

-- Sends one active location iteration to every player that can currently hear it.
---@param soundData ServerSoundData
local function sendSoundToVisiblePlayers(soundData)
    local players = GetPlayers()

    for i = 1, #players do
        local playerId = tonumber(players[i])

        if (playerId and isSoundVisibleToPlayer(soundData, playerId)) then
            sendSoundToPlayer(playerId, soundData)
        end
    end
end

---@param soundId string
---@param fade? number
---@param forceFull? boolean
local function stopTrackedSoundClients(soundId, fade, forceFull)
    for playerId, sounds in pairs(Cache.playerSounds) do
        if (sounds[soundId]) then
            TriggerClientEvent("zyke_sounds:StopSound", playerId, soundId, fade, forceFull)
        end
    end
end

---@param soundId string
---@param shouldStopClients boolean
---@param fade? number
---@param forceFull? boolean
local function removeSound(soundId, shouldStopClients, fade, forceFull)
    local activeSound = Cache.activeSounds[soundId]
    local isStateBagEntitySound = activeSound and isEntitySound(activeSound)

    if (shouldStopClients and not isStateBagEntitySound) then
        stopTrackedSoundClients(soundId, fade, forceFull)
    end

    clearActiveEntityStateBagSound(activeSound, fade, forceFull, shouldStopClients and isStateBagEntitySound)

    Cache.activeSounds[soundId] = nil

    for _, sounds in pairs(Cache.playerSounds) do
        sounds[soundId] = nil
    end
end

---@param looped boolean | number | {[1]: number, [2]: number}
---@return number
local function getLoopWait(looped)
    if (type(looped) == "number") then return math.max(0, looped) end

    if (type(looped) == "table") then
        local minWait = tonumber(looped[1]) or 0
        local maxWait = tonumber(looped[2]) or minWait

        if (maxWait < minWait) then
            minWait, maxWait = maxWait, minWait
        end

        return math.random() * (maxWait - minWait) + minWait
    end

    return 0
end

-- Stores a client-reported duration when it is plausible and consistent with prior reports.
---@param soundName? string
---@param durationMs? integer
local function cacheSoundDuration(soundName, durationMs)
    durationMs = math.floor(tonumber(durationMs) or 0)
    local maxDurationMs = Config.Settings.maxCachedSoundDurationMs or 600000
    local durationToleranceMs = Config.Settings.soundDurationToleranceMs or 500

    if (
        not soundName
        or durationMs <= 0
        or durationMs > maxDurationMs
    ) then
        return
    end

    local cachedDurationMs = Cache.soundDurations[soundName]
    if (cachedDurationMs and math.abs(cachedDurationMs - durationMs) > durationToleranceMs) then return end

    Cache.soundDurations[soundName] = durationMs
end

-- Checks that a reported end event did not arrive too early for the known duration.
---@param soundData ServerSoundData
---@param durationMs? integer
---@return boolean
local function isSoundEndTimingValid(soundData, durationMs)
    durationMs = Cache.soundDurations[soundData.soundName] or math.floor(tonumber(durationMs) or 0)

    if (durationMs <= 0 or durationMs > (Config.Settings.maxCachedSoundDurationMs or 600000)) then return true end

    local elapsedMs = GetGameTimer() - soundData.startedAt
    local durationToleranceMs = Config.Settings.soundDurationToleranceMs or 500

    return elapsedMs + durationToleranceMs >= durationMs
end

-- These scheduler functions call each other, so their local names are declared first.
local handleSoundIterationEnded
local scheduleSoundIterationEnd

-- Starts one selected sound iteration and resets iteration-scoped state.
---@param soundId string
local function playSoundIteration(soundId)
    local soundData = Cache.activeSounds[soundId]
    if (not soundData) then return end

    local selectedSoundName = selectSoundName(soundData.sourceSoundName)
    if (not selectedSoundName) then
        removeSound(soundId, true)

        return
    end

    if (soundData.looped ~= true and soundData.remainingPlays) then
        soundData.remainingPlays = soundData.remainingPlays - 1
    end

    soundData.soundName = selectedSoundName
    soundData.startedAt = GetGameTimer()
    soundData.iteration = soundData.iteration + 1
    soundData.waitingUntil = nil
    soundData.handledIteration = nil
    soundData.scheduledIteration = nil
    soundData.scheduledFallback = nil
    soundData.scheduledEndAt = nil
    soundData.reporterPlayerId = nil

    if (isEntitySound(soundData)) then
        setActiveEntityStateBagSound(soundData)
    else
        sendSoundToVisiblePlayers(soundData)
    end

    scheduleSoundIterationEnd(soundData)
end

-- Schedules the current non-looped iteration to finish, using a fallback until duration is known.
---@param soundData ServerSoundData
scheduleSoundIterationEnd = function(soundData)
    if (soundData.looped == true) then return end

    local durationMs = Cache.soundDurations[soundData.soundName]
    local isFallback = false

    if (not durationMs or durationMs <= 0) then
        durationMs = Config.Settings.unknownSoundDurationMs or 300000
        isFallback = true
    end

    if (soundData.scheduledIteration == soundData.iteration and not soundData.scheduledFallback) then return end
    if (soundData.scheduledIteration == soundData.iteration and soundData.scheduledFallback and isFallback) then return end

    local soundId = soundData.soundId
    local iteration = soundData.iteration
    local waitTime = math.max(0, (soundData.startedAt + durationMs) - GetGameTimer())

    soundData.scheduleToken = (soundData.scheduleToken or 0) + 1
    soundData.scheduledIteration = iteration
    soundData.scheduledFallback = isFallback
    soundData.scheduledEndAt = soundData.startedAt + durationMs

    local scheduleToken = soundData.scheduleToken

    -- Finishes this scheduled iteration if it still owns the latest schedule token.
    CreateThread(function()
        if (waitTime > 0) then
            Wait(waitTime)
        end

        local latestSoundData = Cache.activeSounds[soundId]
        if (not latestSoundData or latestSoundData.scheduleToken ~= scheduleToken) then return end

        local reportedDuration = durationMs
        if (isFallback) then
            reportedDuration = nil
        end

        handleSoundIterationEnded(soundId, iteration, reportedDuration)
    end)
end

-- Completes an iteration, then queues the next loop/play or removes the tracked sound.
---@param soundId string
---@param iteration integer
---@param durationMs? integer
handleSoundIterationEnded = function(soundId, iteration, durationMs)
    local soundData = Cache.activeSounds[soundId]
    if (
        not soundData
        or soundData.iteration ~= iteration
        or soundData.handledIteration == iteration
    ) then
        return
    end

    cacheSoundDuration(soundData.soundName, durationMs)

    if (soundData.looped == true) then return end

    soundData.handledIteration = iteration
    soundData.soundName = nil
    clearActiveEntityStateBagSound(soundData)

    if (type(soundData.looped) == "number" or type(soundData.looped) == "table") then
        local waitTime = getLoopWait(soundData.looped)
        soundData.waitingUntil = GetGameTimer() + waitTime

        -- Starts the next looped sound iteration after its wait.
        CreateThread(function()
            if (waitTime > 0) then
                Wait(waitTime)
            end

            local latestSoundData = Cache.activeSounds[soundId]
            if (latestSoundData and latestSoundData.handledIteration == iteration) then
                playSoundIteration(soundId)
            end
        end)

        return
    end

    if ((soundData.remainingPlays or 0) > 0) then
        playSoundIteration(soundId)

        return
    end

    removeSound(soundId, false)
end

---@return integer
local function getStateBagEmitSlots()
    local slots = math.floor(tonumber(Config.Settings.stateBagEmitSlots) or 4)

    return math.max(1, slots)
end

---@return integer
local function getOneShotStateBagTtlMs()
    local ttlMs = math.floor(tonumber(Config.Settings.oneShotStateBagTtlMs) or 10000)

    return math.max(1000, ttlMs)
end

-- Allows only simple entity one-shots to bypass tracked server sound state.
---@param options table
---@return boolean
local function shouldUseStateBagEntitySound(options)
    if (options.soundType ~= "entity") then return false end
    if (options.id or options.soundId) then return false end
    if (options.looped) then return false end

    return math.max(1, math.floor(tonumber(options.playCount) or 1)) <= 1
end

-- Emits a simple entity one-shot through an entity state bag instead of server tracking.
---@param options table
---@return string? @ Sound id
---@return boolean @ Whether state bag handling completed
local function tryEmitStateBagEntitySound(options)
    if (not shouldUseStateBagEntitySound(options)) then return nil, false end

    local soundNames = getValidSoundNames(options.soundName)
    if (not soundNames) then return nil, true end

    local entity = options.entity
    if (not entity or entity == 0 or not DoesEntityExist(entity)) then
        entity = getPlayerPedEntity(options.playerId) or getEntityFromNetId(options.entityNetId)
    end

    options.playerId = tonumber(options.playerId) or getPlayerIdFromPed(entity)

    local selectedSoundName = selectSoundName(soundNames)
    if (not selectedSoundName) then return nil, true end

    local state, playerId = getEntitySoundState(options, entity)
    if (not state) then return nil, false end

    stateBagEmitSeq = stateBagEmitSeq + 1

    -- Rotate slots so rapid emits on the same entity still trigger state bag changes.
    local soundId = GetDefaultSoundId()
    local ttlMs = getOneShotStateBagTtlMs()
    local startedAt = os.time()
    local emitSeq = stateBagEmitSeq
    local slot = (stateBagEmitSeq - 1) % getStateBagEmitSlots()
    local stateKey = ("zyke_sounds:emit:%d"):format(slot)

    state:set(stateKey, {
        seq = emitSeq,
        soundId = soundId,
        soundType = "entity",
        soundName = selectedSoundName,
        maxVolume = options.maxVolume or 0.3,
        maxDistance = options.maxDistance or 10.0,
        startedAt = startedAt,
        expiresAt = startedAt + math.ceil(ttlMs / 1000),
        ttlMs = ttlMs,
        ownerServerId = playerId or tonumber(options.playerId),
        invoker = GetInvokingResource() or GetCurrentResourceName()
    }, true)

    Cache.stateBagOneShots[soundId] = {
        state = state,
        stateKey = stateKey,
        seq = emitSeq
    }

    -- Clears the transient state bag payload after its TTL.
    CreateThread(function()
        Wait(ttlMs)

        local currentPayload = state[stateKey]

        if (type(currentPayload) == "table" and currentPayload.seq == emitSeq) then
            state:set(stateKey, nil, true)
        end

        Wait(1000)

        local cachedOneShot = Cache.stateBagOneShots[soundId]
        if (cachedOneShot and cachedOneShot.seq == emitSeq) then
            Cache.stateBagOneShots[soundId] = nil
        end
    end)

    return soundId, true
end

-- Registers a tracked sound for lifecycle, scheduling, and explicit stops.
---@param options table
---@return string? @ Sound id
local function registerSound(options)
    local soundId = options.id or options.soundId or GetDefaultSoundId()
    local remainingPlays
    local soundNames = getValidSoundNames(options.soundName)

    if (not soundNames) then return nil end

    if (Cache.activeSounds[soundId]) then
        StopSound(soundId)
    end

    if (not options.looped) then
        remainingPlays = math.max(1, math.floor(tonumber(options.playCount) or 1))
    end

    ---@type ServerSoundData
    local soundData = {
        soundId = soundId,
        soundType = options.soundType,
        sourceSoundName = copySoundName(soundNames),
        soundName = nil,
        maxVolume = options.maxVolume or 0.3,
        maxDistance = options.maxDistance or 10.0,
        location = options.location,
        entity = options.entity,
        entityNetId = options.entityNetId,
        playerId = options.playerId,
        looped = options.looped or false,
        playCount = options.playCount or 1,
        remainingPlays = remainingPlays,
        routingBucket = options.routingBucket or 0,
        global = options.global == true,
        invoker = GetInvokingResource() or GetCurrentResourceName(),
        iteration = 0,
        startedAt = 0
    }

    Cache.activeSounds[soundId] = soundData
    playSoundIteration(soundId)

    return soundId
end

---@param entity integer | table
---@param id? string @ Only needed if you want to manually stop the sound
---@param soundName string | string[] @ Sound name or list of sound names
---@param maxVolume number
---@param maxDistance number
---@param looped boolean | number | {[1]: number, [2]: number} @ Basic looping, loop with time between, loop with random time between
---@param playCount? integer @ If not looping, you can decide how many times the audio will play
---@return string? @ Sound id
function PlaySoundOnEntity(entity, id, soundName, maxVolume, maxDistance, looped, playCount)
    local options = {}

    if (type(entity) == "table") then
        options = copyOptions(entity)
    else
        options = {
            entity = entity,
            id = id,
            soundName = soundName,
            maxVolume = maxVolume,
            maxDistance = maxDistance,
            looped = looped,
            playCount = playCount
        }
    end

    options.playerId = tonumber(options.playerId) or getPlayerIdFromPed(options.entity)
    options.entity = options.entity or getPlayerPedEntity(options.playerId)

    local entityNetId = getEntityNetId(options.entity, options.entityNetId, options.playerId)
    if (not entityNetId) then return nil end

    options.soundType = "entity"
    options.entityNetId = entityNetId

    local stateBagSoundId, handled = tryEmitStateBagEntitySound(options)
    if (handled) then return stateBagSoundId end

    return registerSound(options)
end

exports("PlaySoundOnEntity", PlaySoundOnEntity)

---@param location vector3 | table
---@param id? string @ Only needed if you want to manually stop the sound
---@param soundName string | string[] @ Sound name or list of sound names
---@param maxVolume number
---@param maxDistance number
---@param looped boolean | number | {[1]: number, [2]: number} @ Basic looping, loop with time between, loop with random time between
---@param playCount? integer @ If not looping, you can decide how many times the audio will play
---@return string? @ Sound id
function PlaySoundOnLocation(location, id, soundName, maxVolume, maxDistance, looped, playCount)
    local options = {}

    if (type(location) == "table" and location.location) then
        options = copyOptions(location)
    else
        options = {
            location = location,
            id = id,
            soundName = soundName,
            maxVolume = maxVolume,
            maxDistance = maxDistance,
            looped = looped,
            playCount = playCount
        }
    end

    options.soundType = "location"
    options.routingBucket = options.routingBucket or 0
    options.global = options.global == true

    return registerSound(options)
end

exports("PlaySoundOnLocation", PlaySoundOnLocation)

---@param soundId string
local function clearStateBagOneShot(soundId)
    local oneShotData = Cache.stateBagOneShots[soundId]
    if (not oneShotData) then return end

    local currentPayload = oneShotData.state[oneShotData.stateKey]

    if (type(currentPayload) == "table" and currentPayload.seq == oneShotData.seq) then
        oneShotData.state:set(oneShotData.stateKey, nil, true)
    end

    Cache.stateBagOneShots[soundId] = nil
end

---@param soundId string
---@param fade? number
---@param forceFull? boolean @ Force the audio to play out fully instead of cutting off, ignores fade
function StopSound(soundId, fade, forceFull)
    if (type(soundId) ~= "string") then return end

    if (soundId and Cache.stateBagOneShots[soundId]) then
        clearStateBagOneShot(soundId)
        TriggerClientEvent("zyke_sounds:StopSound", -1, soundId, fade, forceFull)

        return
    end

    if (not Cache.activeSounds[soundId]) then
        TriggerClientEvent("zyke_sounds:StopSound", -1, soundId, fade, forceFull)

        return
    end

    removeSound(soundId, true, fade, forceFull)
end

exports("StopSound", StopSound)

-- Refreshes server-managed location sounds for a player. Entity sounds sync through state bags.
---@param playerId integer | string
function RefreshPlayerSounds(playerId)
    playerId = tonumber(playerId)

    if (not playerId or not GetPlayerName(playerId)) then return end

    Cache.playerSounds[playerId] = Cache.playerSounds[playerId] or {}

    local visibleSounds = {}

    for soundId, soundData in pairs(Cache.activeSounds) do
        if (
            soundData.soundType == "location"
            and isSoundVisibleToPlayer(soundData, playerId)
            and isSoundPlaying(soundData)
        ) then
            visibleSounds[soundId] = soundData.iteration

            if (Cache.playerSounds[playerId][soundId] ~= soundData.iteration) then
                sendSoundToPlayer(playerId, soundData)
            end
        end
    end

    local hiddenSounds = {}

    for soundId in pairs(Cache.playerSounds[playerId]) do
        if (not visibleSounds[soundId]) then
            hiddenSounds[#hiddenSounds + 1] = soundId
        end
    end

    for i = 1, #hiddenSounds do
        local soundId = hiddenSounds[i]
        local activeSound = Cache.activeSounds[soundId]

        if (activeSound and activeSound.reporterPlayerId == playerId) then
            activeSound.reporterPlayerId = nil
        end

        TriggerClientEvent("zyke_sounds:StopSound", playerId, soundId)
        Cache.playerSounds[playerId][soundId] = nil
    end
end

exports("RefreshPlayerSounds", RefreshPlayerSounds)

---@param playerId integer | string
function ClearPlayerSounds(playerId)
    playerId = tonumber(playerId)

    if (not playerId) then return end

    local ownedEntitySounds = {}

    for _, soundData in pairs(Cache.activeSounds) do
        if (soundData.reporterPlayerId == playerId) then
            soundData.reporterPlayerId = nil
        end

        if (soundData.soundType == "entity" and tonumber(soundData.playerId) == playerId) then
            ownedEntitySounds[#ownedEntitySounds + 1] = soundData.soundId
        end
    end

    for i = 1, #ownedEntitySounds do
        removeSound(ownedEntitySounds[i], true)
    end

    Cache.playerBuckets[playerId] = nil
    Cache.playerSounds[playerId] = nil
end

-- Accepts metadata/end reports only from the selected player for the current iteration.
---@param playerId integer | string
---@param data NUISoundEventData
---@return ServerSoundData?
local function getSoundFromClientEvent(playerId, data)
    playerId = tonumber(playerId)

    if (
        not playerId
        or not GetPlayerName(playerId)
        or type(data) ~= "table"
        or type(data.soundId) ~= "string"
        or type(data.soundName) ~= "string"
        or type(data.iteration) ~= "number"
    ) then
        return nil
    end

    local soundData = Cache.activeSounds[data.soundId]
    if (
        not soundData
        or not isSoundPlaying(soundData)
        or soundData.iteration ~= data.iteration
        or soundData.soundName ~= data.soundName
    ) then
        return nil
    end

    if (isEntitySound(soundData)) then
        local ownerPlayerId = tonumber(soundData.playerId)
        if (ownerPlayerId and ownerPlayerId ~= playerId) then return nil end

        return soundData
    end

    if (
        soundData.reporterPlayerId ~= playerId
        or not isSoundVisibleToPlayer(soundData, playerId)
    ) then
        return nil
    end

    local playerSounds = Cache.playerSounds[playerId]
    if (not playerSounds or playerSounds[data.soundId] ~= data.iteration) then return nil end

    return soundData
end

-- Caches the reported duration and replaces fallback end timing when possible.
---@param playerId integer | string
---@param data NUISoundEventData
function HandleSoundMetadata(playerId, data)
    local soundData = getSoundFromClientEvent(playerId, data)
    if (not soundData) then return end

    cacheSoundDuration(soundData.soundName or data.soundName, data.durationMs)
    scheduleSoundIterationEnd(soundData)
end

-- Advances a sound after the selected reporter confirms the current iteration ended.
---@param playerId integer | string
---@param data NUISoundEventData
function HandleSoundEnded(playerId, data)
    local soundData = getSoundFromClientEvent(playerId, data)
    if (not soundData) then return end
    if (data.failed) then return end
    if (not isSoundEndTimingValid(soundData, data.durationMs)) then return end

    cacheSoundDuration(soundData.soundName or data.soundName, data.durationMs)
    handleSoundIterationEnded(data.soundId, data.iteration, data.durationMs)
end

---@param resource string
function StopSoundsForInvoker(resource)
    local soundIds = {}

    for soundId, soundData in pairs(Cache.activeSounds) do
        if (soundData.invoker == resource) then
            soundIds[#soundIds + 1] = soundId
        end
    end

    for i = 1, #soundIds do
        StopSound(soundIds[i])
    end
end

-- Drops tracked entity sounds once their owning player/entity is gone.
local function cleanupMissingEntitySounds()
    local soundIds = {}

    for soundId, soundData in pairs(Cache.activeSounds) do
        if (soundData.soundType == "entity") then
            local playerId = tonumber(soundData.playerId)

            if (
                playerId
                and not GetPlayerName(playerId)
            ) then
                soundIds[#soundIds + 1] = soundId
            elseif (not playerId and not getSoundEntity(soundData)) then
                soundIds[#soundIds + 1] = soundId
            end
        end
    end

    for i = 1, #soundIds do
        removeSound(soundIds[i], false)
    end
end

-- Refreshes players whose routing buckets changed.
local function refreshTrackedPlayers()
    local players = GetPlayers()

    for i = 1, #players do
        local playerId = tonumber(players[i])

        if (playerId) then
            local routingBucket = GetPlayerRoutingBucket(playerId) or 0

            if (Cache.playerBuckets[playerId] ~= routingBucket) then
                Cache.playerBuckets[playerId] = routingBucket
                RefreshPlayerSounds(playerId)
            end
        end
    end
end

---@return boolean
local function hasPlayingSounds()
    for _, soundData in pairs(Cache.activeSounds) do
        if (soundData.soundType == "location" and isSoundPlaying(soundData)) then return true end
    end

    return false
end

-- Refreshes every currently connected player.
local function refreshAllPlayers()
    for _, playerId in ipairs(GetPlayers()) do
        RefreshPlayerSounds(playerId)
    end
end

-- Tracks routing bucket/distance changes for location sounds and cleanup for entity sounds.
CreateThread(function()
    Wait(500)

    local lastSoundCullingRefresh = 0

    while (true) do
        local routingBucketUpdateInterval = math.max(100, tonumber(Config.Settings.routingBucketUpdateInterval) or 1000)
        local soundCullingUpdateInterval = math.max(100, tonumber(Config.Settings.soundCullingUpdateInterval) or 1000)
        cleanupMissingEntitySounds()
        refreshTrackedPlayers()

        local now = GetGameTimer()
        if (
            hasPlayingSounds()
            and now - lastSoundCullingRefresh >= soundCullingUpdateInterval
        ) then
            lastSoundCullingRefresh = now
            refreshAllPlayers()
        end

        Wait(math.min(routingBucketUpdateInterval, soundCullingUpdateInterval))
    end
end)

-- Validates a sound file name against the NUI sound folder.
---@param fileName string
---@return boolean
function DoesFileExist(fileName)
    if (type(fileName) ~= "string" or fileName == "") then return false end
    if (fileName:find("%.%.") or fileName:find("[/\\]")) then return false end

    local lowerFileName = fileName:lower()
    if (
        not lowerFileName:match("%.mp3$")
        and not lowerFileName:match("%.ogg$")
        and not lowerFileName:match("%.wav$")
    ) then
        return false
    end

    local file = io.open(soundsPath .. fileName, "r")
    if (file) then
        file:close()

        return true
    end

    return false
end

exports("DoesFileExist", DoesFileExist)

local isWindows = os.getenv("OS") == "Windows"
local command
if (isWindows) then
    command = 'dir "' .. soundsPath .. '" /b'
else
    command = 'ls "' .. soundsPath .. '"'
end

---@param soundName string
---@return boolean
local function isValidSoundName(soundName)
    if (type(soundName) ~= "string" or soundName == "") then return false end

    local lowerSoundName = soundName:lower()

    return lowerSoundName:match("%.mp3$") ~= nil or lowerSoundName:match("%.ogg$") ~= nil or lowerSoundName:match("%.wav$") ~= nil
end

local debugEnabled = Config.Settings.debug
local commandPipe = io.popen(command)
if (commandPipe) then
    for file in commandPipe:lines() do
        if (isValidSoundName(file)) then
            loadedSounds[file] = true

            if (debugEnabled) then
                print("^4[DEBUG] ^2Registered " .. file .. " as loaded sound.^7")
            end
        end
    end

    commandPipe:close()
end

---@param soundName string
---@return boolean
function DoesSoundExist(soundName)
    return loadedSounds[soundName] ~= nil
end

exports("DoesSoundExist", DoesSoundExist)

---@return table<string, boolean> @ File name, exists
function GetLoadedSounds()
    return loadedSounds
end

exports("GetLoadedSounds", GetLoadedSounds)