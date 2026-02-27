-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  Client-side Config
--  NOT: Discord webhook ve sunucu ayarları server_config.lua dosyasındadır.
--       Bu dosya yalnızca client script tarafından yüklenir.
-- ─────────────────────────────────────────────────────────────────────────────
Config = {}

-- Komutlar
Config.Command      = 'report'   -- Oyuncunun rapor menüsünü açma komutu
Config.AdminCommand = 'reports'  -- Admin paneli açma komutu

-- Rapor kategorileri (NUI'ye gönderilir)
Config.Categories = {
    { id = 'cheating',  label = 'Cheating / Hacking',      icon = '🎮', color = '#e74c3c' },
    { id = 'rdm',       label = 'RDM (Random Deathmatch)',  icon = '🔫', color = '#e67e22' },
    { id = 'vdm',       label = 'VDM (Vehicle Deathmatch)', icon = '🚗', color = '#f39c12' },
    { id = 'toxicity',  label = 'Toxicity / Harassment',    icon = '💬', color = '#9b59b6' },
    { id = 'bug',       label = 'Bug Report',               icon = '🐛', color = '#3498db' },
    { id = 'other',     label = 'Other',                    icon = '📋', color = '#95a5a6' },
}

-- Client bildirim metinleri
Config.Notifications = {
    ReportSent  = 'Raporunuz iletildi. Bir yetkili en kısa sürede inceleyecek.',
    AdminNotify = 'Yeni bir oyuncu raporu alındı.',
}
