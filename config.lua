-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  Client-side Config
--  NOT: Discord webhook ve sunucu ayarları server_config.lua dosyasındadır.
--       Bu dosya yalnızca client script tarafından yüklenir.
-- ─────────────────────────────────────────────────────────────────────────────
Config = {}

-- ── Dil ayarı ─────────────────────────────────────────────────────────────────
-- 'tr' = Türkçe  |  'en' = English
Config.Locale = 'tr'

-- ── Komutlar ──────────────────────────────────────────────────────────────────
Config.Command            = 'report'        -- Oyuncunun rapor menüsünü açma komutu
Config.AdminCommand       = 'reports'       -- Admin paneli açma komutu
Config.SuperAdminCommand  = 'reporthistory' -- Geçmiş + istatistik paneli (superadmin)

-- ── Rapor kategorileri (NUI'ye gönderilir) ────────────────────────────────────
-- Etiketler locale dosyasından otomatik çekilir (locale sistemi yüklendikten sonra güncellenir)
Config.Categories = {
    { id = 'cheating',  icon = '🎮', color = '#e74c3c' },
    { id = 'rdm',       icon = '🔫', color = '#e67e22' },
    { id = 'vdm',       icon = '🚗', color = '#f39c12' },
    { id = 'toxicity',  icon = '💬', color = '#9b59b6' },
    { id = 'bug',       icon = '🐛', color = '#3498db' },
    { id = 'other',     icon = '📋', color = '#95a5a6' },
}
