'use strict';

/* ═══════════════════════════════════════════════════════
   QBCore Report System – NUI JavaScript Logic
═══════════════════════════════════════════════════════ */

// ─────────────────────────────────────────
//  State
// ─────────────────────────────────────────
const State = {
    selectedCategory:      null,
    selectedCategoryLabel: null,
    selectedPlayer:        null,
    allPlayers:            [],
    allReports:            [],
    activeFilter:          'all',
    isLoading:             false,
    pendingAction:         null,
};

// ─────────────────────────────────────────
//  DOM References
// ─────────────────────────────────────────
const $id = id => document.getElementById(id);

const reportOverlay      = $id('report-overlay');
const categoryGrid       = $id('category-grid');
const playerSearch       = $id('player-search');
const playerList         = $id('player-list');
const selectedPlayerDiv  = $id('selected-player-display');
const selectedPlayerName = $id('selected-player-name');
const clearPlayerBtn     = $id('clear-player');
const reportDesc         = $id('report-description');
const charCount          = $id('char-count');
const submitBtn          = $id('submit-report');

const adminOverlay   = $id('admin-overlay');
const reportListEl   = $id('report-list');
const emptyState     = $id('empty-state');
const statTotal      = $id('stat-total');
const statOpen       = $id('stat-open');
const statClaimed    = $id('stat-claimed');
const statResolved   = $id('stat-resolved');

const toastContainer   = $id('toast-container');
const confirmOverlay   = $id('confirm-overlay');
const confirmMessage   = $id('confirm-message');
const confirmOkBtn     = $id('confirm-ok');
const confirmCancelBtn = $id('confirm-cancel');
const loadingSpinner   = $id('loading-spinner');

// ─────────────────────────────────────────
//  Debounce
// ─────────────────────────────────────────
function debounce(fn, delay) {
    let timer;
    return function (...args) {
        clearTimeout(timer);
        timer = setTimeout(() => fn.apply(this, args), delay);
    };
}

// ─────────────────────────────────────────
//  Loading spinner
// ─────────────────────────────────────────
function setLoading(visible) {
    State.isLoading = visible;
    if (loadingSpinner) loadingSpinner.classList.toggle('hidden', !visible);
}

// ─────────────────────────────────────────
//  Toast
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
        <span class="toast-text">${escapeHtml(message)}</span>`;
    toastContainer.appendChild(toast);
    setTimeout(() => {
        toast.classList.add('toast-out');
        toast.addEventListener('animationend', () => toast.remove(), { once: true });
    }, duration);
}

// ─────────────────────────────────────────
//  Confirm dialog
// ─────────────────────────────────────────
function showConfirm(message, onConfirm) {
    if (!confirmOverlay) { onConfirm(); return; }
    confirmMessage.textContent = message;
    confirmOverlay.classList.remove('hidden');
    State.pendingAction = onConfirm;
}

confirmOkBtn.addEventListener('click', () => {
    confirmOverlay.classList.add('hidden');
    if (typeof State.pendingAction === 'function') {
        State.pendingAction();
    }
    State.pendingAction = null;
});

confirmCancelBtn.addEventListener('click', () => {
    confirmOverlay.classList.add('hidden');
    State.pendingAction = null;
});

// ─────────────────────────────────────────
//  NUI post helper
// ─────────────────────────────────────────
function nuiPost(action, data = {}) {
    const resourceName = (typeof window.GetParentResourceName === 'function')
        ? window.GetParentResourceName()
        : 'qb-report';
    return fetch(`https://${resourceName}/${action}`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(data),
    }).catch(() => { /* NUI dışı ortamda sessizce başarısız ol */ });
}

// ─────────────────────────────────────────
//  XSS guard
// ─────────────────────────────────────────
function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// ─────────────────────────────────────────
//  Form validation
// ─────────────────────────────────────────
function validateForm() {
    const hasCategory = !!State.selectedCategory;
    const hasDesc     = reportDesc.value.trim().length >= 5;
    submitBtn.disabled = !(hasCategory && hasDesc);
}

