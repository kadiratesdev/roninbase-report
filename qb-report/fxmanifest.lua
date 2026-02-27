fx_version 'cerulean'
game 'gta5'

author 'YourServer'
description 'QBCore Beautiful Report System with NUI'
version '1.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/css/style.css',
    'html/assets/js/app.js'
}

lua54 'yes'
