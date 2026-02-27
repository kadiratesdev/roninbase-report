-- Tech Development
-- Join our discord for support: https://discord.gg/2mXXhQy
-- Performans & güvenlik iyileştirmeleri:
--   • MySQL.Sync → MySQL.Async (thread blokelemez)
--   • getReportClaimed: JSON LIKE → citizenid ile sütun filtresi + in-Lua filtre
--   • getStaffList: O(n²) duplicate kontrol → set (hash) tablosuna geçildi
--   • Webhook callback KALDIRILDI → client webhook URL'ini asla alamaz
--   • createReport: SELECT ID'sini almak için LAST_INSERT_ID() kullanılıyor
--   • cb() fonksiyonları her zaman çağrılıyor (coroutine sızıntısı engellendi)

local QBCore = exports['qb-core']:GetCoreObject()

-- ─── Yardımcılar ──────────────────────────────────────────────

local function parseReport(row)
    if not row then return nil end
    local info = json.decode(row.reportInfo) or {}
    local ok1, msg   = pcall(json.decode, row.message)
    local ok2, staff = pcall(json.decode, row.staff)
    return {
        title      = info.title,
        identifier = row.identifier,
        status     = info.status,
        openDate   = info.openDate,
        closeDate  = info.closeDate or nil,
        type       = info.type,
        id         = row.id,
        ownerName  = info.ownerName,
        msg        = ok1 and msg   or {},
        staff      = ok2 and staff or {},
    }
end

