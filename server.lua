local QBCore = exports['qb-core']:GetCoreObject()

RegisterServerEvent('ricky-report:createReport')
AddEventHandler('ricky-report:createReport', function(title, type)
  local src = source
  local xPlayer = QBCore.Functions.GetPlayer(src)
  if not xPlayer then return end

  if type == 1 then 
    type = 'player'
  elseif type == 2 then
    type = 'bug'
  elseif type == 3 then
    type = 'other'
  end

  local info = {
    title = title,
    ownerName = GetPlayerName(src),
    type = type,
    openDate = os.date('%d/%m/%Y %H:%M'), 
    status = "pending"
  }

  MySQL.Sync.execute("INSERT INTO ricky_report (identifier, reportInfo) VALUES(@identifier, @reportInfo)", {
    ['@identifier'] = xPlayer.PlayerData.citizenid,
    ['@reportInfo'] = json.encode(info)
  })


  local result = MySQL.Sync.fetchAll("SELECT id FROM ricky_report WHERE identifier = @identifier AND reportInfo = @reportInfo", {
    ['@identifier'] = xPlayer.PlayerData.citizenid,
    ['@reportInfo'] = json.encode(info)
  })
    local idReport = result[1].id
    TriggerClientEvent('ricky-report:updateReport', -1)
    sendNotificationStaff(src,Config.Locales["new_report"], "success")
    Wait(500)
    TriggerClientEvent('ricky-report:openReportUser', src, idReport)

end)


getUserReport = function(source)
  local xPlayer = QBCore.Functions.GetPlayer(source)
  if not xPlayer then return end
  local reports = {}

  local result =  MySQL.Sync.fetchAll("SELECT * FROM ricky_report WHERE identifier = @identifier", {
        ['@identifier'] = xPlayer.PlayerData.citizenid,
  })
  for i=1, #result,1 do 
    local info = json.decode(result[i].reportInfo)
    table.insert(reports, {
      title = info.title,
      identifier = result[i].identifier,
      status = info.status,
      openDate = info.openDate,
      closeDate = info.closeDate or nil,
      type = info.type,
      id = result[i].id,
      ownerName = info.ownerName,
      msg = json.decode(result[i].message),
      staff = json.decode(result[i].staff),
    })
  end

  return reports
end

getAllReport = function()
  local reports = {}

  local result =  MySQL.Sync.fetchAll("SELECT * FROM ricky_report", {})
  for i=1, #result,1 do 
    local info = json.decode(result[i].reportInfo)
    table.insert(reports, {
      title = info.title,
      identifier = result[i].identifier,
      status = info.status,
      openDate = info.openDate,
      closeDate = info.closeDate or nil,
      type = info.type,
      id = result[i].id,
      ownerName = info.ownerName,
      msg = json.decode(result[i].message),
      staff = json.decode(result[i].staff),
    })
  end

  return reports
end

getReportClaimed = function(source)
  local xPlayer = QBCore.Functions.GetPlayer(source)
  local citizenId = xPlayer.PlayerData.citizenid
  if not xPlayer then return end
  local reports = {}

  local result =  MySQL.Sync.fetchAll("SELECT * FROM ricky_report WHERE staff LIKE @staff", {
        ['@staff'] = '%'..GetPlayerName(source)..'%',
  })
  for i=1, #result,1 do 
    local info = json.decode(result[i].reportInfo)
    table.insert(reports, {
      title = info.title,
      identifier = result[i].identifier,
      status = info.status,
      openDate = info.openDate,
      closeDate = info.closeDate or nil,
      type = info.type,
      id = result[i].id,
      ownerName = info.ownerName,
      msg = json.decode(result[i].message),
      staff = json.decode(result[i].staff),
    })
  end

  return reports
end

getStaffList = function()
  local xPlayers = QBCore.Functions.GetPlayers()
  local staff = {}
  for _, xPlayer in pairs(xPlayers) do
    if xPlayer then 
      for k,v in pairs(Config.AdminGroups) do 
        if QBCore.Functions.HasPermission(xPlayer, v) then 
          if #staff == 0 then 
            table.insert(staff, {
              name = GetPlayerName(xPlayer),
              status = "online",
            })
          end
          local isdetect  = false
          for k,v in pairs(staff) do 
            if v.name == GetPlayerName(xPlayer) then 
              isdetect = true
            end
          end
          if not isdetect then 
            table.insert(staff, {
              name = GetPlayerName(xPlayer),
              status = "online",
            })
          end
        end
      end
    end
  end
  return staff
end

QBCore.Functions.CreateCallback('ricky-report:getData', function(source, cb)
  local data = {}

  data.reportPlayer = getUserReport(source)
  data.allReport = getAllReport()
  data.reportClaimed = getReportClaimed(source)
  data.staffList = getStaffList()
  cb(data)
end)

RegisterServerEvent('ricky-report:sendMessage')
AddEventHandler('ricky-report:sendMessage', function(data)
  local src = source
  local xPlayer = QBCore.Functions.GetPlayer(src)


  local result =  MySQL.Sync.fetchAll("SELECT * FROM ricky_report WHERE id = @id", {
        ['@id'] = data.reportId,
  })

  local message = json.decode(result[1].message)
  table.insert(message, {
    content = data.content,
    sender = data.sender,
    type = data.type,
    name = GetPlayerName(src),
    id = xPlayer.source
  })

  MySQL.Sync.execute("UPDATE ricky_report SET message = @message WHERE id = @id", {
    ['@message'] = json.encode(message),
    ['@id'] = data.reportId
  })
  TriggerClientEvent('ricky-report:updateReport', -1)
  Wait(300)
  TriggerClientEvent('ricky-report:scrollMessage', -1, data.reportId)
  
  local identifier = xPlayer.PlayerData.citizenid
  if identifier ~= result[1].identifier then 
     sendNotificationPlayer(result[1].identifier, Config.Locales["new_message"], "success")
  else
    sendNotificationStaff(src,Config.Locales["new_message"], "success")
  end
end)

