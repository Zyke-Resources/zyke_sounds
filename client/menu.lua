-- Opens the sound configuration menu.
RegisterCommand(Config.Settings.commandName, function()
    SendNUIMessage({
        event = "SetOpen",
        data = true
    })

    SetNuiFocus(true, true)
end, false)