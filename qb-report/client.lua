-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  client.lua
--  Performans notları:
--    • ESC thread: NUI kapalıyken Citizen.Wait(500) → CPU'ya yük yok
--    • NUI açıkken: Citizen.Wait(0) ile anlık ESC algılaması
--    • NUI Callback'lerde tip + uzunluk kontrolü yapılır
--    • Server'a asla ham/unsafe veri gönderilmez
-- ─────────────────────────────────────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

local isNUIOpen       = false
local isAdminOpen     = false

-- ─────────────────────────────────────────
--  Yardımcı: NUI'yi kapat
-- ─────────────────────────────────────────
local function CloseNUI()
    isNUIOpen     = false
    isAdminOpen   = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAll' })
end

-- ─────────────────────────────────────────
--  Kategori listesi (config'den)
-- ─────────────────────────────────────────
local function GetCategories()
    local cats = {}
    for _, v in ipairs(Config.Categories) do
        cats[#cats + 1] = v
    end
    return cats
end

-- ─────────────────────────────────────────
--  Rapor menüsünü aç
-- ─────────────────────────────────────────
local function OpenReportMenu()
    if isNUIOpen or isAdminOpen then return end

    QBCore.Functions.TriggerCallback('qb-report:server:getPlayers', function(players)
        isNUIOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action     = 'openReport',
            categories = GetCategories(),
            players    = players,
        })
    end)
end

-- ─────────────────────────────────────────
--  Admin paneli aç (server onayından sonra)
-- ─────────────────────────────────────────
local function OpenAdminPanel(reports)
    if isNUIOpen or isAdminOpen then return end
    isAdminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action  = 'openAdmin',
        reports = reports,
    })
end

-- ─────────────────────────────────────────
--  Komutlar
-- ─────────────────────────────────────────
RegisterCommand(Config.Command, function()
    OpenReportMenu()
end, false)

RegisterCommand(Config.AdminCommand, function()
    TriggerServerEvent('qb-report:server:checkAdmin')
end, false)

-- ─────────────────────────────────────────
--  Server → Client olayları
-- ─────────────────────────────────────────
RegisterNetEvent('qb-report:client:openAdminPanel', function()
    TriggerServerEvent('qb-report:server:getReports')
end)

RegisterNetEvent('qb-report:client:receiveReports', function(reports)
    if type(reports) ~= 'table' then return end
    OpenAdminPanel(reports)
end)

RegisterNetEvent('qb-report:client:reportSent', function()
    CloseNUI()
    QBCore.Functions.Notify(Config.Notifications.ReportSent, 'success', 5000)
end)

RegisterNetEvent('qb-report:client:cooldown', function(remaining)
    remaining = tonumber(remaining) or 0
    CloseNUI()
    QBCore.Functions.Notify(
        'Tekrar rapor göndermek için ' .. remaining .. ' saniye beklemeniz gerekiyor.',
        'error', 4000
    )
end)

RegisterNetEvent('qb-report:client:refreshReports', function(reports)
    if type(reports) ~= 'table' then return end
    -- Yalnızca admin paneli açıksa güncelle
    if isAdminOpen then
        SendNUIMessage({ action = 'updateReports', reports = reports })
    end
end)

RegisterNetEvent('qb-report:client:newReportAlert', function(report)
    if type(report) ~= 'table' then return end
    SendNUIMessage({ action = 'newReportAlert', report = report })
    QBCore.Functions.Notify(Config.Notifications.AdminNotify, 'primary', 5000)
end)

RegisterNetEvent('qb-report:client:teleportCoords', function(coords)
    if type(coords) ~= 'table' then return end
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then return end
    SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, true)
end)

-- ─────────────────────────────────────────
--  NUI Callbacks  (input guard ile)
-- ─────────────────────────────────────────

RegisterNUICallback('closeReport', function(_, cb)
    isNUIOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('closeAdmin', function(_, cb)
    isAdminOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('submitReport', function(data, cb)
    if type(data) ~= 'table' then cb('err') return end

    -- Tip kontrolü
    local cat   = type(data.category) == 'string'     and data.category    or nil
    local label = type(data.categoryLabel) == 'string' and data.categoryLabel or nil
    local desc  = type(data.description) == 'string'  and data.description  or nil

    if not cat or not desc or #desc < 5 then cb('err') return end

    -- targetId: sayı ya da nil
    local tid  = tonumber(data.targetId)
    local tname = type(data.targetName) == 'string' and data.targetName or nil

    TriggerServerEvent('qb-report:server:submitReport', {
        category      = cat,
        categoryLabel = label,
        description   = desc:sub(1, 500),  -- client-side ön kesim
        targetId      = tid,
        targetName    = tname,
    })

    cb('ok')
end)

RegisterNUICallback('claimReport', function(data, cb)
    if type(data) ~= 'table' then cb('err') return end
    local id = tonumber(data.reportId)
    if not id then cb('err') return end
    TriggerServerEvent('qb-report:server:claimReport', id)
    cb('ok')
end)

RegisterNUICallback('resolveReport', function(data, cb)
    if type(data) ~= 'table' then cb('err') return end
    local id = tonumber(data.reportId)
    if not id then cb('err') return end
    TriggerServerEvent('qb-report:server:resolveReport', id)
    cb('ok')
end)

RegisterNUICallback('teleportToReporter', function(data, cb)
    if type(data) ~= 'table' then cb('err') return end
    local pid = tonumber(data.playerId)
    if not pid then cb('err') return end
    TriggerServerEvent('qb-report:server:teleportToReporter', pid)
    cb('ok')
end)

RegisterNUICallback('refreshReports', function(_, cb)
    TriggerServerEvent('qb-report:server:getReports')
    cb('ok')
end)

-- ─────────────────────────────────────────
--  ESC Thread  (optimize edilmiş)
--  NUI kapalıyken 500ms uyur → ~0% CPU kullanımı
--  NUI açıkken  0ms   döner  → anlık ESC algılaması
-- ─────────────────────────────────────────
Citizen.CreateThread(function()
    while true do
        if isNUIOpen or isAdminOpen then
            Citizen.Wait(0)
            if IsControlJustReleased(0, 200) then  -- INPUT_FRONTEND_CANCEL (ESC)
                CloseNUI()
            end
        else
            Citizen.Wait(500)
        end
    end
end)
