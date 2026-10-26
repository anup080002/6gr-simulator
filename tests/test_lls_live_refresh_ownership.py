"""Execute production live-refresh JS with declared, mocked HTTP responses.

These are browser ownership/parser checks, not simulator or PHY evidence.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_web_dashboard as dashboard  # noqa: E402

SOURCE = (ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
NAV_JS = SOURCE[SOURCE.index("  function queryRunId()"):
                SOURCE.index("  function selectedRunId()")]
REFRESH_JS = SOURCE[SOURCE.index("  function livePayloadRunId("):
                    SOURCE.index("  async function fetchContractSectionEvidence(")]
LOG_JS = SOURCE[SOURCE.index("  function realtimeLogPanel() {"):
                SOURCE.index("  function realtime() {", SOURCE.index("  function realtimeLogPanel() {"))]

HARNESS = r"""
const assert = require('node:assert/strict');
let selected = '101';
const state = {page:'realtime', live:null, liveFullPayload:null,
  liveVersion:'', liveArtifactVersion:'', filter:'',
  liveComponentFilter:'all', liveLogLevel:'all'};
let renders = 0;
const requests = [];
const selectedRunId = () => selected;
const interactionLocked = () => false;
const pageUsesLive = page => page === 'realtime';
const render = () => { renders += 1; };
const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;');
const unavailable = value => `<p>${esc(value)}</p>`;
const fetch = url => new Promise((resolve, reject) => requests.push({url, resolve, reject}));
const flush = () => new Promise(resolve => setImmediate(resolve));
function answer(request, body, ok = true) {
  request.resolve({ok, json:async () => body});
}
function payload(run, version, slot, extra = {}) {
  return {run:{run_id:run}, artifact_version:version,
    payload_version:`${run}|${version}|${slot}`, lite:true,
    runtime_context:{stage:{CurrentSlot:slot}},
    logs_recent:[{message_text:`slot ${slot}`, component:'system'}], ...extra};
}
"""


def execute_js(body: str, *, renderer: bool = False) -> None:
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    script = HARNESS + NAV_JS + REFRESH_JS + (LOG_JS if renderer else "")
    script += "\n(async () => {\n" + body + "\n})().catch(error => { console.error(error); process.exitCode = 1; });"
    result = subprocess.run([node, "-e", script], capture_output=True,
                            text=True, timeout=15)
    assert result.returncode == 0, result.stdout + result.stderr


def test_explicit_historical_selection_follows_result_navigation_only() -> None:
    execute_js(r"""
globalThis.location = new URL('http://127.0.0.1:62906/realtime?run_id=9769067634');
globalThis.window = {location};
for (const page of ['realtime','phy_grid','plots','tables','reports','analytics','artifacts','qualification']) {
  const target = new URL(runScopedHref(`/${page}?view=details#evidence`, page), location);
  assert.equal(target.searchParams.get('run_id'), '9769067634');
  assert.equal(target.searchParams.get('view'), 'details');
  assert.equal(target.hash, '#evidence');
}
assert.equal(runScopedHref('/plots?run_id=202', 'plots'), '/plots?run_id=202');
assert.equal(runScopedHref('/run-control', 'run_control'), '/run-control');
assert.equal(runScopedHref('/runs', 'runs'), '/runs');
assert.equal(runScopedHref('https://example.org/plots', 'plots'), 'https://example.org/plots');
globalThis.location = new URL('http://127.0.0.1:62906/realtime');
window.location = location;
assert.equal(runScopedHref('/realtime', 'realtime'), '/realtime');
assert.equal(runScopedHref('/plots', 'plots'), '/plots');
""")
    assert "const nextHref = runScopedHref(p.getAttribute('href'), nextPage);" in SOURCE


def test_lite_merge_preserves_same_run_previews_but_never_another_run() -> None:
    execute_js(r"""
