-- ─────────────────────────────────────────────────────────────────────────────
--  qb-report  |  English Translations
-- ─────────────────────────────────────────────────────────────────────────────
return {
    -- Client notifications
    report_sent         = 'Your report has been submitted. A staff member will review it shortly.',
    admin_notify        = 'A new player report has been received.',
    cooldown            = 'You must wait {seconds} seconds before submitting another report.',
    no_permission    = 'You do not have permission to use this command.',
    already_have_active_report = 'You already have an active report. Please wait for it to be resolved.',
    desc_too_short      = 'Please provide a more detailed description (min. 5 characters).',
    report_claimed      = 'A staff member has claimed your report.',
    report_resolved     = 'Your report has been resolved by a staff member.',

    -- Discord embed labels
    discord_new_report        = '🚨 New Report #',
    discord_new_report_desc   = 'A player has submitted a report.',
    discord_claimed           = ' Claimed',
    discord_resolved          = ' Resolved',
    discord_field_category    = '📋 Category',
    discord_field_reporter    = '👤 Reporter',
    discord_field_target      = '🎯 Reported Player',
    discord_field_description = '📝 Description',
    discord_field_admin       = '👮 Staff',
    discord_field_report_id   = '🔔 Report ID',
    discord_field_closer      = '👮 Closed By',
    discord_field_duration    = '⏱️ Duration',
    discord_field_not_specified = 'Not specified',
    discord_duration_fmt      = '{min}m {sec}s',

    -- Category labels
    cat_cheating   = 'Cheating / Hacking',
    cat_rdm        = 'RDM (Random Deathmatch)',
    cat_vdm        = 'VDM (Vehicle Deathmatch)',
    cat_toxicity   = 'Toxicity / Harassment',
    cat_bug        = 'Bug Report',
    cat_other      = 'Other',
}
