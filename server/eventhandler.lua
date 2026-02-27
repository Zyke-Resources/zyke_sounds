Z.callback.register("zyke_sounds:GetSoundNames", function(_)
    local sounds = {}

    for name in pairs(GetLoadedSounds()) do
        sounds[#sounds + 1] = name
    end

    table.sort(sounds)

    return sounds
end)