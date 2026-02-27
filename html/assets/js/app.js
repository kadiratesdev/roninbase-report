'use strict';

/* ═══════════════════════════════════════════════════════
   QBCore Report System – NUI JavaScript Logic
═══════════════════════════════════════════════════════ */

/* ─────────────────────────────────────────
   i18n Engine
───────────────────────────────────────── */
const I18n = {
    locale: 'en',
    translations: {},

    async load(lang) {
        try {
            const res = await fetch(`assets/locales/${lang}.json`);
            if (!res.ok) throw new Error('locale not found');
            this.translations[lang] = await res.json();
        } catch (e) {
            console.warn(`[i18n] Could not load locale: ${lang}`, e);
        }
    },

    t(key, vars) {
        const dict = this.translations[this.locale] || this.translations['en'] || {};
        let str = dict[key] || key;
        if (vars) {
            for (const [k, v] of Object.entries(vars)) {
                str = str.replace(new RegExp(`\\{${k}\\}`, 'g'), v);
            }
        }
        return str;
    },

    async setLocale(lang) {
        if (!this.translations[lang]) await this.load(lang);
        this.locale = lang;
        localStorage.setItem('qb_report_lang', lang);
        document.documentElement.lang = lang;
        this.applyToDOM();
        this.updateLangButtons();
    },

    applyToDOM() {
        // text content
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.dataset.i18n;
            el.textContent = this.t(key);
        });
        // placeholders
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            el.placeholder = this.t(el.dataset.i18nPlaceholder);
        });
        // select options
        document.querySelectorAll('select option[data-i18n]').forEach(el => {
            el.textContent = this.t(el.dataset.i18n);
        });
    },

    updateLangButtons() {
        document.querySelectorAll('.lang-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.lang === this.locale);
        });
    },

    async init() {
        const saved = localStorage.getItem('qb_report_lang') || 'en';
        await Promise.all([this.load('en'), this.load('tr')]);
        this.locale = saved;
        document.documentElement.lang = saved;
        this.applyToDOM();
        this.updateLangButtons();

        document.querySelectorAll('.lang-btn').forEach(btn => {
            btn.addEventListener('click', () => this.setLocale(btn.dataset.lang));
        });
    }
};

/* ─────────────────────────────────────────
   State
───────────────────────────────────────── */
const State = {
    selectedCategory: null, selectedCategoryLabel: null, selectedPlayer: null,
    allPlayers: [], allReports: [], activeFilter: 'all', adminPage: 1, adminPageSize: 10,
    isLoading: false, pendingAction: null,
    historyPage: 1, historyTotal: 0, historyFilter: 'all', historySearch: '', historyStatus: 'all', historyPageSize: 20,
};

const $id = id => document.getElementById(id);

const reportOverlay = $id('report-overlay'), categoryGrid = $id('category-grid'),
      playerSearch = $id('player-search'), playerList = $id('player-list'),
      selectedPlayerDiv = $id('selected-player-display'), selectedPlayerName = $id('selected-player-name'),
      clearPlayerBtn = $id('clear-player'), reportDesc = $id('report-description'),
      charCount = $id('char-count'), submitBtn = $id('submit-report'),
      adminOverlay = $id('admin-overlay'), reportListEl = $id('report-list'),
      emptyState = $id('empty-state'), statTotal = $id('stat-total'),
      statOpen = $id('stat-open'), statClaimed = $id('stat-claimed'),
      adminPrev = $id('admin-prev'), adminNext = $id('admin-next'), adminPageInfo = $id('admin-page-info'),
      historyOverlay = $id('history-overlay'), historyList = $id('history-list'),
      historyEmpty = $id('history-empty'), historyPageInfo = $id('history-page-info'),
      historySearchEl = $id('history-search'), historyFilterEl = $id('history-filter'),
      historyStatusFilterEl = $id('history-status-filter'),
      statsSummary = $id('stats-summary'), statsTbody = $id('stats-tbody'),
      toastContainer = $id('toast-container'), confirmOverlay = $id('confirm-overlay'),
      confirmMessage = $id('confirm-message'), confirmOkBtn = $id('confirm-ok'),
      confirmCancelBtn = $id('confirm-cancel'), loadingSpinner = $id('loading-spinner');

