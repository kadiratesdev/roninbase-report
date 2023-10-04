Config = {}

Config.CommandName = 'report'

Config.AdminGroups = {
    "god",
    'admin',
    "mod"
}

Config.Locales = {
    ["create_new_report"] = "Yeni Rapor Oluştur",
    ['my_report'] = "Raporlarım",
    ['my_report_sub'] = "Oluşturduğunuz tüm raporları görüntüleyin",
    ['staff_list'] = "Aktif Yetkililer",
    ['fill_all'] = "Lütfen tüm gerekli alanları doldurun",
    ["player"] = "Oyuncu",
    ['bug'] = "Hata",
    ["other"] = "Diğer",
    ['type_title'] = "Başlık Türü",
    ['create'] = "Oluştur",
    ['no_closedate'] = "Hiçbiri",
    ['pending'] = "Beklemede",
    ['open'] = "Açık",
    ['closed'] = "Kapalı",
    ['view_image'] = "Resmi Görüntüle",
    ['title'] = "Başlık",
    ['status'] = "Durum",
    ['open_date'] = "Açılış Tarihi",
    ['close_date'] = "Kapanış Tarihi",
    ['type_message'] = "Bir mesaj yazın",
    ['admin_in_report'] = "İlgilenen Yetkili Sayısı",
    ['all_report'] = "Tüm Raporlar",
    ['report_claimed'] = "Üzerine Aldıkların",
    ['ban'] = "Banla",
    ['kick'] = "Oyundan At",
    ['close_report'] = "Raporu Kapat",
    ['claim_report'] = "Raporu Üzerine Al",
    ['player_name'] = "Oyuncu Adı",
    ['copied'] = "Kopyalandı!",
    ['message_error'] = "Mesaj hata...",
    ['type'] = "Tür",
    ['send_image'] = "[E] Resim Gönder",
    ['new_message'] = "Raporunuzda yeni bir mesajınız var",
    ['your_report_claimed'] = "Raporunuz talep edildi",
    ['confirm'] = "Onayla",
    ['type_reason'] = "Bir neden yazın",
    ['player_off'] = "Oyuncu çevrimdışı",
    ['new_report'] = "Yeni Rapor!",
    ['reason_error'] = "Geçersiz neden!"
}

Ban = function(identifier, reason)
    print("Banned "..identifier.." for "..reason)
    -- Inserire il trigger
end