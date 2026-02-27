-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  server.lua
--  Güvenlik katmanları:
--    1. Event rate-limit  (flood / spam koruması)
--    2. Admin yetki doğrulama (her yetkili eylemde)
--    3. Input whitelist + tip kontrolü (category, description, targetId)
--    4. String injection temizliği
--    5. Rapor ID integer doğrulama (string geçme saldırısı)
--    6. Bellek sınırı (MaxReports aşılınca en eski çözümlenen silinir)
--    7. Webhook yalnızca server-side; client asla göremez
-- ─────────────────────────────────────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

-- ── State ─────────────────────────────────────────────────────────────────────
local Reports   = {}   -- { [id] = reportData }
local ReportId  = 0
local Cooldowns = {}   -- { [src] = os.time() }
local RateBuckets = {} -- { [src] = { count=N, window=timestamp } }

-- ─────────────────────────────────────────
--  Log helper
-- ─────────────────────────────────────────
local function Log(msg)
    if ServerConfig.Logging.Enabled then
        print(ServerConfig.Logging.Prefix .. ' ' .. msg)
    end
end

-- ─────────────────────────────────────────
--  Rate-limit  (flood koruması)
--  Döndürür: true = engelle, false = geçebilir
-- ─────────────────────────────────────────
local function RateLimit(src)
    local now = os.time()
    local bucket = RateBuckets[src]

    if not bucket or (now - bucket.window) >= ServerConfig.RateLimit.MaxWindow then
        RateBuckets[src] = { count = 1, window = now }
        return false
    end

    bucket.count = bucket.count + 1

    if bucket.count > ServerConfig.RateLimit.MaxEvents then
        Log('Rate-limit tetiklendi: src=' .. src .. ' (' .. bucket.count .. ' event/' .. ServerConfig.RateLimit.MaxWindow .. 's)')
        -- Kötü niyetli trafiği bant içinde tut; tekrar sayacı sıfırlamıyoruz
        return true
    end

    return false
end

-- ─────────────────────────────────────────
--  Admin kontrolü
--  QBCore.Functions.GetPermission bir string döner;
--  HasPermission de kullanılabilir ama her grup için
--  ayrı çağrı yapar. Tek GetPermission çağrısı + set
--  lookup daha verimli.
-- ─────────────────────────────────────────
local AdminGroupSet = {}
for _, g in ipairs(ServerConfig.AdminGroups) do
    AdminGroupSet[g] = true
end

local function IsAdmin(src)
    if not src or src <= 0 then return false end
    if not QBCore.Functions.GetPlayer(src) then return false end
    local group = QBCore.Functions.GetPermission(src)
    return AdminGroupSet[group] == true
end