sendNotificationPlayer = function(identifier, msg, type)
  local xPlayers = QBCore.Functions.GetPlayers()
  for _, xPlayer in pairs(xPlayers) do
    local data = QBCore.Functions.GetPlayer(xPlayer)
    if data.PlayerData.citizenid == identifier then
       TriggerClientEvent(
        "ricky-report:notification",
        xPlayer,
        msg,
        type
       )
    end
  end
end


sonoStaff = function(source)
  local xPlayer = QBCore.Functions.GetPlayer(source)
  if not xPlayer then return end

  for k,v in pairs(Config.AdminGroups) do 
    if QBCore.Functions.HasPermission(source, v) then 
      return true
    end
  end
  return false
end

QBCore.Functions.CreateCallback('ricky-report:sonoStaff', function(source, cb)
  cb(sonoStaff(source))
end)

RegisterServerEvent('ricky-report:claimReport')
AddEventHandler('ricky-report:claimReport', function(reportId)
  local src = source
  local xPlayer = QBCore.Functions.GetPlayer(src)

  local result =  MySQL.Sync.fetchAll("SELECT * FROM ricky_report WHERE id = @id", {
        ['@id'] = reportId,
  })

  local staff = json.decode(result[1].staff)
  table.insert(staff, {
    name = GetPlayerName(src),
    identifier = xPlayer.identifier
  })

  MySQL.Sync.execute("UPDATE ricky_report SET staff = @staff WHERE id = @id", {
    ['@staff'] = json.encode(staff),
    ['@id'] = reportId
  })

  local reportInfo = json.decode(result[1].reportInfo)
  reportInfo.status = "open"
  MySQL.Sync.execute("UPDATE ricky_report SET reportInfo = @reportInfo WHERE id = @id", {
    ['@reportInfo'] = json.encode(reportInfo),
    ['@id'] = reportId
  })

  TriggerClientEvent('ricky-report:updateReport', -1)

  sendNotificationPlayer(result[1].identifier,"Ticket'ınızı bir yetkili üzerine aldı.", "success")
end)


RegisterServerEvent('ricky-report:action')
AddEventHandler('ricky-report:action', function(action, reportId)
  local src = source
  local xPlayer = QBCore.Functions.GetPlayer(src)

  if action == 'closereport' then 
    local result =  MySQL.Sync.fetchAll("SELECT * FROM ricky_report WHERE id = @id", {
        ['@id'] = reportId,
    })

    local reportInfo = json.decode(result[1].reportInfo)
    reportInfo.status = "closed"
    reportInfo.closeDate = os.date('%d/%m/%Y %H:%M')
    MySQL.Sync.execute("UPDATE ricky_report SET reportInfo = @reportInfo WHERE id = @id", {
      ['@reportInfo'] = json.encode(reportInfo),
      ['@id'] = reportId
    })
  end

  TriggerClientEvent('ricky-report:updateReport', -1)
end)


QBCore.Functions.CreateCallback('ricky-report:getWebhook', function(source, cb)
  cb(ConfigS.Webhook)
end)

RegisterServerEvent('ricky-report:sendImage')
AddEventHandler('ricky-report:sendImage', function(reportId, url)
  local src = source
  local sender = ""
  if sonoStaff(src) then 
    sender = "staff"
  else
    sender = "player"
  end

  local result =  MySQL.Sync.fetchAll("SELECT * FROM ricky_report WHERE id = @id", {
        ['@id'] = reportId,
  })

  local message = json.decode(result[1].message)

  table.insert(message, {
    content = url,
    sender = sender,
    type = "image",
    name = GetPlayerName(src),
    id = src
  })


  MySQL.Sync.execute("UPDATE ricky_report SET message = @message WHERE id = @id", {
    ['@message'] = json.encode(message),
    ['@id'] = reportId
  })

  TriggerClientEvent('ricky-report:updateReport', -1)
  if not sonoStaff(src) then 
    sendNotificationStaff(src, Config.Locales["new_message"], "success")
    TriggerClientEvent('ricky-report:openReportUser', src, reportId)
  else
    sendNotificationPlayer(result[1].identifier, Config.Locales["new_message"], "success")
    TriggerClientEvent('ricky-report:openReportStaff', src, reportId)
  end
end)

sendNotificationStaff = function(id,msg, type)
  local xPlayers = QBCore.Functions.GetPlayers()
  for _, xPlayer in pairs(xPlayers) do
    if tonumber(id)~= tonumber(xPlayer) then
      local isnotify = false
      for k,v in pairs(Config.AdminGroups) do
        if QBCore.Functions.HasPermission(xPlayer, v) and not isnotify then
          isnotify = true
          TriggerClientEvent('ricky-report:notification', xPlayer, msg, type)
        end
      end
   end
  end
end

RegisterServerEvent('ricky-report:brutalAction')
AddEventHandler('ricky-report:brutalAction', function(action, reportId, reason)
  local result = MySQL.Sync.fetchAll("SELECT * FROM ricky_report WHERE id = @id", {
        ['@id'] = reportId,
  })

  local staff = QBCore.Functions.GetPlayer(source)

  if action == 'kick' then 
    local citizenid = result[1].identifier
    local Players = QBCore.Functions.GetPlayers()
    for k,v in pairs(Players) do 
      local xPlayer = QBCore.Functions.GetPlayer(v)
      if xPlayer.PlayerData.citizenid == citizenid then 
        DropPlayer(v, reason)
      end
    end
  elseif action == 'ban' then 
    Ban(result[1].identifier, reason)
  end
end)