Cache = {}

-- Locally cached sounds keyed by sound id. Location sounds arrive from server snapshots/events,
-- while entity sounds arrive from state bags. Muted entity sounds stay cached so volume reacts immediately.
Cache.activeSounds = {}

-- Per-sound user volume multipliers (0.0-2.0), persisted in resource KVP.
---@type table<string, number>
Cache.soundVolumes = {}

-- Sound picker presets registered by other resources for the config menu.
---@type table<string, { invoker: string, sounds: string[] }>
Cache.presets = {}

---@param name string @ Preset display name (ex. "Consumables" or "Consumables (Eating)")
---@param sounds string[] @ List of sound file names (ex. {"x.ogg", "y.ogg"})
function AddPreset(name, sounds)
    Cache.presets[name] = {
        invoker = GetInvokingResource() or "unknown",
        sounds = sounds,
    }
end

exports("AddPreset", AddPreset)

---@return table<string, { invoker: string, sounds: string[] }>
function GetPresets()
    return Cache.presets
end

-- Entities that do not muffle sounds played with a matching occlusionIgnore key, keyed by that key.
-- Kept per client, as locally spawned props have a different handle on every client
---@type table<string, { invoker: string, entities: table<integer, true> }>
Cache.occlusionIgnores = {}

-- Sounds played with this key pass through these entities, every other sound is still muffled by them
---@param key string @ Same key as the occlusionIgnore option the sounds are played with
---@param entities? integer | integer[] @ Replaces the previous entities, nil clears the key
function SetOcclusionIgnore(key, entities)
    if (type(key) ~= "string") then return end

    if (type(entities) == "number") then entities = {entities} end
    if (type(entities) ~= "table" or #entities == 0) then
        Cache.occlusionIgnores[key] = nil

        return
    end

    local set = {}

    for i = 1, #entities do
        set[entities[i]] = true
    end

    Cache.occlusionIgnores[key] = {
        invoker = GetInvokingResource() or "unknown",
        entities = set,
    }
end

exports("SetOcclusionIgnore", SetOcclusionIgnore)

-- Load persisted per-sound volume multipliers.
local storedJson = GetResourceKvpString(Config.Settings.kvpKey)
if (storedJson) then
    Cache.soundVolumes = json.decode(storedJson) or {}
end

-- Persists client sound volume multipliers to KVP storage.
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

-- Returns the volume multiplier for the requested sound.
---@param soundName string | string[]
---@return number
function GetVolumeMultiplier(soundName)
    if (type(soundName) == "table") then
        soundName = soundName[1]
    end

    return Cache.soundVolumes[soundName] or 1.0
end

-- Returns all sound files with their current volume multipliers.
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