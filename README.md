<div align="center">

<img src="https://i.imgur.com/HcZHHUR.png" width="80" height="80" alt="roninbase-report logo" />

# roninbase-report

**A modern, feature-rich player report system for QBCore FiveM servers**

[![Version](https://img.shields.io/badge/version-1.3.0-blue?style=for-the-badge)](https://github.com/kadiratesdev/roninbase-report/releases)
[![FiveM](https://img.shields.io/badge/FiveM-QBCore-orange?style=for-the-badge)](https://github.com/qbcore-framework)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![i18n](https://img.shields.io/badge/i18n-TR%20%7C%20EN-purple?style=for-the-badge)](#-multi-language)

[Features](#-features) · [Installation](#-installation) · [Configuration](#-configuration) · [Commands](#-commands) · [Multi-Language](#-multi-language)

</div>

---

## ✨ Features

| | | |
|---|---|---|
| 🎨 **Beautiful NUI** | Modern glassmorphism design with smooth animations |
| 📋 **Category System** | 6 built-in report categories with custom icons & colors |
| 👮 **Admin Panel** | Real-time report management with claim/resolve/teleport |
| 📜 **History & Stats** | Full resolved report history + per-admin performance stats |
| 🌍 **Multi-Language** | Built-in Turkish & English support, switchable in-game |
| 🔔 **Discord Webhooks** | Rich embeds for new reports, claims and resolutions |
| 🛡️ **Rate Limiting** | Flood protection with per-player event buckets |
| ⏱️ **Cooldown System** | Configurable cooldown between player reports |
| 🔐 **ACE Permissions** | ACE-first permission system with QBCore group fallback |
| 💾 **MySQL Persistent** | All reports (active & resolved) saved to database via oxmysql |
| 🚫 **Validation** | Prevents multiple active reports from the same player |

---

> **NUI built with vanilla HTML/CSS/JS** — zero external frameworks, optimized for FiveM's CEF renderer.

---

## 📦 Installation

### 1. Dependencies

Make sure these resources are installed and started **before** `roninbase-report`:

- [`qb-core`](https://github.com/qbcore-framework/qb-core)
- [`oxmysql`](https://github.com/overextended/oxmysql)

### 2. Download

```bash
# Clone into your resources folder
git clone https://github.com/kadiratesdev/roninbase-report.git
```

Or download the latest release as a ZIP and extract it into your `resources/` directory.

### 3. Add to server.cfg

```cfg
ensure roninbase-report
```

### 4. ACE Permissions (Recommended)

Add these lines to your `server.cfg` for permission control:

```cfg
add_ace group.admin       roninbase-report.admin      allow
add_ace group.mod         roninbase-report.admin      allow
add_ace group.superadmin  roninbase-report.admin      allow
add_ace group.superadmin  roninbase-report.superadmin allow
```

> If ACE permissions are not set, the resource falls back to QBCore group checks defined in `server_config.lua`.

### 5. Discord Webhook

Open `server_config.lua` and set your webhook URL:

```lua
ServerConfig.Discord = {
    Enabled = true,
    Webhook = 'YOUR_DISCORD_WEBHOOK_URL_HERE',
    ...
}
```

The database table (`qb_reports`) is created automatically on first start.

---

## ⚙️ Configuration

### `config.lua` — Client side

```lua
-- Language: 'tr' = Turkish | 'en' = English
Config.Locale = 'tr'

-- Commands
Config.Command           = 'report'        -- Opens report menu (players)
Config.AdminCommand      = 'reports'       -- Opens admin panel
Config.SuperAdminCommand = 'reporthistory' -- Opens history + stats panel

-- Report categories (labels auto-loaded from locale files)
Config.Categories = {
    { id = 'cheating',  icon = '🎮', color = '#e74c3c' },
    { id = 'rdm',       icon = '🔫', color = '#e67e22' },
    { id = 'vdm',       icon = '🚗', color = '#f39c12' },
    { id = 'toxicity',  icon = '💬', color = '#9b59b6' },
    { id = 'bug',       icon = '🐛', color = '#3498db' },
    { id = 'other',     icon = '📋', color = '#95a5a6' },
}
```

### `server_config.lua` — Server side

```lua
-- Language for server notifications & Discord embeds
ServerConfig.Locale = 'tr'

ServerConfig.Cooldown      = 120   -- Seconds between reports
ServerConfig.MaxDescLength = 500   -- Max description characters
ServerConfig.MaxReports    = 200   -- Max reports kept in memory

ServerConfig.RateLimit = {
    MaxWindow = 10,   -- seconds
    MaxEvents = 8,    -- max events in window
}
```

---

## 💬 Commands

| Command | Who | Description |
|---|---|---|
| `/report` | Players | Opens the report submission menu |
| `/reports` | Admins | Opens the live admin report panel |
| `/reporthistory` | SuperAdmins | Opens history + staff statistics panel |

---

## 🌍 Multi-Language

`roninbase-report` has full **Turkish** and **English** support across all layers:

### In-game NUI
Click the **🇬🇧 EN** / **🇹🇷 TR** button in the top-right corner of any panel. The language switches instantly and is remembered via `localStorage`.

### Notifications & Discord
Set the locale in the config files:

```lua
-- config.lua (client notifications)
Config.Locale = 'en'

-- server_config.lua (server notifications + Discord embeds)
ServerConfig.Locale = 'en'
```

### Adding a New Language

1. Copy `locales/en.lua` → `locales/xx.lua` (server/client strings)
2. Copy `html/assets/locales/en.json` → `html/assets/locales/xx.json` (NUI strings)
3. Translate all values
4. Add the new locale file to `files {}` in `fxmanifest.lua`
5. Add a button in `html/index.html`:
    ```html
    <button class="lang-btn" data-lang="xx">🏳️ XX</button>
    ```

---

## 📁 File Structure

```
roninbase-report/
├── fxmanifest.lua          # Resource manifest
├── config.lua              # Client-side config (locale, commands, categories)
├── server_config.lua       # Server-side config (webhook, cooldown, permissions)
├── client.lua              # FiveM client script
├── server.lua              # FiveM server script
├── locales/
│   ├── en.lua              # English – Lua strings (notifications, Discord)
│   └── tr.lua              # Turkish – Lua strings (notifications, Discord)
└── html/
    ├── index.html          # NUI entry point
    └── assets/
        ├── css/style.css   # NUI styles
        ├── js/app.js       # NUI logic + i18n engine
        └── locales/
            ├── en.json     # English – NUI strings
            └── tr.json     # Turkish – NUI strings
```

---

## 🔒 Security

- **Webhook URL** is loaded only in `server_config.lua` — never sent to clients
- **Server-side category whitelist** prevents invalid report categories
- **Rate limiting** blocks event flooding per player
- **Input sanitization** strips control characters and enforces max lengths
- **Permission checks** on every admin/superadmin event handler
- **Double-spending protection** for report submissions

---

## 📜 Changelog

### v1.3.0
- Added full **multi-language support** (Turkish & English)
- NUI language switcher button (🇬🇧 / 🇹🇷) with localStorage persistence
- Locale files for both client/server Lua and NUI JSON
- Category labels now sourced from locale files
- **Real-time database persistence** (reports saved on creation)
- **Active report validation** (prevents duplicate reports per player)
- Improved admin history with advanced filtering and search

### v1.2.0
- Added **Report History** panel for SuperAdmins
- Added **Staff Statistics** table (total resolved, avg time, top category)
- Pagination, search and filter on history panel

### v1.1.0
- Initial admin panel with claim / resolve / teleport actions
- Discord webhook integration with rich embeds
- Rate limiting & cooldown system

---

## 🤝 Contributing

Pull requests are welcome. For major changes please open an issue first to discuss what you would like to change.

---

<div align="center">

Made with ❤️ for the FiveM community

</div>