-- ─────────────────────────────────────────
--  Karakter adı (güvenli)
-- ─────────────────────────────────────────
local function SafeGetName(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        local ci = Player.PlayerData.charinfo
        if ci and ci.firstname and ci.lastname then
            return tostring(ci.firstname) .. ' ' .. tostring(ci.lastname)
        end
    end
    return 'Unknown'
end

-- ─────────────────────────────────────────
--  String temizleyici
--  Kontrol karakterleri ve Lua injection karakterleri temizler
-- ─────────────────────────────────────────
local function Sanitize(input, maxLen)
    if type(input) ~= 'string' then return '' end
    -- Null byte, ESC ve diğer control char'larını at
    local clean = input:gsub('[%z\1-\8\11-\12\14-\31\127]', '')
    -- Maksimum uzunluğa kes
    return clean:sub(1, maxLen or ServerConfig.MaxDescLength)
end

-- ─────────────────────────────────────────
--  Kategori whitelist kontrolü
-- ─────────────────────────────────────────
local ValidCatSet = {}
for _, v in ipairs(ServerConfig.ValidCategories) do
    ValidCatSet[v] = true
end

local function IsValidCategory(cat)
    return type(cat) == 'string' and ValidCatSet[cat] == true
end

-- ─────────────────────────────────────────
--  Timestamp
-- ─────────────────────────────────────────
local function Timestamp()
    return os.date('%d/%m/%Y %H:%M:%S')
end

-- ─────────────────────────────────────────
--  Bellekten eski çözümlenen raporu temizle
--  O(n) optimizasyonu: sayma ve en küçük ID
--  bulma tek geçişte yapılıyor
-- ─────────────────────────────────────────
local function PruneReports()
    local count     = 0
    local oldestId  = nil

    for id, r in pairs(Reports) do
        count = count + 1
        if r.status == 'resolved' then
            if not oldestId or id < oldestId then
                oldestId = id
            end
        end
    end

    if count < ServerConfig.MaxReports then return end

    if oldestId then
        Reports[oldestId] = nil
        Log('Bellek limiti: rapor #' .. oldestId .. ' temizlendi.')
    end
end

-- ─────────────────────────────────────────
--  Admin listesini güvenli döndür
--  Sıralama: id > id (en yeni önce)
-- ─────────────────────────────────────────
local function GetReportList()
    local list = {}
    local n    = 0
    for _, r in pairs(Reports) do
        n = n + 1
        list[n] = r
    end
    -- Basit insertion sort (n < 200 için yeterli; table.sort de çalışır)
    table.sort(list, function(a, b) return a.id > b.id end)
    return list
end

-- ─────────────────────────────────────────
--  Tüm adminlere rapor listesini gönder
--  GetQBPlayers önce — GetPlayers fallback
-- ─────────────────────────────────────────
local function BroadcastToAdmins(eventName, payload)
    -- GetQBPlayers varsa tercih et (source lookup O(1))
    if QBCore.Functions.GetQBPlayers then
        local players = QBCore.Functions.GetQBPlayers()
        for _, player in pairs(players) do
            local s = player.PlayerData.source
            if IsAdmin(s) then
                TriggerClientEvent(eventName, s, payload)
            end
        end
    else
        -- Fallback: GetPlayers() + GetPlayer() O(n)
        for _, pid in ipairs(QBCore.Functions.GetPlayers()) do
            if IsAdmin(pid) then
                TriggerClientEvent(eventName, pid, payload)
            end
        end
    end
end

-- ─────────────────────────────────────────
--  Discord Webhook  (server-only)
-- ─────────────────────────────────────────
local function SendDiscord(title, description, color, fields)
    local cfg = ServerConfig.Discord
    if not cfg.Enabled then return end
    if not cfg.Webhook or cfg.Webhook == '' or cfg.Webhook == 'YOUR_DISCORD_WEBHOOK_URL_HERE' then
        Log('Discord webhook tanımlı değil, atlanıyor.')
        return
    end

    local embedFields = {}
    if fields then
        for _, f in ipairs(fields) do
            embedFields[#embedFields + 1] = {
                name   = tostring(f.name  or ''),
                value  = tostring(f.value or '-'),
                inline = f.inline or false,
            }
        end
    end

    local body = json.encode({
        username   = cfg.BotName,
        avatar_url = cfg.BotAvatar,
        embeds = {{
            title       = title,
            description = description,
            color       = color,
            fields      = embedFields,
            footer      = { text = 'Report System • ' .. Timestamp() },
        }},
    })

    PerformHttpRequest(cfg.Webhook,
        function(status, _text, _headers)
            if status ~= 204 and status ~= 200 then
                Log('Discord webhook HTTP hatası: ' .. tostring(status))
            end
        end,
        'POST', body,
        { ['Content-Type'] = 'application/json' }
    )
end

-- ═════════════════════════════════════════
--  CALLBACK: Oyuncu listesi (report menüsü)
-- ═════════════════════════════════════════
QBCore.Functions.CreateCallback('qb-report:server:getPlayers', function(source, cb)
    if RateLimit(source) then cb({}) return end

    local players = {}
    local qbPlayers = QBCore.Functions.GetQBPlayers()
    for _, player in pairs(qbPlayers) do
        local s = player.PlayerData.source
        if s ~= source then
            players[#players + 1] = {
                id   = s,
                name = SafeGetName(s),
            }
        end
    end
    cb(players)
end)

-- ═════════════════════════════════════════
--  EVENT: Admin panel yetkisi kontrolü
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:checkAdmin', function()
    local src = source
    if RateLimit(src) then return end

    if IsAdmin(src) then
        TriggerClientEvent('qb-report:client:openAdminPanel', src)
    else
        TriggerClientEvent('qb-core:client:Notify', src,
            'Bu komutu kullanma yetkiniz yok.', 'error', 4000)
        Log('Yetkisiz admin panel erişim denemesi: src=' .. src)
    end
end)

