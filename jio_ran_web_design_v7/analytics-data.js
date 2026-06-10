(function () {
  "use strict";

  const ANALYTICS_FILES = [
    "throughput_analytics.csv",
    "goodput_analytics.csv",
    "link_adaptation_analytics.csv",
    "cqi_mcs_consistency_analytics.csv",
    "prach_analytics.csv",
    "beam_analytics.csv",
    "channel_estimation_analytics.csv",
    "mobility_analytics.csv",
    "fairness_analytics.csv",
    "energy_efficiency_analytics.csv",
    "power_analytics.csv",
    "waveform_analytics.csv",
    "harq_analytics.csv",
    "harq_process_analytics.csv",
    "resource_grid_analytics.csv",
    "impairment_analytics.csv",
    "evm_analytics.csv",
    "papr_analytics.csv",
    "propagation_analytics.csv",
    "decoder_analytics.csv"
  ];

  const REPORT_FILES = [
    "reports/csv/live_dl_scheduler_grants.csv",
    "reports/csv/live_ul_scheduler_grants.csv",
    "reports/csv/live_control_gating_state.csv",
    "reports/csv/live_csi_feedback_stats.csv",
    "reports/csv/live_user_performance_snapshot.csv"
  ];

  function unique(items) {
    return [...new Set(items.filter(Boolean))];
  }

  function parseCSV(text) {
    const rows = [];
    let row = [];
    let field = "";
    let quoted = false;
    for (let i = 0; i < text.length; i += 1) {
      const ch = text[i];
      const next = text[i + 1];
      if (quoted) {
        if (ch === '"' && next === '"') {
          field += '"';
          i += 1;
        } else if (ch === '"') {
          quoted = false;
        } else {
          field += ch;
        }
        continue;
      }
      if (ch === '"') {
        quoted = true;
      } else if (ch === ",") {
        row.push(field);
        field = "";
      } else if (ch === "\n") {
        row.push(field);
        rows.push(row);
        row = [];
        field = "";
      } else if (ch !== "\r") {
        field += ch;
      }
    }
    if (field.length || row.length) {
      row.push(field);
      rows.push(row);
    }
    if (!rows.length) return [];
    const header = rows.shift().map((item) => item.trim());
    return rows
      .filter((items) => items.some((item) => String(item || "").trim().length))
      .map((items) => {
        const out = {};
        header.forEach((key, idx) => {
          const raw = items[idx] == null ? "" : String(items[idx]).trim();
          if (raw === "") {
            out[key] = null;
          } else if (/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(raw)) {
            out[key] = Number(raw);
          } else {
            out[key] = raw;
          }
        });
        return out;
      });
  }

  function number(row, keys, fallback = NaN) {
    for (const key of keys) {
      const value = row ? row[key] : undefined;
      if (typeof value === "number" && Number.isFinite(value)) return value;
      if (typeof value === "string" && value.trim() !== "" && Number.isFinite(Number(value))) return Number(value);
    }
    return fallback;
  }

  function text(row, keys, fallback = "") {
    for (const key of keys) {
      const value = row ? row[key] : undefined;
      if (value != null && String(value).trim() !== "") return String(value);
    }
    return fallback;
  }

  function finite(values) {
    return values.filter((value) => typeof value === "number" && Number.isFinite(value));
  }

  function quantile(values, q) {
    const sorted = finite(values).sort((a, b) => a - b);
    if (!sorted.length) return null;
    const pos = (sorted.length - 1) * q;
    const lo = Math.floor(pos);
    const hi = Math.ceil(pos);
    if (lo === hi) return sorted[lo];
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  function rowsByKey(rows, keyFn) {
    const out = new Map();
    rows.forEach((row) => {
      const key = keyFn(row);
      if (key == null || key === "") return;
      out.set(key, [...(out.get(key) || []), row]);
    });
    return out;
  }

  class AnalyticsDataStore extends EventTarget {
    constructor() {
      super();
      this.cache = {};
      this.sources = {};
      this.errors = [];
      this.ready = false;
      this.loading = false;
      this.runRef = "";
    }

    inferRunRef() {
      const params = new URLSearchParams(window.location.search || "");
      return (
        window.ACTIVE_RUN_PATH ||
        window.ACTIVE_RUN_ID ||
        params.get("run_path") ||
        params.get("run") ||
        params.get("run_id") ||
        localStorage.getItem("sixgr_active_run_path") ||
        localStorage.getItem("sixgr_active_run_id") ||
        ""
      );
    }

    async load(runRef) {
      this.runRef = String(runRef || this.inferRunRef() || "").trim();
      this.cache = {};
      this.sources = {};
      this.errors = [];
      this.ready = false;
      this.loading = true;
      if (!this.runRef) {
        this.loading = false;
        this.ready = true;
        this.errors.push("No run_path or run_id was provided, so analytics charts are intentionally empty.");
        this.dispatchEvent(new CustomEvent("ready", { detail: this }));
        return this;
      }

      const loaders = [];
      if (/^\d+$/.test(this.runRef)) {
        loaders.push(this.loadFromDashboardRunId(this.runRef));
      } else {
        loaders.push(this.loadFromRunPath(this.runRef));
      }
      await Promise.allSettled(loaders);
      this.loading = false;
      this.ready = true;
      this.dispatchEvent(new CustomEvent("ready", { detail: this }));
      return this;
    }

    async loadFromRunPath(runPath) {
      const root = String(runPath || "").replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
      const prefixes = unique([
        root,
        root.startsWith("results/") ? root : `../results/lls/${root}`,
        root.startsWith("../results/") ? root : `../${root}`
      ]);
      await Promise.all(ANALYTICS_FILES.map(async (file) => {
        const key = file.replace("_analytics.csv", "").replace(".csv", "");
        const relativePaths = prefixes.map((prefix) => `${prefix}/analytics/csv/${file}`);
        await this.loadFirstCSV(key, relativePaths);
      }));
      await Promise.all(REPORT_FILES.map(async (file) => {
        const key = file.split("/").pop().replace(".csv", "");
        const relativePaths = prefixes.map((prefix) => `${prefix}/${file}`);
        await this.loadFirstCSV(key, relativePaths);
      }));
    }

    async loadFromDashboardRunId(runId) {
      const payload = await fetch(`/api/run/${encodeURIComponent(runId)}/tables-browser`, { cache: "no-store" })
        .then((resp) => (resp.ok ? resp.json() : null))
        .catch(() => null);
      const tables = Array.isArray(payload && payload.tables) ? payload.tables : [];
      const byPath = new Map();
      tables.forEach((item) => {
        const path = String(item.logical_path || item.path || "").toLowerCase();
        if (path) byPath.set(path, item);
      });
      await Promise.all(ANALYTICS_FILES.map(async (file) => {
        const logical = `analytics/csv/${file}`.toLowerCase();
        const item = byPath.get(logical);
        if (!item) return;
        const key = file.replace("_analytics.csv", "").replace(".csv", "");
        const url = item.raw_url || item.download_url || (item.artifact_id ? `/artifact/${item.artifact_id}/raw` : "");
        await this.loadFirstCSV(key, [url]);
      }));
      await Promise.all(REPORT_FILES.map(async (file) => {
        const logical = file.toLowerCase();
        const item = byPath.get(logical);
        if (!item) return;
        const key = file.split("/").pop().replace(".csv", "");
        const url = item.raw_url || item.download_url || (item.artifact_id ? `/artifact/${item.artifact_id}/raw` : "");
        await this.loadFirstCSV(key, [url]);
      }));
    }

    async loadFirstCSV(key, urls) {
      for (const url of urls.filter(Boolean)) {
        try {
          const resp = await fetch(url, { cache: "no-store" });
          if (!resp.ok) continue;
          const parsed = parseCSV(await resp.text());
          this.cache[key] = parsed;
          this.sources[key] = url;
          return parsed;
        } catch (err) {
          this.errors.push(`${key}: ${String(err && err.message ? err.message : err)}`);
        }
      }
      this.cache[key] = this.cache[key] || [];
      return [];
    }

    onReady(callback) {
      if (this.ready) callback(this);
      else this.addEventListener("ready", () => callback(this), { once: true });
    }

    get(key) {
      return this.cache[key] || [];
    }

    source(key) {
      return this.sources[key] || "not loaded";
    }

    sourceLabel(key) {
      const source = this.source(key);
      return source === "not loaded" ? source : source.split("/").slice(-3).join("/");
    }

    hasAnyData() {
      return Object.values(this.cache).some((rows) => Array.isArray(rows) && rows.length > 0);
    }

    throughputRows(direction) {
      const rows = this.get("throughput").length ? this.get("throughput") : this.get("goodput");
      const token = String(direction || "").toUpperCase();
      return token ? rows.filter((row) => text(row, ["Direction", "direction"]).toUpperCase() === token) : rows;
    }

    measuredSINRRows(direction) {
      return this.throughputRows(direction)
        .map((row) => ({ row, value: number(row, ["MeasuredTrialSINR_dB", "MeasuredSINR_dB", "MeasuredWidebandSINR_dB"]) }))
        .filter((item) => Number.isFinite(item.value));
    }

    blerVsSINR() {
      const rows = this.measuredSINRRows("DL");
      if (!rows.length) return [];
      const values = rows.map((item) => item.value);
      const min = Math.floor(Math.min(...values) / 5) * 5;
      const max = Math.ceil(Math.max(...values) / 5) * 5;
      const bins = [];
      for (let lo = min; lo < max; lo += 5) {
        const hi = lo + 5;
        const inBin = rows.filter((item) => item.value >= lo && item.value < hi);
        if (!inBin.length) continue;
        const pass = inBin.filter((item) => number(item.row, ["CRCPass", "DecodeSuccess", "SuccessFlag"], 0) === 1).length;
        bins.push({ x: (lo + hi) / 2, y: 1 - pass / inBin.length, count: inBin.length, label: `${lo} to ${hi} dB` });
      }
      return bins;
    }

    sinrCDF() {
      const values = this.measuredSINRRows().map((item) => item.value).sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value, y: (idx + 1) / values.length }));
    }

    throughputCDF(direction = "DL") {
      const byUE = rowsByKey(this.throughputRows(direction), (row) => number(row, ["UEIndex", "UEID", "ue_id"], NaN));
      const totals = [];
      byUE.forEach((rows) => {
        totals.push(rows.reduce((sum, row) => sum + Math.max(0, number(row, ["Goodput_Mbps", "goodput_mbps", "mean_mbps"], 0)), 0));
      });
      totals.sort((a, b) => a - b);
      return totals.map((value, idx) => ({ x: value, y: (idx + 1) / totals.length }));
    }

    cqiDistribution() {
      const counts = Array.from({ length: 16 }, (_, cqi) => ({ x: cqi, y: 0 }));
      this.throughputRows().forEach((row) => {
        const cqi = Math.round(number(row, ["WidebandCQI"], NaN));
        if (cqi >= 0 && cqi <= 15) counts[cqi].y += 1;
      });
      return counts;
    }

    mcsDistribution() {
      const counts = new Map();
      this.throughputRows().forEach((row) => {
        const mcs = Math.round(number(row, ["MCSIndex", "MCS", "mcs"], NaN));
        if (Number.isFinite(mcs)) counts.set(mcs, (counts.get(mcs) || 0) + 1);
      });
      return [...counts.entries()].sort((a, b) => a[0] - b[0]).map(([x, y]) => ({ x, y }));
    }

    evmCDF() {
      const values = this.throughputRows()
        .map((row) => number(row, ["EVM_rms"], NaN))
        .filter((value) => Number.isFinite(value) && value >= 0)
        .sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value * 100, y: (idx + 1) / values.length }));
    }

    prbHeatmap() {
      const rows = this.get("resource_grid");
      if (rows.length) {
        return rows.map((row) => ({
          slot: number(row, ["slot", "Slot"], 0),
          ue: number(row, ["ue_id", "UEIndex", "UEID"], 0),
          start: number(row, ["prb_start", "PRBStart"], 0),
          count: number(row, ["prb_count", "PRBs", "AllocatedPRBCount"], 0)
        })).filter((row) => row.count > 0);
      }
      return this.throughputRows().map((row) => ({
        slot: number(row, ["Slot", "slot"], 0),
        ue: number(row, ["UEIndex", "UEID"], 0),
        start: number(row, ["PRBStart"], 0),
        count: number(row, ["PRBs", "AllocatedPRBCount"], 0)
      })).filter((row) => row.count > 0);
    }

    sinrPipelineComparison() {
      return this.get("link_adaptation").map((row) => ({
        slot: number(row, ["Slot", "slot"], 0),
        ue: number(row, ["UEIndex", "UEID"], 0),
        measured: number(row, ["MeasuredTrialSINR_dB", "MeasuredWidebandSINR_dB"], NaN),
        largeScale: number(row, ["LargeScaleSINR_dB", "LargeScaleWidebandSINR_dB"], NaN),
        hest: number(row, ["ReceiverHestSINR_dB"], NaN),
        cqi: number(row, ["WidebandCQI"], NaN),
        mcsDerived: number(row, ["CQIDerivedMCS"], NaN),
        mcsUsed: number(row, ["MCSIndex"], NaN)
      }));
    }

    harqCombiningGain() {
      return this.throughputRows()
        .filter((row) => number(row, ["HARQIsRetransmission"], 0) === 1)
        .map((row) => ({
          rv: number(row, ["HARQRV"], 0),
          applied: number(row, ["HARQCombiningApplied"], 0),
          gain: number(row, ["HARQLLRCombiningGain_dB"], NaN),
          crc: number(row, ["CRCPass"], 0)
        }));
    }

    prachDetectionCurve() {
      return this.get("prach").map((row) => ({
        x: number(row, ["SNR_dB", "ConfiguredSNR_dB"], NaN),
        y: number(row, ["DetectionMetric"], NaN),
        threshold: number(row, ["DetectionThreshold"], NaN),
        falseAlarm: number(row, ["FalseAlarm", "FalseAlarmFlag"], 0),
        missedDetection: number(row, ["MissedDetection"], 0)
      })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y)).sort((a, b) => a.x - b.x);
    }

    uePositions() {
      return this.get("mobility").map((row) => ({
        ue: number(row, ["UEID", "UEIndex", "ue_id"], 0),
        x: number(row, ["X_m", "x_m"], NaN),
        y: number(row, ["Y_m", "y_m"], NaN),
        rsrp: number(row, ["ServingRSRP_dBm", "RSRP_dBm"], NaN),
        sinr: number(row, ["MeasuredTrialSINR_dB", "MeasuredWidebandSINR_dB", "LargeScaleSINR_dB"], NaN),
        los: number(row, ["LOSFlag", "los_flag"], 0),
        cell: number(row, ["ServingCell"], 0)
      })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y));
    }

    nmseVsSNR() {
      return this.get("channel_estimation")
        .filter((row) => text(row, ["Metric"]).toUpperCase() === "NMSE_DB")
        .map((row) => ({
          x: number(row, ["SNR_dB"], NaN),
          y: number(row, ["MeanValue"], NaN),
          p05: number(row, ["P05Value"], NaN),
          p95: number(row, ["P95Value"], NaN),
          count: number(row, ["SampleCount"], 0)
        }))
        .filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y))
        .sort((a, b) => a.x - b.x);
    }

    fairnessSummary() {
      const fairness = this.get("fairness");
      const perUE = this.throughputCDF("DL").map((row, idx) => ({ x: idx + 1, y: row.x }));
      return {
        fairness,
        perUE,
        jain: number((fairness || []).find((row) => text(row, ["direction", "Direction"]).toUpperCase() === "DL"), ["jain_fairness_index"], NaN),
        zeroUsers: number((fairness || []).find((row) => text(row, ["direction", "Direction"]).toUpperCase() === "DL"), ["zero_throughput_user_count"], NaN)
      };
    }

    energyBreakdown() {
      const rows = this.get("energy_efficiency").length ? this.get("energy_efficiency") : this.get("power");
      return rows.map((row) => ({
        key: text(row, ["MetricKey", "metric_name", "Entity"], "metric"),
        value: number(row, ["Value", "ValueNumeric", "mean", "mean_mbps"], NaN),
        unit: text(row, ["Unit"], "")
      })).filter((row) => Number.isFinite(row.value));
    }

    waveformTimeDomain() {
      const rows = this.get("waveform").slice(0, 4096);
      return rows.map((row) => ({
        x: number(row, ["Time_s", "SampleIndex"], NaN),
        tx: number(row, ["TxMagnitude"], NaN),
        rx: number(row, ["RxMagnitude"], NaN)
      })).filter((row) => Number.isFinite(row.x) && (Number.isFinite(row.tx) || Number.isFinite(row.rx)));
    }

    rsrpCDF() {
      const values = this.get("mobility")
        .map((row) => number(row, ["ServingRSRP_dBm", "RSRP_dBm"], NaN))
        .filter((value) => Number.isFinite(value))
        .sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value, y: (idx + 1) / values.length }));
    }

    pathlossVsDistance() {
      const throughputRows = this.throughputRows().map((row) => ({
        x: number(row, ["PropagationDistance_m", "Distance_m", "distance_m"], NaN),
        y: number(row, ["AppliedPathloss_dB", "Pathloss_dB", "pathloss_dB"], NaN)
      })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y));
      if (throughputRows.length) return throughputRows;
      return this.get("mobility").map((row) => ({
        x: Math.hypot(number(row, ["X_m", "x_m"], NaN), number(row, ["Y_m", "y_m"], NaN)),
        y: number(row, ["Pathloss_dB", "AppliedPathloss_dB", "pathloss_dB"], NaN)
      })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y));
    }

    timingErrorDistribution() {
      const values = this.throughputRows()
        .map((row) => number(row, ["TimingError_samples", "ResidualTimingError_PostCorrection_samples"], NaN))
        .filter((value) => Number.isFinite(value))
        .sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value, y: (idx + 1) / values.length }));
    }

    decoderIterations() {
      const counts = new Map();
      this.throughputRows().forEach((row) => {
        const iters = Math.round(number(row, ["DecoderIterations"], NaN));
        if (Number.isFinite(iters)) counts.set(iters, (counts.get(iters) || 0) + 1);
      });
      return [...counts.entries()].sort((a, b) => a[0] - b[0]).map(([x, y]) => ({ x, y }));
    }

    spectralEfficiencyVsSINR() {
      return this.throughputRows("DL").map((row) => ({
        x: number(row, ["MeasuredTrialSINR_dB", "MeasuredSINR_dB"], NaN),
        y: number(row, ["SpectralEfficiency_bpsHz", "SpectralEfficiency_bps_per_Hz", "SpectralEfficiency_bits_per_s_Hz"], NaN)
      })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y));
    }

    llrMeanAbsCDF() {
      const values = this.throughputRows()
        .map((row) => number(row, ["LLRMeanAbs"], NaN))
        .filter((value) => Number.isFinite(value))
        .sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value, y: (idx + 1) / values.length }));
    }

    tbsDistributionByMCS() {
      return this.throughputRows().map((row) => ({
        x: number(row, ["MCSIndex", "MCS"], NaN),
        y: number(row, ["TBSize_bits", "TBSBits"], NaN)
      })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y));
    }

    conditionNumberCDF() {
      const values = this.throughputRows()
        .map((row) => number(row, ["ConditionNumber_dB"], NaN))
        .filter((value) => Number.isFinite(value))
        .sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value, y: (idx + 1) / values.length }));
    }

    noiseVarianceVsSINR() {
      return this.throughputRows().map((row) => ({
        x: number(row, ["MeasuredTrialSINR_dB", "MeasuredSINR_dB"], NaN),
        y: number(row, ["NoiseVariance"], NaN)
      })).filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y));
    }

    beamHitRateVsSINR() {
      const rows = this.measuredSINRRows("DL").filter((item) => Number.isFinite(number(item.row, ["BeamHit"], NaN)));
      if (!rows.length) return [];
      const values = rows.map((item) => item.value);
      const min = Math.floor(Math.min(...values) / 5) * 5;
      const max = Math.ceil(Math.max(...values) / 5) * 5;
      const bins = [];
      for (let lo = min; lo < max; lo += 5) {
        const hi = lo + 5;
        const inBin = rows.filter((item) => item.value >= lo && item.value < hi);
        if (!inBin.length) continue;
        const hits = inBin.filter((item) => number(item.row, ["BeamHit"], 0) === 1).length;
        bins.push({ x: (lo + hi) / 2, y: hits / inBin.length, count: inBin.length });
      }
      return bins;
    }

    residualCfoCDF() {
      const values = this.throughputRows()
        .map((row) => number(row, ["ResidualCFO_PostCorrection_Hz", "CFOError_Hz"], NaN))
        .filter((value) => Number.isFinite(value))
        .sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value, y: (idx + 1) / values.length }));
    }

    paprCDF() {
      const direct = this.throughputRows()
        .map((row) => number(row, ["PAPR_dB"], NaN))
        .filter((value) => Number.isFinite(value));
      const summarized = this.get("papr")
        .filter((row) => text(row, ["MetricKey", "MetricName"]).toLowerCase().includes("papr"))
        .map((row) => number(row, ["ValueNumeric", "Value"], NaN))
        .filter((value) => Number.isFinite(value));
      const values = (direct.length ? direct : summarized).sort((a, b) => a - b);
      return values.map((value, idx) => ({ x: value, y: (idx + 1) / values.length }));
    }

    summaryTiles() {
      const dl = this.throughputRows("DL");
      const ul = this.throughputRows("UL");
      const pass = dl.filter((row) => number(row, ["CRCPass"], 0) === 1).length;
      const sinr = finite(dl.map((row) => number(row, ["MeasuredTrialSINR_dB", "MeasuredSINR_dB"], NaN)));
      const goodput = finite(dl.map((row) => number(row, ["Goodput_Mbps"], NaN)));
      const fairness = this.fairnessSummary();
      return [
        { label: "DL BLER", value: dl.length ? `${((1 - pass / dl.length) * 100).toFixed(1)}%` : "no DL rows", status: dl.length ? "green" : "amber" },
        { label: "Mean DL SINR", value: sinr.length ? `${(sinr.reduce((a, b) => a + b, 0) / sinr.length).toFixed(1)} dB` : "no SINR", status: sinr.length ? "blue" : "amber" },
        { label: "P05 Goodput", value: goodput.length ? `${quantile(goodput, 0.05).toFixed(3)} Mbps` : "no goodput", status: goodput.length ? "blue" : "amber" },
        { label: "DL Trials", value: dl.length, status: dl.length ? "green" : "amber" },
        { label: "UL Trials", value: ul.length, status: ul.length ? "green" : "amber" },
        { label: "PRACH Rows", value: this.get("prach").length, status: this.get("prach").length ? "green" : "amber" },
        { label: "Jain Fairness", value: Number.isFinite(fairness.jain) ? fairness.jain.toFixed(3) : "not loaded", status: Number.isFinite(fairness.jain) ? "blue" : "amber" },
        { label: "Data Source", value: this.hasAnyData() ? "CSV loaded" : "no CSV loaded", status: this.hasAnyData() ? "green" : "amber" }
      ];
    }
  }

  window.AnalyticsHelpers = { number, text, quantile };
  window.AnalyticsData = new AnalyticsDataStore();

  document.addEventListener("DOMContentLoaded", () => {
    window.AnalyticsData.load();
  });
})();
