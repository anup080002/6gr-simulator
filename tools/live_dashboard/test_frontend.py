"""Run the additive live frontend in Node with controlled HTTP and UI clocks.

No browser, simulation, receiver or physical measurement is executed here.
"""
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
NAV = SOURCE[SOURCE.index("  function runStatusToken(run)"):
             SOURCE.index("  function runSelectOptions(selected, options)")]
BASE = r"""
const assert = require('node:assert/strict');
let location = new URL('http://localhost/realtime?run_id=101');
let locked = false, renders = 0, surfaces = 0, childWorkspaceCalls = 0;
const timers = new Map(); let timerId = 0;
const setTimeout = fn => { timers.set(++timerId, fn); return timerId; };
const clearTimeout = id => timers.delete(id);
const setInterval = setTimeout, clearInterval = clearTimeout;
const listeners = {};
const document = {activeElement:null, visibilityState:'visible',
  addEventListener:(name,fn) => { listeners[name]=fn; },
  querySelector:() => null, querySelectorAll:() => [],getElementById:()=>null};
const window = {location, addEventListener:document.addEventListener,
  setTimeout, clearTimeout, setInterval, clearInterval};
const root = {backend:{latest_run_id:'101'}};
const state = {page:'realtime',runs:[],runsDigest:'',live:null,liveFullPayload:null,
  liveVersion:'',liveArtifactVersion:''};
const main = {innerHTML:'',insertAdjacentHTML:()=>{},querySelector:()=>null};
const matchesResultMode = () => true;
function interactionLocked() {return locked;}
const pageUsesLive = page => page === 'realtime';
const pageUsesRuns = () => true;
const render = () => {renders++;};
const refreshRunsSurfaces = () => {surfaces++;};
const compare = () => {surfaces++;};
const esc = value => String(value);
function liveWorkspace() {childWorkspaceCalls++;main.innerHTML='original child workspace';}
const title = () => {};
const liveTabs = () => '<nav>Live tabs</nav>';
const pageRunSelector = () => '<select data-run-selector="true"></select>';
const realtimeLogPanel = () => '<section>original selected run logs</section>';
function sweepProgressPanel() { return ''; }
function livePayloadRunId(value) { return String(value?.run?.run_id ?? ''); }
const requests = [];
function fetch(url) {
  return new Promise((resolve,reject) => requests.push({url,resolve,reject,settled:false}));
}
function take(kind,run='101') {
  const request=requests.find(r => !r.settled && (kind==='runs' ? r.url.startsWith('/api/runs?') :
    r.url.startsWith(`/api/run/${run}/live`) && r.url.includes('lite=1')===(kind==='lite')));
  assert.ok(request,`No pending ${kind} for ${run}: ${requests.map(r=>r.url).join(',')}`);
  request.settled=true; return request;
}
function answer(request,body,ok=true) { request.resolve({ok,status:ok?200:503,json:async()=>body}); }
const flush = async () => {await new Promise(r=>setImmediate(r)); await new Promise(r=>setImmediate(r));};
function payload(run,version,slot,extra={}) {return {run:{run_id:run},artifact_version:version,
  payload_version:`${run}|${version}|${slot}`,lite:true,
  runtime_context:{stage:{CurrentSlot:slot}},logs_recent:[{message_text:`slot ${slot}`}],...extra};}
function select(run) {location=new URL(`http://localhost/realtime?run_id=${run}`);window.location=location;}
async function poll(run,version,slot) {
  const promise=fetchCanonicalLivePayload(run);
  answer(take('lite',run),payload(run,version,slot));
  const value=await promise; publishCanonicalLivePayload(value); return value;
}
"""


