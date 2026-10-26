/* Insert inside the dashboard's DOMContentLoaded closure, before hydration.
 * This read-only display overlay does not alter any simulator artifact.
 */
function normalizedLiveRunFolder(value) {
  const parts = String(value || '').trim().replace(/\\/g, '/').replace(/^\/\/\?\//, '').split('/');
  const normalized = [];
  for (const part of parts) {
    if (!part || part === '.') continue;
    if (part === '..') { if (normalized.length) normalized.pop(); continue; }
    normalized.push(part.toLowerCase());
  }
  return normalized.join('/');
}

function isOwnSweepChild(parent, child) {
  const parentFolder = normalizedLiveRunFolder((parent || {}).run_folder);
  const childFolder = normalizedLiveRunFolder((child || {}).run_folder);
  return Boolean(parentFolder && childFolder.startsWith(parentFolder + '/sweeps/')
    && childFolder.length > parentFolder.length + '/sweeps/'.length
    && String(parent.run_id) !== String(child.run_id));
}

function isGenericSweepParent(run) {
  return [run?.profile_name, run?.backend].some(value => String(value || '').toLowerCase() === 'generic_sweep');
}

function interactionLocked() {
  if (Date.now() < Number(state.uiInteractionUntil || 0)) return true;
  const active = typeof document === 'undefined' ? null : document.activeElement;
  const tag = String(active?.tagName || '').toLowerCase();
  return ['input', 'select', 'textarea'].includes(tag) || active?.isContentEditable === true;
}

function compareLiveClock(left, right) {
  const a = left?.runtime_context?.stage || {};
  const b = right?.runtime_context?.stage || {};
  const number = value => value !== null && value !== undefined && value !== ''
    && typeof value !== 'boolean' && Number.isFinite(Number(value)) ? Number(value) : null;
  const aTotal = number(a.TotalSlots), bTotal = number(b.TotalSlots);
  if (aTotal !== null && bTotal !== null && aTotal !== bTotal) return null;
  for (const key of ['CompletedSlots', 'CurrentSlot']) {
    const av = number(a[key]), bv = number(b[key]);
    if (av !== null && bv !== null && av !== bv) return av < bv ? -1 : 1;
  }
  return 0;
}

function currentPreferredRunId(runRows, pageId) {
  const page = String(pageId || state.page || '');
  const ordered = sortedRuns((runRows || state.runs || []).filter(matchesResultMode), page === 'realtime');
  const candidates = page === 'realtime' ? ordered.filter(parent => !(
    isActiveRun(parent) && isGenericSweepParent(parent)
    && ordered.some(child => isActiveRun(child) && isOwnSweepChild(parent, child))
  )) : ordered;
  return String((candidates[0] || {}).run_id || '');
}

function mergeLivePayload(previous, incoming) {
  if (!previous) return incoming;
  if (!incoming) return previous;
  if (livePayloadRunId(previous) !== livePayloadRunId(incoming)) return incoming;
  // A completed full refresh is authoritative, including genuinely empty
  // arrays and null measurements. Only the intentionally partial lite
  // response inherits fields it did not supply.
  if (incoming.lite !== true) return incoming;
  const previousClockIsNewer = compareLiveClock(previous, incoming) === 1;
  const merged = {...previous, ...incoming};
  merged.run = {...(previous.run || {}), ...(incoming.run || {})};
  const stickyKeys = ['tables_all', 'tables_recent', 'tables_summary', 'images_all',
    'images_recent', 'output_coverage', 'feature_policy', 'contract_surface',
    'output_contract', 'timing', 'map', 'metric_explorer', 'debug',
    'mode_validation', 'realtime_dashboard'];
  stickyKeys.forEach(key => { if (incoming[key] === undefined) merged[key] = previous[key]; });
  merged.summary = {...(previous.summary || {}), ...(incoming.summary || {})};
  const before = previous.runtime_context || {};
  const after = incoming.runtime_context || {};
  merged.runtime_context = {...before, ...after,
    stage: previousClockIsNewer ? before.stage : {...(before.stage || {}), ...(after.stage || {})},
    truth_modes: {...(before.truth_modes || {}), ...(after.truth_modes || {})}};
  if (previousClockIsNewer) {
    merged.run = {...(incoming.run || {}), ...(previous.run || {})};
    merged.summary = {...(incoming.summary || {}), ...(previous.summary || {})};
    merged.logs_recent = previous.logs_recent;
  }
  merged.charts = {...(previous.charts || {}), ...(incoming.charts || {})};
  const gallery = incoming.reference_plot_gallery;
  const placeholderGallery = gallery && Object.keys(gallery).length === 1
    && Array.isArray(gallery.items) && gallery.items.length === 0;
  if (gallery === undefined || placeholderGallery) merged.reference_plot_gallery = previous.reference_plot_gallery;
  const liteMetrics = incoming.metrics;
  if (previous.metrics && Array.isArray(liteMetrics) && liteMetrics.length === 3
      && liteMetrics.every(item => ['Artifacts', 'Tables', 'Logs'].includes(item.label))) {
    merged.metrics = previous.metrics;
  }
  return merged;
}

function liveRefreshOwnerFor(runId) {
  if (!state.liveRefreshOwner || state.liveRefreshOwner.runId !== runId) {
    state.liveRefreshOwner = {runId, nextLite:0, acceptedLite:0, latestLite:null,
      artifactVersion:null, fullArtifactVersion:null, pendingLite:null, pendingFull:null,
      lastFullRunId:null, lastFullReceivedUtc:null, lastFullSourceUtc:null,
      fullError:'', liteError:''};
  }
  return state.liveRefreshOwner;
}

function ownsLiveRefresh(owner) {
  return state.liveRefreshOwner === owner && String(selectedRunId()) === owner.runId;
}

function liveRefreshNoticeHTML() {
  const selected = String(selectedRunId());
  const owner = state.liveRefreshOwner?.runId === selected ? state.liveRefreshOwner : null;
  const ownPayload = livePayloadRunId(state.live) === selected ? state.live : null;
  const parentScope = isGenericSweepParent(ownPayload?.run);
  const fullLoaded = Boolean(owner?.lastFullRunId);
  const pending = Boolean(owner?.pendingFull);
  const delayed = fullLoaded && owner.artifactVersion !== owner.fullArtifactVersion;
  let message = fullLoaded
    ? (pending ? 'Refreshing measurements; the last completed display remains available.'
      : delayed ? 'Measurements are retained from the last completed refresh. A newer source version will be loaded.'
        : 'Measurements loaded. The clock and event stream refresh separately.')
    : 'Loading measurement tables. Blank panels during this refresh do not mean that the simulator produced no data.';
  if (parentScope) message = pending
    ? 'Refreshing sweep progress. Open a waveform point run for its PHY measurements.'
    : 'Sweep progress loaded. Open a waveform point run for its PHY measurements.';
  const errors = [owner?.liteError, owner?.fullError, state.runsRefreshError].filter(Boolean);
  if (errors.length) message += ' A refresh failed; retained values remain visible and the next poll will retry.';
  if (state.liveRenderPending) message += ' New data is waiting to be displayed while you interact; it will appear after editing or scrolling stops.';
  const status = String(ownPayload?.run?.status_text || '').toLowerCase();
  const acceptance = /running|queued|launching|initializing|finalizing|retry/.test(status)
    ? 'Final acceptance is pending. Live slots, trial rows and CRC observations do not establish checkpoint60 or final-report success.'
    : 'Final acceptance must be read from the original checkpoint and final reports; missing acceptance fields remain unavailable.';
  const receipt = fullLoaded
    ? `Last completed ${parentScope ? 'parent detail' : 'measurement'} refresh: run ${owner.lastFullRunId}; source record timestamp ${owner.lastFullSourceUtc || 'unavailable'}; browser receipt ${owner.lastFullReceivedUtc}.`
    : `Selected run ${selected || 'unavailable'}; no completed ${parentScope ? 'parent detail' : 'measurement'} refresh has been received yet.`;
  return `<div class="toolbar" style="justify-content:space-between"><h3 style="margin:0">Live display status</h3><button type="button" id="liveRefreshNow"${owner?.pendingLite || pending ? ' disabled' : ''}>${owner?.pendingLite || pending ? 'Refresh in progress' : 'Refresh now'}</button></div><p>${esc(message)}</p><p class="small">${esc(receipt)}</p>`
    + (owner?.fullArtifactVersion ? `<details><summary>${parentScope ? 'Parent detail' : 'Measurement'} source version</summary><code style="overflow-wrap:anywhere">${esc(owner.fullArtifactVersion)}</code></details>` : '')
    + (errors.length ? `<p class="small">${esc(errors.join(' · '))}</p>` : '')
    + `<p class="small">${esc(acceptance)}</p>`;
}

function updateLiveRefreshNotice() {
  if (state.page !== 'realtime' || typeof document === 'undefined') return;
  const panel = document.getElementById('liveRefreshStatus');
  if (panel) panel.innerHTML = liveRefreshNoticeHTML();
}

function queueLiveRender() {
  if (state.liveRenderTimer) return;
  state.liveRenderTimer = window.setTimeout(() => {
    state.liveRenderTimer = null;
    flushLiveRenderPending();
  }, 500);
}

function flushLiveRenderPending() {
  if (!state.liveRenderPending) return false;
  if (livePayloadRunId(state.live) !== String(selectedRunId()) || !pageUsesLive(state.page)) {
    state.liveRenderPending = false;
    return false;
  }
  if (document.visibilityState === 'hidden' || interactionLocked()) {
    queueLiveRender();
    return false;
  }
  state.liveRenderPending = false;
  render({preserveScroll:true});
  updateLiveRefreshNotice();
  return true;
}

function publishCanonicalLivePayload(payload, forceRender = false) {
  if (!payload || payload !== state.liveFullPayload || livePayloadRunId(payload) !== String(selectedRunId())) return false;
  const version = String(payload.payload_version || '');
  const changed = version !== state.liveVersion;
  state.live = payload;
  state.liveVersion = version;
  state.liveArtifactVersion = String(payload.artifact_version || '');
  if (changed || forceRender) state.liveRenderPending = true;
  // This small status panel has no editable controls. It can update while a
  // focused selector or log filter safely holds the larger page redraw.
  updateLiveRefreshNotice();
  flushLiveRenderPending();
  return true;
}

async function readLiveJSON(url) {
  const response = await fetch(url, {cache:'no-store'});
  if (!response.ok) throw new Error(`HTTP ${response.status || 'error'}`);
  const value = await response.json();
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid live response');
  return value;
}

function startFullLiveRefresh(owner) {
  if (!ownsLiveRefresh(owner) || owner.pendingFull || owner.fullArtifactVersion === owner.artifactVersion) return;
  const request = {sequence:owner.acceptedLite, version:owner.artifactVersion};
  owner.pendingFull = request;
  owner.fullError = '';
  updateLiveRefreshNotice();
  request.promise = readLiveJSON(`/api/run/${encodeURIComponent(owner.runId)}/live`)
    .then(full => {
      if (!ownsLiveRefresh(owner) || owner.pendingFull !== request) return;
      if (livePayloadRunId(full) !== owner.runId || full.lite === true || !full.artifact_version) {
        throw new Error('Full measurement response has an unexpected run or payload identity');
      }
      // Artifact digests are opaque, not chronological sequence numbers. A
      // full response can legitimately be newer OR older than a concurrent
      // lite poll. Accept this sole owned request and identify its actual
      // source version; never relabel it as the latest lite version.
      owner.fullArtifactVersion = String(full.artifact_version);
      owner.lastFullRunId = owner.runId;
      owner.lastFullReceivedUtc = new Date().toISOString();
      owner.lastFullSourceUtc = full.run?.updated_utc || null;
      owner.fullError = '';
      const clockOrder = compareLiveClock(full, owner.latestLite);
      const fullTerminal = /^(completed|failed|aborted|stopped|cancelled|error|timeout)/i.test(String(full.run?.status_text || ''));
      const liteActive = /^(running|queued|launching|initializing|finalizing|retry)$/i.test(String(owner.latestLite?.run?.status_text || ''));
      const useLite = owner.acceptedLite > request.sequence && clockOrder !== 1 && !(fullTerminal && liteActive);
      state.liveFullPayload = useLite ? mergeLivePayload(full, owner.latestLite) : full;
      publishCanonicalLivePayload(state.liveFullPayload, true);
    })
    .catch(error => {
      if (ownsLiveRefresh(owner)) owner.fullError = `Measurement refresh: ${error.message || String(error)}`;
    })
    .finally(() => {
      if (owner.pendingFull === request) owner.pendingFull = null;
      if (ownsLiveRefresh(owner)) updateLiveRefreshNotice();
      // The next regular poll requests another full version if necessary.
      // Do not spin a retry loop or accumulate full requests during writes.
    });
}

function fetchCanonicalLivePayload(runId) {
  runId = String(runId);
  if (runId !== String(selectedRunId())) return Promise.resolve(null);
  const owner = liveRefreshOwnerFor(runId);
  if (owner.pendingLite) return owner.pendingLite.promise;
  const request = {sequence:++owner.nextLite};
  owner.pendingLite = request;
  request.promise = readLiveJSON(`/api/run/${encodeURIComponent(runId)}/live?lite=1`)
    .then(lite => {
      if (!ownsLiveRefresh(owner)) return null;
      if (livePayloadRunId(lite) !== runId) throw new Error('Live response belongs to another run');
      owner.acceptedLite = request.sequence;
      owner.latestLite = lite;
      owner.artifactVersion = String(lite.artifact_version || '');
      owner.liteError = '';
      const merged = mergeLivePayload(state.liveFullPayload, lite);
      state.liveFullPayload = merged;
      startFullLiveRefresh(owner);
      return merged;
    })
    .catch(error => {
      if (ownsLiveRefresh(owner)) {
        owner.liteError = `Clock and event refresh: ${error.message || String(error)}`;
        updateLiveRefreshNotice();
      }
      return null;
    })
    .finally(() => {
      if (owner.pendingLite === request) owner.pendingLite = null;
    });
  return request.promise;
}

function refreshRunsList(shouldRender) {
  if (state.runsRefreshPending) {
    state.runsRefreshPending.shouldRender ||= Boolean(shouldRender);
    return state.runsRefreshPending.promise;
  }
  const request = {shouldRender:Boolean(shouldRender)};
  state.runsRefreshPending = request;
  const limit = ['runs', 'previous_runs'].includes(state.page) ? 5000 : 200;
  request.promise = readLiveJSON(`/api/runs?limit=${limit}`)
    .then(payload => {
      if (!Array.isArray(payload.runs)) throw new Error('Run-list response has no runs array');
      const nextRuns = payload.runs;
      const digest = runsDigest(nextRuns);
      const changed = digest !== state.runsDigest;
      state.runs = nextRuns;
      state.runsDigest = digest;
      state.runsRefreshError = '';
      if (request.shouldRender && changed && !interactionLocked()) {
        if (['home', 'run_control'].includes(state.page)) render({preserveScroll:true});
        else if (state.page === 'compare') compare();
        else if (document.querySelector('[data-run-selector="true"]') || ['runs', 'plots', 'tables'].includes(state.page)) refreshRunsSurfaces();
      }
      updateLiveRefreshNotice();
      return state.runs;
    })
    .catch(error => {
      state.runsRefreshError = `Run list refresh: ${error.message || String(error)}`;
      updateLiveRefreshNotice();
      return state.runs || [];
    })
    .finally(() => { if (state.runsRefreshPending === request) state.runsRefreshPending = null; });
  return request.promise;
}

const originalSweepProgressPanel = sweepProgressPanel;
sweepProgressPanel = function(sweep) {
  const original = originalSweepProgressPanel(sweep);
  if (!sweep?.run_folder) return original;
  const parent = {run_id:livePayloadRunId(state.live), run_folder:sweep.run_folder};
  const children = (state.runs || []).filter(child => isOwnSweepChild(parent, child));
  if (!children.length) return original;
  const links = sortedRuns(children, true).map(child =>
    `<a class="button-link" href="/realtime?run_id=${encodeURIComponent(String(child.run_id))}">Run ${esc(child.run_id)} · ${esc(child.run_tag || '')} · ${esc(child.status_text || 'unknown')}</a>`).join('');
  return original + `<section class="panel"><h3>Waveform point runs</h3><p>The sweep parent tracks point progress. Open a point run for its own PHY measurements; child measurements are not merged into the parent.</p><div class="toolbar">${links}</div></section>`;
};

const originalLiveWorkspace = liveWorkspace;
liveWorkspace = function() {
  const live = state.live;
  const run = live?.run;
  if (run && isGenericSweepParent(run)) {
    title('Live sweep', 'Sweep progress and original waveform point runs.');
    const activeChild = sortedRuns((state.runs || []).filter(child => isOwnSweepChild(run, child)), true).find(isActiveRun);
    const activeLink = activeChild
      ? `<a class="button-link primary" href="/realtime?run_id=${encodeURIComponent(String(activeChild.run_id))}">Open active waveform point · Run ${esc(activeChild.run_id)}</a>` : '';
    const parentLogs = Array.isArray(live.logs_recent) ? live.logs_recent : (live.realtime_dashboard?.logs || []);
    main.innerHTML = `${liveTabs('realtime')}<section class="panel"><h3>Sweep run ${esc(run.run_id)}</h3>${pageRunSelector('realtimeRunSelect', 'Run', {runningOnly:false})}<p>Parent status: <strong>${esc(run.status_text || 'unavailable')}</strong></p><p>This parent coordinates the sweep. PHY observations belong to each waveform point run and remain separate from parent progress.</p>${activeLink}</section>${sweepProgressPanel(live.sweep_progress || {run_folder:run.run_folder})}${parentLogs.length ? realtimeLogPanel() : ''}`;
  } else {
    originalLiveWorkspace();
  }
  const stage = state.live?.runtime_context?.stage || {};
  if (!Object.prototype.hasOwnProperty.call(stage, 'DataReady')) {
    for (const row of main.querySelectorAll?.('.live-progress-summary tr') || []) {
      if (row.querySelector('th')?.textContent.trim() === 'Data ready') {
        const cell = row.querySelector('td');
        if (cell) cell.textContent = 'No combined DataReady flag is published. See the original DL/UL readiness fields in the stage audit.';
      }
    }
  }
  const selector = main.querySelector('[data-run-selector="true"]');
  const anchor = selector?.closest('section.panel');
  const notice = `<section class="panel" id="liveRefreshStatus" aria-live="polite">${liveRefreshNoticeHTML()}</section>`;
  if (anchor) anchor.insertAdjacentHTML('afterend', notice);
  else main.insertAdjacentHTML('afterbegin', notice);
};

document.addEventListener('focusout', () => { if (state.liveRenderPending) queueLiveRender(); }, true);
document.addEventListener('visibilitychange', () => { if (state.liveRenderPending) flushLiveRenderPending(); });
document.addEventListener('click', event => {
  if (event.target?.id !== 'liveRefreshNow') return;
  // Clicking this button is an explicit request to update the display. Keep
  // a short interaction pause, without stealing focus from any editor.
  state.uiInteractionUntil = Date.now() + 1000;
  const runId = selectedRunId();
  if (runId) fetchCanonicalLivePayload(runId).then(payload => publishCanonicalLivePayload(payload, true));
});
