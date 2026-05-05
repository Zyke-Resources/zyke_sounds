if (not Config.Settings.debug) then return end

-- Draws debug markers for active location and entity sounds.
CreateThread(function()
    while (true) do
        for _, soundData in pairs(Cache.activeSounds) do
            if (soundData.pos) then
                -- Sound position
                ---@diagnostic disable-next-line: param-type-mismatch
                DrawMarker(28, soundData.pos.x, soundData.pos.y, soundData.pos.z, 0, 0, 0, 0, 0, 0, 0.25, 0.25, 0.25, 255, 255, 255, 200, false, false, 2, nil, nil, false, false)

                -- Max distance
                ---@diagnostic disable-next-line: param-type-mismatch
                DrawMarker(28, soundData.pos.x, soundData.pos.y, soundData.pos.z, 0, 0, 0, 0, 0, 0, soundData.maxDistance + 0.0, soundData.maxDistance + 0.0, soundData.maxDistance + 0.0, 255, 255, 255, 100, false, false, 2, nil, nil, false, false)
            end
        end

        Wait(1)
    end
end)