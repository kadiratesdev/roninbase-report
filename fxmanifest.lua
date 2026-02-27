fx_version 'cerulean'
game 'gta5'

author 'YourServer'
description 'QBCore Beautiful Report System with NUI'
version '1.1.0'

-- Sadece client tarafına gönderilir (kategori listesi, komut isimleri)
client_scripts {
    'config.lua',
    'client.lua'
}

-- server_config.lua yalnızca sunucu tarafında yüklenir → webhook asla client'a sızmaz
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server_config.lua',
    'server.lua'
}

dependencies {
    'oxmysql',
    'qb-core',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/css/style.css',
    'html/assets/js/app.js'
}

lua54 'yes'
