Cache = {}
Cache.activeSounds = {}
Cache.soundVolumes = {} -- Per-sound volume multipliers (0.0-2.0)

-- Load our old config, which is {[key: string]: number} JSON encoded
local storedJson = GetResourceKvpString(Config.Settings.kvpKey)
if (storedJson) then
    Cache.soundVolumes = json.decode(storedJson) or {}
end

local function saveSoundVolumes()
    SetResourceKvp(Config.Settings.kvpKey, json.encode(Cache.soundVolumes))
end

---@param soundName string
---@param value number @ 0.0-2.0
function SetSoundVolume(soundName, value)
    value = math.max(0.0, math.min(2.0, value + 0.0))
    Cache.soundVolumes[soundName] = value

    saveSoundVolumes()
end

--- Get the volume multiplier for a given soundName (string or string[])
---@param soundName string | string[]
---@return number
function GetVolumeMultiplier(soundName)
    if (type(soundName) == "table") then
        -- For random-pick sounds, use the first entry's multiplier as representative
        -- Weird side-effect, should randomly grab the sound on the server instead
        soundName = soundName[1]
    end

    return Cache.soundVolumes[soundName] or 1.0
end

--- Returns a list of all sound files with their current volume multipliers
---@return table[]
function GetSoundsList()
    local soundNames = Z.callback.request("zyke_sounds:GetSoundNames", nil)
    local sounds = {}

    for i = 1, #soundNames do
        local name = soundNames[i]

        sounds[#sounds + 1] = {
            name = name,
            volume = Cache.soundVolumes[name] or 1.0,
        }
    end

    return sounds
end