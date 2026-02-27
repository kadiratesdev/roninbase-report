/* ═══════════════════════════════════════════════════════
   QBCore Report System – NUI JavaScript Logic
═══════════════════════════════════════════════════════ */

'use strict';

// ─────────────────────────────────────────
//  State
// ─────────────────────────────────────────
const State = {
    selectedCategory:  null,
    selectedCategoryLabel: null,
    selectedPlayer:    null,
    allPlayers:        [],
    allReports:        [],
    activeFilter:      'all',
};

// ─────────────────────────────────────────
//  DOM References
// ─────────────────────────────────────────
const $ = id => document.getElementById(id);

// Report Modal
const reportOverlay     = $('report-overlay');
const categoryGrid      = $('category-grid');
const playerSearch      = $('player-search');
const playerList        = $('player-list');
const selectedPlayerDiv = $('selected-player-display');
const selectedPlayerName= $('selected-player-name');
const clearPlayerBtn    = $('clear-player');
const reportDesc        = $('report-description');
const charCount         = $('char-count');
const submitBtn         = $('submit-report');

// Admin Modal
const adminOverlay      = $('admin-overlay');
const reportListEl      = $('report-list');
const emptyState        = $('empty-state');
const statTotal         = $('stat-total');
const statOpen          = $('stat-open');
const statClaimed       = $('stat-claimed');
const statResolved      = $('stat-resolved');

// Toast
const toastContainer    = $('toast-container');

// ─────────────────────────────────────────
//  Toast Helper
// ─────────────────────────────────────────
function showToast(message, type = 'info', duration = 4000) {
    const icons = {
        success: 'fa-circle-check',
        error:   'fa-circle-xmark',
        info:    'fa-circle-info',
        warning: 'fa-triangle-exclamation',
    };

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `
        <i class="fas ${icons[type] || icons.info} toast-icon"></i>
        <span class="toast-text">${message}</span>
    `;

    toastContainer.appendChild(toast);

    setTimeout(() => {
        toast.classList.add('toast-out');
        toast.addEventListener('animationend', () => toast.remove());
    }, duration);
}

// ─────────────────────────────────────────
//  NUI Post Helper
// ─────────────────────────────────────────
function nuiPost(action, data = {}) {
    return fetch(`https://qb-report/${action}`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(data),
    });
}

// ─────────────────────────────────────────
//  Validate: enable/disable submit btn
// ─────────────────────────────────────────
function validateForm() {
    const hasCategory = !!State.selectedCategory;
    const hasDesc     = reportDesc.value.trim().length >= 5;
    submitBtn.disabled = !(hasCategory && hasDesc);
}

// ─────────────────────────────────────────
//  Build Category Grid
// ─────────────────────────────────────────
function buildCategories(categories) {
    categoryGrid.innerHTML = '';

    categories.forEach(cat => {
        const card = document.createElement('div');
        card.className = 'cat-card';
        card.dataset.id    = cat.id;
        card.dataset.label = cat.label;
        if (cat.color) card.style.setProperty('--cat-color', cat.color);

        card.innerHTML = `
            <div class="cat-check"><i class="fas fa-check"></i></div>
            <span class="cat-icon">${cat.icon || '📋'}</span>
            <span class="cat-label">${cat.label}</span>
        `;

        card.addEventListener('click', () => selectCategory(cat.id, cat.label, card));
        categoryGrid.appendChild(card);
    });
}

function selectCategory(id, label, cardEl) {
    document.querySelectorAll('.cat-card').forEach(c => c.classList.remove('selected'));
    cardEl.classList.add('selected');
    State.selectedCategory      = id;
    State.selectedCategoryLabel = label;
    validateForm();
}

// ─────────────────────────────────────────
//  Build Player List
// ─────────────────────────────────────────
function buildPlayerList(players, filter = '') {
    playerList.innerHTML = '';

    const filtered = players.filter(p =>
        p.name.toLowerCase().includes(filter.toLowerCase()) ||
        String(p.id).includes(filter)
    );

    if (filtered.length === 0) {
        playerList.innerHTML = `
            <div style="padding:14px;text-align:center;color:var(--text-muted);font-size:12px;">
                No players found
            </div>`;
        return;
    }

    filtered.forEach(player => {
        const initials = player.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();

        const item = document.createElement('div');
        item.className = 'player-item';
        item.innerHTML = `
            <div class="player-avatar">${initials}</div>
            <div class="player-info">
                <div class="player-name">${player.name}</div>
                <div class="player-id">Server ID: ${player.id}</div>
            </div>
        `;

        item.addEventListener('click', () => selectPlayer(player));
        playerList.appendChild(item);
    });
}

