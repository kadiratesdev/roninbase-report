-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  server.lua
-- ─────────────────────────────────────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

-- ── State ─────────────────────────────────────────────────────────────────────
local Reports         = {}   -- { [id] = reportData }  (yalnızca open/claimed)
local ReportId        = 0
local ReportIdReady   = false  -- Flag to check if MAX(id) query has completed
local Cooldowns       = {}   -- { [src] = os.time() }
local RateBuckets     = {}   -- { [src] = { count, window } }

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
            `claimed_by`       VARCHAR(128)     NULL DEFAULT NULL COMMENT 'Yetkili license identifier',
            `resolved_by`      VARCHAR(128)     NULL DEFAULT NULL COMMENT 'Yetkili license identifier',
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
        
        MySQL.query('SELECT MAX(id) as maxId FROM qb_reports', {}, function(result)
            local prevReportId = ReportId
            if result and result[1] and result[1].maxId then
                ReportId = result[1].maxId
                print('^2[qb-report] Rapor ID başlangıcı ayarlandı: ' .. ReportId .. '^0')
            else
                -- DEBUG: Log when table is empty or MAX returns NULL
                print('^3[qb-report DEBUG] MAX(id) returned nil - table may be empty or first report needed. Previous ReportId: ' .. prevReportId .. '^0')
            end
            ReportIdReady = true  -- Mark as ready after query completes
            print('^3[qb-report DEBUG] ReportIdReady set to true^0')
        end)

        -- Sunucu başladığında aktif raporları DB'den memory'e yükle
        -- claimed_by license'ını players tablosundan JOIN ile isim olarak çek
        MySQL.query([[
            SELECT
                r.*,
                COALESCE(p_claim.name, r.claimed_by) AS claimed_by_display
            FROM qb_reports r
            LEFT JOIN players p_claim ON p_claim.license = r.claimed_by
            WHERE r.status IN ('open', 'claimed', 'in_progress')
        ]], {}, function(activeReports)
            if activeReports and #activeReports > 0 then
                for _, row in ipairs(activeReports) do
                    local created_ts = os.time()
                    if type(row.created_at) == "number" then
                        created_ts = row.created_at > 10000000000 and math.floor(row.created_at / 1000) or row.created_at
                    elseif type(row.created_at) == "string" then
                        local y, m, d, h, min, s = row.created_at:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
                        if y and m and d and h and min and s then
                            created_ts = os.time({year=y, month=m, day=d, hour=h, min=min, sec=s})
                        end
                    end
                    Reports[row.id] = {
                        id = row.id,
                        category = row.category,
                        categoryLabel = row.category_label,
                        description = row.description,
                        reporterId = row.reporter_id,
                        reporterName = row.reporter_name,
                        targetId = row.target_id,
                        targetName = row.target_name,
                        status = row.status,
                        -- claimed_by_display: players JOIN ile çekilen isim (yoksa license değeri)
                        claimedBy = row.claimed_by_display or row.claimed_by,
                        claimedByLicense = row.claimed_by,
                        claimedAt = row.claimed_at,
                        timestamp = row.created_at and tostring(row.created_at) or tostring(os.time()),
                        createdAt = created_ts
                    }
                end
                print('^2[qb-report] Toplam ' .. #activeReports .. ' aktif rapor belleğe yüklendi.^0')
            end
        end)
    end)
end)

-- ─────────────────────────────────────────
--  Locale sistemi (server tarafı)
-- ─────────────────────────────────────────
local Locale = {}

local function LoadLocale(lang)
    local ok, data = pcall(function()
        return LoadResourceFile(GetCurrentResourceName(), 'locales/' .. lang .. '.lua')
    end)
    if ok and data then
        local fn, err = load(data)
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
--  Oyuncu license'ı al
-- ─────────────────────────────────────────
local function GetPlayerLicense(src)
    -- Önce QBCore PlayerData'dan dene
    local p = QBCore.Functions.GetPlayer(src)
    if p and p.PlayerData and p.PlayerData.license then
        return tostring(p.PlayerData.license)
    end
    -- Fallback: GetPlayerIdentifiers üzerinden
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, 8) == 'license:' then
            return id
        end
    end
    return nil
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

