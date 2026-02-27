-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  Server-side Config  (server_config.lua)
--  Bu dosya YALNIZCA server script olarak yüklenir.
--  Webhook URL'i ve hassas ayarlar client tarafına HİÇBİR ZAMAN gönderilmez.
-- ─────────────────────────────────────────────────────────────────────────────
ServerConfig = {}

-- ── Genel ────────────────────────────────────────────────────────────────────
ServerConfig.Cooldown       = 120    -- Rapor gönderme bekleme süresi (saniye)
ServerConfig.MaxDescLength  = 500    -- Açıklama maksimum karakter
ServerConfig.MaxReports     = 200    -- Bellekte tutulacak maksimum rapor sayısı

-- ── Admin Grupları (QBCore fallback) ─────────────────────────────────────────
-- Öncelikli yöntem: server.cfg'de ACE permission tanımı
--   add_ace group.admin       rb-report.admin      allow
--   add_ace group.mod         rb-report.admin      allow
--   add_ace group.superadmin  rb-report.admin      allow
--   add_ace group.superadmin  rb-report.superadmin allow
-- ACE izni yoksa aşağıdaki QBCore grupları fallback olarak kullanılır.
ServerConfig.AdminGroups = {
    'admin',
    'superadmin',
    'mod',
    'moderator',
}

-- ── SuperAdmin Grupları ───────────────────────────────────────────────────────
-- Geçmiş rapor geçmişine ve admin istatistiklerine yalnızca bu gruplar erişir.
ServerConfig.SuperAdminGroups = {
    'superadmin',
}

-- ── Rate-Limit (flood koruması) ───────────────────────────────────────────────
-- Bir oyuncu MaxEvents kadar event'i MaxWindow saniye içinde gönderirse banlanır
ServerConfig.RateLimit = {
    MaxWindow   = 10,   -- saniye
    MaxEvents   = 8,    -- bu süre içinde maksimum event sayısı
}

-- ── Geçerli Kategori ID'leri (server-side whitelist) ─────────────────────────
ServerConfig.ValidCategories = {
    'cheating', 'rdm', 'vdm', 'toxicity', 'bug', 'other',
}

-- ── Discord Webhook ───────────────────────────────────────────────────────────
ServerConfig.Discord = {
    Enabled   = true,
    Webhook   = 'YOUR_DISCORD_WEBHOOK_URL_HERE',  -- Webhook URL'ini buraya yaz
    BotName   = 'Report System',
    BotAvatar = 'https://i.imgur.com/HcZHHUR.png',

    -- Embed renkleri (ondalık)
    Colors = {
        NewReport = 15548997,  -- Kırmızı
        Claimed   = 16776960,  -- Sarı
        Resolved  = 5763719,   -- Yeşil
    },
}

-- ── Log (sunucu konsolu) ──────────────────────────────────────────────────────
ServerConfig.Logging = {
    Enabled  = true,
    Prefix   = '^3[qb-report]^0',
}