function selectPlayer(player) {
    State.selectedPlayer    = player;
    selectedPlayerName.textContent = `${player.name} (ID: ${player.id})`;
    selectedPlayerDiv.classList.remove('hidden');
    playerSearch.value      = '';
    playerList.innerHTML    = '';
}

clearPlayerBtn.addEventListener('click', () => {
    State.selectedPlayer = null;
    selectedPlayerDiv.classList.add('hidden');
    playerSearch.value = '';
    buildPlayerList(State.allPlayers);
});

playerSearch.addEventListener('input', () => {
    buildPlayerList(State.allPlayers, playerSearch.value);
});

// ─────────────────────────────────────────
//  Character Counter
// ─────────────────────────────────────────
reportDesc.addEventListener('input', () => {
    const len = reportDesc.value.length;
    charCount.textContent = len;
    charCount.style.color = len > 450 ? '#ef4444' : '';
    validateForm();
});

// ─────────────────────────────────────────
//  Submit Report
// ─────────────────────────────────────────
submitBtn.addEventListener('click', () => {
    if (submitBtn.disabled) return;

    nuiPost('submitReport', {
        category:      State.selectedCategory,
        categoryLabel: State.selectedCategoryLabel,
        description:   reportDesc.value.trim(),
        targetId:      State.selectedPlayer?.id   ?? null,
        targetName:    State.selectedPlayer?.name ?? null,
    });

    closeReportModal();
    showToast('Report submitted successfully!', 'success');
});

// ─────────────────────────────────────────
//  Close handlers (Report)
// ─────────────────────────────────────────
$('close-report').addEventListener('click',  closeReportModal);
$('cancel-report').addEventListener('click', closeReportModal);

function closeReportModal() {
    reportOverlay.classList.add('hidden');
    nuiPost('closeReport');
    resetReportForm();
}

function resetReportForm() {
    State.selectedCategory      = null;
    State.selectedCategoryLabel = null;
    State.selectedPlayer        = null;
    document.querySelectorAll('.cat-card').forEach(c => c.classList.remove('selected'));
    reportDesc.value         = '';
    charCount.textContent    = '0';
    playerSearch.value       = '';
    playerList.innerHTML     = '';
    selectedPlayerDiv.classList.add('hidden');
    submitBtn.disabled       = true;
}

// ─────────────────────────────────────────
//  Close handlers (Admin)
// ─────────────────────────────────────────
$('close-admin').addEventListener('click', closeAdminPanel);

function closeAdminPanel() {
    adminOverlay.classList.add('hidden');
    nuiPost('closeAdmin');
}

// ─────────────────────────────────────────
//  Admin: Refresh
// ─────────────────────────────────────────
$('refresh-reports').addEventListener('click', () => {
    nuiPost('refreshReports');
    showToast('Refreshing reports...', 'info', 2000);
});

// ─────────────────────────────────────────
//  Admin: Filter Tabs
// ─────────────────────────────────────────
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        State.activeFilter = btn.dataset.filter;
        renderReports(State.allReports);
    });
});

// ─────────────────────────────────────────
//  Admin: Render Reports
// ─────────────────────────────────────────
function renderReports(reports) {
    State.allReports = reports;

    // Update stats
    const total    = reports.length;
    const open     = reports.filter(r => r.status === 'open').length;
    const claimed  = reports.filter(r => r.status === 'claimed').length;
    const resolved = reports.filter(r => r.status === 'resolved').length;

    statTotal.textContent    = total;
    statOpen.textContent     = open;
    statClaimed.textContent  = claimed;
    statResolved.textContent = resolved;

    // Filter
    const filtered = State.activeFilter === 'all'
        ? reports
        : reports.filter(r => r.status === State.activeFilter);

    // Clear existing cards (keep empty state ref)
    reportListEl.querySelectorAll('.report-card').forEach(c => c.remove());

    if (filtered.length === 0) {
        emptyState.style.display = 'flex';
        return;
    }

    emptyState.style.display = 'none';

    filtered.forEach(r => {
        const card = buildReportCard(r);
        reportListEl.appendChild(card);
    });
}