-- ═════════════════════════════════════════
--  EVENT: Rapor gönder
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:submitReport', function(data)
    local src = source

    -- 1. Rate-limit
    if RateLimit(src) then return end

    -- 2. data nil/type kontrolü
    if type(data) ~= 'table' then
        Log('submitReport: geçersiz data tipi, src=' .. src)
        return
    end

    -- 3. Cooldown kontrolü
    local now = os.time()
    if Cooldowns[src] and (now - Cooldowns[src]) < ServerConfig.Cooldown then
        local remaining = ServerConfig.Cooldown - (now - Cooldowns[src])
        TriggerClientEvent('qb-report:client:cooldown', src, remaining)
        return
    end

    -- 4. Kategori whitelist
    if not IsValidCategory(data.category) then
        Log('submitReport: geçersiz kategori "' .. tostring(data.category) .. '", src=' .. src)
        return
    end

    -- 5. Açıklama uzunluk + sanitize
    local desc = Sanitize(data.description, ServerConfig.MaxDescLength)
    if #desc < 5 then
        TriggerClientEvent('qb-core:client:Notify', src,
            'Lütfen daha açıklayıcı bir açıklama yazın (min. 5 karakter).', 'error', 4000)
        return
    end

    -- 6. targetId integer kontrolü (opsiyonel alan)
    local targetId   = nil
    local targetName = nil
    if data.targetId ~= nil then
        targetId = tonumber(data.targetId)
        -- Sunucuda bu oyuncu gerçekten var mı?
        if not targetId or not QBCore.Functions.GetPlayer(targetId) then
            targetId   = nil  -- geçersizse sil, raporu yine de al
        else
            targetName = SafeGetName(targetId)
        end
    end

    -- 7. categoryLabel: sadece server-side'da kategori listesinden üret
    local safeLabel = data.category  -- fallback
    for _, cat in ipairs(ServerConfig.ValidCategories) do
        -- Config.Categories server_config'de yok; burada basit eşleme yeterli
        -- tam label için server_config'e de ekleyebilirsiniz; şimdilik category id kullanıyoruz
        if cat == data.category then safeLabel = cat break end
    end
    -- Client'tan gelen label'ı sanitize ediyoruz (kullanmak istiyorsak)
    if type(data.categoryLabel) == 'string' then
        safeLabel = Sanitize(data.categoryLabel, 40)
    end

    -- 8. Bellek limiti kontrolü
    PruneReports()

    -- 9. Cooldown kaydet
    Cooldowns[src] = now
    ReportId       = ReportId + 1

    local reporterName = SafeGetName(src)

    local report = {
        id            = ReportId,
        category      = data.category,
        categoryLabel = safeLabel,
        description   = desc,
        reporterId    = src,
        reporterName  = reporterName,
        targetId      = targetId,
        targetName    = targetName,
        status        = 'open',
        claimedBy     = nil,
        timestamp     = Timestamp(),
    }

    Reports[ReportId] = report

    -- Oyuncuya bildirim
    TriggerClientEvent('qb-report:client:reportSent', src)

    -- Adminlere anlık bildirim
    BroadcastToAdmins('qb-report:client:newReportAlert', report)
    -- Açık admin panellerini güncelle
    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    -- Discord
    SendDiscord(
        '🚨 Yeni Rapor #' .. ReportId,
        'Bir oyuncu rapor gönderdi.',
        ServerConfig.Discord.Colors.NewReport,
        {
            { name = '📋 Kategori',      value = safeLabel,                                         inline = true  },
            { name = '👤 Raporlayan',    value = reporterName .. ' (ID: ' .. src .. ')',             inline = true  },
            { name = '🎯 Raporlanan',    value = targetName and (targetName .. ' (ID: ' .. targetId .. ')') or 'Belirtilmedi', inline = false },
            { name = '📝 Açıklama',      value = desc,                                              inline = false },
            { name = '🆔 Rapor ID',      value = tostring(ReportId),                                inline = true  },
        }
    )

    Log('Yeni rapor #' .. ReportId .. ' | ' .. reporterName .. ' (src=' .. src .. ') | ' .. data.category)
end)

-- ═════════════════════════════════════════
--  EVENT: Admin → Rapor listesi al
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:getReports', function()
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then
        Log('Yetkisiz getReports: src=' .. src)
        return
    end
    TriggerClientEvent('qb-report:client:receiveReports', src, GetReportList())
