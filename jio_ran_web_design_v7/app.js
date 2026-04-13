(function(){
  const $ = (sel, el=document)=>el.querySelector(sel);
  const $$ = (sel, el=document)=>[...el.querySelectorAll(sel)];
  const data = window.RAN_DATA;

  function buildSidebar(active){
    const root = document.getElementById('sidebar');
    if(!root) return;
    root.innerHTML = `
      <div class="brand">
        <div class="brand-badge">J</div>
        <div>
          <h1>${data.app.title}</h1>
          <p>${data.app.subtitle}</p>
        </div>
      </div>
      <div class="mode-cluster">
        <a class="mode-pill active" href="index.html">LLS</a>
        <a class="mode-pill" href="#">SLS</a>
        <a class="mode-pill" href="#">E2E</a>
      </div>
      <div class="nav-section">
        <div class="nav-label">Workspace</div>
        <div class="nav-list">
          ${data.nav.map(n=>`<a class="nav-item ${active===n.id?'active':''}" href="${n.href}"><span class="nav-dot"></span><span>${n.label}</span></a>`).join('')}
        </div>
      </div>
      <div class="nav-section">
        <div class="nav-label">Profiles</div>
        <div class="summary-list">
          ${data.profiles.map(p=>`<div class="summary-item"><span class="key">${p.name}</span><span class="val">${p.runtime}</span></div>`).join('')}
        </div>
      </div>
    `;
  }

  function buildRightbar(){
    const root = document.getElementById('rightbar');
    if(!root) return;
    root.innerHTML = `
      <div class="status-tile"><h4>Scenario</h4><div class="big">${data.app.scenario}</div><div class="small-note">Canonical browser-owned LLS study</div></div>
      <div class="status-tile"><h4>Run profile</h4><div class="big">${data.app.runProfile}</div><div class="small-note">Modify presets from Scenario page</div></div>
      <div class="status-tile"><h4>Status</h4><div class="big">${data.app.status}</div><div class="small-note">DB: ${data.app.db}<br>Backend: ${data.app.matlab}</div></div>
      <div class="status-tile"><h4>Config hash</h4><div class="big" style="font-size:16px;font-family:var(--mono)">${data.app.configHash}</div><div class="small-note">Last save ${data.app.lastSaved}</div></div>
      <div class="panel" style="margin-top:14px"><div class="panel-header"><div><h3 class="panel-title">Quick actions</h3><p class="panel-subtitle">Always visible in the shell</p></div></div><div class="panel-body"><div class="action-row"><a class="btn primary" href="realtime.html">Run Scenario</a><a class="btn secondary" href="parameter_catalog.html">Validate</a><a class="btn secondary" href="sample_lls_config.json">Download Config JSON</a><a class="btn ghost" href="analytics.html">Open Analytics</a></div></div></div>
    `;
  }

  function buildTopbar(page){
    const root = document.getElementById('topbar');
    if(!root) return;
    const map = {
      home:['Simulation workstation','Select a mode, understand the same-flow architecture, then open the exact page you need.'],
      scenario:['Scenario','Define study identity, seeds, runtime budget, export policy, and reproducibility.'],
      geometry:['Geometry','Configure sites, sectors, UE placement, wrap-around, hotspots, and mobility.'],
      waveform:['Waveform','Set carrier, numerology, TDD, waveform, coding, and RF impairments with consistency warnings.'],
      traffic:['Traffic','Build service mix, QoS, load, packet models, and latency budgets.'],
      mac:['MAC / Scheduler','Configure scheduling, PRBs, HARQ, OLLA, fairness, and link adaptation.'],
      l1:['L1 / PHY Explorer','Drill into every PHY family: DL control, DL data, UL control, UL data, RS/MIMO, and Massive MIMO.'],
      antenna:['Antenna & Air Interface','Inspect BS/UE arrays, air-interface coupling, channel assumptions, beam truth, ToA/ToD.'],
      studio:['Block Studio','Edit requested/resolved/applied/measured values for any block in one engineering workspace.'],
      realtime:['Real-Time Data','Monitor live DB-backed grants, channel state, control state, artifacts, and truth contract health.'],
      analytics:['Analytics','Generate and inspect post-run reports, root cause dashboards, and compare-runs evidence.'],
      artifacts:['Artifact Explorer','Inspect canonical artifacts, mirrors, coverage, row counts, and provenance.'],
      catalog:['Parameter Catalog','See every parameter, owner, exposure level, and runtime source classification.'],
      compare:['Compare Runs','Pair compatible runs, inspect KPI deltas, overlays, config diffs, and artifact diffs.']
    };
    const [title, desc] = map[page] || ['Page',''];
    root.innerHTML = `
      <div class="topbar-row">
        <div class="topbar-title">
          <div class="kicker">Jio Platforms Limited RAN Simulator</div>
          <h2>${title}</h2>
          <p>${desc}</p>
        </div>
        <div class="action-row">
          <a class="btn secondary" href="scenario.html">Validate</a>
          <a class="btn primary" href="realtime.html">Run Scenario</a>
          <a class="btn secondary" href="sample_lls_config.json">Download Config JSON</a>
        </div>
      </div>
    `;
  }

  function makeKpis(target){
    target.innerHTML = data.realtimeKpis.slice(0,8).map(([l,v])=>`<div class="kpi-card"><div class="label">${l}</div><div class="value">${v}</div></div>`).join('');
  }

  function lineSpark(values, color='#1b63f0'){
    const max = Math.max(...values), min = Math.min(...values);
    const pts = values.map((v,i)=>{
      const x = i*(100/(values.length-1));
      const y = 100-((v-min)/(max-min||1))*80-10;
      return `${x},${y}`;
    }).join(' ');
    return `<svg viewBox="0 0 100 100" preserveAspectRatio="none"><polyline fill="none" stroke="${color}" stroke-width="2.6" points="${pts}"/><polyline fill="rgba(27,99,240,.10)" stroke="none" points="0,95 ${pts} 100,95"/></svg>`;
  }

  function barSpark(values, colors=['#1b63f0','#6e61ff','#11b2b8','#d88b10']){
    const max = Math.max(...values);
    return `<svg viewBox="0 0 100 100" preserveAspectRatio="none">${values.map((v,i)=>{
      const w = 100/values.length-4, x = i*(100/values.length)+2, h = (v/(max||1))*72, y = 90-h;
      return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="4" fill="${colors[i%colors.length]}" opacity="0.85"/>`;
    }).join('')}</svg>`;
  }

  function heatMap(){
    const cells=[];
    for(let r=0;r<10;r++) for(let c=0;c<18;c++){
      const v = Math.floor((Math.sin(r*.8+c*.3)+1)*4+1);
      const cols=['#edf4ff','#cfe2ff','#a6c8ff','#6d9eff','#2d6cf6'];
      cells.push(`<rect x="${c*5.4+1}" y="${r*9+3}" width="4.3" height="7" rx="1.3" fill="${cols[v-1]}"/>`)
    }
    return `<svg viewBox="0 0 100 100" preserveAspectRatio="none">${cells.join('')}</svg>`;
  }

  function renderHome(){
    makeKpis($('#homeKpis'));
    $('#modeCards').innerHTML = data.modeCards.map(m=>`<div class="mode-card"><div class="badge ${m.name==='LLS'?'green':'blue'}">${m.tag}</div><h4>${m.name}</h4><p>${m.desc}</p><ul>${m.bullets.map(b=>`<li>${b}</li>`).join('')}</ul><div class="mode-card-footer"><a class="btn ${m.name==='LLS'?'primary':'secondary'}" href="${m.route}">${m.name==='LLS'?'Open LLS Builder':'View Mode'}</a><span class="meta-pill">Same-flow UI</span></div></div>`).join('');
    $('#profiles').innerHTML = data.profiles.map(p=>`<div class="profile-card"><h4>${p.name}</h4><div class="badge blue">${p.runtime}</div><p>${p.notes}</p></div>`).join('');
    $('#routeGrid').innerHTML = data.nav.slice(1).map(n=>`<a class="route-item" href="${n.href}"><span>${n.label}</span><span class="meta-pill">Open</span></a>`).join('');
    $('#sameFlow').innerHTML = data.sameFlow.map(s=>`<a class="stage-card" href="${s.href}"><div class="stage-top"><div><h4>${s.title}</h4><p>${s.desc}</p></div><span class="badge ${s.status.includes('Deep')?'purple':s.status==='Operational'?'amber':'green'}">${s.status}</span></div><ul>${s.items.map(i=>`<li>${i}</li>`).join('')}</ul><div class="stage-meta"><span class="meta-pill">${s.params} params</span><span class="meta-pill">Click to open</span></div></a>`).join('');
  }

  function renderScenarioPage(id, heading){
    const sections = data.builderSections;
    const forms = sections.map(sec=>`<div class="form-group"><h4>${sec.title}</h4><div class="form-grid">${sec.fields.map(f=>`<div class="field"><label>${f}</label><input value="${mockValue(f)}"/></div>`).join('')}</div></div>`).join('');
    $('#scenarioForms').innerHTML = forms;
    $('#scenarioSummary').innerHTML = `
      <div class="panel"><div class="panel-header"><div><h3 class="panel-title">Live summary</h3><p class="panel-subtitle">Requested vs resolved scenario status</p></div><span class="badge green">Complete</span></div><div class="panel-body"><div class="summary-list">
      <div class="summary-item"><span class="key">Scenario</span><span class="val">${data.app.scenario}</span></div>
      <div class="summary-item"><span class="key">Mode</span><span class="val">LLS</span></div>
      <div class="summary-item"><span class="key">Profile</span><span class="val">${data.app.runProfile}</span></div>
      <div class="summary-item"><span class="key">Sites / sectors / UEs</span><span class="val">19 / 57 / 100</span></div>
      <div class="summary-item"><span class="key">Carrier / BW</span><span class="val">4 GHz / 100 MHz</span></div>
      <div class="summary-item"><span class="key">SCS / μ</span><span class="val">30 kHz / 1</span></div>
      <div class="summary-item"><span class="key">Scheduler</span><span class="val">PF + beam-aware</span></div>
      <div class="summary-item"><span class="key">Truth contract</span><span class="val">No proxy PHY</span></div>
      </div><div class="clean-note" style="margin-top:14px">This page is intentionally parameter-heavy. It is where requested values are edited; resolved, applied, measured, and derived values belong to the Block Studio, Real-Time Data, and Analytics pages.</div></div></div>`;
  }

  function mockValue(label){
    const map = {
      'Scenario ID':'LLS_4GHz_100MHz_19S3_100UE_UMa','Study mode':'baseline','Simulation mode':'full_phy','Random seed master':'73030','Num drops':'20','Warmup / measurement window':'200 / 1000 ms',
      'Num sites':'19','Sectors per site':'3','Inter-site distance':'600 m','Wrap-around':'enabled','UE count':'100','Hotspots':'10','Handover policy':'A3_like',
      'Carrier frequency':'4.0e9 Hz','Bandwidth':'100e6 Hz','Numerology':'μ=1','SCS':'30 kHz','TDD pattern':'DDDDU','Waveform DL/UL':'CP-OFDM / CP-OFDM','FFT size':'4096','Grid size':'273 RB',
      'Traffic mix':'40 eMBB / 20 FTP / 20 XR / 10 VoIP / 10 UL-heavy','QoS class':'mixed','DL/UL asymmetry':'80/20','Queue depth':'5 MB','Latency budget':'5–100 ms','Packet model':'class-based',
      'Scheduler type':'pf','Frequency-domain scheduling':'enabled','Beam-aware scheduling':'enabled','OLLA':'enabled','Target BLER':'0.1 / 0.1','HARQ processes':'16 DL / 16 UL',
      'Coding':'LDPC / Polar','Modulation set':'QPSK..256QAM','DMRS/PTRS':'enabled','CSI-RS':'enabled','SRS':'enabled','PDCCH':'enabled','PBCH':'enabled','PRACH':'enabled','PUCCH':'enabled',
      'Channel family':'tr38901_geometry','Pathloss':'38.901 UMa','Shadowing':'enabled','O2I':'enabled','Spatial consistency':'enabled','Interference mode':'full_per_link_channel_waveform_sum','Noise mode':'receiver_noise_figure_thermal_noise','Impairments':'nominal',
      'Run profile':'Baseline','Canonical artifacts':'enabled','Raw IQ capture':'off','Constellation save':'on','Energy trace':'on','Compare-runs support':'enabled'
    };
    return map[label] || 'value';
  }

  function renderGeometry(){
    $('#geomKpis').innerHTML = [['Sites','19'],['Cells','57'],['UEs','100'],['Indoor','20%'],['Hotspots','10'],['Wrap-around','2 rings']].map(([l,v])=>`<div class="kpi-card"><div class="label">${l}</div><div class="value">${v}</div></div>`).join('');
    $('#geomCanvas').innerHTML = `<div class="chart-grid"><div class="chart-card"><h4>Topology canvas</h4><div class="heatmap">${heatMap()}</div><div class="legend" style="margin-top:10px"><span><i style="background:#2d6cf6"></i>Serving coverage</span><span><i style="background:#11b2b8"></i>Hotspot region</span><span><i style="background:#d88b10"></i>Cell-edge pressure</span></div></div><div class="chart-card"><h4>UE scatter / mobility paths</h4><div class="spark">${lineSpark([1,3,2,5,3,6,4,7,3,8],'#11b2b8')}</div><div class="small-note" style="margin-top:8px">Trajectory overlay, serving cell colors, hotspot membership, and handover markers would render here.</div></div></div>`;
    $('#geomControls').innerHTML = `<div class="form-group"><h4>Deployment</h4><div class="form-grid"><div class="field"><label>Layout type</label><input value="hexagonal_wraparound"></div><div class="field"><label>Inter-site distance</label><input value="600"></div><div class="field"><label>Wrap-around</label><input value="enabled"></div><div class="field"><label>Wrap-around rings</label><input value="2"></div></div></div><div class="form-group"><h4>UE placement & mobility</h4><div class="form-grid"><div class="field"><label>Indoor UE fraction</label><input value="0.2"></div><div class="field"><label>Hotspot user fraction</label><input value="0.35"></div><div class="field"><label>Mobility profile</label><input value="80x3 km/h + 20x30 km/h"></div><div class="field"><label>Association metric</label><input value="rsrp"></div></div></div>`;
  }

  function renderWaveform(){
    $('#waveformConsistency').innerHTML = [['Numerology','μ=1'],['SCS','30 kHz'],['Slots/frame','20'],['Slot duration','0.5 ms'],['Active grid','273 RB'],['FFT size','4096']].map(([l,v])=>`<div class="kpi-card"><div class="label">${l}</div><div class="value">${v}</div></div>`).join('');
    $('#waveformPanels').innerHTML = `<div class="layout-board">
      <div class="layout-col"><h4>Carrier</h4><ul><li>4 GHz center frequency</li><li>100 MHz system bandwidth</li><li>Single component carrier</li><li>TDD duplex</li></ul></div>
      <div class="layout-col"><h4>Numerology</h4><ul><li>μ = 1</li><li>SCS = 30 kHz</li><li>Normal CP</li><li>20 slots per frame</li></ul></div>
      <div class="layout-col"><h4>Waveforms</h4><ul><li>DL CP-OFDM</li><li>UL CP-OFDM default</li><li>UL DFT-s-OFDM alt</li><li>Waveform switching ready</li></ul></div>
      <div class="layout-col"><h4>RF impairments</h4><ul><li>CFO enabled nominal</li><li>Timing offset configurable</li><li>Phase noise nominal</li><li>PA/IQ optional stress modes</li></ul></div>
    </div>`;
  }

  function renderTraffic(){
    $('#trafficCards').innerHTML = `<div class="metric-grid">
      ${[['eMBB',40],['FTP3',20],['XR',20],['VoIP',10],['UL-heavy',10],['Offered load','70–90%']].map(([l,v])=>`<div class="metric"><div class="m-title">${l}</div><div class="m-value">${v}</div><div class="m-sub">${typeof v==='number'?'UEs':'Target baseline cell load'}</div></div>`).join('')}
    </div>`;
    $('#trafficCharts').innerHTML = `<div class="chart-grid"><div class="chart-card"><h4>Traffic mix</h4><div class="bars">${barSpark([40,20,20,10,10])}</div></div><div class="chart-card"><h4>Latency budgets</h4><div class="bars">${barSpark([20,20,5,10,20],['#1b63f0','#6e61ff','#11b2b8','#d88b10','#169c62'])}</div><div class="small-note" style="margin-top:8px">eMBB 20 ms · FTP 20 ms · XR 5 ms · VoIP 10 ms · UL-heavy 20 ms</div></div></div>`;
  }

  function renderMac(){
    $('#macWorkflow').innerHTML = `<div class="flow-grid" style="grid-template-columns:repeat(6,minmax(0,1fr))">
      ${['Queue state','Eligibility','Control gating','Candidate ranking','PRB allocation','MCS/TBS + HARQ'].map((n,i)=>`<div class="stage-card" style="min-height:170px"><div class="stage-top"><div><h4>${n}</h4><p>${['UE queues, HOL delay, QoS, backlog','Cell acquisition, access, SRS/TRS validity, control eligibility','Grant validity from PDCCH / control state','PF/fairness/latency/channel/beam metrics','RB/symbol allocation and fragmentation','Actual operating point, HARQ process, RV, NDI'][i]}</p></div><span class="badge ${i<3?'blue':'green'}">${i<3?'state':'decision'}</span></div></div>`).join('')}
    </div>`;
    $('#macSummary').innerHTML = `<div class="summary-list">${[['Scheduler','PF + beam-aware'],['OLLA','enabled'],['Target BLER DL/UL','0.1 / 0.1'],['HARQ processes','16 / 16'],['Retransmission limit','4'],['Fairness window','100 ms']].map(([k,v])=>`<div class="summary-item"><span class="key">${k}</span><span class="val">${v}</span></div>`).join('')}</div>`;
  }

  function renderL1(){
    const famRoot = $('#familyNav'), canvas = $('#blockCanvas'), inspector = $('#blockInspector');
    let activeFamily = data.l1Families[0].id; let activeBlock = data.l1Families[0].blocks[0].id;
    function draw(){
      famRoot.innerHTML = data.l1Families.map(f=>`<button class="family-btn ${f.id===activeFamily?'active':''}" data-family="${f.id}"><span>${f.title}</span><span class="meta-pill">${f.blocks.length} blocks</span></button>`).join('');
      const family = data.l1Families.find(f=>f.id===activeFamily);
      $('#familyTitle').innerHTML = `<div class="family-header"><div><div class="kicker">L1 / PHY family</div><h3>${family.title}</h3><p>${family.summary}</p></div><div class="legend"><span><i style="background:#1b63f0"></i>Configured / requested</span><span><i style="background:#11b2b8"></i>Applied / runtime</span><span><i style="background:#d88b10"></i>Artifacts / evidence</span></div></div>`;
      canvas.innerHTML = family.blocks.map(b=>`<div class="block-card ${b.id===activeBlock?'active':''}" data-block="${b.id}"><div class="block-tags"><span class="badge blue">${b.group}</span><span class="badge green">runtime</span></div><h4>${b.name}</h4><p>${b.purpose}</p><div class="block-tags"><span class="chip">${b.params.length} params</span><span class="chip green">${b.outputs.length} outputs</span><span class="chip amber">${b.artifacts.length} artifacts</span></div><div class="block-meta"><div class="mini">Requested → Resolved</div><div class="mini">Applied → Measured</div></div></div>`).join('');
      const block = family.blocks.find(b=>b.id===activeBlock) || family.blocks[0];
      inspector.innerHTML = `<h3>${block.name}</h3><p>${block.purpose}</p>
        <div class="inspector-card"><div class="kv-list"><div class="k">Algorithm / processing</div><div class="v">${block.algo}</div><div class="k">Family</div><div class="v">${block.group}</div><div class="k">Truth source</div><div class="v">Active runtime path</div></div></div>
        <div class="inspector-card"><h4 style="margin:0 0 10px">Requested / configurable parameters</h4><div class="list-chips">${block.params.map(p=>`<span class="chip">${p}</span>`).join('')}</div></div>
        <div class="inspector-card"><h4 style="margin:0 0 10px">Runtime / resolved / measured values</h4><div class="list-chips">${block.runtime.map(r=>`<span class="chip green">${r}</span>`).join('')}</div></div>
        <div class="inspector-card"><h4 style="margin:0 0 10px">Canonical outputs / artifacts</h4><div class="list-chips">${block.artifacts.map(a=>`<span class="chip amber">${a}</span>`).join('')}</div></div>
        <div class="inspector-card"><h4 style="margin:0 0 10px">Inspector actions</h4><div class="action-row"><a class="btn secondary" href="block_studio.html">Open in Block Studio</a><a class="btn secondary" href="artifacts.html">See artifacts</a><a class="btn ghost" href="parameter_catalog.html">Parameter catalog</a></div></div>`;
      $$('.family-btn', famRoot).forEach(btn=>btn.onclick=()=>{activeFamily=btn.dataset.family; activeBlock=data.l1Families.find(f=>f.id===activeFamily).blocks[0].id; draw();});
      $$('.block-card', canvas).forEach(btn=>btn.onclick=()=>{activeBlock=btn.dataset.block; draw();});
    }
    draw();
  }

  function renderBlockStudio(){
    $('#studioStepper').innerHTML = ['Choose block','Inspect ownership','Edit requested values','Review resolved/appplied values','Save + download JSON'].map((s,i)=>`<span class="step ${i===1?'active':''}">${s}</span>`).join('');
    $('#studioTable').innerHTML = `<div class="table-card"><div class="table-head"><h4>Selected block parameter sheet — PDSCH TX Chain</h4><span class="badge green">Configurable + traceable</span></div><div class="table-wrap"><table class="data-table param-table"><thead><tr><th>Parameter</th><th>Category</th><th>Requested</th><th>Resolved</th><th>Applied</th><th>Measured</th><th>Unit</th><th>Source</th><th>Status</th></tr></thead><tbody>${[
      ['max_modulation_dl','coding/modulation','256QAM','256QAM','64QAM in this grant','N/A','enum','browser+yml / scheduler grant','changed at runtime'],
      ['decoder_iterations_max','decoder','12','12','12','7','iterations','browser+yml / decoder','runtime used'],
      ['dmrs_type','reference signal','type1','type1','type1','DMRSRECount=48','enum','browser+yml / tx kernel','runtime used'],
      ['ptrs_enable','reference signal','on','on','off for this grant','PTRSRECount=0','bool','browser+yml / MCS rule','conditional'],
      ['RequestedPrecoderPMI','beamforming','3','3','3','AppliedPrecoderPMI=3','int','CSI/beam manager','applied'],
      ['RequestedBeamIndexSet','beamforming','1|2','1|2','2','SelectedBeamIndex=2','set','beam manager','applied']
    ].map(r=>`<tr>${r.map(c=>`<td>${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div></div>`;
  }

  function renderRealtime(){
    $('#rtKpis').innerHTML = data.realtimeKpis.map(([l,v])=>`<div class="metric"><div class="m-title">${l}</div><div class="m-value">${v}</div></div>`).join('');
    $('#rtGrants').innerHTML = tableHtml(['Time','Dir','Cell','UE','PRB','MCS','HARQ','Control','Beam'], data.realtimeTables.grants);
    $('#rtControl').innerHTML = tableHtml(['UE','Acquisition','Access','PDCCH','SRS','TRS','Scheduling'], data.realtimeTables.control);
    $('#rtChannel').innerHTML = tableHtml(['UE','Serving cell','RSRP','Measured SINR','Speed','Doppler','Condition'], data.realtimeTables.channel);
    $('#rtEvents').innerHTML = `<div class="stream">${[
      ['Truth contract warning','Roundtrip mismatch count = 2. Browser submitted fields differ from resolved runtime aliases.'],
      ['Grant executed','DL UE 044 Cell 18 MCS 24 RV0 beam 7 committed to DB artifacts.'],
      ['Control update','UE 011 PDCCH failed in previous slot, blocked one DL grant, retried next slot.'],
      ['Channel state refresh','Spatial consistency and large-scale state updated at 100 ms boundary.'],
      ['Artifact flush','live_dl_scheduler_grants.csv and live_control_gating_state.csv checkpointed.']
    ].map(([a,b])=>`<div class="stream-item"><strong>${a}</strong><p>${b}</p></div>`).join('')}</div>`;
  }

  function tableHtml(headers, rows){
    return `<div class="table-card"><div class="table-wrap"><table class="data-table"><thead><tr>${headers.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.map(r=>`<tr>${r.map(c=>`<td>${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div></div>`;
  }

  function renderAnalytics(){
    $('#analyticsCards').innerHTML = `<div class="card-grid">${data.analyticsCards.map(c=>`<div class="callout col-4"><h4>${c.title}</h4><p>${c.desc}</p></div>`).join('')}</div>`;
    $('#analyticsCharts').innerHTML = `<div class="chart-grid">
      <div class="chart-card"><h4>KPI overview</h4><div class="bars">${barSpark([84,72,65,91,58,74])}</div></div>
      <div class="chart-card"><h4>PRB allocation heatmap</h4><div class="heatmap">${heatMap()}</div></div>
      <div class="chart-card"><h4>Beam stability</h4><div class="spark">${lineSpark([2,3,2,4,3,5,4,3,4,5,4,6],'#6e61ff')}</div></div>
      <div class="chart-card"><h4>Latency CDF</h4><div class="spark">${lineSpark([1,2,3,5,8,13,21,34,55,89],'#11b2b8')}</div></div>
      <div class="chart-card"><h4>Interference decomposition</h4><div class="bars">${barSpark([52,28,12,8],['#1b63f0','#6e61ff','#11b2b8','#d88b10'])}</div></div>
      <div class="chart-card"><h4>Energy per bit</h4><div class="spark">${lineSpark([90,84,80,76,72,68,66,63,61,59],'#169c62')}</div></div>
    </div>`;
  }

  function renderArtifacts(){
    $('#artifactTable').innerHTML = tableHtml(['Artifact','Class','Canonical','Rows','Schema','Browser consumer'], [
      ['air_interface/csv/dl_pdsch_trials.csv','raw runtime waveform evidence','yes','220','v5','PHY analytics'],
      ['air_interface/csv/ul_pusch_trials.csv','raw runtime waveform evidence','yes','217','v5','PHY analytics'],
      ['control/csv/pdcch_trials.csv','raw control evidence','yes','437','v4','Control / Access'],
      ['reports/csv/live_control_gating_state.csv','runtime state evidence','yes','30','v3','Real-Time + Analytics'],
      ['packet_flow/csv/live_dl_scheduler_grants.csv','grant/runtime trace','yes','220','v5','Real-Time'],
      ['reports/csv/runtime_operating_mode.csv','config/mode disclosure','yes','2','v4','Overview'],
      ['control/csv/control_gating_state.csv','legacy mirror','no','0','legacy','never if canonical exists']
    ]);
  }

  function renderCatalog(){
    $('#catalogTable').innerHTML = tableHtml(['Parameter','Group','Exposure','Type','Value','Role'], data.parameterRows);
  }

  function renderCompare(){
    $('#compareTable').innerHTML = tableHtml(['Metric','Baseline','Candidate','Δ','Comparability','Better'], [
      ['DL Throughput','8.1 Gbps','8.4 Gbps','+3.7%','compatible','candidate'],
      ['UL Throughput','1.88 Gbps','1.96 Gbps','+4.2%','compatible','candidate'],
      ['DL BLER','9.8%','8.8%','-1.0 pp','compatible','candidate'],
      ['Energy per bit','142 nJ','134 nJ','-5.6%','compatible','candidate'],
      ['Latency p95','11.4 ms','10.7 ms','-6.1%','compatible','candidate']
    ]);
  }

  const page = document.body.dataset.page || 'home';
  buildSidebar(page); buildRightbar(); buildTopbar(page);
  if(page==='home') renderHome();
  if(page==='scenario') renderScenarioPage();
  if(page==='geometry') renderGeometry();
  if(page==='waveform') renderWaveform();
  if(page==='traffic') renderTraffic();
  if(page==='mac') renderMac();
  if(page==='l1') renderL1();
  if(page==='studio') renderBlockStudio();
  if(page==='realtime') renderRealtime();
  if(page==='analytics') renderAnalytics();
  if(page==='artifacts') renderArtifacts();
  if(page==='catalog') renderCatalog();
  if(page==='compare') renderCompare();
})();
