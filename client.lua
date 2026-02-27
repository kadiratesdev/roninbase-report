-- Tech Development
-- Join our discord for support: https://discord.gg/2mXXhQy
-- Performance optimizations:
--   • SonoStaff sonucu cache'leniyor → her açılışta tek server round-trip
--   • Screenshot thread: gönderim yokken Wait(1000), gönderim varken Wait(0)
--   • LoadData tek callback içinde yapılıyor; SonoStaff cache kullanıyor
--   • postNUI inline edildi (gereksiz wrapper kaldırıldı)

local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}
local sendingImage = false
local sendingImageReportId = 0
local open = false

-- Cache: staff durumu bir kez sorulur, logout/login'de sıfırlanır
local _staffCache = nil

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    _staffCache = nil  -- yeni karakter yüklenince cache'i sıfırla
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    _staffCache = nil
end)

RegisterNetEvent('ricky-report:open')
AddEventHandler('ricky-report:open', function()
    OpenReport()
end)

RegisterCommand(Config.CommandName, function(source, args, rawCommand)
    OpenReport()
end)

-- Asenkron callback + cache destekli staff kontrol
-- onResult(bool) şeklinde çağrılır
local function GetStaffAsync(onResult)
    if _staffCache ~= nil then
        onResult(_staffCache)
        return
    end
    QBCore.Functions.TriggerCallback('ricky-report:sonoStaff', function(staff)
        _staffCache = staff
        onResult(staff)
    end)
end

LoadData = function()
    -- Önce staff kontrolü, sonra tek seferde data al
    GetStaffAsync(function(isStaff)
        QBCore.Functions.TriggerCallback('ricky-report:getData', function(data)

            SendNUIMessage({
                type = "SET_LOCALES",
                locales = Config.Locales
            })

            SendNUIMessage({
                type = "SET_STAFF",
                staff = isStaff
            })

            SendNUIMessage({
                type = 'LOAD_STAFF_LIST',
                staffList = data.staffList
            })

            if not isStaff then
                SendNUIMessage({
                    type = 'LOAD_PLAYER_REPORT',
                    reportPlayer = data.reportPlayer
                })
            else
                SendNUIMessage({
                    type = 'SET_INFO_STAFF',
                    identifier = PlayerData.identifier,
                    name = GetPlayerName(PlayerId()),
                })

                SendNUIMessage({
                    type = 'LOAD_CLAIMED_REPORT',
                    claimedReport = data.reportClaimed
                })

                SendNUIMessage({
                    type = 'LOAD_ALL_REPORT',
                    allReport = data.allReport
                })
            end
        end)
    end)
end

OpenReport = function()
    if open then return end  -- çift açılmayı engelle

    GetStaffAsync(function(isStaff)
        SendNUIMessage({
            type = "SET_DEFAULT_SCHERMATA",
            schermata = isStaff and 'all_report' or 1
        })
        LoadData()
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'OPEN' })
        open = true
    end)
end

RegisterNetEvent('ricky-report:openReportUser')
AddEventHandler('ricky-report:openReportUser', function(idReport)
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'OPEN_REPORT_USER',
        idReport = idReport
    })
end)

RegisterNetEvent('ricky-report:openReportStaff')
AddEventHandler('ricky-report:openReportStaff', function(idReport)
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'OPEN_REPORT_STAFF',
        idReport = idReport
    })
end)

RegisterNUICallback('sendImage', function(data, cb)
    SetNuiFocus(false, false)
    sendingImage = true
    sendingImageReportId = data.reportId
    cb('ok')
end)

RegisterNUICallback('createReport', function(data, cb)
    local title = tostring(data.title or ''):sub(1, 100)
    local rtype = tonumber(data.type)
    if not rtype then cb('err') return end
    TriggerServerEvent('ricky-report:createReport', title, rtype)
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    local action = tostring(data.action or '')
    local reportId = tonumber(data.reportId)
    if not reportId then cb('err') return end
    TriggerServerEvent('ricky-report:action', action, reportId)
    cb('ok')
end)

RegisterNUICallback('sendMessage', function(data, cb)
    local content = tostring(data.content or ''):sub(1, 500)
    if #content < 1 then cb('err') return end
    TriggerServerEvent('ricky-report:sendMessage', {
        content  = content,
        sender   = data.sender,
        type     = data.type,
        reportId = tonumber(data.reportId)
    })
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    open = false
    cb('ok')
end)

RegisterNUICallback('claimReport', function(data, cb)
    local reportId = tonumber(data.reportId)
    if not reportId then cb('err') return end
    TriggerServerEvent('ricky-report:claimReport', reportId)
    cb('ok')
end)

RegisterNetEvent('ricky-report:updateReport')
AddEventHandler('ricky-report:updateReport', function()
    if open then
        LoadData()
    end
end)

RegisterNetEvent('ricky-report:scrollMessage')
AddEventHandler('ricky-report:scrollMessage', function(reportId)
    SendNUIMessage({
        type = "SCROLL_MESSAGE",
        reportId = reportId
    })
end)

-- ─── Screenshot Thread ────────────────────────────────────────
-- sendingImage yokken 1000ms uyur → neredeyse sıfır CPU kullanımı
-- sendingImage varken 0ms → anlık E tuşu algılaması
Citizen.CreateThread(function()
    while true do
        if sendingImage then
            Citizen.Wait(0)
            if IsControlJustPressed(0, 38) then  -- E tuşu
                -- Webhook server-side'dan alınır, client'a doğrudan geçirilmez
                -- screenshot-basic doğrudan upload URL'e istek atar
                QBCore.Functions.TriggerCallback('ricky-report:getScreenshotUrl', function(uploadUrl)
                    if not uploadUrl or uploadUrl == '' then
                        TriggerEvent('ricky-report:notification', 'Görüntü servisi bulunamadı.', 'error')
                        return
                    end
                    exports['screenshot-basic']:requestScreenshotUpload(uploadUrl, 'files[]', function(resp)
                        if resp == nil then
                            TriggerEvent('ricky-report:notification', 'Error, try again', 'error')
                            return
                        end
                        local ok, decoded = pcall(json.decode, resp)
                        if not ok or not decoded or not decoded.attachments or not decoded.attachments[1] then
                            TriggerEvent('ricky-report:notification', 'Görüntü parse hatası.', 'error')
                            return
                        end
                        local url = decoded.attachments[1].url
                        TriggerServerEvent('ricky-report:sendImage', sendingImageReportId, url)
                        sendingImage = false
                    end)
                end)
            end
        else
            Citizen.Wait(1000)
        end
    end
end)

RegisterNetEvent('ricky-report:notification')
AddEventHandler('ricky-report:notification', function(msg, type)
    exports["urp-notify"]:Alert("REPORT", msg, 5000, type)
end)

RegisterNUICallback('brutalAction', function(data, cb)
    local action   = tostring(data.action or '')
    local reportId = tonumber(data.reportId)
    local reason   = tostring(data.reason or ''):sub(1, 200)
    if not reportId or action == '' then cb('err') return end
    TriggerServerEvent('ricky-report:brutalAction', action, reportId, reason)
    cb('ok')
end)
