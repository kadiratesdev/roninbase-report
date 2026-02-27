local QBCore = exports['qb-core']:GetCoreObject()
local isNUIOpen = false
local isAdminPanelOpen = false

-- ─────────────────────────────────────────
--  Helper: Build category list for NUI
-- ─────────────────────────────────────────
local function GetCategories()
    local cats = {}
    for _, v in ipairs(Config.Categories) do
        cats[#cats + 1] = v
    end
    return cats
end

-- ─────────────────────────────────────────
--  Open Report Menu
-- ─────────────────────────────────────────
local function OpenReportMenu()
    if isNUIOpen or isAdminPanelOpen then return end
    isNUIOpen = true

    -- Fetch online players for "report a player" feature
    QBCore.Functions.TriggerCallback('qb-report:server:getPlayers', function(players)
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'openReport',
            categories = GetCategories(),
            players = players,
        })
    end)
end

-- ─────────────────────────────────────────
--  Open Admin Panel
-- ─────────────────────────────────────────
local function OpenAdminPanel()
    if isNUIOpen or isAdminPanelOpen then return end
    isAdminPanelOpen = true

    TriggerServerEvent('qb-report:server:getReports')
end

RegisterNetEvent('qb-report:client:receiveReports', function(reports)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openAdmin',
        reports = reports,
    })
end)

-- ─────────────────────────────────────────
--  Commands
-- ─────────────────────────────────────────
RegisterCommand(Config.Command, function()
    OpenReportMenu()
end, false)

RegisterCommand(Config.AdminCommand, function()
    TriggerServerEvent('qb-report:server:checkAdmin')
end, false)

RegisterNetEvent('qb-report:client:openAdminPanel', function()
    OpenAdminPanel()
end)

-- ─────────────────────────────────────────
--  NUI Callbacks
-- ─────────────────────────────────────────

-- Close report menu
RegisterNUICallback('closeReport', function(_, cb)
    isNUIOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Close admin panel
RegisterNUICallback('closeAdmin', function(_, cb)
    isAdminPanelOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Submit a report
RegisterNUICallback('submitReport', function(data, cb)
    TriggerServerEvent('qb-report:server:submitReport', {
        category   = data.category,
        categoryLabel = data.categoryLabel,
        description = data.description,
        targetId   = data.targetId,    -- may be nil
        targetName = data.targetName,  -- may be nil
    })
    cb('ok')
end)

-- Admin: claim report
RegisterNUICallback('claimReport', function(data, cb)
    TriggerServerEvent('qb-report:server:claimReport', data.reportId)
    cb('ok')
end)

-- Admin: resolve report
RegisterNUICallback('resolveReport', function(data, cb)
    TriggerServerEvent('qb-report:server:resolveReport', data.reportId)
    cb('ok')
end)

-- Admin: teleport to reporter
RegisterNUICallback('teleportToReporter', function(data, cb)
    TriggerServerEvent('qb-report:server:teleportToReporter', data.playerId)
    cb('ok')
end)

-- Admin: refresh list
RegisterNUICallback('refreshReports', function(_, cb)
    TriggerServerEvent('qb-report:server:getReports')
    cb('ok')
end)

-- ─────────────────────────────────────────
--  Server → Client events
-- ─────────────────────────────────────────

-- Report was submitted OK
RegisterNetEvent('qb-report:client:reportSent', function()
    isNUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAll' })
    QBCore.Functions.Notify(Config.Notifications.ReportSent, 'success', 5000)
end)

-- Still on cooldown
RegisterNetEvent('qb-report:client:cooldown', function(remaining)
    QBCore.Functions.Notify('You must wait ' .. remaining .. ' seconds before reporting again.', 'error', 4000)
    isNUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAll' })
end)

-- Admin: report list updated (push to open panel)
RegisterNetEvent('qb-report:client:refreshReports', function(reports)
    SendNUIMessage({
        action = 'updateReports',
        reports = reports,
    })
end)

-- Admin: notify new report arrived while panel is open
RegisterNetEvent('qb-report:client:newReportAlert', function(report)
    SendNUIMessage({
        action  = 'newReportAlert',
        report  = report,
    })
    QBCore.Functions.Notify(Config.Notifications.AdminNotify, 'primary', 5000)
end)

-- Teleport coords received
RegisterNetEvent('qb-report:client:teleportCoords', function(coords)
    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, true)
end)

-- ─────────────────────────────────────────
--  ESC key to close NUI
-- ─────────────────────────────────────────
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if (isNUIOpen or isAdminPanelOpen) and IsControlJustReleased(0, 200) then
            isNUIOpen = false
            isAdminPanelOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'closeAll' })
        end
    end
end)
