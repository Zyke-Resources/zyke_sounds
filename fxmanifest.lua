fx_version "cerulean"
game "gta5"
lua54 "yes"
author "https://discord.zykeresources.com"
version "0.6.0"

ui_page "nui/index.html"

files {
    "nui/**/*",
    "nui/sounds/**/*",
    "locales/*.lua"
}

shared_script "@zyke_lib/imports.lua"

shared_scripts {
    "shared/config.lua"
}

client_scripts {
    "client/main.lua",
    "client/functions.lua",
    "client/eventhandler.lua",
    "client/menu.lua",
    "client/debug.lua",
}

server_scripts {
    "server/sound_scanner.js",
    "server/functions.lua",
    "server/eventhandler.lua"
}

dependency "zyke_lib"