// ─────────────────────────────────────────
//  Category grid
// ─────────────────────────────────────────
function buildCategories(categories) {
    const fragment = document.createDocumentFragment();
    categories.forEach(cat => {
        const card = document.createElement('div');
        card.className = 'cat-card';
        card.dataset.id    = cat.id;
        card.dataset.label = cat.label;
        if (cat.color) card.style.setProperty('--cat-color', cat.color);
        card.innerHTML = `
            <div class="cat-check"><i class="fas fa-check"></i></div>
            <span class="cat-icon">${escapeHtml(cat.icon || '📋')}</span>
            <span class="cat-label">${escapeHtml(cat.label)}</span>`;
        card.addEventListener('click', () => selectCategory(cat.id, cat.label, card));
        fragment.appendChild(card);
    });
    categoryGrid.innerHTML = '';
    categoryGrid.appendChild(fragment);
}

function selectCategory(id, label, cardEl) {
    categoryGrid.querySelectorAll('.cat-card').forEach(c => c.classList.remove('selected'));
    cardEl.classList.add('selected');
    State.selectedCategory      = id;
    State.selectedCategoryLabel = label;
    validateForm();
}

// ─────────────────────────────────────────
//  Player list
// ─────────────────────────────────────────
function buildPlayerList(players, filter = '') {
    const lower    = filter.toLowerCase();
    const filtered = filter
        ? players.filter(p =>
            p.name.toLowerCase().includes(lower) ||
            String(p.id).includes(filter))
        : players;

    if (filtered.length === 0) {
        playerList.innerHTML = '<div class="player-empty">No players found</div>';
        return;
    }

    const fragment = document.createDocumentFragment();
    filtered.forEach(player => {
        const initials = player.name.split(' ')
            .map(w => w[0] || '').join('').slice(0, 2).toUpperCase();
        const item = document.createElement('div');
        item.className = 'player-item';
        item.innerHTML = `
            <div class="player-avatar">${escapeHtml(initials)}</div>
            <div class="player-info">
                <div class="player-name">${escapeHtml(player.name)}</div>
                <div class="player-id">Server ID: ${player.id}</div>
            </div>`;
        item.addEventListener('click', () => selectPlayer(player));
        fragment.appendChild(item);
    });
    playerList.innerHTML = '';
    playerList.appendChild(fragment);
}

function selectPlayer(player) {
    State.selectedPlayer = player;
    selectedPlayerName.textContent = `${player.name} (ID: ${player.id})`;
    selectedPlayerDiv.classList.remove('hidden');
    playerSearch.value   = '';
    playerList.innerHTML = '';
}

clearPlayerBtn.addEventListener('click', () => {
    State.selectedPlayer = null;
    selectedPlayerDiv.classList.add('hidden');
    playerSearch.value = '';
    buildPlayerList(State.allPlayers);
});

// 250ms debounce: her tuş basışında DOM yeniden oluşturulmaz
playerSearch.addEventListener('input', debounce(() => {
    buildPlayerList(State.allPlayers, playerSearch.value);
}, 250));

// ─────────────────────────────────────────
//  Character counter
// ─────────────────────────────────────────
reportDesc.addEventListener('input', () => {
    const len = reportDesc.value.length;
    charCount.textContent = len;
    charCount.style.color = len > 450 ? '#ef4444' : '';
    validateForm();
});

// ─────────────────────────────────────────
//  Submit report
// ─────────────────────────────────────────
submitBtn.addEventListener('click', () => {
    if (submitBtn.disabled || State.isLoading) return;

    nuiPost('submitReport', {
        category:      State.selectedCategory,
        categoryLabel: State.selectedCategoryLabel,
        description:   reportDesc.value.trim(),
        targetId:      State.selectedPlayer ? State.selectedPlayer.id   : null,
        targetName:    State.selectedPlayer ? State.selectedPlayer.name : null,
    });

    // closeReportModal nuiPost('closeReport') da çağırır — bunu istemiyoruz,
    // sadece UI'yi sıfırla, NUI focus'u kaldır
    reportOverlay.classList.add('hidden');
    SetNuiFocus_safe(false);
    resetReportForm();
    showToast('Report submitted!', 'success');
});

// ─────────────────────────────────────────
//  Close / reset helpers
// ─────────────────────────────────────────

