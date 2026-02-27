-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  Türkçe Çeviriler
-- ─────────────────────────────────────────────────────────────────────────────
return {
    -- Client bildirimleri
    report_sent         = 'Raporunuz iletildi. Bir yetkili en kısa sürede inceleyecek.',
    admin_notify        = 'Yeni bir oyuncu raporu alındı.',
    cooldown            = 'Tekrar rapor göndermek için {seconds} saniye beklemeniz gerekiyor.',
    no_permission    = 'Bu komutu kullanma yetkiniz yok.',
    already_have_active_report = 'Zaten açık bir raporunuz bulunuyor, lütfen çözülmesini bekleyin.',
    desc_too_short      = 'Lütfen daha açıklayıcı bir açıklama yazın (min. 5 karakter).',
    report_claimed      = 'Bir yetkili raporunuzu üstlendi.',
    report_resolved     = 'Raporunuz bir yetkili tarafından çözüldü.',

    -- Discord embed etiketleri
    discord_new_report        = '🚨 Yeni Rapor #',
    discord_new_report_desc   = 'Bir oyuncu rapor gönderdi.',
    discord_claimed           = ' Üstlenildi',
    discord_resolved          = ' Çözüldü',
    discord_field_category    = '📋 Kategori',
    discord_field_reporter    = '👤 Raporlayan',
    discord_field_target      = '🎯 Raporlanan',
    discord_field_description = '📝 Açıklama',
    discord_field_admin       = '👮 Yetkili',
    discord_field_report_id   = '🆔 Rapor ID',
    discord_field_closer      = '👮 Kapatan',
    discord_field_duration    = '⏱️ Süre',
    discord_field_not_specified = 'Belirtilmedi',
    discord_duration_fmt      = '{min} dk {sec} sn',
    
    filter_all      = 'Tümü',

    -- Kategori etiketleri
    cat_cheating   = 'Hile / Hack',
    cat_rdm        = 'RDM (Rastgele Öldürme)',
    cat_vdm        = 'VDM (Araçla Öldürme)',
    cat_toxicity   = 'Toksisite / Taciz',
    cat_bug        = 'Hata Bildirimi',
    cat_other      = 'Diğer',
}
