(function () {
  "use strict";

  const W = 460;
  const H = 260;
  const PAD = { top: 34, right: 20, bottom: 46, left: 58 };
  const IW = W - PAD.left - PAD.right;
  const IH = H - PAD.top - PAD.bottom;
  const COLORS = ["#1b63f0", "#11b2b8", "#169c62", "#d88b10", "#d94b4b", "#6e61ff"];

  function esc(value) {
    return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;"
    }[ch]));
  }

  function finite(values) {
    return values.filter((value) => typeof value === "number" && Number.isFinite(value));
  }

  function extent(values, fallback = [0, 1]) {
    const nums = finite(values);
    if (!nums.length) return fallback;
    let lo = Math.min(...nums);
    let hi = Math.max(...nums);
    if (lo === hi) {
      lo -= 1;
      hi += 1;
    }
    return [lo, hi];
  }

  function scale(domain, range) {
    const [d0, d1] = domain;
    const [r0, r1] = range;
    return (value) => r0 + ((value - d0) / ((d1 - d0) || 1)) * (r1 - r0);
  }

  function ticks(domain, count = 5) {
    const [lo, hi] = domain;
    return Array.from({ length: count }, (_, idx) => {
      const value = lo + ((hi - lo) * idx) / Math.max(count - 1, 1);
      return Math.abs(value) >= 100 ? value.toFixed(0) : value.toFixed(2).replace(/\.?0+$/, "");
    });
  }

  function wrap(title, subtitle, body) {
    return `<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${esc(title)}">
      <rect width="${W}" height="${H}" rx="14" fill="#fff"/>
      <text x="${PAD.left}" y="18" class="chart-title">${esc(title)}</text>
      ${subtitle ? `<text x="${PAD.left}" y="32" class="chart-sub">${esc(subtitle)}</text>` : ""}
      <g transform="translate(${PAD.left},${PAD.top})">${body}</g>
    </svg>`;
  }

  function placeholder(title, reason) {
    return `<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${esc(title)} unavailable">
      <rect width="${W}" height="${H}" rx="14" fill="#f8fbff"/>
      <text x="${W / 2}" y="${H / 2 - 10}" text-anchor="middle" class="chart-title">${esc(title)}</text>
      <text x="${W / 2}" y="${H / 2 + 12}" text-anchor="middle" class="chart-sub">${esc(reason || "No runtime CSV evidence loaded")}</text>
    </svg>`;
  }

  function axes(xDomain, yDomain, xLabel, yLabel) {
    const sx = scale(xDomain, [0, IW]);
    const sy = scale(yDomain, [IH, 0]);
    let out = "";
    ticks(yDomain, 5).forEach((label) => {
      const y = sy(Number(label));
      out += `<line x1="0" y1="${y}" x2="${IW}" y2="${y}" class="chart-grid-line"/>`;
      out += `<text x="-8" y="${y + 4}" text-anchor="end" class="chart-tick">${esc(label)}</text>`;
    });
    ticks(xDomain, 6).forEach((label) => {
      const x = sx(Number(label));
      out += `<text x="${x}" y="${IH + 18}" text-anchor="middle" class="chart-tick">${esc(label)}</text>`;
    });
    out += `<line x1="0" y1="0" x2="0" y2="${IH}" class="chart-axis"/>`;
    out += `<line x1="0" y1="${IH}" x2="${IW}" y2="${IH}" class="chart-axis"/>`;
    out += `<text x="${IW / 2}" y="${IH + 38}" text-anchor="middle" class="chart-label">${esc(xLabel)}</text>`;
    out += `<text x="${-IH / 2}" y="-44" text-anchor="middle" transform="rotate(-90)" class="chart-label">${esc(yLabel)}</text>`;
    return { sx, sy, out };
  }

  function lineChart(title, points, xLabel, yLabel, subtitle, color = COLORS[0]) {
    const clean = (points || []).filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y));
    if (!clean.length) return placeholder(title, "No rows with finite x/y values");
    const xDomain = extent(clean.map((p) => p.x));
    const yDomain = extent(clean.map((p) => p.y));
    const ctx = axes(xDomain, yDomain, xLabel, yLabel);
    const path = clean.map((p) => `${ctx.sx(p.x)},${ctx.sy(p.y)}`).join(" ");
    const body = `${ctx.out}<polyline points="${path}" fill="none" stroke="${color}" stroke-width="2.4"/>`;
    return wrap(title, subtitle, body);
  }

  function scatterChart(title, points, xLabel, yLabel, subtitle, colorKey) {
    const clean = (points || []).filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y));
    if (!clean.length) return placeholder(title, "No rows with finite scatter coordinates");
    const xDomain = extent(clean.map((p) => p.x));
    const yDomain = extent(clean.map((p) => p.y));
    const ctx = axes(xDomain, yDomain, xLabel, yLabel);
    const colorDomain = extent(clean.map((p) => Number(p[colorKey])), [0, 1]);
    const colorScale = scale(colorDomain, [0, COLORS.length - 1]);
    const dots = clean.map((p) => {
      const rawColor = colorKey ? Number(p[colorKey]) : NaN;
      const idx = Number.isFinite(rawColor) ? Math.max(0, Math.min(COLORS.length - 1, Math.round(colorScale(rawColor)))) : 0;
      return `<circle cx="${ctx.sx(p.x)}" cy="${ctx.sy(p.y)}" r="3.6" fill="${COLORS[idx]}" opacity="0.78"/>`;
    }).join("");
    return wrap(title, subtitle, `${ctx.out}${dots}`);
  }

  function barChart(title, rows, xLabel, yLabel, subtitle, color = COLORS[0]) {
    const clean = (rows || []).filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y));
    if (!clean.length) return placeholder(title, "No finite bar values");
    const yMax = Math.max(1, ...clean.map((p) => p.y));
    const ctx = axes([0, Math.max(clean.length - 1, 1)], [0, yMax], xLabel, yLabel);
    const width = Math.max(2, IW / clean.length - 2);
    const bars = clean.map((p, idx) => {
      const h = IH - ctx.sy(p.y);
      return `<rect x="${idx * (IW / clean.length) + 1}" y="${ctx.sy(p.y)}" width="${width}" height="${Math.max(h, 0)}" rx="2" fill="${color}" opacity="0.82"><title>${esc(p.x)}: ${esc(p.y)}</title></rect>`;
    }).join("");
    const labels = clean.length <= 18 ? clean.map((p, idx) => `<text x="${idx * (IW / clean.length) + width / 2}" y="${IH + 17}" text-anchor="middle" class="chart-tick">${esc(p.x)}</text>`).join("") : "";
    return wrap(title, subtitle, `${ctx.out}${bars}${labels}`);
  }

  function multiLineChart(title, series, xLabel, yLabel, subtitle) {
    const all = series.flatMap((item) => item.points || []).filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y));
    if (!all.length) return placeholder(title, "No finite series data");
    const ctx = axes(extent(all.map((p) => p.x)), extent(all.map((p) => p.y)), xLabel, yLabel);
    const lines = series.map((item, idx) => {
      const color = COLORS[idx % COLORS.length];
      const pts = (item.points || []).filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y)).map((p) => `${ctx.sx(p.x)},${ctx.sy(p.y)}`).join(" ");
      return `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2"/><text x="${IW - 4}" y="${14 + idx * 14}" text-anchor="end" fill="${color}" class="chart-tick">${esc(item.label)}</text>`;
    }).join("");
    return wrap(title, subtitle, `${ctx.out}${lines}`);
  }

  function prbHeatmap(rows) {
    const clean = (rows || []).filter((row) => Number.isFinite(row.slot) && Number.isFinite(row.start) && Number.isFinite(row.count));
    if (!clean.length) return placeholder("PRB Allocation Heatmap", "No resource_grid or grant PRB rows loaded");
    const slots = [...new Set(clean.map((row) => row.slot))].sort((a, b) => a - b);
    const maxPrb = Math.max(1, ...clean.map((row) => row.start + row.count));
    const sx = scale([Math.min(...slots), Math.max(...slots) || Math.min(...slots) + 1], [0, IW]);
    const sy = scale([0, maxPrb], [IH, 0]);
    const slotWidth = Math.max(2, IW / Math.max(slots.length, 1));
    const rects = clean.map((row) => {
      const color = COLORS[Math.abs(Math.round(row.ue)) % COLORS.length];
      return `<rect x="${sx(row.slot)}" y="${sy(row.start + row.count)}" width="${slotWidth}" height="${Math.max(1, sy(row.start) - sy(row.start + row.count))}" fill="${color}" opacity="0.76"><title>slot ${row.slot}, UE ${row.ue}, PRB ${row.start}-${row.start + row.count}</title></rect>`;
    }).join("");
    const body = `<line x1="0" y1="${IH}" x2="${IW}" y2="${IH}" class="chart-axis"/><line x1="0" y1="0" x2="0" y2="${IH}" class="chart-axis"/>${rects}<text x="${IW / 2}" y="${IH + 36}" text-anchor="middle" class="chart-label">Slot</text><text x="${-IH / 2}" y="-44" text-anchor="middle" transform="rotate(-90)" class="chart-label">PRB index</text>`;
    return wrap("PRB Allocation Heatmap", "CSV: resource_grid_analytics or scheduler grants", body);
  }

  function ueScatterMap(rows) {
    const clean = (rows || []).map((row) => ({ x: row.x, y: row.y, sinr: row.sinr, los: row.los })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y));
    return scatterChart("UE Position Scatter", clean, "X position (m)", "Y position (m)", "CSV: mobility_analytics", "sinr");
  }

  function blerVsSINR(data) {
    return lineChart("BLER vs Measured SINR", data, "Measured SINR (dB)", "BLER", "CSV: throughput_analytics", COLORS[4]);
  }

  function sinrCDF(data) {
    return lineChart("Measured SINR CDF", data, "Measured SINR (dB)", "CDF", "CSV: throughput_analytics", COLORS[0]);
  }

  function throughputCDF(data) {
    return lineChart("Per-UE Throughput CDF", data, "DL goodput (Mbps)", "CDF", "CSV: throughput_analytics", COLORS[2]);
  }

  function sinrPipelineChart(rows) {
    const sorted = (rows || []).slice().sort((a, b) => a.slot - b.slot);
    return multiLineChart("SINR Pipeline Comparison", [
      { label: "measured", points: sorted.map((r) => ({ x: r.slot, y: r.measured })) },
      { label: "large-scale", points: sorted.map((r) => ({ x: r.slot, y: r.largeScale })) },
      { label: "receiver Hest", points: sorted.map((r) => ({ x: r.slot, y: r.hest })) }
    ], "Slot", "SINR (dB)", "CSV: link_adaptation_analytics");
  }

  function cqiDistributionChart(data) {
    return barChart("CQI Distribution", data, "CQI", "Count", "CSV: throughput_analytics", COLORS[1]);
  }

  function mcsDistributionChart(data) {
    return barChart("MCS Distribution", data, "MCS index", "Count", "CSV: throughput_analytics", COLORS[0]);
  }

  function evmCDF(data) {
    return lineChart("EVM CDF", data, "EVM (%)", "CDF", "CSV: throughput_analytics or evm_analytics", COLORS[3]);
  }

  function harqCombiningChart(rows) {
    const counts = new Map();
    (rows || []).forEach((row) => {
      const key = `RV${row.rv}`;
      const cur = counts.get(key) || { x: key, y: 0, total: 0 };
      cur.y += row.applied ? 1 : 0;
      cur.total += 1;
      counts.set(key, cur);
    });
    const fractions = [...counts.values()].map((row) => ({ x: row.x, y: row.total ? row.y / row.total : 0 }));
    return barChart("HARQ Combining Fraction by RV", fractions, "RV", "Applied fraction", "CSV: throughput_analytics", COLORS[2]);
  }

  function prachDetectionChart(rows) {
    return multiLineChart("PRACH Detection vs SNR", [
      { label: "metric", points: (rows || []).map((r) => ({ x: r.x, y: r.y })) },
      { label: "threshold", points: (rows || []).filter((r) => Number.isFinite(r.threshold)).map((r) => ({ x: r.x, y: r.threshold })) }
    ], "SNR (dB)", "Detection metric", "CSV: prach_analytics");
  }

  function nmseVsSINR(data) {
    return lineChart("Channel Estimation NMSE", data, "SNR bin (dB)", "NMSE (dB)", "CSV: channel_estimation_analytics", COLORS[4]);
  }

  function fairnessChart(summary) {
    const subtitle = Number.isFinite(summary && summary.jain) ? `CSV: fairness_analytics, Jain=${summary.jain.toFixed(3)}` : "CSV: fairness_analytics";
    return barChart("Per-UE Throughput Fairness", (summary && summary.perUE) || [], "UE rank", "DL goodput (Mbps)", subtitle, COLORS[1]);
  }

  function energyBreakdown(rows) {
    return barChart("Energy Breakdown", (rows || []).slice(0, 14).map((row, idx) => ({ x: idx + 1, y: row.value, label: row.key })), "Metric rank", "Value", "CSV: energy_efficiency_analytics", COLORS[2]);
  }

  function waveformTimeDomain(rows) {
    const clean = rows || [];
    return multiLineChart("Waveform Time Domain", [
      { label: "TX", points: clean.map((row) => ({ x: row.x, y: row.tx })) },
      { label: "RX", points: clean.map((row) => ({ x: row.x, y: row.rx })) }
    ], "Time or sample", "Magnitude", "CSV: waveform_analytics");
  }

  function rsrpCDF(data) {
    return lineChart("RSRP CDF", data, "Serving RSRP (dBm)", "CDF", "CSV: mobility_analytics", COLORS[4]);
  }

  function pathlossVsDistance(data) {
    return scatterChart("Pathloss vs Distance", data, "Distance from origin (m)", "Pathloss (dB)", "CSV: mobility_analytics", "y");
  }

  function timingErrorCDF(data) {
    return lineChart("Timing Error CDF", data, "Timing error (samples)", "CDF", "CSV: throughput_analytics", COLORS[3]);
  }

  function decoderIterationsChart(data) {
    return barChart("LDPC Decoder Iterations", data, "Iterations", "Count", "CSV: throughput_analytics", COLORS[5]);
  }

  function spectralEfficiencyChart(data) {
    return scatterChart("Spectral Efficiency vs SINR", data, "Measured SINR (dB)", "Spectral efficiency (bps/Hz)", "CSV: throughput_analytics", null);
  }

  function llrMeanAbsCDF(data) {
    return lineChart("LLR Mean Abs CDF", data, "Mean |LLR|", "CDF", "CSV: throughput_analytics", COLORS[1]);
  }

  function tbsByMCS(data) {
    return scatterChart("TBS Distribution per MCS", data, "MCS index", "TB size (bits)", "CSV: throughput_analytics", null);
  }

  function conditionNumberCDF(data) {
    return lineChart("Condition Number CDF", data, "Condition number (dB)", "CDF", "CSV: throughput_analytics", COLORS[3]);
  }

  function noiseVarianceVsSINR(data) {
    return scatterChart("Noise Variance vs SINR", data, "Measured SINR (dB)", "Noise variance", "CSV: throughput_analytics", null);
  }

  function beamHitRateVsSINR(data) {
    return lineChart("Beam-Hit Rate vs SINR", data, "Measured SINR (dB)", "Beam-hit fraction", "CSV: throughput_analytics", COLORS[2]);
  }

  function residualCfoCDF(data) {
    return lineChart("Residual CFO CDF", data, "Residual CFO (Hz)", "CDF", "CSV: throughput_analytics", COLORS[4]);
  }

  function paprCDF(data) {
    return lineChart("PAPR CDF", data, "PAPR (dB)", "CDF", "CSV: throughput_analytics or papr_analytics", COLORS[5]);
  }

  window.Charts = {
    placeholder,
    blerVsSINR,
    sinrCDF,
    throughputCDF,
    prbHeatmap,
    sinrPipelineChart,
    cqiDistributionChart,
    mcsDistributionChart,
    evmCDF,
    harqCombiningChart,
    prachDetectionChart,
    ueScatterMap,
    nmseVsSINR,
    fairnessChart,
    energyBreakdown,
    waveformTimeDomain,
    rsrpCDF,
    pathlossVsDistance,
    timingErrorCDF,
    decoderIterationsChart,
    spectralEfficiencyChart,
    llrMeanAbsCDF,
    tbsByMCS,
    conditionNumberCDF,
    noiseVarianceVsSINR,
    beamHitRateVsSINR,
    residualCfoCDF,
    paprCDF,
    lineChart,
    barChart,
    scatterChart
  };
})();
