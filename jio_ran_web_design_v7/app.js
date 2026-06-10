(function () {
  "use strict";

  const $ = (sel, el = document) => el.querySelector(sel);
  const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];
  const data = window.RAN_DATA || {};

  function buildSidebar(active) {
    const root = $("#sidebar");
    if (!root) return;
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
          ${(data.nav || []).map((n) => `<a class="nav-item ${active === n.id ? "active" : ""}" href="${n.href}"><span class="nav-dot"></span><span>${n.label}</span></a>`).join("")}
        </div>
      </div>
      <div class="nav-section">
        <div class="nav-label">Profiles</div>
        <div class="summary-list">
          ${(data.profiles || []).map((p) => `<div class="summary-item"><span class="key">${p.name}</span><span class="val">${p.runtime}</span></div>`).join("")}
        </div>
      </div>
    `;
  }

  function buildRightbar() {
    const root = $("#rightbar");
    if (!root) return;
    root.innerHTML = `
      <div class="status-tile"><h4>Scenario</h4><div class="big">${ConfigStore.get("meta.scenario_id")}</div><div class="small-note">ConfigStore-owned LLS study</div></div>
      <div class="status-tile"><h4>Run profile</h4><div class="big">${ConfigStore.get("meta.run_profile")}</div><div class="small-note">Modify from Scenario page</div></div>
      <div class="status-tile"><h4>Status</h4><div class="big">${data.app.status}</div><div class="small-note">DB: ${data.app.db}<br>Backend: ${data.app.matlab}</div></div>
      <div class="status-tile"><h4>Config status</h4><div class="big" style="font-size:16px;font-family:var(--mono)">${ConfigStore.violations().length} violations</div><div class="small-note">Parent-child constraints live in parameter_constraints.json</div></div>
      <div class="panel" style="margin-top:14px"><div class="panel-header"><div><h3 class="panel-title">Quick actions</h3><p class="panel-subtitle">Always visible in the shell</p></div></div><div class="panel-body"><div class="action-row"><a class="btn primary" href="realtime.html">Run Scenario</a><a class="btn secondary" href="parameter_catalog.html">Validate</a><button class="btn secondary" data-config-download="json" type="button">Download Config JSON</button><button class="btn ghost" data-config-download="yaml" type="button">Download YAML</button><a class="btn ghost" href="analytics.html">Open Analytics</a></div></div></div>
    `;
  }

  function buildTopbar(page) {
    const root = $("#topbar");
    if (!root) return;
    const map = {
      home: ["Simulation workstation", "Select a mode, understand the same-flow architecture, then open the exact page you need."],
      scenario: ["Scenario", "Define study identity, seeds, runtime budget, export policy, and reproducibility."],
      geometry: ["Geometry", "Configure sites, sectors, UE placement, wrap-around, hotspots, and mobility."],
      waveform: ["Waveform", "Set carrier, numerology, TDD, waveform, coding, and RF impairments with consistency warnings."],
      traffic: ["Traffic", "Build service mix, QoS, load, packet models, and latency budgets."],
      mac: ["MAC / Scheduler", "Configure scheduling, PRBs, HARQ, OLLA, fairness, and link adaptation."],
      l1: ["L1 / PHY Explorer", "Drill into every PHY family with requested/resolved/applied/runtime boundaries."],
      antenna: ["Antenna & Air Interface", "Inspect BS/UE arrays, air-interface coupling, channel assumptions, beam truth, and ToA/ToD."],
      studio: ["Block Studio", "Inspect requested, resolved, applied, measured, and derived values per block."],
      realtime: ["Real-Time Data", "Monitor live DB-backed grants, channel state, control state, artifacts, and truth contract health."],
      analytics: ["Analytics", "Generate and inspect post-run reports, root cause dashboards, and compare-runs evidence."],
      artifacts: ["Artifact Explorer", "Inspect canonical artifacts, mirrors, coverage, row counts, and provenance."],
      catalog: ["Parameter Catalog", "See every parameter, owner, exposure level, and runtime source classification."],
      compare: ["Compare Runs", "Pair compatible runs, inspect KPI deltas, overlays, config diffs, and artifact diffs."]
    };
    const [title, desc] = map[page] || ["Page", ""];
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
          <button class="btn secondary" data-config-download="json" type="button">Download Config JSON</button>
        </div>
      </div>
    `;
  }

  function configPanel(sectionIds, title = "Browser-owned configuration", subtitle = "Every input writes to ConfigStore and is validated against the shared parent-child constraint catalog.") {
    return `<section class="panel"><div class="panel-header"><div><h3 class="panel-title">${title}</h3><p class="panel-subtitle">${subtitle}</p></div><div class="action-row"><button class="btn secondary" type="button" data-config-download="json">Download JSON</button><button class="btn ghost" type="button" data-config-download="yaml">Download YAML</button></div></div><div class="panel-body">${ConfigFormRenderer.buildSections(sectionIds)}<div style="margin-top:14px">${ConfigFormRenderer.buildViolationPanel()}</div></div></section>`;
  }

  function refreshConfigPanels() {
    $$("[data-config-panel]").forEach((panel) => {
      const sections = (panel.dataset.configPanel || "").split(",").map((s) => s.trim()).filter(Boolean);
      panel.innerHTML = configPanel(sections);
      ConfigFormRenderer.bind(panel, refreshConfigPanels);
    });
    bindGlobalConfigActions();
  }

  function makeKpis(target, rows) {
    if (!target) return;
    target.innerHTML = rows.map(([label, value]) => `<div class="kpi-card"><div class="label">${label}</div><div class="value">${value}</div></div>`).join("");
  }

  function chartCard(title, svgHtml, source, note = "") {
    return `
      <div class="chart-card-full">
        <div class="chart-header">
          <h4>${title}</h4>
          <span class="badge blue">${source}</span>
          ${note ? `<span class="chart-note">${note}</span>` : ""}
        </div>
        <div class="chart-body">${svgHtml}</div>
      </div>
    `;
  }

  function dataNote() {
    const aData = window.AnalyticsData;
    if (!aData) return "AnalyticsData is not loaded.";
    if (!aData.runRef) return "No run selected. Add ?run_path=<scenario>/<run> or ?run_id=<id> to load CSV-backed charts.";
    return aData.hasAnyData() ? `Loaded runtime CSV evidence from ${aData.runRef}.` : `No CSV artifacts were loaded for ${aData.runRef}.`;
  }

  function withAnalyticsReady(draw) {
    const aData = window.AnalyticsData;
    if (!aData) {
      draw(null);
      return;
    }
    if (aData.ready) draw(aData);
    else aData.onReady(draw);
  }

  function renderHome() {
    makeKpis($("#homeKpis"), [
      ["Mode", ConfigStore.get("run_control.execution_mode")],
      ["Scenario", ConfigStore.get("meta.scenario_id")],
      ["BW", `${ConfigStore.get("frequency.bandwidth_hz")} Hz`],
      ["SCS", `${ConfigStore.get("frame.scs_khz")} kHz`],
      ["NRB", ConfigStore.get("phy.carrier.NSizeGrid")],
      ["Cells", ConfigStore.get("scenario.layout.nSites") * ConfigStore.get("scenario.layout.nSectorsPerSite")],
      ["UEs", ConfigStore.get("scenario.ue.nUE")],
      ["Constraints", ConfigStore.violations().length]
    ]);
    $("#modeCards").innerHTML = (data.modeCards || []).map((m) => `<div class="mode-card"><div class="badge ${m.name === "LLS" ? "green" : "blue"}">${m.tag}</div><h4>${m.name}</h4><p>${m.desc}</p><ul>${m.bullets.map((b) => `<li>${b}</li>`).join("")}</ul><div class="mode-card-footer"><a class="btn ${m.name === "LLS" ? "primary" : "secondary"}" href="${m.route}">${m.name === "LLS" ? "Open LLS Builder" : "View Mode"}</a><span class="meta-pill">Same-flow UI</span></div></div>`).join("");
    $("#profiles").innerHTML = (data.profiles || []).map((p) => `<div class="profile-card"><h4>${p.name}</h4><div class="badge blue">${p.runtime}</div><p>${p.notes}</p></div>`).join("");
    $("#routeGrid").innerHTML = (data.nav || []).slice(1).map((n) => `<a class="route-item" href="${n.href}"><span>${n.label}</span><span class="meta-pill">Open</span></a>`).join("");
    $("#sameFlow").innerHTML = (data.sameFlow || []).map((s) => `<a class="stage-card" href="${s.href}"><div class="stage-top"><div><h4>${s.title}</h4><p>${s.desc}</p></div><span class="badge ${s.status.includes("Deep") ? "purple" : s.status === "Operational" ? "amber" : "green"}">${s.status}</span></div><ul>${s.items.map((i) => `<li>${i}</li>`).join("")}</ul><div class="stage-meta"><span class="meta-pill">${s.params} params</span><span class="meta-pill">Click to open</span></div></a>`).join("");
  }

  function renderScenarioPage() {
    $("#scenarioForms").innerHTML = `<div data-config-panel="scenario,geometry,waveform,traffic,mac,l1,antenna,outputs"></div>`;
    refreshConfigPanels();
    $("#scenarioSummary").innerHTML = `
      <div class="panel"><div class="panel-header"><div><h3 class="panel-title">Live summary</h3><p class="panel-subtitle">Requested vs resolved scenario status</p></div><span class="badge green">ConfigStore</span></div><div class="panel-body"><div class="summary-list">
      <div class="summary-item"><span class="key">Scenario</span><span class="val">${ConfigStore.get("meta.scenario_id")}</span></div>
      <div class="summary-item"><span class="key">Mode</span><span class="val">${ConfigStore.get("run_control.execution_mode")}</span></div>
      <div class="summary-item"><span class="key">Profile</span><span class="val">${ConfigStore.get("meta.run_profile")}</span></div>
      <div class="summary-item"><span class="key">Sites / sectors / UEs</span><span class="val">${ConfigStore.get("scenario.layout.nSites")} / ${ConfigStore.get("scenario.layout.nSectorsPerSite")} / ${ConfigStore.get("scenario.ue.nUE")}</span></div>
      <div class="summary-item"><span class="key">Carrier / BW</span><span class="val">${ConfigStore.get("frequency.center_frequency_hz")} Hz / ${ConfigStore.get("frequency.bandwidth_hz")} Hz</span></div>
      <div class="summary-item"><span class="key">SCS / NRB</span><span class="val">${ConfigStore.get("frame.scs_khz")} kHz / ${ConfigStore.get("phy.carrier.NSizeGrid")} RB</span></div>
      <div class="summary-item"><span class="key">Scheduler</span><span class="val">${ConfigStore.get("scheduler.scheduler_type")} + beam-aware=${ConfigStore.get("scheduler.beam_aware_scheduler_enable")}</span></div>
      <div class="summary-item"><span class="key">Truth contract</span><span class="val">No proxy PHY</span></div>
      </div><div class="clean-note" style="margin-top:14px">Requested values are edited here; resolved, applied, measured, and derived runtime values belong to Block Studio, Real-Time Data, and Analytics.</div></div></div>`;
  }

  function renderGeometry() {
    makeKpis($("#geomKpis"), [
      ["Sites", ConfigStore.get("scenario.layout.nSites")],
      ["Cells", ConfigStore.get("scenario.layout.nSites") * ConfigStore.get("scenario.layout.nSectorsPerSite")],
      ["UEs", ConfigStore.get("scenario.ue.nUE")],
      ["Indoor", `${Math.round(ConfigStore.get("scenario.ue.distribution.indoorFraction") * 100)}%`],
      ["ISD", `${ConfigStore.get("scenario.layout.interSiteDistance_m")} m`],
      ["Wrap", ConfigStore.get("scenario.layout.wrapAround") ? "on" : "off"]
    ]);
    const geomCanvas = $("#geomCanvas");
    geomCanvas.innerHTML = `<div class="loading-state">${dataNote()}</div>`;
    withAnalyticsReady((aData) => {
      const Charts = window.Charts;
      if (!aData || !Charts) {
        geomCanvas.innerHTML = `<div class="clean-note">No analytics chart engine is loaded.</div>`;
        return;
      }
      geomCanvas.innerHTML = `
        <div class="chart-row">
          ${chartCard("UE Position Scatter", Charts.ueScatterMap(aData.uePositions()), aData.sourceLabel("mobility"), "Color is SINR when mobility CSV publishes it.")}
          ${chartCard("Pathloss vs Distance", Charts.pathlossVsDistance(aData.pathlossVsDistance()), "throughput_analytics.csv or mobility_analytics.csv", "Uses exported distance/pathloss fields only.")}
        </div>
      `;
    });
    $("#geomControls").innerHTML = `<div data-config-panel="geometry"></div>`;
    refreshConfigPanels();
  }

  function renderWaveform() {
    makeKpis($("#waveformConsistency"), [
      ["Numerology", `mu=${ConfigStore.get("frame.numerology_mu")}`],
      ["SCS", `${ConfigStore.get("frame.scs_khz")} kHz`],
      ["BW", `${ConfigStore.get("frequency.bandwidth_hz")} Hz`],
      ["Duplex", ConfigStore.get("phy.duplex.mode")],
      ["Active grid", `${ConfigStore.get("phy.carrier.NSizeGrid")} RB`],
      ["FFT size", ConfigStore.get("waveform.fft_size")]
    ]);
    $("#waveformPanels").innerHTML = `<div class="layout-board">
      <div class="layout-col"><h4>Carrier</h4><ul><li>${ConfigStore.get("frequency.center_frequency_hz")} Hz center frequency</li><li>${ConfigStore.get("frequency.bandwidth_hz")} Hz bandwidth</li><li>${ConfigStore.get("frequency.range_name")}</li><li>${ConfigStore.get("phy.duplex.mode")} duplex</li></ul></div>
      <div class="layout-col"><h4>Numerology</h4><ul><li>mu = ${ConfigStore.get("frame.numerology_mu")}</li><li>SCS = ${ConfigStore.get("frame.scs_khz")} kHz</li><li>${ConfigStore.get("frame.cp_type")} CP</li><li>Grid = ${ConfigStore.get("phy.carrier.NSizeGrid")} RB</li></ul></div>
      <div class="layout-col"><h4>Waveforms</h4><ul><li>DL ${ConfigStore.get("waveform.dl")}</li><li>UL ${ConfigStore.get("waveform.ul")}</li><li>Transform precoding ${ConfigStore.get("waveform.transform_precoding_enabled")}</li><li>FFT ${ConfigStore.get("waveform.fft_size")}</li></ul></div>
      <div class="layout-col"><h4>RF impairments</h4><ul><li>CFO ${ConfigStore.get("impairments.cfo_enabled")}</li><li>Timing ${ConfigStore.get("impairments.timing_offset_enabled")}</li><li>Phase noise ${ConfigStore.get("impairments.phase_noise_enabled")}</li><li>PA/IQ ${ConfigStore.get("impairments.pa_nonlinearity_enabled")} / ${ConfigStore.get("impairments.iq_imbalance_enabled")}</li></ul></div>
    </div><div style="margin-top:16px" data-config-panel="waveform"></div>`;
    refreshConfigPanels();
  }

  function renderTraffic() {
    $("#trafficCards").innerHTML = `<div class="metric-grid">${[["Service", ConfigStore.get("traffic.service_class")], ["Mix", ConfigStore.get("traffic.traffic_mix_mode")], ["DL/UL", ConfigStore.get("traffic.dl_ul_ratio")], ["Queue", `${ConfigStore.get("traffic.queue_depth_bytes")} B`], ["Latency", `${ConfigStore.get("traffic.latency_budget_ms")} ms`], ["Packet", ConfigStore.get("traffic.packet_model")]].map(([l, v]) => `<div class="metric"><div class="m-title">${l}</div><div class="m-value">${v}</div></div>`).join("")}</div>`;
    const trafficCharts = $("#trafficCharts");
    trafficCharts.innerHTML = `<div class="loading-state">${dataNote()}</div><div style="margin-top:16px" data-config-panel="traffic"></div>`;
    withAnalyticsReady((aData) => {
      const Charts = window.Charts;
      if (!aData || !Charts) return;
      trafficCharts.innerHTML = `
        <div class="chart-row">
          ${chartCard("Per-UE DL Throughput CDF", Charts.throughputCDF(aData.throughputCDF("DL")), aData.sourceLabel("throughput"), "Runtime goodput aggregated by UE.")}
          ${chartCard("Per-UE Fairness", Charts.fairnessChart(aData.fairnessSummary()), aData.sourceLabel("fairness"), "Jain fairness and zero-throughput users are CSV evidence.")}
        </div>
        <div style="margin-top:16px" data-config-panel="traffic"></div>
      `;
      refreshConfigPanels();
    });
    refreshConfigPanels();
  }

  function renderMac() {
    $("#macWorkflow").innerHTML = `<div class="flow-grid" style="grid-template-columns:repeat(6,minmax(0,1fr))">${["Queue state", "Eligibility", "Control gating", "Candidate ranking", "PRB allocation", "MCS/TBS + HARQ"].map((n, i) => `<div class="stage-card" style="min-height:170px"><div class="stage-top"><div><h4>${n}</h4><p>${["UE queues, HOL delay, QoS, backlog", "Cell acquisition, access, SRS/TRS validity, control eligibility", "Grant validity from PDCCH / control state", "PF/fairness/latency/channel/beam metrics", "RB/symbol allocation and fragmentation", "Actual operating point, HARQ process, RV, NDI"][i]}</p></div><span class="badge ${i < 3 ? "blue" : "green"}">${i < 3 ? "state" : "decision"}</span></div></div>`).join("")}</div>`;
    $("#macSummary").innerHTML = `<div class="summary-list">${[["Scheduler", ConfigStore.get("scheduler.scheduler_type")], ["OLLA", ConfigStore.get("link_adaptation.outer_loop_flag") ? "enabled" : "disabled"], ["Target BLER DL/UL", `${ConfigStore.get("link_adaptation.target_bler_dl")} / ${ConfigStore.get("link_adaptation.target_bler_ul")}`], ["HARQ processes", ConfigStore.get("harq.n_harq_processes")], ["Retransmission limit", ConfigStore.get("harq.max_retransmissions")], ["Fairness window", `${ConfigStore.get("scheduler.fairness_window_ms")} ms`]].map(([k, v]) => `<div class="summary-item"><span class="key">${k}</span><span class="val">${v}</span></div>`).join("")}</div><div style="margin-top:16px" data-config-panel="mac"></div>`;
    refreshConfigPanels();
  }

  function renderL1() {
    const famRoot = $("#familyNav"), canvas = $("#blockCanvas"), inspector = $("#blockInspector");
    if (!famRoot || !canvas || !inspector) return;
    let activeFamily = data.l1Families[0].id;
    let activeBlock = data.l1Families[0].blocks[0].id;
    function draw() {
      famRoot.innerHTML = data.l1Families.map((f) => `<button class="family-btn ${f.id === activeFamily ? "active" : ""}" data-family="${f.id}"><span>${f.title}</span><span class="meta-pill">${f.blocks.length} blocks</span></button>`).join("");
      const family = data.l1Families.find((f) => f.id === activeFamily);
      $("#familyTitle").innerHTML = `<div class="family-header"><div><div class="kicker">L1 / PHY family</div><h3>${family.title}</h3><p>${family.summary}</p></div><div class="legend"><span><i style="background:#1b63f0"></i>Configured / requested</span><span><i style="background:#11b2b8"></i>Applied / runtime</span><span><i style="background:#d88b10"></i>Artifacts / evidence</span></div></div>`;
      canvas.innerHTML = family.blocks.map((b) => `<div class="block-card ${b.id === activeBlock ? "active" : ""}" data-block="${b.id}"><div class="block-tags"><span class="badge blue">${b.group}</span><span class="badge green">runtime</span></div><h4>${b.name}</h4><p>${b.purpose}</p><div class="block-tags"><span class="chip">${b.params.length} params</span><span class="chip green">${b.outputs.length} outputs</span><span class="chip amber">${b.artifacts.length} artifacts</span></div><div class="block-meta"><div class="mini">Requested -> Resolved</div><div class="mini">Applied -> Measured</div></div></div>`).join("");
      const block = family.blocks.find((b) => b.id === activeBlock) || family.blocks[0];
      inspector.innerHTML = `<h3>${block.name}</h3><p>${block.purpose}</p><div class="inspector-card"><div class="kv-list"><div class="k">Algorithm / processing</div><div class="v">${block.algo}</div><div class="k">Family</div><div class="v">${block.group}</div><div class="k">Truth source</div><div class="v">Active runtime path</div></div></div><div class="inspector-card"><h4 style="margin:0 0 10px">Requested / configurable parameters</h4><div class="list-chips">${block.params.map((p) => `<span class="chip">${p}</span>`).join("")}</div></div><div class="inspector-card"><h4 style="margin:0 0 10px">Runtime / resolved / measured values</h4><div class="list-chips">${block.runtime.map((r) => `<span class="chip green">${r}</span>`).join("")}</div></div><div class="inspector-card"><h4 style="margin:0 0 10px">Canonical outputs / artifacts</h4><div class="list-chips">${block.artifacts.map((a) => `<span class="chip amber">${a}</span>`).join("")}</div></div><div class="inspector-card"><h4 style="margin:0 0 10px">Inspector actions</h4><div class="action-row"><a class="btn secondary" href="block_studio.html">Open in Block Studio</a><a class="btn secondary" href="artifacts.html">See artifacts</a><a class="btn ghost" href="parameter_catalog.html">Parameter catalog</a></div></div>`;
      $$(".family-btn", famRoot).forEach((btn) => { btn.onclick = () => { activeFamily = btn.dataset.family; activeBlock = data.l1Families.find((f) => f.id === activeFamily).blocks[0].id; draw(); }; });
      $$(".block-card", canvas).forEach((btn) => { btn.onclick = () => { activeBlock = btn.dataset.block; draw(); }; });
    }
    draw();
    document.querySelector(".main")?.insertAdjacentHTML("beforeend", configPanel(["l1"], "L1 / PHY editable parameters"));
    ConfigFormRenderer.bind(document.querySelector(".main"), refreshConfigPanels);
  }

  function renderBlockStudio() {
    $("#studioStepper").innerHTML = ["Choose block", "Inspect ownership", "Edit requested values", "Review resolved/applied values", "Save + download JSON"].map((s, i) => `<span class="step ${i === 1 ? "active" : ""}">${s}</span>`).join("");
    $("#studioTable").innerHTML = configPanel(["l1", "mac"], "Block Parameter Studio", "Requested values are editable here; applied/measured runtime values still come only from completed runs.");
    ConfigFormRenderer.bind($("#studioTable"), refreshConfigPanels);
  }

  function tableHtml(headers, rows) {
    return `<div class="table-card"><div class="table-wrap"><table class="data-table"><thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div></div>`;
  }

  function renderRealtime() {
    $("#rtKpis").innerHTML = `<div class="loading-state">${dataNote()}</div>`;
    $("#rtGrants").innerHTML = tableHtml(["Status"], [["Waiting for runtime CSV evidence"]]);
    $("#rtControl").innerHTML = tableHtml(["Status"], [["Waiting for control CSV evidence"]]);
    $("#rtChannel").innerHTML = tableHtml(["Status"], [["Waiting for mobility/channel CSV evidence"]]);
    $("#rtEvents").innerHTML = `<div class="stream"><div class="stream-item"><strong>Runtime evidence</strong><p>${dataNote()}</p></div></div>`;
    withAnalyticsReady((aData) => {
      const helper = window.AnalyticsHelpers || {};
      const n = helper.number || ((row, keys, fallback) => keys.reduce((found, key) => Number.isFinite(found) ? found : Number(row[key]), fallback));
      const t = helper.text || ((row, keys, fallback = "") => keys.map((key) => row[key]).find((value) => value != null && String(value).trim()) || fallback);
      if (!aData) return;
      const tiles = aData.summaryTiles().map((item) => [item.label, item.value]);
      makeKpis($("#rtKpis"), tiles);
      const grantRows = aData.throughputRows().slice(-8).reverse().map((row) => [
        `F${n(row, ["Frame"], 0)} S${n(row, ["Slot"], 0)}`,
        t(row, ["Direction"], ""),
        n(row, ["ServingCell", "BaseStationID"], ""),
        n(row, ["UEIndex", "UEID"], ""),
        `${n(row, ["PRBStart"], 0)} + ${n(row, ["PRBs", "AllocatedPRBCount"], 0)}`,
        n(row, ["MCSIndex", "MCS"], ""),
        `RV${n(row, ["HARQRV"], 0)}`,
        t(row, ["GrantControlState", "Status"], ""),
        t(row, ["AppliedBeamIndexSet", "SelectedBeamIndex"], "")
      ]);
      $("#rtGrants").innerHTML = tableHtml(["Time", "Dir", "Cell", "UE", "PRB", "MCS", "HARQ", "Control", "Beam"], grantRows.length ? grantRows : [["No grant rows loaded", "", "", "", "", "", "", "", ""]]);
      const controlRows = aData.throughputRows().slice(-8).reverse().map((row) => [
        n(row, ["UEIndex", "UEID"], ""),
        t(row, ["CellAcquisitionState"], ""),
        t(row, ["AccessState"], ""),
        t(row, ["GrantControlState"], ""),
        t(row, ["SRSValidityState"], ""),
        t(row, ["TRSValidityState"], ""),
        t(row, ["ControlEligible"], "")
      ]);
      $("#rtControl").innerHTML = tableHtml(["UE", "Acquisition", "Access", "PDCCH", "SRS", "TRS", "Scheduling"], controlRows.length ? controlRows : [["No control rows loaded", "", "", "", "", "", ""]]);
      const channelRows = aData.uePositions().slice(-8).reverse().map((row) => [
        row.ue,
        row.cell,
        Number.isFinite(row.rsrp) ? `${row.rsrp.toFixed(1)} dBm` : "",
        Number.isFinite(row.sinr) ? `${row.sinr.toFixed(1)} dB` : "",
        "",
        "",
        row.los ? "LOS" : "NLOS/unknown"
      ]);
      $("#rtChannel").innerHTML = tableHtml(["UE", "Serving cell", "RSRP", "Measured SINR", "Speed", "Doppler", "Condition"], channelRows.length ? channelRows : [["No channel rows loaded", "", "", "", "", "", ""]]);
      $("#rtEvents").innerHTML = `<div class="stream">${[
        ["CSV source", dataNote()],
        ["Throughput rows", `${aData.throughputRows().length} rows from ${aData.sourceLabel("throughput")}`],
        ["Mobility rows", `${aData.get("mobility").length} rows from ${aData.sourceLabel("mobility")}`],
        ["Control lineage", "Only runtime CSV fields are displayed; no static grant/control rows are injected."]
      ].map(([a, b]) => `<div class="stream-item"><strong>${a}</strong><p>${b}</p></div>`).join("")}</div>`;
    });
  }

  function renderAnalytics() {
    $("#analyticsCards").innerHTML = `<div class="clean-note">${dataNote()}</div><div class="card-grid">${(data.analyticsCards || []).map((c) => `<div class="callout col-4"><h4>${c.title}</h4><p>${c.desc}</p></div>`).join("")}</div>`;
    $("#analyticsCharts").innerHTML = `<div class="loading-state">${dataNote()}</div>`;
    withAnalyticsReady((aData) => {
      const Charts = window.Charts;
      if (!aData || !Charts) {
        $("#analyticsCharts").innerHTML = `<div class="clean-note">No analytics chart engine is loaded.</div>`;
        return;
      }
      const kpiStrip = document.getElementById("analyticsKpiStrip");
      if (kpiStrip) {
        kpiStrip.innerHTML = aData.summaryTiles().map((item) => `<div class="kpi-card evidence-${item.status}"><div class="label">${item.label}</div><div class="value">${item.value}</div></div>`).join("");
      }
      $("#analyticsCards").innerHTML = `<div class="clean-note">${dataNote()}</div>`;
      $("#analyticsCharts").innerHTML = `
        <div class="analytics-dashboard">
          <div class="chart-row">
            ${chartCard("BLER vs Measured SINR", Charts.blerVsSINR(aData.blerVsSINR()), aData.sourceLabel("throughput"), "CRC outcomes binned by measured receiver SINR.")}
            ${chartCard("Measured SINR CDF", Charts.sinrCDF(aData.sinrCDF()), aData.sourceLabel("throughput"), "Post-equalization measured SINR only.")}
            ${chartCard("Per-UE Throughput CDF", Charts.throughputCDF(aData.throughputCDF("DL")), aData.sourceLabel("throughput"), "DL goodput aggregated per UE.")}
          </div>
          <div class="chart-row">
            ${chartCard("SINR Pipeline Comparison", Charts.sinrPipelineChart(aData.sinrPipelineComparison()), aData.sourceLabel("link_adaptation"), "Measured, large-scale, and receiver-estimate SINR are separate.")}
            ${chartCard("CQI Distribution", Charts.cqiDistributionChart(aData.cqiDistribution()), aData.sourceLabel("throughput"), "Uses WidebandCQI values if exported.")}
            ${chartCard("MCS Distribution", Charts.mcsDistributionChart(aData.mcsDistribution()), aData.sourceLabel("throughput"), "Shows applied runtime MCS indices.")}
          </div>
          <div class="chart-row">
            ${chartCard("HARQ IR Combining", Charts.harqCombiningChart(aData.harqCombiningGain()), aData.sourceLabel("throughput"), "Retransmission rows only.")}
            ${chartCard("EVM CDF", Charts.evmCDF(aData.evmCDF()), aData.sourceLabel("throughput"), "EVM from runtime receiver trials.")}
            ${chartCard("Waveform Time Domain", Charts.waveformTimeDomain(aData.waveformTimeDomain()), aData.sourceLabel("waveform"), "TX magnitude from waveform_analytics.csv.")}
          </div>
          <div class="chart-row">
            ${chartCard("Channel Estimation NMSE", Charts.nmseVsSINR(aData.nmseVsSNR()), aData.sourceLabel("channel_estimation"), "Aggregated by measured SNR bin.")}
            ${chartCard("UE Position Scatter", Charts.ueScatterMap(aData.uePositions()), aData.sourceLabel("mobility"), "Runtime UE coordinates and SINR/RSRP evidence.")}
            ${chartCard("PRACH Detection vs SNR", Charts.prachDetectionChart(aData.prachDetectionCurve()), aData.sourceLabel("prach"), "Detection metric and threshold from PRACH rows.")}
          </div>
          <div class="chart-row">
            ${chartCard("PRB Allocation Heatmap", Charts.prbHeatmap(aData.prbHeatmap()), "resource_grid_analytics.csv or throughput_analytics.csv", "Per-slot PRB allocation from resource-grid or grant rows.")}
            ${chartCard("Per-UE Fairness", Charts.fairnessChart(aData.fairnessSummary()), aData.sourceLabel("fairness"), "Jain index and per-UE goodput distribution.")}
            ${chartCard("Energy Breakdown", Charts.energyBreakdown(aData.energyBreakdown()), aData.sourceLabel("energy_efficiency"), "Energy metrics from runtime exports.")}
          </div>
          <div class="chart-row">
            ${chartCard("RSRP CDF", Charts.rsrpCDF(aData.rsrpCDF()), aData.sourceLabel("mobility"), "Serving RSRP distribution.")}
            ${chartCard("Pathloss vs Distance", Charts.pathlossVsDistance(aData.pathlossVsDistance()), "throughput_analytics.csv or mobility_analytics.csv", "Channel/pathloss sanity scatter from exported distance/pathloss fields.")}
            ${chartCard("LDPC Decoder Iterations", Charts.decoderIterationsChart(aData.decoderIterations()), aData.sourceLabel("throughput"), "Decoder iteration histogram from runtime rows.")}
          </div>
          <div class="chart-row">
            ${chartCard("Spectral Efficiency vs SINR", Charts.spectralEfficiencyChart(aData.spectralEfficiencyVsSINR()), aData.sourceLabel("throughput"), "Shown only when runtime exports spectral-efficiency fields.")}
            ${chartCard("TBS Distribution per MCS", Charts.tbsByMCS(aData.tbsDistributionByMCS()), aData.sourceLabel("throughput"), "Grant/TB size evidence grouped by applied MCS.")}
            ${chartCard("LLR Mean Abs CDF", Charts.llrMeanAbsCDF(aData.llrMeanAbsCDF()), aData.sourceLabel("throughput"), "Decoder-input LLR magnitude evidence.")}
          </div>
          <div class="chart-row">
            ${chartCard("Condition Number CDF", Charts.conditionNumberCDF(aData.conditionNumberCDF()), aData.sourceLabel("throughput"), "MIMO/equalizer conditioning evidence.")}
            ${chartCard("Timing Error CDF", Charts.timingErrorCDF(aData.timingErrorDistribution()), aData.sourceLabel("throughput"), "Residual timing error after runtime correction.")}
            ${chartCard("Noise Variance vs SINR", Charts.noiseVarianceVsSINR(aData.noiseVarianceVsSINR()), aData.sourceLabel("throughput"), "Noise variance exported by the receiver path.")}
          </div>
          <div class="chart-row">
            ${chartCard("Beam-Hit Rate vs SINR", Charts.beamHitRateVsSINR(aData.beamHitRateVsSINR()), aData.sourceLabel("throughput"), "Beam selection hit fraction binned by measured SINR.")}
            ${chartCard("Residual CFO CDF", Charts.residualCfoCDF(aData.residualCfoCDF()), aData.sourceLabel("throughput"), "Post-correction CFO residuals from runtime rows.")}
            ${chartCard("PAPR CDF", Charts.paprCDF(aData.paprCDF()), aData.get("papr").length ? aData.sourceLabel("papr") : aData.sourceLabel("throughput"), "PAPR values from runtime rows or PAPR analytics summary.")}
          </div>
        </div>
      `;
    });
  }

  function renderArtifacts() {
    $("#artifactTable").innerHTML = tableHtml(["Artifact", "Class", "Canonical", "Rows", "Schema", "Browser consumer"], [
      ["air_interface/csv/dl_pdsch_trials.csv", "raw runtime waveform evidence", "yes", "runtime", "v5", "PHY analytics"],
      ["air_interface/csv/ul_pusch_trials.csv", "raw runtime waveform evidence", "yes", "runtime", "v5", "PHY analytics"],
      ["control/csv/pdcch_trials.csv", "raw control evidence", "yes", "runtime", "v4", "Control / Access"],
      ["reports/csv/live_control_gating_state.csv", "runtime state evidence", "yes", "runtime", "v3", "Real-Time + Analytics"]
    ]);
    document.querySelector(".main")?.insertAdjacentHTML("beforeend", configPanel(["outputs"], "Output persistence config"));
    ConfigFormRenderer.bind(document.querySelector(".main"), refreshConfigPanels);
  }

  function renderCatalog() {
    const rows = Object.values(window.SixGRConfigCatalog.FIELD_SECTIONS).flatMap((section) => (section.fields || []).map((field) => [field.path, section.title, "browser+json+yaml", field.type, ConfigStore.get(field.path, ""), field.readonly ? "computed/readonly" : "configured"]));
    $("#catalogTable").innerHTML = tableHtml(["Parameter", "Group", "Exposure", "Type", "Value", "Role"], rows);
  }

  function renderCompare() {
    $("#compareTable").innerHTML = tableHtml(["Metric", "Baseline", "Candidate", "Delta", "Comparability", "Better"], [
      ["DL Throughput", "runtime", "runtime", "from DB", "requires matching scenario hash", "runtime decides"],
      ["UL Throughput", "runtime", "runtime", "from DB", "requires matching scenario hash", "runtime decides"],
      ["DL BLER", "runtime", "runtime", "from DB", "requires matching scenario hash", "runtime decides"],
      ["Energy per bit", "runtime", "runtime", "from DB", "requires matching scenario hash", "runtime decides"]
    ]);
  }

  function renderAntennaConfig() {
    document.querySelector(".main")?.insertAdjacentHTML("beforeend", configPanel(["antenna"], "Antenna, channel, and air-interface config", "Array, channel, pathloss, O2I, spatial consistency, interference, and noise options are ConfigStore-backed."));
    ConfigFormRenderer.bind(document.querySelector(".main"), refreshConfigPanels);
  }

  function bindGlobalConfigActions() {
    $$("[data-config-download]").forEach((btn) => {
      btn.onclick = () => ConfigFormRenderer.downloadConfig(btn.dataset.configDownload);
    });
  }

  async function start() {
    await ConfigStore.init();
    const page = document.body.dataset.page || "home";
    buildSidebar(page);
    buildRightbar();
    buildTopbar(page);
    if (page === "home") renderHome();
    if (page === "scenario") renderScenarioPage();
    if (page === "geometry") renderGeometry();
    if (page === "waveform") renderWaveform();
    if (page === "traffic") renderTraffic();
    if (page === "mac") renderMac();
    if (page === "l1") renderL1();
    if (page === "antenna") renderAntennaConfig();
    if (page === "studio") renderBlockStudio();
    if (page === "realtime") renderRealtime();
    if (page === "analytics") renderAnalytics();
    if (page === "artifacts") renderArtifacts();
    if (page === "catalog") renderCatalog();
    if (page === "compare") renderCompare();
    bindGlobalConfigActions();
  }

  start();
})();
