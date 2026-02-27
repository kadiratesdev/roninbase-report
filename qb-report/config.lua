Config = {}

-- General Settings
Config.Command = 'report'          -- Command to open report menu
Config.AdminCommand = 'reports'    -- Command to open admin panel
Config.Cooldown = 120              -- Cooldown between reports in seconds
Config.MaxDescLength = 500         -- Max characters in report description

-- Admin Groups (QBCore permission levels)
Config.AdminGroups = {
    'admin',
    'superadmin',
    'mod',
    'moderator'
}

-- Discord Webhook
Config.Discord = {
    Enabled = true,
    Webhook = 'YOUR_DISCORD_WEBHOOK_URL_HERE',  -- Replace with your webhook
    BotName = 'Report System',
    BotAvatar = 'https://i.imgur.com/HcZHHUR.png',  -- Bot avatar URL

    -- Colors (decimal format)
    Colors = {
        NewReport  = 16711680,   -- Red
        Claimed    = 16776960,   -- Yellow
        Resolved   = 65280,      -- Green
    }
}

-- Report Categories
Config.Categories = {
    { id = 'cheating',    label = 'Cheating / Hacking',       icon = '🎮', color = '#e74c3c' },
    { id = 'rdm',         label = 'RDM (Random Deathmatch)',   icon = '🔫', color = '#e67e22' },
    { id = 'vdm',         label = 'VDM (Vehicle Deathmatch)',  icon = '🚗', color = '#f39c12' },
    { id = 'toxicity',    label = 'Toxicity / Harassment',     icon = '💬', color = '#9b59b6' },
    { id = 'bug',         label = 'Bug Report',                icon = '🐛', color = '#3498db' },
    { id = 'other',       label = 'Other',                     icon = '📋', color = '#95a5a6' },
}

-- Notification Settings (uses QBCore notifications)
Config.Notifications = {
    ReportSent     = 'Your report has been submitted. An admin will review it shortly.',
    ReportCooldown = 'You must wait before submitting another report.',
    AdminNotify    = 'New report received from a player.',
    Claimed        = 'You have claimed this report.',
    Resolved       = 'Report has been marked as resolved.',
    NoAdmins       = 'There are no admins online right now. Your report has been logged.',
}