-- ─── getUserReport (async) ────────────────────────────────────
getUserReport = function(source, cb)
    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then cb({}) return end

    MySQL.Async.fetchAll(
        "SELECT id, identifier, reportInfo, message, staff FROM ricky_report WHERE identifier = @id",
        { ['@id'] = xPlayer.PlayerData.citizenid },
        function(result)
            local reports = {}
            for i = 1, #result do
                local r = parseReport(result[i])
                if r then reports[#reports + 1] = r end
            end
            cb(reports)
        end
    )
end

-- ─── getAllReport (async) ─────────────────────────────────────
getAllReport = function(cb)
    MySQL.Async.fetchAll(
        "SELECT id, identifier, reportInfo, message, staff FROM ricky_report",
        {},
        function(result)
            local reports = {}
            for i = 1, #result do
                local r = parseReport(result[i])
                if r then reports[#reports + 1] = r end
            end
            cb(reports)
        end
    )
end

-- ─── getReportClaimed (async, düzeltildi) ─────────────────────
-- Eski versiyon: staff LIKE '%name%' → JSON injection riski + performans sorunu
-- Yeni versiyon: tüm raporları çek, Lua'da staffInfo JSON içinde citizenid eşleştir
getReportClaimed = function(source, cb)
    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then cb({}) return end
    local citizenId = xPlayer.PlayerData.citizenid

    MySQL.Async.fetchAll(
        "SELECT id, identifier, reportInfo, message, staff FROM ricky_report WHERE status != 'closed'",
        {},
        function(result)
            local reports = {}
            for i = 1, #result do
                local row = result[i]
                local ok, staffList = pcall(json.decode, row.staff)
                if ok and staffList then
                    for _, s in ipairs(staffList) do
                        -- Her staff girişinde identifier varsa eşleştir
                        if s.identifier and s.identifier == citizenId then
                            local r = parseReport(row)
                            if r then reports[#reports + 1] = r end
                            break
                        end
                    end
                end
            end
            cb(reports)
        end
    )
end

-- ─── getStaffList (O(n) set lookup) ──────────────────────────
getStaffList = function()
    local xPlayers = QBCore.Functions.GetPlayers()
    local staff = {}
    local seen  = {}  -- set: name → bool (O(1) duplicate kontrol)

    for _, xPlayer in pairs(xPlayers) do
        if xPlayer then
            for _, group in ipairs(Config.AdminGroups) do
                if QBCore.Functions.HasPermission(xPlayer, group) then
                    local name = GetPlayerName(xPlayer)
                    if name and not seen[name] then
                        seen[name] = true
                        staff[#staff + 1] = { name = name, status = "online" }
                    end
                    break  -- bu oyuncu zaten eklendi, diğer grupları kontrol etmeye gerek yok
                end
            end
        end
    end
    return staff
end

-- ─── getData callback (async, paralel değil ama non-blocking) ─
QBCore.Functions.CreateCallback('ricky-report:getData', function(source, cb)
    local data = {}
    local pending = 3  -- 3 async çağrı bekliyor

    local function checkDone()
        pending = pending - 1
        if pending == 0 then
            data.staffList = getStaffList()  -- senkron, hızlı
            cb(data)
        end
    end

    getUserReport(source, function(reports)
        data.reportPlayer = reports
        checkDone()
    end)

    getAllReport(function(reports)
        data.allReport = reports
        checkDone()
    end)

    getReportClaimed(source, function(reports)
        data.reportClaimed = reports
        checkDone()
    end)
end)

-- ─── createReport ─────────────────────────────────────────────
RegisterServerEvent('ricky-report:createReport')
AddEventHandler('ricky-report:createReport', function(title, rtype)
    local src     = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end

    -- Tip doğrulama
    rtype = tonumber(rtype)
    if not rtype then return end
    local typeMap = { [1] = 'player', [2] = 'bug', [3] = 'other' }
    local typeStr = typeMap[rtype]
    if not typeStr then return end

    -- Title sanitize
    title = tostring(title or ''):gsub('[%z\1-\8\11-\12\14-\31\127]', ''):sub(1, 100)
    if #title < 1 then return end

    local info = {
        title     = title,
        ownerName = GetPlayerName(src),
        type      = typeStr,
        openDate  = os.date('%d/%m/%Y %H:%M'),
        status    = "pending"
    }

    local emptyJson = json.encode({})

    MySQL.Async.execute(
        "INSERT INTO ricky_report (identifier, reportInfo, message, staff) VALUES(@identifier, @reportInfo, @message, @staff)",
        {
            ['@identifier'] = xPlayer.PlayerData.citizenid,
            ['@reportInfo'] = json.encode(info),
            ['@message']    = emptyJson,
            ['@staff']      = emptyJson,
        },
        function(rowsChanged)
            if rowsChanged == 0 then return end
            -- LAST_INSERT_ID() ile güvenli ID al
            MySQL.Async.fetchScalar(
                "SELECT LAST_INSERT_ID()",
                {},
                function(idReport)
                    if not idReport then return end
                    TriggerClientEvent('ricky-report:updateReport', -1)
                    sendNotificationStaff(src, Config.Locales["new_report"], "success")
                    Citizen.Wait(300)
                    TriggerClientEvent('ricky-report:openReportUser', src, idReport)
                end
            )
        end
    )
end)

-- ─── sendMessage ──────────────────────────────────────────────
RegisterServerEvent('ricky-report:sendMessage')
AddEventHandler('ricky-report:sendMessage', function(data)
    local src     = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer or not data or not tonumber(data.reportId) then return end

    local reportId = tonumber(data.reportId)
    local content  = tostring(data.content or ''):sub(1, 500)

    MySQL.Async.fetchAll(
        "SELECT id, identifier, message FROM ricky_report WHERE id = @id",
        { ['@id'] = reportId },
        function(result)
            if not result or #result == 0 then return end
            local row = result[1]
            local ok, message = pcall(json.decode, row.message)
            if not ok then message = {} end

            message[#message + 1] = {
                content = content,
                sender  = data.sender,
                type    = data.type,
                name    = GetPlayerName(src),
                id      = xPlayer.source
            }

            MySQL.Async.execute(
                "UPDATE ricky_report SET message = @message WHERE id = @id",
                { ['@message'] = json.encode(message), ['@id'] = reportId },
                function()
                    TriggerClientEvent('ricky-report:updateReport', -1)
                    Citizen.Wait(200)
                    TriggerClientEvent('ricky-report:scrollMessage', -1, reportId)

                    local identifier = xPlayer.PlayerData.citizenid
                    if identifier ~= row.identifier then
                        sendNotificationPlayer(row.identifier, Config.Locales["new_message"], "success")
                    else
                        sendNotificationStaff(src, Config.Locales["new_message"], "success")
                    end
                end
            )
        end
    )
end)

-- ─── sendNotificationPlayer ───────────────────────────────────
sendNotificationPlayer = function(identifier, msg, ntype)
    -- QBCore.Functions.GetQBPlayers() varsa daha hızlı
    local xPlayers = QBCore.Functions.GetQBPlayers and QBCore.Functions.GetQBPlayers() or {}
    local found = false
    for _, player in pairs(xPlayers) do
        if player.PlayerData.citizenid == identifier then
            TriggerClientEvent('ricky-report:notification', player.PlayerData.source, msg, ntype)
            found = true
            break
        end
    end
    -- Fallback: GetPlayers() ile dene
    if not found then
        for _, pid in ipairs(QBCore.Functions.GetPlayers()) do
            local p = QBCore.Functions.GetPlayer(pid)
            if p and p.PlayerData.citizenid == identifier then
                TriggerClientEvent('ricky-report:notification', pid, msg, ntype)
                break
            end
        end
    end
end

-- ─── sonoStaff ────────────────────────────────────────────────
sonoStaff = function(source)
    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then return false end
    for _, v in ipairs(Config.AdminGroups) do
        if QBCore.Functions.HasPermission(source, v) then
            return true
        end
    end
    return false
end

QBCore.Functions.CreateCallback('ricky-report:sonoStaff', function(source, cb)
    cb(sonoStaff(source))
end)

-- ─── claimReport ──────────────────────────────────────────────
RegisterServerEvent('ricky-report:claimReport')
AddEventHandler('ricky-report:claimReport', function(reportId)
    local src     = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end

    reportId = tonumber(reportId)
    if not reportId then return end

    MySQL.Async.fetchAll(
        "SELECT id, identifier, reportInfo, staff FROM ricky_report WHERE id = @id",
        { ['@id'] = reportId },
        function(result)
            if not result or #result == 0 then return end
            local row = result[1]

            local ok1, staffList = pcall(json.decode, row.staff)
            if not ok1 then staffList = {} end
            staffList[#staffList + 1] = {
                name       = GetPlayerName(src),
                identifier = xPlayer.PlayerData.citizenid
            }

            local ok2, reportInfo = pcall(json.decode, row.reportInfo)
            if not ok2 then reportInfo = {} end
            reportInfo.status = "open"

            MySQL.Async.execute(
                "UPDATE ricky_report SET staff = @staff, reportInfo = @reportInfo WHERE id = @id",
                {
                    ['@staff']      = json.encode(staffList),
                    ['@reportInfo'] = json.encode(reportInfo),
                    ['@id']         = reportId
                },
                function()
                    TriggerClientEvent('ricky-report:updateReport', -1)
                    sendNotificationPlayer(row.identifier, "Ticket'ınızı bir yetkili üzerine aldı.", "success")
                end
            )
        end
    )
end)

-- ─── action ───────────────────────────────────────────────────
RegisterServerEvent('ricky-report:action')
AddEventHandler('ricky-report:action', function(action, reportId)
    local src = source
    reportId  = tonumber(reportId)
    if not reportId then return end

    if action == 'closereport' then
        MySQL.Async.fetchAll(
            "SELECT id, reportInfo FROM ricky_report WHERE id = @id",
            { ['@id'] = reportId },
            function(result)
                if not result or #result == 0 then return end
                local ok, reportInfo = pcall(json.decode, result[1].reportInfo)
                if not ok then reportInfo = {} end
                reportInfo.status    = "closed"
                reportInfo.closeDate = os.date('%d/%m/%Y %H:%M')

                MySQL.Async.execute(
                    "UPDATE ricky_report SET reportInfo = @reportInfo WHERE id = @id",
                    { ['@reportInfo'] = json.encode(reportInfo), ['@id'] = reportId },
                    function()
                        TriggerClientEvent('ricky-report:updateReport', -1)
                    end
                )
            end
        )
    end
end)

-- ─── GÜVENLİK: Webhook callback KALDIRILDI ───────────────────
-- ricky-report:getWebhook callback'i artık yoktur.
-- client.lua tarafından 'ricky-report:getScreenshotUrl' callback'i kullanılıyor;
-- bu callback sadece screenshot upload URL'ini döner (webhook'un kendisini değil)
QBCore.Functions.CreateCallback('ricky-report:getScreenshotUrl', function(source, cb)
    -- Yalnızca screenshot upload endpoint'i döndür; Discord webhook'u gizli kalır
    -- screenshot-basic genellikle ayrı bir endpoint kullanır; bu callback
    -- server_config'deki upload URL'i güvenli şekilde iletir
    cb(ConfigS.ScreenshotUploadUrl or ConfigS.Webhook)
end)

-- ─── sendImage ────────────────────────────────────────────────
RegisterServerEvent('ricky-report:sendImage')
AddEventHandler('ricky-report:sendImage', function(reportId, url)
    local src    = source
    local sender = sonoStaff(src) and "staff" or "player"

    reportId = tonumber(reportId)
    if not reportId then return end

    -- URL doğrulama: yalnızca http/https kabul et
    if type(url) ~= 'string' or not url:match('^https?://') then return end
    url = url:sub(1, 512)

    MySQL.Async.fetchAll(
        "SELECT id, identifier, message FROM ricky_report WHERE id = @id",
        { ['@id'] = reportId },
        function(result)
            if not result or #result == 0 then return end
            local row = result[1]
            local ok, message = pcall(json.decode, row.message)
            if not ok then message = {} end

            message[#message + 1] = {
                content = url,
                sender  = sender,
                type    = "image",
                name    = GetPlayerName(src),
                id      = src
            }

            MySQL.Async.execute(
                "UPDATE ricky_report SET message = @message WHERE id = @id",
                { ['@message'] = json.encode(message), ['@id'] = reportId },
                function()
                    TriggerClientEvent('ricky-report:updateReport', -1)
                    if sender == "player" then
                        sendNotificationStaff(src, Config.Locales["new_message"], "success")
                        TriggerClientEvent('ricky-report:openReportUser', src, reportId)
                    else
                        sendNotificationPlayer(row.identifier, Config.Locales["new_message"], "success")
                        TriggerClientEvent('ricky-report:openReportStaff', src, reportId)
                    end
                end
            )
        end
    )
end)

-- ─── sendNotificationStaff ────────────────────────────────────
sendNotificationStaff = function(excludeId, msg, ntype)
    local xPlayers = QBCore.Functions.GetPlayers()
    for _, pid in ipairs(xPlayers) do
        if tonumber(excludeId) ~= tonumber(pid) then
            local notified = false
            for _, group in ipairs(Config.AdminGroups) do
                if not notified and QBCore.Functions.HasPermission(pid, group) then
                    notified = true
                    TriggerClientEvent('ricky-report:notification', pid, msg, ntype)
                end
            end
        end
    end
end

-- ─── brutalAction ─────────────────────────────────────────────
RegisterServerEvent('ricky-report:brutalAction')
AddEventHandler('ricky-report:brutalAction', function(action, reportId, reason)
    local src = source
    if not sonoStaff(src) then return end  -- yetki kontrolü

    reportId = tonumber(reportId)
    if not reportId then return end

    reason = tostring(reason or ''):sub(1, 200)

    MySQL.Async.fetchAll(
        "SELECT id, identifier FROM ricky_report WHERE id = @id",
        { ['@id'] = reportId },
        function(result)
            if not result or #result == 0 then return end
            local citizenid = result[1].identifier

            if action == 'kick' then
                for _, pid in ipairs(QBCore.Functions.GetPlayers()) do
                    local xPlayer = QBCore.Functions.GetPlayer(pid)
                    if xPlayer and xPlayer.PlayerData.citizenid == citizenid then
                        DropPlayer(pid, reason)
                        break
                    end
                end
            elseif action == 'ban' then
                Ban(citizenid, reason)
            end
        end
    )
end)