function debounce(fn, delay) { let t; return function(...a){ clearTimeout(t); t=setTimeout(()=>fn.apply(this,a),delay); }; }
function setLoading(v) { State.isLoading=v; if(loadingSpinner) loadingSpinner.classList.toggle('hidden',!v); }

function showToast(msg, type='info', dur=4000) {
    const icons={success:'fa-circle-check',error:'fa-circle-xmark',info:'fa-circle-info',warning:'fa-triangle-exclamation'};
    const t=document.createElement('div'); t.className=`toast toast-${type}`;
    t.innerHTML=`<i class="fas ${icons[type]||icons.info} toast-icon"></i><span class="toast-text">${escapeHtml(msg)}</span>`;
    toastContainer.appendChild(t);
    setTimeout(()=>{ t.classList.add('toast-out'); t.addEventListener('animationend',()=>t.remove(),{once:true}); },dur);
}

function showConfirm(msg, cb) {
    if(!confirmOverlay){cb();return;} confirmMessage.textContent=msg;
    confirmOverlay.classList.remove('hidden'); State.pendingAction=cb;
}
confirmOkBtn.addEventListener('click',()=>{ confirmOverlay.classList.add('hidden'); if(typeof State.pendingAction==='function') State.pendingAction(); State.pendingAction=null; });
confirmCancelBtn.addEventListener('click',()=>{ confirmOverlay.classList.add('hidden'); State.pendingAction=null; });

