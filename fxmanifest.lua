fx_version 'cerulean'
game 'gta5'

author 'YourServer'
description 'QBCore Beautiful Report System with NUI'
version '1.3.0'

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
    'html/assets/js/app.js',
    'html/assets/locales/en.json',
    'html/assets/locales/tr.json',
    'locales/en.lua',
    'locales/tr.lua'
}

lua54 'yes'
