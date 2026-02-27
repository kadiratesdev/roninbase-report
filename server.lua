-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  server.lua
-- ─────────────────────────────────────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

-- ── Otomatik tablo oluşturma ──────────────────────────────────────────────────
MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `qb_reports` (
            `id`               INT          NOT NULL AUTO_INCREMENT,
            `category`         VARCHAR(64)  NOT NULL,
            `category_label`   VARCHAR(128) NOT NULL DEFAULT '',
            `description`      TEXT         NOT NULL,
            `reporter_id`      INT          NOT NULL,
            `reporter_name`    VARCHAR(128) NOT NULL DEFAULT 'Unknown',
            `target_id`        INT              NULL DEFAULT NULL,
            `target_name`      VARCHAR(128)     NULL DEFAULT NULL,
            `status`           ENUM('open','claimed','resolved') NOT NULL DEFAULT 'open',
            `claimed_by`       VARCHAR(128)     NULL DEFAULT NULL,
            `resolved_by`      VARCHAR(128)     NULL DEFAULT NULL,
            `claimed_at`       DATETIME         NULL DEFAULT NULL,
            `resolved_at`      DATETIME         NULL DEFAULT NULL,
            `resolve_duration` INT              NULL DEFAULT NULL COMMENT 'saniye cinsinden çözüm süresi',
            `created_at`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_status`      (`status`),
            INDEX `idx_resolved_by` (`resolved_by`(64)),
            INDEX `idx_created_at`  (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]], {}, function()
        print('^2[qb-report] qb_reports tablosu hazır.^0')
    end)
end)

-- ── State ─────────────────────────────────────────────────────────────────────
local Reports     = {}   -- { [id] = reportData }  (yalnızca open/claimed)
local ReportId    = 0
local Cooldowns   = {}   -- { [src] = os.time() }
local RateBuckets = {}   -- { [src] = { count, window } }

-- ─────────────────────────────────────────
--  Locale sistemi (server tarafı)
-- ─────────────────────────────────────────
local Locale = {}

local function LoadLocale(lang)
    local ok, data = pcall(function()
        return LoadResourceFile(GetCurrentResourceName(), 'locales/' .. lang .. '.lua')
    end)
    if ok and data then
        local fn, err = load('return ' .. data)
        if fn then
            return fn()
        else
            print('^1[qb-report] Locale parse hatası (' .. lang .. '): ' .. tostring(err) .. '^0')
        end
    end
    return nil
end

local function InitLocale()
    local lang = ServerConfig.Locale or 'tr'
    local data = LoadLocale(lang)
    if not data then
        print('^3[qb-report] ' .. lang .. ' server locale yüklenemedi, İngilizce\'ye düşülüyor.^0')
        data = LoadLocale('en')
    end
    Locale = data or {}
end

-- ServerConfig yüklenince locale başlat
CreateThread(function()
    Wait(0)
    InitLocale()
end)

local function T(key, vars)
    local str = Locale[key] or key
    if vars then
        for k, v in pairs(vars) do
            str = str:gsub('{' .. k .. '}', tostring(v))
        end
    end
    return str
end

-- ─────────────────────────────────────────
--  Log helper
-- ─────────────────────────────────────────
local function Log(msg)
    if ServerConfig.Logging.Enabled then
        print(ServerConfig.Logging.Prefix .. ' ' .. msg)
    end
end

-- ─────────────────────────────────────────
--  Rate-limit
-- ─────────────────────────────────────────
local function RateLimit(src)
    local now    = os.time()
    local bucket = RateBuckets[src]
    if not bucket or (now - bucket.window) >= ServerConfig.RateLimit.MaxWindow then
        RateBuckets[src] = { count = 1, window = now }
        return false
    end
    bucket.count = bucket.count + 1
    if bucket.count > ServerConfig.RateLimit.MaxEvents then
        Log('Rate-limit: src=' .. src)
        return true
    end
    return false
end

-- ─────────────────────────────────────────
--  Admin kontrolü (ACE önce, QBCore fallback)
-- ─────────────────────────────────────────
local function IsAdmin(src)
    if not src or src <= 0 then return false end
    if IsPlayerAceAllowed(tostring(src), 'rb-report.admin') then return true end
    for _, g in ipairs(ServerConfig.AdminGroups) do
        if QBCore.Functions.HasPermission(src, g) then return true end
    end
    return false
end

-- ─────────────────────────────────────────
--  SuperAdmin kontrolü (geçmiş + istatistik)
-- ─────────────────────────────────────────
local function IsSuperAdmin(src)
    if not src or src <= 0 then return false end
    if IsPlayerAceAllowed(tostring(src), 'rb-report.superadmin') then return true end
    for _, g in ipairs(ServerConfig.SuperAdminGroups) do
        if QBCore.Functions.HasPermission(src, g) then return true end
    end
    return false
end

-- ─────────────────────────────────────────
--  Karakter adı
-- ─────────────────────────────────────────
local function SafeGetName(src)
    local p = QBCore.Functions.GetPlayer(src)
    if p then
        local ci = p.PlayerData.charinfo
        if ci and ci.firstname and ci.lastname then
            return tostring(ci.firstname) .. ' ' .. tostring(ci.lastname)
        end
    end
    return 'Unknown'
end

-- ─────────────────────────────────────────
--  Sanitize
-- ─────────────────────────────────────────
local function Sanitize(input, maxLen)
    if type(input) ~= 'string' then return '' end
    return input:gsub('[%z\1-\8\11-\12\14-\31\127]', ''):sub(1, maxLen or ServerConfig.MaxDescLength)
end

-- ─────────────────────────────────────────
--  Kategori whitelist
-- ─────────────────────────────────────────
local ValidCatSet = {}
for _, v in ipairs(ServerConfig.ValidCategories) do ValidCatSet[v] = true end

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
--  Aktif rapor listesi (open + claimed)
--  Resolved buraya girmez
-- ─────────────────────────────────────────
local function GetReportList()
    local list, n = {}, 0
    for _, r in pairs(Reports) do
        if r.status ~= 'resolved' then
            n = n + 1
            list[n] = r
        end
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    return list
end

-- ─────────────────────────────────────────
--  Tüm adminlere yayın
-- ─────────────────────────────────────────
local function BroadcastToAdmins(eventName, payload)
    local players = QBCore.Functions.GetQBPlayers and QBCore.Functions.GetQBPlayers() or {}
    for _, player in pairs(players) do
        local s = player and player.PlayerData and player.PlayerData.source
        if s and IsAdmin(s) then
            TriggerClientEvent(eventName, s, payload)
        end
    end
end

-- ─────────────────────────────────────────
--  Discord Webhook
-- ─────────────────────────────────────────
local function SendDiscord(title, description, color, fields)
    local cfg = ServerConfig.Discord
    if not cfg.Enabled then return end
    if not cfg.Webhook or cfg.Webhook == '' or cfg.Webhook == 'YOUR_DISCORD_WEBHOOK_URL_HERE' then return end

    local embedFields = {}
    if fields then
        for _, f in ipairs(fields) do
            embedFields[#embedFields + 1] = { name = tostring(f.name or ''), value = tostring(f.value or '-'), inline = f.inline or false }
        end
    end

    PerformHttpRequest(cfg.Webhook,
        function(status)
            if status ~= 204 and status ~= 200 then Log('Discord HTTP hatası: ' .. tostring(status)) end
        end,
        'POST',
        json.encode({
            username = cfg.BotName, avatar_url = cfg.BotAvatar,
            embeds = {{ title = title, description = description, color = color, fields = embedFields,
                        footer = { text = 'Report System • ' .. Timestamp() } }},
        }),
        { ['Content-Type'] = 'application/json' }
    )
end

-- ═════════════════════════════════════════
--  CALLBACK: Oyuncu listesi
-- ═════════════════════════════════════════
QBCore.Functions.CreateCallback('qb-report:server:getPlayers', function(source, cb)
    if RateLimit(source) then cb({}) return end
    local players   = {}
    local qbPlayers = QBCore.Functions.GetQBPlayers()
    if not qbPlayers then cb(players) return end
    for _, player in pairs(qbPlayers) do
        if player and player.PlayerData then
            local s = player.PlayerData.source
            if s and s ~= source then
                players[#players + 1] = { id = s, name = SafeGetName(s) }
            end
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
        TriggerClientEvent('qb-core:client:Notify', src, T('no_permission'), 'error', 4000)
        Log('Yetkisiz admin panel: src=' .. src)
    end
end)

-- ═════════════════════════════════════════
--  EVENT: SuperAdmin → Geçmiş paneli
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:checkSuperAdmin', function()
    local src = source
    if RateLimit(src) then return end
    if IsSuperAdmin(src) then
        TriggerClientEvent('qb-report:client:openHistoryPanel', src)
    else
        TriggerClientEvent('qb-core:client:Notify', src, T('no_permission'), 'error', 4000)
        Log('Yetkisiz superadmin panel: src=' .. src)
    end
end)

-- ═════════════════════════════════════════
--  CALLBACK: Geçmiş raporlar (DB'den)
-- ═════════════════════════════════════════
QBCore.Functions.CreateCallback('qb-report:server:getHistory', function(source, cb, params)
    if not IsSuperAdmin(source) then cb({ reports = {}, stats = {} }) return end

    local page   = tonumber((params or {}).page)   or 1
    local limit  = 20
    local offset = (page - 1) * limit
    local filter = type((params or {}).filter) == 'string' and Sanitize(params.filter, 32) or ''
    local search = type((params or {}).search) == 'string' and Sanitize(params.search, 64) or ''

    local where  = "WHERE status = 'resolved'"
    local args   = {}
    if filter ~= '' and filter ~= 'all' then
        where = where .. " AND category = @cat"
        args['@cat'] = filter
    end
    if search ~= '' then
        where = where .. " AND (reporter_name LIKE @s OR resolved_by LIKE @s OR description LIKE @s)"
        args['@s'] = '%' .. search .. '%'
    end

    args['@limit']  = limit
    args['@offset'] = offset

    local done    = 0
    local result  = {}

    MySQL.query('SELECT * FROM qb_reports ' .. where .. ' ORDER BY resolved_at DESC LIMIT @limit OFFSET @offset', args,
        function(rows)
            result.reports = rows or {}
            done = done + 1
            if done == 3 then cb(result) end
        end
    )

    MySQL.query([[
        SELECT
            resolved_by                                      AS admin_name,
            COUNT(*)                                         AS total_resolved,
            AVG(resolve_duration)                            AS avg_duration_sec,
            MIN(resolve_duration)                            AS min_duration_sec,
            MAX(resolve_duration)                            AS max_duration_sec,
            SUM(CASE WHEN category='cheating' THEN 1 ELSE 0 END) AS cat_cheating,
            SUM(CASE WHEN category='rdm'      THEN 1 ELSE 0 END) AS cat_rdm,
            SUM(CASE WHEN category='vdm'      THEN 1 ELSE 0 END) AS cat_vdm,
            SUM(CASE WHEN category='toxicity' THEN 1 ELSE 0 END) AS cat_toxicity,
            SUM(CASE WHEN category='bug'      THEN 1 ELSE 0 END) AS cat_bug,
            SUM(CASE WHEN category='other'    THEN 1 ELSE 0 END) AS cat_other
        FROM qb_reports
        WHERE status = 'resolved' AND resolved_by IS NOT NULL
        GROUP BY resolved_by
        ORDER BY total_resolved DESC
    ]], {}, function(rows)
        result.adminStats = rows or {}
        done = done + 1
        if done == 3 then cb(result) end
    end)

    MySQL.query('SELECT COUNT(*) AS total FROM qb_reports ' .. where, args,
        function(rows)
            result.total = rows and rows[1] and rows[1].total or 0
            done = done + 1
            if done == 3 then cb(result) end
        end
    )
end)

-- ═════════════════════════════════════════
--  EVENT: Rapor gönder
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:submitReport', function(data)
    local src = source
    if RateLimit(src) then return end
    if type(data) ~= 'table' then return end

    local now = os.time()
    if Cooldowns[src] and (now - Cooldowns[src]) < ServerConfig.Cooldown then
        TriggerClientEvent('qb-report:client:cooldown', src, ServerConfig.Cooldown - (now - Cooldowns[src]))
        return
    end

    if not IsValidCategory(data.category) then return end

    local desc = Sanitize(data.description, ServerConfig.MaxDescLength)
    if #desc < 5 then
        TriggerClientEvent('qb-core:client:Notify', src, T('desc_too_short'), 'error', 4000)
        return
    end

    local targetId, targetName = nil, nil
    if data.targetId ~= nil then
        targetId = tonumber(data.targetId)
        if targetId and QBCore.Functions.GetPlayer(targetId) then
            targetName = SafeGetName(targetId)
        else
            targetId = nil
        end
    end

    local safeLabel = data.category
    if type(data.categoryLabel) == 'string' then
        safeLabel = Sanitize(data.categoryLabel, 40)
    end

    Cooldowns[src] = now
    ReportId       = ReportId + 1

    local reporterName = SafeGetName(src)
    local createdAt    = os.time()

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
        claimedAt     = nil,
        timestamp     = Timestamp(),
        createdAt     = createdAt,
    }

    Reports[ReportId] = report

    TriggerClientEvent('qb-report:client:reportSent', src)
    BroadcastToAdmins('qb-report:client:newReportAlert', report)
    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    SendDiscord(T('discord_new_report') .. ReportId, T('discord_new_report_desc'),
        ServerConfig.Discord.Colors.NewReport, {
            { name = T('discord_field_category'),    value = safeLabel,                                                                                               inline = true  },
            { name = T('discord_field_reporter'),    value = reporterName .. ' (ID: ' .. src .. ')',                                                                  inline = true  },
            { name = T('discord_field_target'),      value = targetName and (targetName .. ' (ID: ' .. targetId .. ')') or T('discord_field_not_specified'),           inline = false },
            { name = T('discord_field_description'), value = desc,                                                                                                    inline = false },
        }
    )
    Log('Yeni rapor #' .. ReportId .. ' | ' .. reporterName .. ' | ' .. data.category)
end)

-- ═════════════════════════════════════════
--  EVENT: Rapor listesi
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:getReports', function()
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then Log('Yetkisiz getReports: src=' .. src) return end
    TriggerClientEvent('qb-report:client:receiveReports', src, GetReportList())
end)

-- ═════════════════════════════════════════
--  EVENT: Raporu üstlen
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:claimReport', function(reportId)
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then Log('Yetkisiz claimReport: src=' .. src) return end

    reportId = tonumber(reportId)
    if not reportId then return end

    local r = Reports[reportId]
    if not r or r.status ~= 'open' then return end

    r.status    = 'claimed'
    r.claimedBy = SafeGetName(src) .. ' (ID: ' .. src .. ')'
    r.claimedAt = os.time()

    if r.reporterId and QBCore.Functions.GetPlayer(r.reporterId) then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId, T('report_claimed'), 'success', 6000)
    end

    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    SendDiscord(T('discord_new_report') .. reportId .. T('discord_claimed'), '', ServerConfig.Discord.Colors.Claimed, {
        { name = T('discord_field_report_id'), value = tostring(reportId), inline = true  },
        { name = T('discord_field_admin'),     value = r.claimedBy,        inline = true  },
        { name = T('discord_field_category'),  value = r.categoryLabel,    inline = false },
    })
    Log('Rapor #' .. reportId .. ' üstlenildi → ' .. r.claimedBy)
end)

-- ═════════════════════════════════════════
--  EVENT: Raporu çöz → DB'ye kaydet, bellekten sil
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:resolveReport', function(reportId)
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then Log('Yetkisiz resolveReport: src=' .. src) return end

    reportId = tonumber(reportId)
    if not reportId then return end

    local r = Reports[reportId]
    if not r or r.status == 'resolved' then return end

    local resolvedBy   = SafeGetName(src) .. ' (ID: ' .. src .. ')'
    local resolvedAt   = os.time()
    local resolvedAtDT = os.date('%Y-%m-%d %H:%M:%S', resolvedAt)
    local claimedAtDT  = r.claimedAt and os.date('%Y-%m-%d %H:%M:%S', r.claimedAt) or nil
    local duration     = resolvedAt - (r.createdAt or resolvedAt)

    if r.reporterId and QBCore.Functions.GetPlayer(r.reporterId) then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId, T('report_resolved'), 'success', 6000)
    end

    MySQL.query([[
        INSERT INTO qb_reports
            (id, category, category_label, description, reporter_id, reporter_name,
             target_id, target_name, status, claimed_by, resolved_by,
             claimed_at, resolved_at, resolve_duration, created_at)
        VALUES
            (@id, @cat, @catLabel, @desc, @rid, @rname,
             @tid, @tname, 'resolved', @claimedBy, @resolvedBy,
             @claimedAt, @resolvedAt, @duration, @createdAt)
        ON DUPLICATE KEY UPDATE
            status           = 'resolved',
            claimed_by       = @claimedBy,
            resolved_by      = @resolvedBy,
            claimed_at       = @claimedAt,
            resolved_at      = @resolvedAt,
            resolve_duration = @duration
    ]], {
        ['@id']         = r.id,
        ['@cat']        = r.category,
        ['@catLabel']   = r.categoryLabel,
        ['@desc']       = r.description,
        ['@rid']        = r.reporterId,
        ['@rname']      = r.reporterName,
        ['@tid']        = r.targetId,
        ['@tname']      = r.targetName,
        ['@claimedBy']  = r.claimedBy,
        ['@resolvedBy'] = resolvedBy,
        ['@claimedAt']  = claimedAtDT,
        ['@resolvedAt'] = resolvedAtDT,
        ['@duration']   = duration,
        ['@createdAt']  = os.date('%Y-%m-%d %H:%M:%S', r.createdAt or resolvedAt),
    }, function() end)

    Reports[reportId] = nil

    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    local durMin = math.floor(duration / 60)
    local durSec = duration % 60
    local durStr = T('discord_duration_fmt', { min = durMin, sec = durSec })

    SendDiscord(T('discord_new_report') .. reportId .. T('discord_resolved'), '', ServerConfig.Discord.Colors.Resolved, {
        { name = T('discord_field_report_id'),   value = tostring(reportId), inline = true  },
        { name = T('discord_field_closer'),      value = resolvedBy,         inline = true  },
        { name = T('discord_field_duration'),    value = durStr,             inline = true  },
        { name = T('discord_field_category'),    value = r.categoryLabel,    inline = false },
        { name = T('discord_field_description'), value = r.description,      inline = false },
    })
    Log('Rapor #' .. reportId .. ' çözüldü → ' .. resolvedBy .. ' (' .. duration .. 's)')
end)

-- ═════════════════════════════════════════
--  EVENT: Oyuncuya ışınlan
-- ═════════════════════════════════════════
RegisterNetEvent('qb-report:server:teleportToReporter', function(targetPlayerId)
    local src = source
    if RateLimit(src) then return end
    if not IsAdmin(src) then Log('Yetkisiz teleport: src=' .. src) return end

    targetPlayerId = tonumber(targetPlayerId)
    if not targetPlayerId or not QBCore.Functions.GetPlayer(targetPlayerId) then return end

    local coords = GetEntityCoords(GetPlayerPed(targetPlayerId))
    if coords then
        TriggerClientEvent('qb-report:client:teleportCoords', src, { x = coords.x, y = coords.y, z = coords.z })
    end
end)

-- ═════════════════════════════════════════
--  Oyuncu çıkınca temizle
-- ═════════════════════════════════════════
AddEventHandler('playerDropped', function()
    local src = source
    Cooldowns[src]   = nil
    RateBuckets[src] = nil
end)
