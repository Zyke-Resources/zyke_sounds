---@return string[]
Z.callback.register("zyke_sounds:GetSoundNames", function()
    local sounds = {}

    for name in pairs(GetLoadedSounds()) do
        sounds[#sounds + 1] = name
    end

    table.sort(sounds)

    return sounds
end)

-- Sends the current server-managed location sound snapshot to the requesting player.
RegisterNetEvent("zyke_sounds:RequestSnapshot", function()
    RefreshPlayerSounds(source)
end)

---@param playerId integer | string
RegisterNetEvent("zyke_sounds:RefreshPlayerSounds", function(playerId)
    if (source and source > 0) then
        RefreshPlayerSounds(source)

        return
    end

    RefreshPlayerSounds(playerId)
end)

---@param data NUISoundEventData
RegisterNetEvent("zyke_sounds:SoundMetadata", function(data)
    HandleSoundMetadata(source, data)
end)

---@param data NUISoundEventData
RegisterNetEvent("zyke_sounds:SoundEnded", function(data)
    HandleSoundEnded(source, data)
end)

-- Clears cached sound state for a dropped player.
AddEventHandler("playerDropped", function()
    ClearPlayerSounds(source)
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    StopSoundsForInvoker(resource)
end)