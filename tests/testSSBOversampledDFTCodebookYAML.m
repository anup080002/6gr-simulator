function ok = testSSBOversampledDFTCodebookYAML()
%TESTSSBOVERSAMPLEDFTCODEBOOKYAML Preserve Lmax beams on a smaller URA.

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_webgui_full_stack_sinr_geometry_qualification.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
% The SSB fixture has four CSI ports; declare its matching Type-I report
% panel explicitly instead of inheriting the master's larger panel tuple.
data=scfg.toStruct();
% Scope: SSB codebook construction only, not full-stack coexistence or CSI
% acquisition. Disable unrelated CSI through the canonical boolean owners;
% do not move its colliding REs or bypass the production separation guard.
for feature=["csi_rs_enabled","csi_reporting_enabled","cqi_reporting_enabled", ...
        "pmi_reporting_enabled","ri_reporting_enabled","cri_reporting_enabled"]
    data.reference_signals.(feature)=false;
end
report=data.csi_acquisition_and_reporting.report_configuration;
report.n1=2; report.n2=1; report.o1=4; report.o2=1; report.panels=1;
report.codebook_mode=1;
data.csi_acquisition_and_reporting.report_configuration=report;
% Keep this SSB-only configuration fixture valid under the current UL
% coexistence contract: PUSCH 0..10, SRS 11, short PUCCH 12..13. Import the
% installed resource plan without shortening a long-format PUCCH into an
% illegal allocation. This fixture still makes no UL execution claim.
timingScenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    'simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml'));
timingData=timingScenario.toStruct();
data.pusch.start_symbol=timingData.pusch.start_symbol;
data.pusch.num_symbols=timingData.pusch.num_symbols;
data.pusch.time_domain_allocations=timingData.pusch.time_domain_allocations;
data.reference_signals.srs.symbol_start=timingData.reference_signals.srs.symbol_start;
data.reference_signals.srs.num_srs_symbols=timingData.reference_signals.srs.num_srs_symbols;
data.reference_signals.srs.pucch_collision_policy= ...
    timingData.reference_signals.srs.pucch_collision_policy;
data.pucch_resources=timingData.pucch_resources;
scfg=sixgr.lls6g.config.ScenarioConfig(data,'SourceFiles',scfg.SourceFiles, ...
    'ConfigPath',scfg.ConfigPath,'ConfigHash',sixgr.util.sha256Hex(jsonencode(data)));
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
assert(~cfg.phy.csirs.enable && ~cfg.phy.csi.enable && ~cfg.phy.csi.reportCSI, ...
    'This fixture must remain explicitly scoped to SSB codebook construction.');

matrices = sixgr.util.structGet(cfg, "phy.ssb.precoderMatrices", []);
assert(isequal(size(matrices), [8 4]), ...
    "Eight SSB candidates must resolve to eight physical four-element beams.");
assert(isequal(double(sixgr.util.structGet(cfg, ...
    "phy.ssb.precoderBeamGrid", [])), [2 4]), ...
    "The YAML-owned oversampled beam-grid dimensions were not preserved.");
beamIndices = double(sixgr.util.structGet(cfg, ...
    "phy.ssb.precoderBeamIndices", []));
assert(isequal(beamIndices(:).', 0:7), ...
    "The YAML-owned SSB beam indices were not preserved.");
assert(all(abs(sum(abs(matrices).^2, 2) - 1) < 1e-12), ...
    "Every physical SSB beam must preserve unit transmit power.");
assert(numel(unique(string(sixgr.util.structGet(cfg, ...
    "phy.ssb.precoderIDs", strings(0, 1))))) == 8, ...
    "Every SSB candidate must retain a distinct physical-beam identity.");

ok = true;
end
