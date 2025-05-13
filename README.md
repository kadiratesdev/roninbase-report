# QBCore Report System

A comprehensive report management system for QBCore Framework. This system allows players to submit reports and administrators to manage them efficiently.

## 🌟 Features

- **Player Reports**: Players can submit reports with detailed information
- **Admin Panel**: Comprehensive admin interface for report management
- **Discord Integration**: Automatic Discord webhook notifications
- **Report Categories**: Organized report types (Bug, Cheat, Roleplay, etc.)
- **Status Tracking**: Track report status (Open, In Progress, Closed)
- **Admin Notes**: Add private notes to reports
- **Report History**: Keep track of all reports and their status
- **Priority System**: Set report priority levels
- **Player History**: View player's report history

## 🚀 Installation

1. Download the resource
2. Place it in your server's resources folder
3. Add `ensure roninbase-report` to your server.cfg
4. Configure the config.lua file
5. Restart your server

## 💻 Configuration

### config.lua
```lua
Config = {}
Config.DiscordWebhook = "YOUR_WEBHOOK_HERE"
Config.AdminGroups = {
    ['admin'] = true,
    ['mod'] = true
}
Config.ReportCategories = {
    'Bug',
    'Cheat',
    'Roleplay',
    'Other'
}
```

## 📋 Commands

- `/report [category] [message]` - Submit a new report
- `/reports` - Open report management panel (Admin only)


## ⚙️ Dependencies

- QBCore Framework
- qb-core

## 👨‍💻 Author

- **kadiratesdev** - *Initial work*

## 🔗 Links

- [Discord Community](https://discord.gg/roninrp)