// NUI dışı ortamda (tarayıcı testi) hata vermesin
function SetNuiFocus_safe(state) {
    // FiveM NUI'de bu bildirim Lua'ya gidiyor, doğrudan erişim yok
    // Kapatma her zaman nuiPost üzerinden yapılıyor
}

$id('close-report').addEventListener('click', closeReportModal);
$id('cancel-report').addEventListener('click', closeReportModal);

function closeReportModal() {
    reportOverlay.classList.add('hidden');
    nuiPost('closeReport');
    resetReportForm();
}

function resetReportForm() {
    State.selectedCategory      = null;
    State.selectedCategoryLabel = null;
    State.selectedPlayer        = null;
    categoryGrid.querySelectorAll('.cat-card').forEach(c => c.classList.remove('selected'));
    reportDesc.value         = '';
    charCount.textContent    = '0';
    playerSearch.value       = '';
    playerList.innerHTML     = '';
    selectedPlayerDiv.classList.add('hidden');
    submitBtn.disabled       = true;
}

$id('close-admin').addEventListener('click', closeAdminPanel);

function closeAdminPanel() {
    adminOverlay.classList.add('hidden');
    nuiPost('closeAdmin');
}

// ─────────────────────────────────────────
//  Admin: refresh
// ─────────────────────────────────────────
$id('refresh-reports').addEventListener('click', () => {
    setLoading(true);
    nuiPost('refreshReports').finally(() => setTimeout(() => setLoading(false), 800));
    showToast('Refreshing reports...', 'info', 2000);
});

// ─────────────────────────────────────────
//  Admin: filter tabs
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
//  Admin: render reports (diff-based)
// ─────────────────────────────────────────
function renderReports(reports) {
    State.allReports = reports;

    // Stats
    let open = 0, claimed = 0, resolved = 0;
    for (let i = 0; i < reports.length; i++) {
        const s = reports[i].status;
        if      (s === 'open')     open++;
        else if (s === 'claimed')  claimed++;
        else if (s === 'resolved') resolved++;
    }
    statTotal.textContent    = reports.length;
    statOpen.textContent     = open;
    statClaimed.textContent  = claimed;
    statResolved.textContent = resolved;

    // Filter
    const filtered = State.activeFilter === 'all'
        ? reports
        : reports.filter(r => r.status === State.activeFilter);

    // Diff: mevcut kartları karşılaştır
    const existingCards = reportListEl.querySelectorAll('.report-card');
    const existingMap   = new Map();
    existingCards.forEach(c => existingMap.set(Number(c.dataset.id), c));

    const newIdSet = new Set(filtered.map(r => r.id));

    // Artık gerekmeyenleri kaldır
    existingMap.forEach((card, id) => {
        if (!newIdSet.has(id)) card.remove();
    });

    if (filtered.length === 0) {
        emptyState.style.display = 'flex';
        return;
    }
    emptyState.style.display = 'none';

    const fragment = document.createDocumentFragment();
    let needsAppend = false;

    filtered.forEach(r => {
        const existing = existingMap.get(r.id);
        if (existing) {
            // Sadece statü değiştiyse kartı yenile
            const currentStatus = existing.querySelector('.report-status-badge')
                ? existing.querySelector('.report-status-badge').dataset.status
                : null;
            if (currentStatus !== r.status) {
                existing.replaceWith(buildReportCard(r));
            }
        } else {
            fragment.appendChild(buildReportCard(r));
            needsAppend = true;
        }
    });

    if (needsAppend) reportListEl.appendChild(fragment);
}