def execute(body):
    node = shutil.which("node")
    if not node:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    overlay = (Path(__file__).parent / "frontend.js").read_text(encoding="utf-8")
    script = BASE + NAV + overlay + "\n(async()=>{\n" + body + (
        "\n})().catch(error=>{console.error(error);process.exitCode=1;});")
    result = subprocess.run([node, "-e", script], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stdout + result.stderr


def test_same_run_merge_keeps_full_metadata_and_rejects_cross_run():
    execute(r"""
const full=payload('101','v1',1,{lite:false,run:{run_id:'101',config_hash:'original'},
  summary:{observed_trials:10},metrics:[{label:'Measured EVM',value:null}],
  reference_plot_gallery:{items:[{path:'actual.png'}]},
  tables_all:[{path:'original.csv'}],runtime_context:{stage:{CurrentSlot:1},
  data_trial_previews:{dl:[{CRCPass:false}]}},realtime_dashboard:{components:[{status:'unqualified'}]}});
const before=JSON.stringify(full);
const merged=mergeLivePayload(full,payload('101','v2',2,{logs_recent:[],summary:{current_slot:2},
  reference_plot_gallery:{items:[]},metrics:[{label:'Artifacts'},{label:'Tables'},{label:'Logs'}]}));
assert.equal(merged.runtime_context.stage.CurrentSlot,2);
assert.equal(merged.runtime_context.data_trial_previews.dl[0].CRCPass,false);
assert.equal(merged.run.config_hash,'original');
assert.equal(merged.summary.observed_trials,10);assert.equal(merged.summary.current_slot,2);
assert.equal(merged.metrics[0].label,'Measured EVM');assert.equal(merged.metrics[0].value,null);
assert.equal(merged.reference_plot_gallery.items[0].path,'actual.png');
assert.equal(merged.tables_all[0].path,'original.csv');
assert.deepEqual(merged.logs_recent,[]);
assert.equal(JSON.stringify(full),before);
const other=mergeLivePayload(full,payload('202','v1',3));
assert.equal(other.tables_all,undefined);
assert.equal(other.run.config_hash,undefined);
const refreshed=mergeLivePayload(full,payload('101','v3',3,{lite:false,tables_all:[],
  runtime_context:{data_trial_previews:{dl:[]}},metrics:[{label:'Measured EVM',value:null}]}));
assert.deepEqual(refreshed.tables_all,[]);
assert.deepEqual(refreshed.runtime_context.data_trial_previews.dl,[]);
assert.equal(refreshed.metrics[0].value,null,'Unavailable measurement must not become zero');
""")


def test_churning_versions_accept_heavy_without_parallel_heavy_requests():
    execute(r"""
await poll('101','v1',1); const heavy=take('full');
for(let slot=2;slot<=6;slot++) await poll('101',`v${slot}`,slot);
assert.equal(requests.filter(r=>r.url.endsWith('/live')).length,1);
answer(heavy,payload('101','v4',4,{lite:false,tables_all:[{id:'measured-full'}],
  runtime_context:{stage:{CurrentSlot:4},data_trial_previews:{dl:[{CRCPass:false}]}}}));
await flush();
assert.equal(state.live.tables_all[0].id,'measured-full');
assert.equal(state.live.runtime_context.stage.CurrentSlot,6);
assert.equal(state.live.logs_recent[0].message_text,'slot 6');
assert.equal(state.liveRefreshOwner.fullArtifactVersion,'v4');
await poll('101','v7',7);
assert.equal(requests.filter(r=>r.url.endsWith('/live')).length,2);
""")


def test_lite_overlap_is_coalesced():
    execute(r"""
const a=fetchCanonicalLivePayload('101'), b=fetchCanonicalLivePayload('101');
assert.equal(requests.length,1);
answer(take('lite'),payload('101','v1',1));
const [one,two]=await Promise.all([a,b]);
assert.equal(one,two);
assert.equal(requests.filter(r=>r.url.endsWith('/live')).length,1);
""")


def test_newer_full_observation_clock_is_not_replaced_by_older_lite():
    execute(r"""
await poll('101','v1',1);const heavy=take('full');
await poll('101','v2',2);
answer(heavy,payload('101','v3',3,{lite:false,tables_all:[{id:'newest-heavy'}]}));await flush();
assert.equal(state.live.runtime_context.stage.CurrentSlot,3);
assert.equal(state.live.logs_recent[0].message_text,'slot 3');
assert.equal(state.live.tables_all[0].id,'newest-heavy');
assert.equal(state.liveRefreshOwner.fullArtifactVersion,'v3');
""")


def test_late_old_run_and_old_generation_full_cannot_contaminate():
    execute(r"""
await poll('101','v1',1);const old=take('full');
select('202');await poll('202','v1',2);const child=take('full','202');
answer(old,payload('101','v9',9,{lite:false,tables_all:[{id:'wrong-parent'}]}));await flush();
assert.equal(state.live.run.run_id,'202');assert.equal(state.live.tables_all,undefined);
select('101');await poll('101','v2',3);const current=take('full');
answer(child,payload('202','v1',2,{lite:false,tables_all:[{id:'wrong-child'}]}));await flush();
assert.equal(state.live.run.run_id,'101');assert.equal(state.live.tables_all,undefined);
answer(current,payload('101','v2',3,{lite:false,tables_all:[{id:'current'}]}));await flush();
assert.equal(state.live.tables_all[0].id,'current');
""")


def test_switch_back_rejects_same_run_id_from_an_old_owner_generation():
    execute(r"""
await poll('101','v1',1);const old=take('full');
select('202');await poll('202','v1',2);
select('101');await poll('101','v1',3);const current=take('full');
answer(old,payload('101','v1',1,{lite:false,tables_all:[{id:'old-generation'}]}));await flush();
assert.equal(state.live.runtime_context.stage.CurrentSlot,3);
assert.equal(state.live.tables_all,undefined);
answer(current,payload('101','v1',3,{lite:false,tables_all:[{id:'current-generation'}]}));await flush();
assert.equal(state.live.tables_all[0].id,'current-generation');
""")


@pytest.mark.parametrize("failure", ["http", "network", "wrong_run"])
def test_failed_or_wrong_identity_heavy_is_retryable(failure):
    failure_js = {
        "http": "answer(heavy,null,false);",
        "network": "heavy.reject(new Error('declared network failure'));",
        "wrong_run": "answer(heavy,payload('202','v1',1,{lite:false}));",
    }[failure]
    execute(r"""
await poll('101','v1',1);const heavy=take('full');
""" + failure_js + r"""
await flush();
assert.equal(state.liveRefreshOwner.fullArtifactVersion,null);
await poll('101','v1',2);
assert.equal(requests.filter(r=>r.url.endsWith('/live')).length,2);
answer(take('full'),payload('101','v1',2,{lite:false,tables_all:[{id:'retry'}]}));await flush();
assert.equal(state.live.tables_all[0].id,'retry');
""")


def test_deferred_render_drains_after_interaction_without_payload_change():
    execute(r"""
locked=true;state.uiInteractionUntil=Date.now()+60000;await poll('101','v1',1);
answer(take('full'),payload('101','v1',1,{lite:false,tables_all:[{id:'ready'}]}));await flush();
assert.equal(renders,0);assert.ok(state.liveRenderPending);
assert.equal(timers.size,1,'Deferred refresh must schedule exactly one drain timer');
locked=false;state.uiInteractionUntil=0;const [id,callback]=[...timers][0];timers.delete(id);callback();
assert.equal(renders,1);assert.ok(!state.liveRenderPending);
flushLiveRenderPending();assert.equal(renders,1);
""")


def test_button_focus_does_not_lock_forever_but_editing_and_cooldown_do():
    execute(r"""
state.uiInteractionUntil=0;
document.activeElement={tagName:'BUTTON',isContentEditable:false};
assert.equal(interactionLocked(),false);
document.activeElement={tagName:'A',isContentEditable:false};
assert.equal(interactionLocked(),false);
for(const tagName of ['INPUT','SELECT','TEXTAREA']) {
  document.activeElement={tagName,isContentEditable:false};
  assert.equal(interactionLocked(),true,`${tagName} editing must defer redraw`);
}
document.activeElement={tagName:'DIV',isContentEditable:true};
assert.equal(interactionLocked(),true);
document.activeElement={tagName:'BUTTON',isContentEditable:false};
state.uiInteractionUntil=Date.now()+60000;assert.equal(interactionLocked(),true);
state.uiInteractionUntil=0;assert.equal(interactionLocked(),false);
""")


@pytest.mark.parametrize("network", [False, True])
def test_failed_run_list_preserves_rows_digest_and_selection(network):
    execute(r"""
state.runs=[{run_id:'101',status_text:'running',updated_utc:'2026-10-26T10:00:00Z'}];
state.runsDigest=runsDigest(state.runs);const before=state.runs,digest=state.runsDigest;
const pending=refreshRunsList(true);const request=take('runs');
""" + ("request.reject(new Error('offline'));" if network else "answer(request,null,false);") + r"""
await pending;assert.equal(state.runs,before);assert.equal(state.runsDigest,digest);
assert.equal(selectedRunId(),'101');assert.ok(state.runsRefreshError);
""")


def test_default_parent_child_ranking_respects_independent_recency_and_explicit_selection():
    execute(r"""
location=new URL('http://localhost/realtime');window.location=location;
const parent={run_id:'100',status_text:'running',run_folder:'E:/results/parent',
  profile_name:'generic_sweep',updated_utc:'2026-10-26T12:00:00Z'};
const child={run_id:'101',status_text:'running',run_folder:'E:/results/parent/sweeps/a',
  updated_utc:'2026-10-26T10:00:00Z'};
state.runs=[parent,child];assert.equal(currentPreferredRunId(state.runs,'realtime'),'101');
const independent={run_id:'300',status_text:'running',run_folder:'E:/results/new',
  updated_utc:'2026-10-26T11:00:00Z'};
state.runs.push(independent);assert.equal(currentPreferredRunId(state.runs,'realtime'),'300');
select('100');assert.equal(selectedRunId(),'100');
select('999');assert.equal(selectedRunId(),'999');
location=new URL('http://localhost/realtime');window.location=location;
state.runs=[parent,{...child,run_folder:'E:/results/parent_other/sweeps/a'}];
assert.equal(currentPreferredRunId(state.runs,'realtime'),'100','Prefix lookalike is not this parent child');
state.runs=[parent,{...child,status_text:'completed'}];
assert.equal(currentPreferredRunId(state.runs,'realtime'),'100','Completed child cannot displace active parent');
state.runs=[{...parent,run_folder:'E:\\Results\\PARENT\\'},
  {...child,run_folder:'e:/results/parent/sweeps/a'}];
assert.equal(currentPreferredRunId(state.runs,'realtime'),'101','Windows path normalization retains real lineage');
""")


def test_explicit_sweep_parent_renders_only_own_overview_and_child_link():
    execute(r"""
select('951');
const parent={run_id:'951',profile_name:'generic_sweep',status_text:'running',run_folder:'E:/runs/parent'};
const child={run_id:'952',status_text:'running',run_folder:'E:/runs/parent/sweeps/point20'};
const unrelated={run_id:'999',status_text:'running',run_folder:'E:/runs/another/sweeps/point20'};
state.runs=[parent,child,unrelated];
state.live={run:parent,logs_recent:[],sweep_progress:{run_folder:parent.run_folder},
  runtime_context:{stage:{CompletedPoints:0}},tables_all:[]};
const owner=liveRefreshOwnerFor('951');
owner.lastFullRunId='951';owner.lastFullReceivedUtc='2026-10-26T10:00:00Z';
owner.fullArtifactVersion='parent-v1';owner.artifactVersion='parent-v1';
const before=JSON.stringify(state.live);
liveWorkspace();
assert.equal(childWorkspaceCalls,0,'Parent must not invoke waveform measurement workspace');
assert.ok(main.innerHTML.includes('Sweep run 951'));
assert.ok(main.innerHTML.includes('Parent status: <strong>running</strong>'));
assert.ok(main.innerHTML.includes('/realtime?run_id=952'));
assert.ok(!main.innerHTML.includes('/realtime?run_id=999'));
assert.equal(selectedRunId(),'951');assert.equal(JSON.stringify(state.live),before);
const notice=liveRefreshNoticeHTML();
assert.ok(!notice.includes('Measurements loaded'));
assert.ok(notice.includes('Sweep progress loaded'));
select('952');state.live={run:child,logs_recent:[]};liveWorkspace();
assert.equal(childWorkspaceCalls,1,'Ordinary child must delegate to original waveform workspace');
assert.equal(main.innerHTML,'original child workspace');
""")