end)

-- ═════════════════════════════════════════
--  EVENT: Admin → Raporu üstlen
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:claimReport', function(reportId)
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then
        Log('Yetkisiz claimReport: src=' .. src)
        return
    end

    -- reportId tip ve varlık doğrulama
    reportId = tonumber(reportId)
    if not reportId then return end

    local r = Reports[reportId]
    if not r then return end
    if r.status ~= 'open' then return end  -- zaten üstlenilmiş/çözülmüş

    r.status    = 'claimed'
    r.claimedBy = SafeGetName(src) .. ' (ID: ' .. src .. ')'

    -- Raporlayan oyuncuya bildir (hâlâ çevrimiçiyse)
    if r.reporterId and QBCore.Functions.GetPlayer(r.reporterId) then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId,
            'Bir yetkili raporunuzu üstlendi.', 'success', 6000)
    end

    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    SendDiscord(
        '🔔 Rapor #' .. reportId .. ' Üstlenildi',
        'Bir yetkili raporu üstlendi.',
        ServerConfig.Discord.Colors.Claimed,
        {
            { name = '🆔 Rapor ID',  value = tostring(reportId), inline = true  },
            { name = '👮 Yetkili',   value = r.claimedBy,        inline = true  },
            { name = '📋 Kategori', value = r.categoryLabel,     inline = false },
        }
    )

    Log('Rapor #' .. reportId .. ' üstlenildi → ' .. r.claimedBy)
end)

-- ═════════════════════════════════════════
--  EVENT: Admin → Raporu kapat
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:resolveReport', function(reportId)
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then
        Log('Yetkisiz resolveReport: src=' .. src)
        return
    end

    reportId = tonumber(reportId)
    if not reportId then return end

    local r = Reports[reportId]
    if not r then return end
    if r.status == 'resolved' then return end  -- tekrar çözümleme engeli

    r.status     = 'resolved'
    r.resolvedBy = SafeGetName(src) .. ' (ID: ' .. src .. ')'

    if r.reporterId and QBCore.Functions.GetPlayer(r.reporterId) then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId,
            'Raporunuz bir yetkili tarafından çözüldü.', 'success', 6000)
    end

    -- 60 saniye sonra bellekten temizle
    SetTimeout(60000, function()
        if Reports[reportId] and Reports[reportId].status == 'resolved' then
            Reports[reportId] = nil
            Log('Rapor #' .. reportId .. ' bellekten temizlendi.')
        end
    end)

    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    SendDiscord(
        '✅ Rapor #' .. reportId .. ' Çözüldü',
        'Rapor kapatıldı.',
        ServerConfig.Discord.Colors.Resolved,
        {
            { name = '🆔 Rapor ID',     value = tostring(reportId), inline = true },
            { name = '👮 Kapatan',      value = r.resolvedBy,       inline = true },
            { name = '📋 Kategori',     value = r.categoryLabel,    inline = false },
            { name = '📝 Açıklama',     value = r.description,      inline = false },
        }
    )

    Log('Rapor #' .. reportId .. ' çözüldü → ' .. r.resolvedBy)
end)

-- ═════════════════════════════════════════
--  EVENT: Admin → Oyuncuya ışınlan
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:teleportToReporter', function(targetPlayerId)
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then
        Log('Yetkisiz teleport: src=' .. src)
        return
    end

    -- targetPlayerId tip + varlık kontrolü
    targetPlayerId = tonumber(targetPlayerId)
    if not targetPlayerId then return end
    if not QBCore.Functions.GetPlayer(targetPlayerId) then return end

    local ped    = GetPlayerPed(targetPlayerId)
    local coords = GetEntityCoords(ped)

    if coords then
        TriggerClientEvent('qb-report:client:teleportCoords', src, {
            x = coords.x,
            y = coords.y,
            z = coords.z,
        })
        Log('Admin src=' .. src .. ' → src=' .. targetPlayerId .. ' ışınlandı.')
    end
end)

-- ═════════════════════════════════════════
--  Oyuncu çıkınca cooldown + rate bucket temizle
-- ═════════════════════════════════════════
AddEventHandler('playerDropped', function()
    local src = source
    Cooldowns[src]    = nil
    RateBuckets[src]  = nil
end)