const full = payload('101','v1',1,{lite:false,
  tables_all:[{logical_path:'original.csv'}],
  runtime_context:{stage:{CurrentSlot:1}, data_trial_previews:{dl:[{CRCPass:false}]}},
  realtime_dashboard:{components:[{status:'runtime_observations_unqualified'}]}});
const current = payload('101','v1',2,{logs_recent:[]});
const before = JSON.stringify(full);
const merged = mergeLivePayload(full,current);
assert.equal(merged.runtime_context.stage.CurrentSlot,2);
assert.equal(merged.runtime_context.data_trial_previews.dl[0].CRCPass,false);
assert.equal(merged.realtime_dashboard.components[0].status,'runtime_observations_unqualified');
assert.deepEqual(merged.logs_recent,[]);
assert.equal(JSON.stringify(full),before);
const child = payload('202','v1',1);
assert.equal(mergeLivePayload(full,child),child);
assert.equal(mergeLivePayload(full,child).tables_all,undefined);
""")


@pytest.mark.parametrize("failure", ["http", "network"])
def test_failed_full_request_retries_without_artifact_change(failure: str) -> None:
    execute_js(r"""
const first = fetchCanonicalLivePayload('101');
answer(requests[0],payload('101','v1',1));
publishCanonicalLivePayload(await first);
assert.equal(requests.length,2);
assert.equal(state.liveArtifactVersion,'v1');
""" + ("answer(requests[1],null,false);" if failure == "http"
         else "requests[1].reject(new Error('declared connection failure'));" ) + r"""
await flush();
assert.equal(state.liveRefreshOwner.fullArtifactVersion,null);
const retry = fetchCanonicalLivePayload('101');
answer(requests[2],payload('101','v1',2));
publishCanonicalLivePayload(await retry);
assert.equal(requests.length,4,'Full request must retry despite published lite v1');
answer(requests[3],payload('101','v1',2,{lite:false,tables_all:[{id:'original-heavy'}]}));
await flush();
assert.equal(state.liveRefreshOwner.fullArtifactVersion,'v1');
assert.equal(state.live.tables_all[0].id,'original-heavy');
const next = fetchCanonicalLivePayload('101');
answer(requests[4],payload('101','v1',3));
publishCanonicalLivePayload(await next);
assert.equal(requests.length,5,'A successful full v1 must not reload on log-only updates');
assert.equal(state.live.runtime_context.stage.CurrentSlot,3);
assert.equal(state.live.tables_all[0].id,'original-heavy');
""")


def test_reversed_lite_responses_cannot_regress_stage_or_launch_old_full() -> None:
    execute_js(r"""
const older = fetchCanonicalLivePayload('101');
const newer = fetchCanonicalLivePayload('101');
answer(requests[1],payload('101','v2',2));
publishCanonicalLivePayload(await newer);
answer(requests[0],payload('101','v1',1));
assert.equal(await older,null);
assert.equal(requests.length,3);
assert.equal(state.live.runtime_context.stage.CurrentSlot,2);
assert.equal(state.liveRefreshOwner.artifactVersion,'v2');
""")


def test_pending_full_from_parent_cannot_replace_selected_child() -> None:
    execute_js(r"""
const parent = fetchCanonicalLivePayload('101');
answer(requests[0],payload('101','v1',1));
const oldParent = await parent;
publishCanonicalLivePayload(oldParent);
selected = '202';
const child = fetchCanonicalLivePayload('202');
answer(requests[2],payload('202','v1',3));
publishCanonicalLivePayload(await child);
answer(requests[3],payload('202','v1',3,{lite:false,tables_all:[{id:'child'}]}));
await flush();
const before = state.live;
answer(requests[1],payload('101','v1',1,{lite:false,tables_all:[{id:'parent'}]}));
await flush();
assert.equal(state.live,before);
assert.equal(state.live.tables_all[0].id,'child');
assert.equal(publishCanonicalLivePayload(oldParent),false);
""")


def test_old_run_generation_cannot_win_after_switching_back() -> None:
    execute_js(r"""