function buildReportCard(r) {
    const statusClass = {
        open:     'badge-open',
        claimed:  'badge-claimed',
        resolved: 'badge-resolved',
    }[r.status] || 'badge-open';

    const statusLabel = r.status.charAt(0).toUpperCase() + r.status.slice(1);

    const card = document.createElement('div');
    card.className  = 'report-card';
    card.dataset.id = r.id;

    card.innerHTML = `
        <div class="report-card-header">
            <span class="report-id">#${r.id}</span>
            <span class="report-category-badge">${escapeHtml(r.categoryLabel || r.category)}</span>
            <span class="report-status-badge ${statusClass}" data-status="${r.status}">${statusLabel}</span>
        </div>
        <div class="report-card-body">
            <div class="report-meta">
                <span><i class="fas fa-user"></i> ${escapeHtml(r.reporterName)} (ID: ${r.reporterId})</span>
                ${r.targetName ? `<span><i class="fas fa-crosshairs"></i> ${escapeHtml(r.targetName)} (ID: ${r.targetId})</span>` : ''}
                <span><i class="fas fa-clock"></i> ${escapeHtml(r.timestamp)}</span>
                ${r.claimedBy ? `<span><i class="fas fa-shield-halved"></i> ${escapeHtml(r.claimedBy)}</span>` : ''}
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
        </div>`;

    const claimBtn = card.querySelector('.claim-btn');
    if (claimBtn) {
        claimBtn.addEventListener('click', () => {
            showConfirm(`Claim report #${r.id}?`, () => {
                nuiPost('claimReport', { reportId: r.id });
                showToast(`Claimed report #${r.id}`, 'warning');
            });
        });
    }

    const resolveBtn = card.querySelector('.resolve-btn');
    if (resolveBtn) {
        resolveBtn.addEventListener('click', () => {
            showConfirm(`Resolve report #${r.id}? Reporter will be notified.`, () => {
                nuiPost('resolveReport', { reportId: r.id });
                showToast(`Resolved report #${r.id}`, 'success');
            });
        });
    }

    const tpBtn = card.querySelector('.teleport-btn');
    if (tpBtn) {
        tpBtn.addEventListener('click', () => {
            nuiPost('teleportToReporter', { playerId: parseInt(tpBtn.dataset.player) });
            closeAdminPanel();
            showToast('Teleporting to reporter...', 'info', 2500);
        });
    }

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
//  NUI message handler
// ─────────────────────────────────────────
window.addEventListener('message', function (event) {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {

        case 'openReport': {
            State.allPlayers = Array.isArray(data.players) ? data.players : [];
            buildCategories(Array.isArray(data.categories) ? data.categories : []);
            buildPlayerList(State.allPlayers);
            resetReportForm();
            reportOverlay.classList.remove('hidden');
            break;
        }

        case 'openAdmin': {
            renderReports(Array.isArray(data.reports) ? data.reports : []);
            adminOverlay.classList.remove('hidden');
            break;
        }

        case 'updateReports': {
            if (Array.isArray(data.reports)) renderReports(data.reports);
            break;
        }

        case 'newReportAlert': {
            const r = data.report;
            if (!r) break;
            showToast(
                `New Report #${r.id} — ${escapeHtml(r.categoryLabel || r.category)} from ${escapeHtml(r.reporterName)}`,
                'error', 6000
            );
            const refreshBtn = $id('refresh-reports');
            if (refreshBtn) {
                refreshBtn.classList.add('btn-alert-pulse');
                setTimeout(() => refreshBtn.classList.remove('btn-alert-pulse'), 3000);
            }
            break;
        }

        case 'closeAll': {
            reportOverlay.classList.add('hidden');
            adminOverlay.classList.add('hidden');
            resetReportForm();
            break;
        }
    }
});

// ─────────────────────────────────────────
//  Keyboard handler
//  ESC → confirm dialog > report modal > admin panel
//        her modal kapanışında Lua'ya escPressed gönder
//  Ctrl+R → admin panelinde yenile
// ─────────────────────────────────────────
document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
        // 1. Confirm dialog açıksa sadece onu kapat, Lua'ya bildirme
        if (confirmOverlay && !confirmOverlay.classList.contains('hidden')) {
            confirmOverlay.classList.add('hidden');
            State.pendingAction = null;
            return;
        }
        // 2. Report modal
        if (!reportOverlay.classList.contains('hidden')) {
            closeReportModal();
            nuiPost('escPressed');
            return;
        }
        // 3. Admin panel
        if (!adminOverlay.classList.contains('hidden')) {
            closeAdminPanel();
            nuiPost('escPressed');
            return;
        }
    }

    if (e.key === 'r' && (e.ctrlKey || e.metaKey) && !adminOverlay.classList.contains('hidden')) {
        e.preventDefault();
        nuiPost('refreshReports');
        showToast('Refreshing...', 'info', 1500);
    }
});