-- Format timestamp (could be string or number) to readable date
local function FormatTimestamp(ts)
    if not ts or ts == '' then return '-' end
    local num = tonumber(ts)
    if num then
        -- Check if it's milliseconds (greater than 10000000000)
        if num > 10000000000 then
            num = math.floor(num / 1000)
        end
        return os.date('%d/%m/%Y %H:%M:%S', num)
    end
    -- If it's already a string, return as-is
    return tostring(ts)
end

-- Format DB row timestamps for frontend
local function FormatReportForHistory(report)
    if not report then return nil end
    local formatted = {}
    for k, v in pairs(report) do
        if k == 'resolved_at' or k == 'claimed_at' or k == 'created_at' then
            formatted[k] = FormatTimestamp(v)
        else
            formatted[k] = v
        end
    end
    return formatted
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
    if not qbPlayers then 
        print('^3[qb-report] GetQBPlayers returned nil^0')
        cb(players) 
        return 
    end
    local playerCount = 0
    for _, player in pairs(qbPlayers) do
        playerCount = playerCount + 1
        if player and player.PlayerData then
            local s = player.PlayerData.source
            -- Debug: Show all players including self
            print('^3[qb-report] Player found: ' .. tostring(s) .. ' (self: ' .. tostring(s == source) .. ')^0')
            if s and s ~= source then
                players[#players + 1] = { id = s, name = SafeGetName(s) }
            end
        end
    end
    print('^3[qb-report] Total players on server: ' .. playerCount .. ', Excluding self: ' .. #players .. '^0')
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
    local categoryFilter = type((params or {}).filter) == 'string' and Sanitize(params.filter, 32) or ''
    local statusFilter = type((params or {}).status) == 'string' and params.status or 'all'
    local search = type((params or {}).search) == 'string' and Sanitize(params.search, 64) or ''

    -- DEBUG: Log the query parameters
    print('^3[qb-report DEBUG] getHistory called - page: ' .. page .. ', categoryFilter: ' .. tostring(categoryFilter) .. ', statusFilter: ' .. tostring(statusFilter) .. ', search: ' .. tostring(search) .. '^0')

    -- Geçmiş raporlar: status filtresi seçilmişse direkt o status, yoksa tüm geçmiş (resolved vb.)
    local where  = "WHERE 1=1"
    local args   = {}

    if statusFilter ~= 'all' then
        -- Belirli bir status seçildi
        where = where .. " AND r.status = @status"
        args['@status'] = statusFilter
    else
        -- "Tümü" seçildi → sadece geçmiş (resolved, closed, canceled) raporları göster
        where = where .. " AND r.status NOT IN ('open', 'claimed', 'in_progress')"
    end
    
    -- Filter by category
    if categoryFilter ~= '' and categoryFilter ~= 'all' then
        where = where .. " AND r.category = @cat"
        args['@cat'] = categoryFilter
    end
    if search ~= '' then
        where = where .. " AND (r.reporter_name LIKE @s OR COALESCE(p_res.name, r.resolved_by) LIKE @s OR r.description LIKE @s)"
        args['@s'] = '%' .. search .. '%'
    end

    args['@limit']  = limit
    args['@offset'] = offset

    local done    = 0
    local result  = {}

    -- Ana sorgu: claimed_by ve resolved_by license'larını players tablosundan JOIN ile isim olarak çek
    local selectQuery = [[
        SELECT
            r.*,
            COALESCE(p_claim.name, r.claimed_by)  AS claimed_by_display,
            COALESCE(p_res.name,   r.resolved_by)  AS resolved_by_display
        FROM qb_reports r
        LEFT JOIN players p_claim ON p_claim.license = r.claimed_by
        LEFT JOIN players p_res   ON p_res.license   = r.resolved_by
        ]] .. where .. [[ ORDER BY r.created_at DESC LIMIT @limit OFFSET @offset]]

    print('^3[qb-report DEBUG] SELECT query with JOIN: ' .. selectQuery .. '^0')

    MySQL.query(selectQuery, args,
        function(rows)
            -- Format timestamps for each report
            if rows and #rows > 0 then
                for i, report in ipairs(rows) do
                    local formatted = FormatReportForHistory(report)
                    -- Display alanlarını claimed_by / resolved_by olarak üzerine yaz
                    formatted.claimed_by  = report.claimed_by_display  or report.claimed_by
                    formatted.resolved_by = report.resolved_by_display or report.resolved_by
                    rows[i] = formatted
                end
            end
            result.reports = rows or {}
            done = done + 1
            if done == 3 then cb(result) end
        end
    )

    -- İstatistik sorgusu: resolved_by license'ını players tablosundan JOIN ile isim olarak çek
    MySQL.query([[
        SELECT
            COALESCE(p.name, r.resolved_by)              AS admin_name,
            r.resolved_by                                AS admin_license,
            COUNT(*)                                     AS total_resolved,
            AVG(r.resolve_duration)                      AS avg_duration_sec,
            MIN(r.resolve_duration)                      AS min_duration_sec,
            MAX(r.resolve_duration)                      AS max_duration_sec,
            SUM(CASE WHEN r.category='cheating' THEN 1 ELSE 0 END) AS cat_cheating,
            SUM(CASE WHEN r.category='rdm'      THEN 1 ELSE 0 END) AS cat_rdm,
            SUM(CASE WHEN r.category='vdm'      THEN 1 ELSE 0 END) AS cat_vdm,
            SUM(CASE WHEN r.category='toxicity' THEN 1 ELSE 0 END) AS cat_toxicity,
            SUM(CASE WHEN r.category='bug'      THEN 1 ELSE 0 END) AS cat_bug,
            SUM(CASE WHEN r.category='other'    THEN 1 ELSE 0 END) AS cat_other
        FROM qb_reports r
        LEFT JOIN players p ON p.license = r.resolved_by
        WHERE r.resolved_by IS NOT NULL
        GROUP BY r.resolved_by, p.name
        ORDER BY total_resolved DESC
    ]], {}, function(rows)
        result.adminStats = rows or {}
        done = done + 1
        if done == 3 then cb(result) end
    end)

    -- COUNT sorgusu
    local countQuery = 'SELECT COUNT(*) AS total FROM qb_reports r LEFT JOIN players p_res ON p_res.license = r.resolved_by ' .. where
    print('^3[qb-report DEBUG] COUNT query: ' .. countQuery .. '^0')
    MySQL.query(countQuery, args,
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

    -- Wait for MAX(id) query to complete before allowing report creation
    if not ReportIdReady then
        print('^3[qb-report DEBUG] Waiting for ReportId initialization...^0')
        local waitCount = 0
        while not ReportIdReady and waitCount < 50 do
            Wait(100)
            waitCount = waitCount + 1
        end
        if not ReportIdReady then
            TriggerClientEvent('qb-core:client:Notify', src, 'System not ready, please try again', 'error', 4000)
            return
        end
    end

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

    -- Doğrulama (Validation): Kullanıcının açık veya üstlenilmiş raporu var mı?
    local hasActive = false
    for _, r in pairs(Reports) do
        if r.reporterId == src and (r.status == 'open' or r.status == 'claimed') then
            hasActive = true
            break
        end
    end

    if hasActive then
        TriggerClientEvent('qb-core:client:Notify', src, T('already_have_active_report') or 'Zaten açık bir raporunuz bulunuyor, lütfen çözülmesini bekleyin.', 'error', 5000)
        return
    end

    Cooldowns[src] = now
    ReportId       = ReportId + 1

    local reporterName = SafeGetName(src)
    local createdAt    = os.time()

    -- DEBUG: Log new ticket creation
    print('^3[qb-report DEBUG] Creating new ticket - ID: ' .. ReportId .. ', Category: ' .. tostring(data.category) .. ', Reporter: ' .. reporterName .. '^0')

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

    -- FIX: Save ticket to database immediately when created, not just when resolved
    -- FIX: Let database auto-increment ID instead of manually specifying it to avoid duplicate key errors
    -- DEBUG: Log the query to see what ID is being used
    print('^3[qb-report DEBUG] INSERT query - Category: ' .. report.category .. ', Reporter: ' .. report.reporterName .. '^0')
    MySQL.insert([[
        INSERT INTO qb_reports
            (category, category_label, description, reporter_id, reporter_name,
             target_id, target_name, status, created_at)
        VALUES
            (@cat, @catLabel, @desc, @rid, @rname,
             @tid, @tname, 'open', @createdAt)
    ]], {
        ['@cat']       = report.category,
        ['@catLabel']  = report.categoryLabel,
        ['@desc']      = report.description,
        ['@rid']       = report.reporterId,
        ['@rname']     = report.reporterName,
        ['@tid']       = report.targetId,
        ['@tname']     = report.targetName,
        ['@createdAt'] = os.date('%Y-%m-%d %H:%M:%S', report.createdAt),
    }, function(insertId)
        -- Update the report and Reports table with the auto-generated ID
        if insertId and insertId > 0 then
            local oldId = report.id
            report.id = insertId
            Reports[insertId] = report
            Reports[oldId] = nil
            ReportId = insertId
            print('^2[qb-report] Ticket saved to database - Auto-generated ID: ' .. insertId .. ' (replaced manual ID: ' .. oldId .. ')^0')
        else
            print('^2[qb-report] Ticket saved to database - ID: ' .. report.id .. '^0')
        end
    end)

    -- Send notifications immediately with the temporary ID (will be updated in DB)
    -- The actual ID will be corrected in the database via the callback
    print('[DEBUG] Server: Triggering qb-report:client:reportSent event to client')
    TriggerClientEvent('qb-report:client:reportSent', src)
    BroadcastToAdmins('qb-report:client:newReportAlert', report)
    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    -- Use report.id (temporary ID) for immediate notifications - DB will have correct auto-increment ID
    SendDiscord(T('discord_new_report') .. report.id, T('discord_new_report_desc'),
        ServerConfig.Discord.Colors.NewReport, {
            { name = T('discord_field_category'),    value = safeLabel,                                                                                               inline = true  },
            { name = T('discord_field_reporter'),    value = reporterName .. ' (ID: ' .. src .. ')',                                                                  inline = true  },
            { name = T('discord_field_target'),      value = targetName and (targetName .. ' (ID: ' .. targetId .. ')') or T('discord_field_not_specified'),           inline = false },
            { name = T('discord_field_description'), value = desc,                                                                                                    inline = false },
        }
    )
    Log('Yeni rapor #' .. report.id .. ' | ' .. reporterName .. ' | ' .. data.category)
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
    r.claimedAt = os.time()

    -- License'ı DB'ye yaz, görüntüleme için isim+ID'yi bellekte tut
    local claimedLicense    = GetPlayerLicense(src)
    local claimedDisplayName = SafeGetName(src) .. ' (ID: ' .. src .. ')'
    r.claimedBy         = claimedDisplayName   -- Bellekte (admin paneli için) isim göster
    r.claimedByLicense  = claimedLicense        -- DB'ye yazılacak license

    -- FIX: Update claim status in database
    MySQL.query([[
        UPDATE qb_reports SET
            status    = 'claimed',
            claimed_by = @claimedBy,
            claimed_at = @claimedAt
        WHERE id = @id
    ]], {
        ['@id']         = r.id,
        ['@claimedBy']  = claimedLicense or claimedDisplayName,
        ['@claimedAt']   = os.date('%Y-%m-%d %H:%M:%S', r.claimedAt),
    }, function()
        print('^2[qb-report] Ticket claimed in database - ID: ' .. r.id .. '^0')
    end)

    if r.reporterId and QBCore.Functions.GetPlayer(r.reporterId) then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId, T('report_claimed'), 'success', 6000)
    end

    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    SendDiscord(T('discord_new_report') .. reportId .. T('discord_claimed'), '', ServerConfig.Discord.Colors.Claimed, {
        { name = T('discord_field_report_id'), value = tostring(reportId), inline = true  },
        { name = T('discord_field_admin'),     value = claimedDisplayName, inline = true  },
        { name = T('discord_field_category'),  value = r.categoryLabel,    inline = false },
    })
    Log('Rapor #' .. reportId .. ' üstlenildi → ' .. claimedDisplayName)
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

    -- License'ı DB'ye yaz, görüntüleme için isim+ID'yi Discord/log'da kullan
    local resolvedLicense      = GetPlayerLicense(src)
    local resolvedDisplayName  = SafeGetName(src) .. ' (ID: ' .. src .. ')'
    local resolvedBy           = resolvedLicense or resolvedDisplayName  -- DB'ye yazılacak değer
    local resolvedAt           = os.time()
    local resolvedAtDT         = os.date('%Y-%m-%d %H:%M:%S', resolvedAt)
    local claimedAtDT          = r.claimedAt and os.date('%Y-%m-%d %H:%M:%S', r.claimedAt) or nil
    local duration             = resolvedAt - (r.createdAt or resolvedAt)

    if r.reporterId and QBCore.Functions.GetPlayer(r.reporterId) then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId, T('report_resolved'), 'success', 6000)
    end

    -- DEBUG: Log database update
    print('^3[qb-report DEBUG] Updating ticket in database - ID: ' .. r.id .. ', Status: resolved, Reporter: ' .. r.reporterName .. '^0')

    -- FIX: Use UPDATE since ticket already exists in database (created on submission)
    -- claimed_by ve resolved_by kolonlarına license yazılır; görüntülemede players JOIN ile isim çekilir
    MySQL.query([[
        UPDATE qb_reports SET
            status           = 'resolved',
            claimed_by       = @claimedBy,
            resolved_by      = @resolvedBy,
            claimed_at       = @claimedAt,
            resolved_at      = @resolvedAt,
            resolve_duration = @duration
        WHERE id = @id
    ]], {
        ['@id']         = r.id,
        ['@claimedBy']  = r.claimedByLicense or r.claimedBy,
        ['@resolvedBy'] = resolvedBy,
        ['@claimedAt']  = claimedAtDT,
        ['@resolvedAt'] = resolvedAtDT,
        ['@duration']   = duration,
    }, function() end)

    Reports[reportId] = nil

    BroadcastToAdmins('qb-report:client:refreshReports', GetReportList())

    local durMin = math.floor(duration / 60)
    local durSec = duration % 60
    local durStr = T('discord_duration_fmt', { min = durMin, sec = durSec })

    SendDiscord(T('discord_new_report') .. reportId .. T('discord_resolved'), '', ServerConfig.Discord.Colors.Resolved, {
        { name = T('discord_field_report_id'),   value = tostring(reportId),  inline = true  },
        { name = T('discord_field_closer'),      value = resolvedDisplayName, inline = true  },
        { name = T('discord_field_duration'),    value = durStr,              inline = true  },
        { name = T('discord_field_category'),    value = r.categoryLabel,     inline = false },
        { name = T('discord_field_description'), value = r.description,       inline = false },
    })
    Log('Rapor #' .. reportId .. ' çözüldü → ' .. resolvedDisplayName .. ' (' .. duration .. 's)')
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