const old = fetchCanonicalLivePayload('101');
answer(requests[0],payload('101','v1',1));
await old;
selected = '202';
const child = fetchCanonicalLivePayload('202');
answer(requests[2],payload('202','v1',1));
await child;
selected = '101';
const current = fetchCanonicalLivePayload('101');
answer(requests[4],payload('101','v1',4));
publishCanonicalLivePayload(await current);
answer(requests[1],payload('101','v1',1,{lite:false,tables_all:[{id:'old-parent'}]}));
await flush();
assert.equal(state.live.runtime_context.stage.CurrentSlot,4);
assert.equal(state.live.tables_all,undefined);
assert.equal(state.liveRefreshOwner.fullArtifactVersion,null);
answer(requests[5],payload('101','v1',4,{lite:false,tables_all:[{id:'current-parent'}]}));
await flush();
assert.equal(state.live.tables_all[0].id,'current-parent');
""")


def test_older_full_version_cannot_replace_newer_heavy_evidence() -> None:
    execute_js(r"""
const older = fetchCanonicalLivePayload('101');
answer(requests[0],payload('101','v1',1));
await older;
const newer = fetchCanonicalLivePayload('101');
answer(requests[2],payload('101','v2',2));
publishCanonicalLivePayload(await newer);
answer(requests[3],payload('101','v2',2,{lite:false,tables_all:[{id:'v2'}]}));
await flush();
answer(requests[1],payload('101','v1',1,{lite:false,tables_all:[{id:'v1'}]}));
await flush();
assert.equal(state.live.tables_all[0].id,'v2');
assert.equal(state.liveRefreshOwner.fullArtifactVersion,'v2');
""")


def test_full_response_preserves_intervening_lite_clock_and_logs() -> None:
    execute_js(r"""
const first = fetchCanonicalLivePayload('101');
answer(requests[0],payload('101','v1',1));
const firstSnapshot = await first;
publishCanonicalLivePayload(firstSnapshot);
const second = fetchCanonicalLivePayload('101');
answer(requests[2],payload('101','v1',2));
publishCanonicalLivePayload(await second);
assert.equal(requests.length,3,'Same version must share the pending full request');
const beforeRender = renders;
answer(requests[1],payload('101','v1',1,{lite:false,tables_all:[{id:'heavy'}],
  runtime_context:{stage:{CurrentSlot:1},data_trial_previews:{ul:[{CRCPass:false}]}}}));
await flush();
assert.equal(state.live.runtime_context.stage.CurrentSlot,2);
assert.equal(state.live.logs_recent[0].message_text,'slot 2');
assert.equal(state.live.tables_all[0].id,'heavy');
assert.equal(state.live.runtime_context.data_trial_previews.ul[0].CRCPass,false);
assert.equal(renders,beforeRender+1,'Heavy evidence renders even when lite payload_version is unchanged');
assert.equal(publishCanonicalLivePayload(firstSnapshot),false);
""")


@pytest.mark.parametrize("wrong", ["run", "version"])
def test_mismatched_full_identity_is_rejected_and_retryable(wrong: str) -> None:
    run, version = ("202", "v1") if wrong == "run" else ("101", "v0")
    execute_js(r"""
const first = fetchCanonicalLivePayload('101');
answer(requests[0],payload('101','v1',1));
publishCanonicalLivePayload(await first);
""" + f"answer(requests[1],payload({json.dumps(run)},{json.dumps(version)},1,{{lite:false}}));" + r"""
await flush();
assert.equal(state.liveRefreshOwner.fullArtifactVersion,null);
const retry = fetchCanonicalLivePayload('101');
answer(requests[2],payload('101','v1',2));
await retry;
assert.equal(requests.length,4);
""")


def test_wrong_lite_run_and_changed_selection_are_not_published() -> None:
    execute_js(r"""