function nuiPost(action, data={}) {
    const n=(typeof window.GetParentResourceName==='function')?window.GetParentResourceName():'roninbase-report';
    return fetch(`https://${n}/${action}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).catch(()=>{});
}

function escapeHtml(s) {
    if(s==null) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

function fmtDuration(sec) {
    if(sec==null||sec<0) return '—';
    sec=Math.round(Number(sec)); const m=Math.floor(sec/60),s=sec%60;
    return m===0?`${s}s`:`${m}m ${s}s`;
}

function validateForm() { submitBtn.disabled=!(!!State.selectedCategory&&reportDesc.value.trim().length>=5); }

function buildCategories(cats) {
    const f=document.createDocumentFragment();
    cats.forEach(cat=>{
        const c=document.createElement('div'); c.className='cat-card'; c.dataset.id=cat.id; c.dataset.label=cat.label;
        if(cat.color) c.style.setProperty('--cat-color',cat.color);
        c.innerHTML=`<div class="cat-check"><i class="fas fa-check"></i></div><span class="cat-icon">${escapeHtml(cat.icon||'📋')}</span><span class="cat-label">${escapeHtml(cat.label)}</span>`;
        c.addEventListener('click',()=>selectCategory(cat.id,cat.label,c)); f.appendChild(c);
    });
    categoryGrid.innerHTML=''; categoryGrid.appendChild(f);
}
function selectCategory(id,label,el) {
    categoryGrid.querySelectorAll('.cat-card').forEach(c=>c.classList.remove('selected')); el.classList.add('selected');
    State.selectedCategory=id; State.selectedCategoryLabel=label; validateForm();
}

function buildPlayerList(players, filter='') {
    const lo=filter.toLowerCase();
    const filtered=filter?players.filter(p=>p.name.toLowerCase().includes(lo)||String(p.id).includes(filter)):players;
    if(!filtered.length){playerList.innerHTML=`<div class="player-empty">${escapeHtml(I18n.t('player_not_found'))}</div>`;return;}
    const f=document.createDocumentFragment();
    filtered.forEach(p=>{
        const inits=p.name.split(' ').map(w=>w[0]||'').join('').slice(0,2).toUpperCase();
        const item=document.createElement('div'); item.className='player-item';
        item.innerHTML=`<div class="player-avatar">${escapeHtml(inits)}</div><div class="player-info"><div class="player-name">${escapeHtml(p.name)}</div><div class="player-id">${escapeHtml(I18n.t('server_id'))}: ${p.id}</div></div>`;
        item.addEventListener('click',()=>selectPlayer(p)); f.appendChild(item);
    });
    playerList.innerHTML=''; playerList.appendChild(f);
}
function selectPlayer(p) {
    State.selectedPlayer=p; selectedPlayerName.textContent=`${p.name} (ID: ${p.id})`;
    selectedPlayerDiv.classList.remove('hidden'); playerSearch.value=''; playerList.innerHTML='';
}
clearPlayerBtn.addEventListener('click',()=>{ State.selectedPlayer=null; selectedPlayerDiv.classList.add('hidden'); playerSearch.value=''; buildPlayerList(State.allPlayers); });
playerSearch.addEventListener('input',debounce(()=>buildPlayerList(State.allPlayers,playerSearch.value),250));

reportDesc.addEventListener('input',()=>{ const l=reportDesc.value.length; charCount.textContent=l; charCount.style.color=l>450?'#ef4444':''; validateForm(); });

submitBtn.addEventListener('click',()=>{
    if(submitBtn.disabled||State.isLoading) return;
    console.log('[DEBUG] Submit button clicked - sending report to server');
    nuiPost('submitReport',{category:State.selectedCategory,categoryLabel:State.selectedCategoryLabel,description:reportDesc.value.trim(),targetId:State.selectedPlayer?State.selectedPlayer.id:null,targetName:State.selectedPlayer?State.selectedPlayer.name:null})
    .then(response => {
        console.log('[DEBUG] submitReport response received:', response);
    })
    .catch(err => {
        console.error('[DEBUG] submitReport error:', err);
    });
    reportOverlay.classList.add('hidden'); resetReportForm(); showToast(I18n.t('toast_report_submitted'),'success');
    // DEBUG: Call closeReport to ensure NUI focus is released
    console.log('[DEBUG] Calling closeReport after submit (immediate)');
    nuiPost('closeReport');
});

$id('close-report').addEventListener('click',closeReportModal);
$id('cancel-report').addEventListener('click',closeReportModal);
function closeReportModal(){reportOverlay.classList.add('hidden');nuiPost('closeReport');resetReportForm();}
function resetReportForm(){
    State.selectedCategory=null;State.selectedCategoryLabel=null;State.selectedPlayer=null;
    categoryGrid.querySelectorAll('.cat-card').forEach(c=>c.classList.remove('selected'));
    reportDesc.value='';charCount.textContent='0';playerSearch.value='';playerList.innerHTML='';
    selectedPlayerDiv.classList.add('hidden');submitBtn.disabled=true;
}

$id('close-admin').addEventListener('click',closeAdminPanel);
function closeAdminPanel(){adminOverlay.classList.add('hidden');nuiPost('closeAdmin');}

$id('close-history').addEventListener('click',closeHistoryPanel);
function closeHistoryPanel(){historyOverlay.classList.add('hidden');nuiPost('closeHistory');}

$id('refresh-reports').addEventListener('click',()=>{
    setLoading(true); nuiPost('refreshReports').finally(()=>setTimeout(()=>setLoading(false),800));
    showToast(I18n.t('toast_refreshing'),'info',2000);
});

document.querySelectorAll('.tab-btn').forEach(btn=>{
    btn.addEventListener('click',()=>{ document.querySelectorAll('.tab-btn').forEach(b=>b.classList.remove('active')); btn.classList.add('active'); State.activeFilter=btn.dataset.filter; State.adminPage=1; renderReports(State.allReports); });
});

if(adminPrev) adminPrev.addEventListener('click',()=>{if(State.adminPage<=1)return;State.adminPage--;renderReports(State.allReports);});
if(adminNext) adminNext.addEventListener('click',()=>{const filtered=State.activeFilter==='all'?State.allReports:State.allReports.filter(r=>r.status===State.activeFilter);if(State.adminPage>=Math.ceil(filtered.length/State.adminPageSize))return;State.adminPage++;renderReports(State.allReports);});

function renderReports(reports) {
    State.allReports=reports;
    let open=0,claimed=0;
    reports.forEach(r=>{ if(r.status==='open') open++; else if(r.status==='claimed') claimed++; });
    statTotal.textContent=reports.length; statOpen.textContent=open; statClaimed.textContent=claimed;
    const filtered=State.activeFilter==='all'?reports:reports.filter(r=>r.status===State.activeFilter);
    
    const totalPages = Math.max(1, Math.ceil(filtered.length / State.adminPageSize));
    if (State.adminPage > totalPages) State.adminPage = totalPages;
    if (adminPageInfo) adminPageInfo.textContent = I18n.t('page_info', {page: State.adminPage, total: totalPages, count: filtered.length});
    if (adminPrev) adminPrev.disabled = State.adminPage <= 1;
    if (adminNext) adminNext.disabled = State.adminPage >= totalPages;

    const startIdx = (State.adminPage - 1) * State.adminPageSize;
    const paginated = filtered.slice(startIdx, startIdx + State.adminPageSize);

    const em=new Map(); reportListEl.querySelectorAll('.report-card').forEach(c=>em.set(Number(c.dataset.id),c));
    const ns=new Set(paginated.map(r=>r.id)); em.forEach((c,id)=>{if(!ns.has(id))c.remove();});
    if(!paginated.length){emptyState.style.display='flex';} else {emptyState.style.display='none';}
    const f=document.createDocumentFragment(); let na=false;
    paginated.forEach(r=>{
        const ex=em.get(r.id);
        if(ex){const b=ex.querySelector('.report-status-badge');if(b&&b.dataset.status!==r.status)ex.replaceWith(buildReportCard(r));}
        else{f.appendChild(buildReportCard(r));na=true;}
    });
    if(na) reportListEl.appendChild(f);
}

function buildReportCard(r) {
    const sc={open:'badge-open',claimed:'badge-claimed'}[r.status]||'badge-open';
    const card=document.createElement('div'); card.className='report-card'; card.dataset.id=r.id;
    let catTxt = I18n.t('cat_'+r.category); if (catTxt === 'cat_'+r.category) catTxt = r.categoryLabel||r.category;
    card.innerHTML=`
        <div class="report-card-header"><span class="report-id">#${r.id}</span><span class="report-category-badge">${escapeHtml(catTxt)}</span><span class="report-status-badge ${sc}" data-status="${r.status}">${r.status.charAt(0).toUpperCase()+r.status.slice(1)}</span></div>
        <div class="report-card-body"><div class="report-meta"><span><i class="fas fa-user"></i> ${escapeHtml(r.reporterName)} (ID:${r.reporterId})</span>${r.targetName?`<span><i class="fas fa-crosshairs"></i> ${escapeHtml(r.targetName)}</span>`:''}<span><i class="fas fa-clock"></i> ${escapeHtml(r.timestamp)}</span>${r.claimedBy?`<span><i class="fas fa-shield-halved"></i> ${escapeHtml(r.claimedBy)}</span>`:''}</div><div class="report-description">${escapeHtml(r.description)}</div></div>
        <div class="report-card-actions">${r.status==='open'?`<button class="btn btn-sm btn-yellow claim-btn" data-id="${r.id}"><i class="fas fa-hand-paper"></i> ${escapeHtml(I18n.t('tab_claimed'))}</button>`:''}<button class="btn btn-sm btn-success resolve-btn" data-id="${r.id}"><i class="fas fa-check"></i> ${escapeHtml(I18n.t('th_resolved'))}</button><button class="btn btn-sm btn-outline teleport-btn" data-player="${r.reporterId}"><i class="fas fa-location-crosshairs"></i> Teleport</button>${r.targetId?`<button class="btn btn-sm btn-danger teleport-target-btn" data-player="${r.targetId}"><i class="fas fa-crosshairs"></i> Tp Reported</button>`:''}</div>`;
    const cb=card.querySelector('.claim-btn');
    if(cb) cb.addEventListener('click',()=>showConfirm(I18n.t('toast_claim_report',{id:r.id}),()=>{nuiPost('claimReport',{reportId:r.id});showToast(I18n.t('toast_claimed',{id:r.id}),'warning');}));
    const rb=card.querySelector('.resolve-btn');
    if(rb) rb.addEventListener('click',()=>showConfirm(I18n.t('toast_resolve_report',{id:r.id}),()=>{nuiPost('resolveReport',{reportId:r.id});showToast(I18n.t('toast_resolved',{id:r.id}),'success');}));
    const tb=card.querySelector('.teleport-btn');
    if(tb) tb.addEventListener('click',()=>{nuiPost('teleportToReporter',{playerId:parseInt(tb.dataset.player)});closeAdminPanel();showToast(I18n.t('toast_teleporting'),'info',2500);});
    const tt=card.querySelector('.teleport-target-btn');
    if(tt) tt.addEventListener('click',()=>{nuiPost('teleportToReporter',{playerId:parseInt(tt.dataset.player)});closeAdminPanel();showToast(I18n.t('toast_teleporting'),'info',2500);});
    return card;
}

// ── History ──
document.querySelectorAll('.history-tab').forEach(btn=>{
    btn.addEventListener('click',()=>{
        document.querySelectorAll('.history-tab').forEach(b=>b.classList.remove('active')); btn.classList.add('active');
        $id('history-tab-content').classList.toggle('hidden',btn.dataset.tab!=='history');
        $id('stats-tab-content').classList.toggle('hidden',btn.dataset.tab!=='stats');
    });
});

historySearchEl.addEventListener('input',debounce(()=>{State.historySearch=historySearchEl.value;State.historyPage=1;fetchHistory();},350));

// Category filter
historyFilterEl.addEventListener('change',()=>{State.historyFilter=historyFilterEl.value;State.historyPage=1;fetchHistory();});

// Status filter - filter by ticket status (all, open, claimed, resolved)
if (historyStatusFilterEl) {
    historyStatusFilterEl.addEventListener('change',()=>{State.historyStatus=historyStatusFilterEl.value;State.historyPage=1;fetchHistory();});
}

$id('history-prev').addEventListener('click',()=>{if(State.historyPage<=1)return;State.historyPage--;fetchHistory();});
$id('history-next').addEventListener('click',()=>{if(State.historyPage>=Math.ceil(State.historyTotal/State.historyPageSize))return;State.historyPage++;fetchHistory();});

function fetchHistory(){
    setLoading(true);
    // Include status filter in the request
    nuiPost('fetchHistory',{page:State.historyPage,filter:State.historyFilter,search:State.historySearch,status:State.historyStatus||'all'}).finally(()=>setLoading(false));
}

function renderHistory(data, page) {
    const reports=Array.isArray(data.reports)?data.reports:[];
    const adminStats=Array.isArray(data.adminStats)?data.adminStats:[];
    State.historyTotal=data.total||0; State.historyPage=page||1;
    const tp=Math.max(1,Math.ceil(State.historyTotal/State.historyPageSize));
    historyPageInfo.textContent=I18n.t('page_info',{page:State.historyPage,total:tp,count:State.historyTotal});
    $id('history-prev').disabled=State.historyPage<=1;
    $id('history-next').disabled=State.historyPage>=tp;
    historyList.querySelectorAll('.history-card').forEach(c=>c.remove());
    if(!reports.length){historyEmpty.style.display='flex';}
    else{ historyEmpty.style.display='none'; const f=document.createDocumentFragment(); reports.forEach(r=>f.appendChild(buildHistoryCard(r))); historyList.appendChild(f); }
    renderAdminStats(adminStats);
}

function buildHistoryCard(r) {
    const card=document.createElement('div'); card.className='history-card';
    let catTxt = I18n.t('cat_'+r.category); if (catTxt === 'cat_'+r.category) catTxt = r.category_label||r.category;
    
    // Status badge styling
    const statusClass = {open:'badge-open',claimed:'badge-claimed',resolved:'badge-resolved'}[r.status]||'badge-open';
    const statusLabel = {open:I18n.t('tab_open')||'Open',claimed:I18n.t('tab_claimed')||'Claimed',resolved:I18n.t('th_resolved')||'Resolved'}[r.status]||r.status;
    
    card.innerHTML=`
        <div class="history-card-top">
            <div class="history-card-badge-group">
                <span class="report-id">#${r.id}</span>
                <span class="report-category-badge">${escapeHtml(catTxt)}</span>
                <span class="report-status-badge ${statusClass}">${escapeHtml(statusLabel)}</span>
            </div>
            <div class="history-card-time-group">
                <span class="history-created"><i class="fas fa-plus-circle"></i> <span class="history-lbl">${escapeHtml(I18n.t('lbl_created'))}:</span> ${escapeHtml(r.created_at||'')}</span>
                ${r.resolved_at ? `<span class="history-date"><i class="fas fa-calendar-alt"></i> <span class="history-lbl">${escapeHtml(I18n.t('lbl_resolved'))}:</span> ${escapeHtml(r.resolved_at)}</span>` : ''}
                ${r.resolve_duration ? `<span class="history-duration"><i class="fas fa-stopwatch"></i> <span class="history-lbl">${escapeHtml(I18n.t('lbl_duration'))}:</span> ${fmtDuration(r.resolve_duration)}</span>` : ''}
            </div>
        </div>
        <div class="history-card-main">
            <div class="history-meta-grid">
                <div class="meta-item">
                    <span class="meta-label">${escapeHtml(I18n.t('lbl_reporter'))}</span>
                    <span class="meta-value"><i class="fas fa-user"></i> ${escapeHtml(r.reporter_name)} <span class="meta-id">(ID: ${r.reporter_id})</span></span>
                </div>
                ${r.target_name ? `
                <div class="meta-item">
                    <span class="meta-label">${escapeHtml(I18n.t('lbl_reported_player'))}</span>
                    <span class="meta-value target-value"><i class="fas fa-crosshairs"></i> ${escapeHtml(r.target_name)}</span>
                </div>
                ` : ''}
                ${r.claimed_by ? `
                <div class="meta-item">
                    <span class="meta-label">${escapeHtml(I18n.t('lbl_claimed_by')||'Claimed By')}</span>
                    <span class="meta-value admin-value"><i class="fas fa-hand-paper"></i> ${escapeHtml(r.claimed_by)}</span>
                </div>
                ` : ''}
                <div class="meta-item">
                    <span class="meta-label">${escapeHtml(I18n.t('lbl_resolved_by'))}</span>
                    <span class="meta-value admin-value"><i class="fas fa-shield-halved"></i> ${escapeHtml(r.resolved_by||'—')}</span>
                </div>
            </div>
            <div class="history-desc-box">
                <span class="desc-label">${escapeHtml(I18n.t('lbl_description'))}</span>
                <p class="report-description">${escapeHtml(r.description)}</p>
            </div>
        </div>`;
    return card;
}

function renderAdminStats(rows) {
    if(!rows||!rows.length){
        statsTbody.innerHTML=`<tr><td colspan="7" class="stats-empty">${escapeHtml(I18n.t('no_data'))}</td></tr>`;
        statsSummary.innerHTML='';
        return;
    }
    const tot=rows.reduce((s,r)=>s+Number(r.total_resolved||0),0);
    const avg=rows.reduce((s,r)=>s+Number(r.avg_duration_sec||0),0)/rows.length;
    statsSummary.innerHTML=`
        <div class="summary-card"><i class="fas fa-check-double"></i><span class="summary-val">${tot}</span><span class="summary-lbl">${escapeHtml(I18n.t('summary_total_resolved'))}</span></div>
        <div class="summary-card"><i class="fas fa-stopwatch"></i><span class="summary-val">${fmtDuration(avg)}</span><span class="summary-lbl">${escapeHtml(I18n.t('summary_avg_time'))}</span></div>
        <div class="summary-card"><i class="fas fa-trophy"></i><span class="summary-val">${escapeHtml(rows[0].admin_name)}</span><span class="summary-lbl">${escapeHtml(I18n.t('summary_top_resolver'))}</span></div>
        <div class="summary-card"><i class="fas fa-users-gear"></i><span class="summary-val">${rows.length}</span><span class="summary-lbl">${escapeHtml(I18n.t('summary_active_staff'))}</span></div>`;
    const ck=['cat_cheating','cat_rdm','cat_vdm','cat_toxicity','cat_bug','cat_other'];
    const clMap={cat_cheating:'cat_cheating',cat_rdm:'cat_rdm',cat_vdm:'cat_vdm',cat_toxicity:'cat_toxicity',cat_bug:'cat_bug',cat_other:'cat_other'};
    const f=document.createDocumentFragment();
    rows.forEach((row,i)=>{
        let tk=ck[0],tv=0; ck.forEach(k=>{if(Number(row[k]||0)>tv){tv=Number(row[k]||0);tk=k;}});
        const tr=document.createElement('tr'); if(i<3)tr.classList.add(`rank-${i+1}`);
        tr.innerHTML=`<td class="rank-cell">${['🥇','🥈','🥉'][i]||i+1}</td><td class="admin-name-cell">${escapeHtml(row.admin_name)}</td><td class="num-cell">${row.total_resolved}</td><td class="dur-cell">${fmtDuration(row.avg_duration_sec)}</td><td class="dur-cell fast">${fmtDuration(row.min_duration_sec)}</td><td class="dur-cell slow">${fmtDuration(row.max_duration_sec)}</td><td><span class="cat-pill">${escapeHtml(I18n.t(clMap[tk]||tk))} (${tv})</span></td>`;
        f.appendChild(tr);
    });
    statsTbody.innerHTML=''; statsTbody.appendChild(f);
}

// ── NUI Messages ──
window.addEventListener('message',function(e){
    const d=e.data; if(!d||!d.action) return;
    switch(d.action){
        case 'openReport': State.allPlayers=Array.isArray(d.players)?d.players:[]; buildCategories(Array.isArray(d.categories)?d.categories:[]); buildPlayerList(State.allPlayers); resetReportForm(); reportOverlay.classList.remove('hidden'); break;
        case 'openAdmin': renderReports(Array.isArray(d.reports)?d.reports:[]); adminOverlay.classList.remove('hidden'); break;
        case 'updateReports': if(Array.isArray(d.reports))renderReports(d.reports); break;
        case 'newReportAlert': {
            const r=d.report; if(!r) break;
            showToast(I18n.t('toast_new_report',{id:r.id,category:escapeHtml(r.categoryLabel||r.category),reporter:escapeHtml(r.reporterName)}),'error',6000);
            const b=$id('refresh-reports');
            if(b){b.classList.add('btn-alert-pulse');setTimeout(()=>b.classList.remove('btn-alert-pulse'),3000);}
            break;
        }
        case 'openHistory':
            State.historyPage=1;State.historySearch='';State.historyFilter='all';State.historyStatus='all';
            historySearchEl.value='';historyFilterEl.value='all';
            if(historyStatusFilterEl) historyStatusFilterEl.value='all';
            document.querySelectorAll('.history-tab').forEach(b=>b.classList.remove('active'));
            document.querySelector('.history-tab[data-tab="history"]').classList.add('active');
            $id('history-tab-content').classList.remove('hidden');
            $id('stats-tab-content').classList.add('hidden');
            historyOverlay.classList.remove('hidden'); break;
        case 'loadHistory': renderHistory(d.data||{},d.page||1); break;
        case 'closeAll': reportOverlay.classList.add('hidden');adminOverlay.classList.add('hidden');historyOverlay.classList.add('hidden');resetReportForm(); break;
        case 'setLang':
            if(d.lang==='tr'||d.lang==='en') I18n.setLocale(d.lang);
            break;
    }
});

// ── Keyboard ──
document.addEventListener('keydown',function(e){
    if(e.key==='Escape'){
        if(confirmOverlay&&!confirmOverlay.classList.contains('hidden')){confirmOverlay.classList.add('hidden');State.pendingAction=null;return;}
        if(!reportOverlay.classList.contains('hidden')){closeReportModal();nuiPost('escPressed');return;}
        if(!adminOverlay.classList.contains('hidden')){closeAdminPanel();nuiPost('escPressed');return;}
        if(!historyOverlay.classList.contains('hidden')){closeHistoryPanel();nuiPost('escPressed');return;}
    }
    if(e.key==='r'&&(e.ctrlKey||e.metaKey)&&!adminOverlay.classList.contains('hidden')){
        e.preventDefault(); nuiPost('refreshReports'); showToast(I18n.t('toast_refreshing'),'info',1500);
    }
});

// ── Boot ──
I18n.init();
