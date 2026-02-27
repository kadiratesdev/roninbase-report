-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  client.lua
-- ─────────────────────────────────────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

local isNUIOpen       = false
local isAdminOpen     = false
local isHistoryOpen   = false

-- ─────────────────────────────────────────
--  Locale sistemi
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

-- Önce seçilen dili yükle, başarısız olursa 'en' fallback
local function InitLocale()
    local lang = Config.Locale or 'en'
    local data = LoadLocale(lang)
    if not data then
        print('^3[qb-report] ' .. lang .. ' locale yüklenemedi, İngilizce\'ye düşülüyor.^0')
        data = LoadLocale('en')
    end
    Locale = data or {}
end

InitLocale()

-- Çeviri fonksiyonu ({key} placeholder desteği)
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
--  Kategori etiketlerini locale'den doldur
-- ─────────────────────────────────────────
local function GetCategories()
    local cats = {}
    for _, v in ipairs(Config.Categories) do
        local label = T('cat_' .. v.id)
        cats[#cats + 1] = {
            id    = v.id,
            label = label,
            icon  = v.icon,
            color = v.color,
        }
    end
    return cats
end

-- ─────────────────────────────────────────
--  NUI'yi kapat
-- ─────────────────────────────────────────
local function CloseNUI()
    isNUIOpen     = false
    isAdminOpen   = false
    isHistoryOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAll' })
end

-- ─────────────────────────────────────────
--  Rapor menüsü
-- ─────────────────────────────────────────
local function OpenReportMenu()
    if isNUIOpen or isAdminOpen or isHistoryOpen then return end
    QBCore.Functions.TriggerCallback('qb-report:server:getPlayers', function(players)
        isNUIOpen = true
        SetNuiFocus(true, true)
        -- NUI'ye dil bilgisini de gönder
        SendNUIMessage({ action = 'setLang', lang = Config.Locale or 'en' })
        SendNUIMessage({ action = 'openReport', categories = GetCategories(), players = players })
    end)
end

-- ─────────────────────────────────────────
--  Admin paneli
-- ─────────────────────────────────────────
local function OpenAdminPanel(reports)
    if isNUIOpen or isAdminOpen or isHistoryOpen then return end
    isAdminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'setLang', lang = Config.Locale or 'en' })
    SendNUIMessage({ action = 'openAdmin', reports = reports })
end

-- ─────────────────────────────────────────
--  History paneli
-- ─────────────────────────────────────────
local function OpenHistoryPanel()
    if isNUIOpen or isAdminOpen or isHistoryOpen then return end
    isHistoryOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'setLang', lang = Config.Locale or 'en' })
    SendNUIMessage({ action = 'openHistory' })
    -- İlk sayfa verilerini hemen yükle
    QBCore.Functions.TriggerCallback('qb-report:server:getHistory', function(data)
        SendNUIMessage({ action = 'loadHistory', data = data, page = 1 })
    end, { page = 1, filter = 'all', search = '' })
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

RegisterCommand(Config.SuperAdminCommand, function()
    TriggerServerEvent('qb-report:server:checkSuperAdmin')
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

RegisterNetEvent('qb-report:client:openHistoryPanel', function()
    OpenHistoryPanel()
end)

RegisterNetEvent('qb-report:client:reportSent', function()
    CloseNUI()
    QBCore.Functions.Notify(T('report_sent'), 'success', 5000)
end)

RegisterNetEvent('qb-report:client:cooldown', function(remaining)
    remaining = tonumber(remaining) or 0
    CloseNUI()
    QBCore.Functions.Notify(T('cooldown', { seconds = remaining }), 'error', 4000)
end)

RegisterNetEvent('qb-report:client:refreshReports', function(reports)
    if type(reports) ~= 'table' then return end
    if isAdminOpen then
        SendNUIMessage({ action = 'updateReports', reports = reports })
    end
end)

RegisterNetEvent('qb-report:client:newReportAlert', function(report)
    if type(report) ~= 'table' then return end
    SendNUIMessage({ action = 'newReportAlert', report = report })
    QBCore.Functions.Notify(T('admin_notify'), 'primary', 5000)
end)

RegisterNetEvent('qb-report:client:teleportCoords', function(coords)
    if type(coords) ~= 'table' then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, true)
end)

-- ─────────────────────────────────────────
--  NUI Callbacks
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

RegisterNUICallback('closeHistory', function(_, cb)
    isHistoryOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('submitReport', function(data, cb)
    if type(data) ~= 'table' then cb('err') return end
    local cat   = type(data.category) == 'string'      and data.category      or nil
    local label = type(data.categoryLabel) == 'string'  and data.categoryLabel or nil
    local desc  = type(data.description) == 'string'   and data.description   or nil
    if not cat or not desc or #desc < 5 then cb('err') return end
    TriggerServerEvent('qb-report:server:submitReport', {
        category      = cat,
        categoryLabel = label,
        description   = desc:sub(1, 500),
        targetId      = tonumber(data.targetId),
        targetName    = type(data.targetName) == 'string' and data.targetName or nil,
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

-- History: sayfalama / filtre / arama
RegisterNUICallback('fetchHistory', function(data, cb)
    if type(data) ~= 'table' then cb('err') return end
    QBCore.Functions.TriggerCallback('qb-report:server:getHistory', function(result)
        SendNUIMessage({ action = 'loadHistory', data = result, page = data.page or 1 })
        cb('ok')
    end, {
        page   = tonumber(data.page)   or 1,
        filter = tostring(data.filter  or 'all'),
        search = tostring(data.search  or ''),
    })
end)

RegisterNUICallback('escPressed', function(_, cb)
    CloseNUI()
    cb('ok')
end)