const wrong = fetchCanonicalLivePayload('101');
answer(requests[0],payload('202','v1',1));
assert.equal(await wrong,null);
assert.equal(requests.length,1);
const changed = fetchCanonicalLivePayload('101');
selected = '202';
answer(requests[1],payload('101','v1',1));
assert.equal(await changed,null);
assert.equal(state.live,null);
assert.equal(requests.length,2);
""")


def test_log_renderer_prefers_current_snapshot_including_empty() -> None:
    execute_js(r"""
state.live = {logs_recent:[{message_text:'current PDCCH original message',component:'pdcch'}],
  realtime_dashboard:{logs:[{message_text:'stale full message',component:'system'}]}};
let html = realtimeLogPanel();
assert.ok(html.includes('current PDCCH original message'));
assert.ok(html.includes('pdcch'));
assert.ok(!html.includes('stale full message'));
state.live.logs_recent = [];
html = realtimeLogPanel();
assert.ok(html.includes('No runtime log rows were persisted'));
assert.ok(!html.includes('stale full message'));
delete state.live.logs_recent;
assert.ok(realtimeLogPanel().includes('stale full message'));
""", renderer=True)


def test_lite_server_annotates_fresh_logs_without_changing_original_rows(tmp_path, monkeypatch) -> None:
    run = {"run_id": 101, "run_folder": str(tmp_path), "status_text": "running",
           "updated_utc": "2026-10-25T00:00:00Z"}
    logs = [{"message_text": "PDCCH DCI decoded for UE 2", "level_str": "INFO"}]
    original = copy.deepcopy(logs)
    monkeypatch.setattr(dashboard, "fetch_run", lambda _: run)
    monkeypatch.setattr(dashboard.sls_dashboard, "is_sls_run", lambda _: False)
    monkeypatch.setattr(dashboard, "sync_runtime_log_for_run", lambda _: 0)
    monkeypatch.setattr(dashboard, "fetch_artifacts", lambda _: [])
    monkeypatch.setattr(dashboard, "is_filesystem_virtual_run_id", lambda _: True)
    monkeypatch.setattr(dashboard, "select_primary_result_artifacts", lambda rows: (rows, {}))
    monkeypatch.setattr(dashboard, "artifact_content_version", lambda *args: "v1")
    monkeypatch.setattr(dashboard, "register_artifact_content_version", lambda *args: None)
    monkeypatch.setattr(dashboard, "observe_sweep", lambda _: {})
    monkeypatch.setattr(dashboard, "CACHED_PAYLOAD_VERSION", {})
    monkeypatch.setattr(dashboard, "LIVE_PAYLOAD_CACHE", {})
    monkeypatch.setattr(dashboard, "fetch_logs", lambda *args, **kwargs: logs)
    monkeypatch.setattr(dashboard, "count_logs", lambda _: len(logs))
    monkeypatch.setattr(dashboard, "parse_status_json", lambda _: {})
    monkeypatch.setattr(dashboard, "parse_config_json", lambda _: {})
    monkeypatch.setattr(dashboard, "compact_run_row", lambda row, _: dict(row))
    result = dashboard.build_lite_live_payload(101)
    assert logs == original
    assert result["logs_recent"] == [dict(original[0], component="pdcch")]
    assert "realtime_dashboard" not in result


def test_poll_and_hydration_use_checked_publication() -> None:
    hydration = SOURCE.split("  function hydrateCurrentPage() {", 1)[1].split(
        "  hydrateCurrentPage();", 1)[0]
    polling = SOURCE.split("  hydrateCurrentPage();", 1)[1].split(
        "  setInterval(() => {\n    if (document.visibilityState === 'visible'", 1)[0]
    assert "publishCanonicalLivePayload(live, true)" in hydration
    assert "publishCanonicalLivePayload(payload)" in polling
    assert "state.live =" not in hydration + polling


def test_live_workspace_event_count_uses_current_log_snapshot() -> None:
    workspace = SOURCE.split("  function liveWorkspace() {", 1)[1].split(
        "  function sweepProgressPanel", 1)[0]
    assert "const allLogs = (Array.isArray(live.logs_recent) ? live.logs_recent" in workspace
