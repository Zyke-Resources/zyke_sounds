---@param soundData SoundDataWithEntity | SoundDataWithLocation
RegisterNetEvent("zyke_sounds:PlaySound", function(soundData)
    local plyPos = GetEntityCoords(PlayerPedId())

    Cache.activeSounds[soundData.soundId] = soundData

    ---@type NUISoundData
    local nuiSoundData = {
        soundId = soundData.soundId,
        soundName = soundData.soundName,
        volume = GetSoundVolume(plyPos, soundData),
        looped = soundData.looped
    }

    SendNUIMessage({
        event = "PlaySound",
        data = nuiSoundData
    })

    UpdateSoundVolumeLoop()
end)

RegisterNUICallback("Eventhandler", function(passed, cb)
    local event = passed.event
    local data = passed.data

    if (event == "SoundEnded") then
        Cache.activeSounds[data.soundId] = nil
        cb("ok")
    elseif (event == "CloseMenu") then
        SetNuiFocus(false, false)
        cb("ok")
    elseif (event == "GetStrings") then
        return cb(Translations)
    elseif (event == "GetSoundsList") then
        return cb(GetSoundsList())
    elseif (event == "SetSoundVolume") then
        SetSoundVolume(data.name, data.volume)
        return cb("ok")
    end
end)

---@param soundId string
---@param fade? number
---@param forceFull? boolean
RegisterNetEvent("zyke_sounds:StopSound", function(soundId, fade, forceFull)
    StopSound(soundId, fade, forceFull)
end)

AddEventHandler("onResourceStop", function(resource)
    for soundId, soundData in pairs(Cache.activeSounds) do
        if (soundData.invoker == resource) then
            StopSound(soundId)
        end
    end
end)