function buildReportCard(r) {
    const card = document.createElement('div');
    card.className = 'report-card';
    card.dataset.id = r.id;

    const statusClass = {
        open:     'badge-open',
        claimed:  'badge-claimed',
        resolved: 'badge-resolved',
    }[r.status] || 'badge-open';

    const statusLabel = r.status.charAt(0).toUpperCase() + r.status.slice(1);

    card.innerHTML = `
        <div class="report-card-header">
            <span class="report-id">#${r.id}</span>
            <span class="report-category-badge">${r.categoryLabel || r.category}</span>
            <span class="report-status-badge ${statusClass}">${statusLabel}</span>
        </div>
        <div class="report-card-body">
            <div class="report-meta">
                <span><i class="fas fa-user"></i> ${r.reporterName} (ID: ${r.reporterId})</span>
                ${r.targetName ? `<span><i class="fas fa-crosshairs"></i> ${r.targetName} (ID: ${r.targetId})</span>` : ''}
                <span><i class="fas fa-clock"></i> ${r.timestamp}</span>
                ${r.claimedBy ? `<span><i class="fas fa-shield-halved"></i> ${r.claimedBy}</span>` : ''}
            </div>
            <div class="report-description">${escapeHtml(r.description)}</div>
        </div>
        <div class="report-card-actions">
            ${r.status === 'open' ? `
                <button class="btn btn-sm btn-yellow claim-btn" data-id="${r.id}">
                    <i class="fas fa-hand-paper"></i> Claim
                </button>` : ''}
            ${r.status !== 'resolved' ? `
                <button class="btn btn-sm btn-success resolve-btn" data-id="${r.id}">
                    <i class="fas fa-check"></i> Resolve
                </button>` : ''}
            <button class="btn btn-sm btn-outline teleport-btn" data-player="${r.reporterId}">
                <i class="fas fa-location-crosshairs"></i> Teleport to Reporter
            </button>
            ${r.targetId ? `
                <button class="btn btn-sm btn-danger teleport-target-btn" data-player="${r.targetId}">
                    <i class="fas fa-crosshairs"></i> Teleport to Reported
                </button>` : ''}
        </div>
    `;

    // Claim
    const claimBtn = card.querySelector('.claim-btn');
    if (claimBtn) {
        claimBtn.addEventListener('click', () => {
            nuiPost('claimReport', { reportId: r.id });
            showToast(`Claimed report #${r.id}`, 'warning');
        });
    }

    // Resolve
    const resolveBtn = card.querySelector('.resolve-btn');
    if (resolveBtn) {
        resolveBtn.addEventListener('click', () => {
            nuiPost('resolveReport', { reportId: r.id });
            showToast(`Resolved report #${r.id}`, 'success');
        });
    }

    // Teleport to reporter
    const tpBtn = card.querySelector('.teleport-btn');
    if (tpBtn) {
        tpBtn.addEventListener('click', () => {
            nuiPost('teleportToReporter', { playerId: parseInt(tpBtn.dataset.player) });
            closeAdminPanel();
            showToast('Teleporting to reporter...', 'info', 2500);
        });
    }

    // Teleport to reported player
    const tpTargetBtn = card.querySelector('.teleport-target-btn');
    if (tpTargetBtn) {
        tpTargetBtn.addEventListener('click', () => {
            nuiPost('teleportToReporter', { playerId: parseInt(tpTargetBtn.dataset.player) });
            closeAdminPanel();
            showToast('Teleporting to reported player...', 'info', 2500);
        });
    }

    return card;
}

// ─────────────────────────────────────────
//  Escape HTML (XSS guard)
// ─────────────────────────────────────────
function escapeHtml(str) {
    const div = document.createElement('div');
    div.appendChild(document.createTextNode(str || ''));
    return div.innerHTML;
}

// ─────────────────────────────────────────
//  Main NUI Message Listener
// ─────────────────────────────────────────
window.addEventListener('message', function(event) {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {

        // ── Open report modal ──
        case 'openReport': {
            State.allPlayers = data.players || [];
            buildCategories(data.categories || []);
            buildPlayerList(State.allPlayers);
            resetReportForm();
            reportOverlay.classList.remove('hidden');
            break;
        }

        // ── Open admin panel ──
        case 'openAdmin': {
            renderReports(data.reports || []);
            adminOverlay.classList.remove('hidden');
            break;
        }

        // ── Update report list (admin panel) ──
        case 'updateReports': {
            renderReports(data.reports || []);
            break;
        }

        // ── New report alert (admin) ──
        case 'newReportAlert': {
            const r = data.report;
            showToast(
                `🚨 New Report #${r.id} — ${r.categoryLabel || r.category} from ${r.reporterName}`,
                'error',
                6000
            );
            // Pulse the refresh button
            const refreshBtn = $('refresh-reports');
            if (refreshBtn) {
                refreshBtn.style.borderColor = 'var(--status-open)';
                setTimeout(() => refreshBtn.style.borderColor = '', 3000);
            }
            break;
        }

        // ── Close all ──
        case 'closeAll': {
            reportOverlay.classList.add('hidden');
            adminOverlay.classList.add('hidden');
            resetReportForm();
            break;
        }
    }
});

// ─────────────────────────────────────────
//  ESC Key (fallback for NUI)
// ─────────────────────────────────────────
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        if (!reportOverlay.classList.contains('hidden')) closeReportModal();
        if (!adminOverlay.classList.contains('hidden'))  closeAdminPanel();
    }
});
