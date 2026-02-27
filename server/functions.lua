---@param soundName string
function PlaySound(soundName)
    TriggerClientEvent("zyke_sounds:PlaySound", -1, soundName)
end

local soundIdCounter = 0

function GetDefaultSoundId()
    soundIdCounter += 1

    return "sound-" .. soundIdCounter
end

---@param entity integer
---@param id string? @Only needed if you want to manually stop the sound
---@param soundName string | string[] @Sound name or list of sound names, will choose randomly every time PlaySound(JS) is called
---@param maxVolume number
---@param maxDistance number
---@param looped boolean | number | {[1]: number, [2]: number} @Basic looping, loop with time between, loop with random time between
---@param playCount integer? @If not looping, you can decide how many times the audio will play
---@return string
function PlaySoundOnEntity(entity, id, soundName, maxVolume, maxDistance, looped, playCount)
    local entityNetId = NetworkGetNetworkIdFromEntity(entity)

    id = id or GetDefaultSoundId()

    ---@type SoundDataWithEntity
    local soundData = {
        soundId = id,
        soundName = soundName,
        entityNetId = entityNetId,
        soundType = "entity",
        maxVolume = maxVolume or 0.3,
        maxDistance = maxDistance or 10.0,
        looped = looped or false,
        playCount = playCount or 1,
        invoker = GetInvokingResource()
    }

    TriggerClientEvent("zyke_sounds:PlaySound", -1, soundData)

    return soundData.soundId
end

exports("PlaySoundOnEntity", PlaySoundOnEntity)

---@param location vector3
---@param id string? @Only needed if you want to manually stop the sound
---@param soundName string | string[] @Sound name or list of sound names, will choose randomly every time PlaySound(JS) is called
---@param maxVolume number
---@param maxDistance number
---@param looped boolean | number | {[1]: number, [2]: number} @Basic looping, loop with time between, loop with random time between
---@param playCount integer? @If not looping, you can decide how many times the audio will play
---@return string
function PlaySoundOnLocation(location, id, soundName, maxVolume, maxDistance, looped, playCount)
    id = id or GetDefaultSoundId()

    ---@type SoundDataWithLocation
    local soundData = {
        soundId = id,
        soundName = soundName,
        location = location,
        soundType = "location",
        maxVolume = maxVolume or 0.3,
        maxDistance = maxDistance or 10.0,
        looped = looped or false,
        playCount = playCount or 1,
        invoker = GetInvokingResource()
    }

    TriggerClientEvent("zyke_sounds:PlaySound", -1, soundData)

    return soundData.soundId
end

exports("PlaySoundOnLocation", PlaySoundOnLocation)

---@param soundId string
---@param fade? number
---@param forceFull? boolean @Force the audio to play out fully instead of cutting off, ignores fade
function StopSound(soundId, fade, forceFull)
    TriggerClientEvent("zyke_sounds:StopSound", -1, soundId, fade, forceFull)
end

exports("StopSound", StopSound)

local soundsPath = GetResourcePath(GetCurrentResourceName()) .. "/nui/sounds/"

-- This is meant to be validated during script initialization for those that use our exports
-- We don't want to perform file validation on every sound play to avoid delay
---@param fileName string
---@return boolean
function DoesFileExist(fileName)
    local filePath = soundsPath .. fileName

    if (
        type(filePath) ~= "string"
        or filePath == ""
        or type(fileName) ~= "string"
        or fileName == ""
    ) then return false end

    -- Specific path validation
    if (
        filePath:find("%.%.") -- check for directory traversal
        or filePath:match("^.+%.[mp3|ogg|wav]+$") == nil -- check for valid file extensions
    ) then return false end

    -- If the file could be opened here, we're good to go
    local file = io.open(filePath, "r")

    if (file) then
        file:close()
        return true
    else
        return false
    end
end

exports("DoesFileExist", DoesFileExist)

---@type table<string, boolean> @file name, exists
local loadedSounds = {}

local isWindows = os.getenv("OS") == "Windows"
local command
if (isWindows) then
    command = 'dir "' .. soundsPath .. '" /b'
else
    -- Untested
    command = 'ls "' .. soundsPath .. '"'
end

---@param soundName string
---@return boolean
local function isValidSoundName(soundName)
    return type(soundName) == "string" and soundName ~= "" and soundName:match("%.mp3$") or soundName:match("%.ogg$") or soundName:match("%.wav$")
end

local debug = Config.Settings.debug
local p = io.popen(command)
if (p) then
    for file in p:lines() do
        if (isValidSoundName(file)) then
            loadedSounds[file] = true

            if (debug) then
                print("^4[DEBUG] ^2Registered " .. file .. " as loaded sound.^7")
            end
        end
    end
end

-- Lightweight check to see if the sound exists in the loaded sounds
---@param soundName string
exports("DoesSoundExist", function(soundName)
    return loadedSounds[soundName] ~= nil
end)

---@return table<string, boolean> @file name, exists
function GetLoadedSounds()
    return loadedSounds
end

exports("GetLoadedSounds", GetLoadedSounds)