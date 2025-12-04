fx_version "cerulean"
game "gta5"
lua54 "yes"
author "realzyke"
version "0.3.3"

ui_page "nui/index.html"

files {
    "nui/**/*",
    "nui/sounds/*"
}

shared_scripts {
    "shared/config.lua"
}

client_scripts {
    "client/main.lua",
    "client/functions.lua",
    "client/eventhandler.lua",
    "client/debug.lua",
}

server_scripts {
    "server/main.lua",
    "server/functions.lua",
    "server/eventhandler.lua"
}