local QBCore = exports['qb-core']:GetCoreObject()

-- In-memory report store  { [id] = reportData }
local Reports   = {}
local ReportId  = 0
-- Cooldown tracking  { [playerId] = timestamp }
local Cooldowns = {}

-- ─────────────────────────────────────────
--  Utility helpers
-- ─────────────────────────────────────────
local function IsAdmin(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    local group = QBCore.Functions.GetPermission(src)
    for _, g in ipairs(Config.AdminGroups) do
        if group == g then return true end
    end
    return false
end

local function GetPlayerName(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        return Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    end
    return GetPlayerName(src) or 'Unknown'
end

local function FormatTimestamp()
    return os.date('%d/%m/%Y %H:%M:%S')
end

-- ─────────────────────────────────────────
--  Discord Webhook
-- ─────────────────────────────────────────
local function SendDiscord(title, description, color, fields)
    if not Config.Discord.Enabled or Config.Discord.Webhook == 'YOUR_DISCORD_WEBHOOK_URL_HERE' then return end

    local embedFields = {}
    if fields then
        for _, f in ipairs(fields) do
            embedFields[#embedFields + 1] = {
                name   = f.name,
                value  = f.value,
                inline = f.inline or false,
            }
        end
    end

    PerformHttpRequest(Config.Discord.Webhook, function(err, text, headers) end, 'POST',
        json.encode({
            username   = Config.Discord.BotName,
            avatar_url = Config.Discord.BotAvatar,
            embeds = {
                {
                    title       = title,
                    description = description,
                    color       = color,
                    fields      = embedFields,
                    footer      = { text = 'Report System • ' .. FormatTimestamp() },
                }
            }
        }),
        { ['Content-Type'] = 'application/json' }
    )
end

-- ─────────────────────────────────────────
--  Notify all online admins
-- ─────────────────────────────────────────
local function NotifyAdmins(report)
    local players = QBCore.Functions.GetQBPlayers()
    for _, player in pairs(players) do
        local src = player.PlayerData.source
        if IsAdmin(src) then
            TriggerClientEvent('qb-report:client:newReportAlert', src, report)
        end
    end
end

-- ─────────────────────────────────────────
--  Build sanitised report list for admins
-- ─────────────────────────────────────────
local function GetReportList()
    local list = {}
    for id, r in pairs(Reports) do
        list[#list + 1] = r
    end
    -- Sort newest first
    table.sort(list, function(a, b) return a.id > b.id end)
    return list
end

-- ─────────────────────────────────────────
--  Callback: get online players (for reporter)
-- ─────────────────────────────────────────
QBCore.Functions.CreateCallback('qb-report:server:getPlayers', function(source, cb)
    local players = {}
    local qbPlayers = QBCore.Functions.GetQBPlayers()
    for _, player in pairs(qbPlayers) do
        local src = player.PlayerData.source
        if src ~= source then
            players[#players + 1] = {
                id   = src,
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
            }
        end
    end
    cb(players)
end)

-- ─────────────────────────────────────────
--  Event: Check if caller is admin
-- ─────────────────────────────────────────
RegisterNetEvent('qb-report:server:checkAdmin', function()
    local src = source
    if IsAdmin(src) then
        TriggerClientEvent('qb-report:client:openAdminPanel', src)
    else
        TriggerClientEvent('qb-core:client:Notify', src, 'You do not have permission to use this command.', 'error', 4000)
    end
end)

-- ─────────────────────────────────────────
--  Event: Submit a report
-- ─────────────────────────────────────────
RegisterNetEvent('qb-report:server:submitReport', function(data)
    local src = source

    -- Cooldown check
    local now = os.time()
    if Cooldowns[src] and (now - Cooldowns[src]) < Config.Cooldown then
        local remaining = Config.Cooldown - (now - Cooldowns[src])
        TriggerClientEvent('qb-report:client:cooldown', src, remaining)
        return
    end

    Cooldowns[src] = now
    ReportId = ReportId + 1

    local reporterName = GetPlayerName(src)

    local report = {
        id            = ReportId,
        category      = data.category,
        categoryLabel = data.categoryLabel,
        description   = string.sub(data.description or '', 1, Config.MaxDescLength),
        reporterId    = src,
        reporterName  = reporterName,
        targetId      = data.targetId,
        targetName    = data.targetName,
        status        = 'open',       -- open | claimed | resolved
        claimedBy     = nil,
        timestamp     = FormatTimestamp(),
    }

    Reports[ReportId] = report

    -- Notify reporter
    TriggerClientEvent('qb-report:client:reportSent', src)

    -- Notify admins
    NotifyAdmins(report)

    -- Push updated list to any open admin panels
    local admins = QBCore.Functions.GetQBPlayers()
    for _, player in pairs(admins) do
        local adminSrc = player.PlayerData.source
        if IsAdmin(adminSrc) then
            TriggerClientEvent('qb-report:client:refreshReports', adminSrc, GetReportList())
        end
    end

    -- Discord
    local fields = {
        { name = '📋 Category',    value = data.categoryLabel or data.category, inline = true  },
        { name = '👤 Reporter',    value = reporterName .. ' (ID: ' .. src .. ')', inline = true  },
        { name = '🎯 Reported Player', value = data.targetName and (data.targetName .. ' (ID: ' .. tostring(data.targetId) .. ')') or 'None', inline = false },
        { name = '📝 Description', value = report.description, inline = false },
        { name = '🆔 Report ID',   value = tostring(ReportId), inline = true  },
    }
    SendDiscord('🚨 New Player Report #' .. ReportId, 'A new report has been submitted.', Config.Discord.Colors.NewReport, fields)

    print('[qb-report] New report #' .. ReportId .. ' from ' .. reporterName .. ' (' .. src .. ')')
end)

-- ─────────────────────────────────────────
--  Event: Get all reports (admin)
-- ─────────────────────────────────────────
RegisterNetEvent('qb-report:server:getReports', function()
    local src = source
    if not IsAdmin(src) then return end
    TriggerClientEvent('qb-report:client:receiveReports', src, GetReportList())
end)

-- ─────────────────────────────────────────
--  Event: Claim report
-- ─────────────────────────────────────────
RegisterNetEvent('qb-report:server:claimReport', function(reportId)
    local src = source
    if not IsAdmin(src) then return end

    local r = Reports[reportId]
    if not r then return end

    r.status    = 'claimed'
    r.claimedBy = GetPlayerName(src) .. ' (ID: ' .. src .. ')'

    -- Notify reporter if still online
    if r.reporterId then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId,
            'An admin has claimed your report. They will be with you shortly.', 'success', 6000)
    end

    -- Refresh admin panels
    local admins = QBCore.Functions.GetQBPlayers()
    for _, player in pairs(admins) do
        local adminSrc = player.PlayerData.source
        if IsAdmin(adminSrc) then
            TriggerClientEvent('qb-report:client:refreshReports', adminSrc, GetReportList())
        end
    end

    SendDiscord('🔔 Report #' .. reportId .. ' Claimed',
        'An admin has claimed a report.',
        Config.Discord.Colors.Claimed,
        {
            { name = '🆔 Report ID',  value = tostring(reportId), inline = true  },
            { name = '👮 Admin',       value = r.claimedBy,        inline = true  },
            { name = '📋 Category',    value = r.categoryLabel,    inline = false },
        }
    )
end)

-- ─────────────────────────────────────────
--  Event: Resolve report
-- ─────────────────────────────────────────
RegisterNetEvent('qb-report:server:resolveReport', function(reportId)
    local src = source
    if not IsAdmin(src) then return end

    local r = Reports[reportId]
    if not r then return end

    r.status = 'resolved'

    -- Notify reporter
    if r.reporterId then
        TriggerClientEvent('qb-core:client:Notify', r.reporterId,
            'Your report has been resolved by an admin.', 'success', 6000)
    end

    -- Remove from active store after short delay
    SetTimeout(30000, function()
        Reports[reportId] = nil
    end)

    -- Refresh admin panels
    local admins = QBCore.Functions.GetQBPlayers()
    for _, player in pairs(admins) do
        local adminSrc = player.PlayerData.source
        if IsAdmin(adminSrc) then
            TriggerClientEvent('qb-report:client:refreshReports', adminSrc, GetReportList())
        end
    end

    SendDiscord('✅ Report #' .. reportId .. ' Resolved',
        'A report has been marked as resolved.',
        Config.Discord.Colors.Resolved,
        {
            { name = '🆔 Report ID', value = tostring(reportId),  inline = true  },
            { name = '👮 Resolved By', value = GetPlayerName(src) .. ' (ID: ' .. src .. ')', inline = true },
        }
    )
end)

-- ─────────────────────────────────────────
--  Event: Teleport admin to reporter
-- ─────────────────────────────────────────
RegisterNetEvent('qb-report:server:teleportToReporter', function(targetPlayerId)
    local src = source
    if not IsAdmin(src) then return end

    local ped    = GetPlayerPed(targetPlayerId)
    local coords = GetEntityCoords(ped)
    if coords then
        TriggerClientEvent('qb-report:client:teleportCoords', src, { x = coords.x, y = coords.y, z = coords.z })
    end
end)
