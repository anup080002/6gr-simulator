function ok=testLLSReportTRSConfiguration()
% Verify the report fixtures' actual NZP resources before expensive execution.
base=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_100mhz_tdlc_bidirectional_truth.yaml');
overlay=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/lls_report_trs_resources.yaml');
scenario=sixgr.util.mergeStruct(base.toStruct(),overlay);
variants={scenario,sixgr.util.mergeStruct(scenario, ...
    sixgr.lls6g.config.readConfigFile('simulator/configs/validation/lls_report_trs_24prb.yaml'))};
for variant=1:numel(variants)
scenario=variants{variant};
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
% The report scenario executes a retained shared RF clock, even when only
% legacy impairment fields are enabled. Its epoch must come from YAML.
epoch=sixgr.util.structGet(cfg,'rf.configurationEpoch',[]);
assert(isequal(epoch,scenario.rf_frontend.configuration_epoch));
carrier=sixgr.phy.grid.makeCarrier(cfg);
ofdm=nrOFDMInfo(carrier);
physical=sixgr.truth.SharedWaveformPhysicalRuntime(ofdm.SampleRate,0,epoch);
assert(physical.ConfigurationEpoch==epoch && physical.NextSampleIndex==0);
strict=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
assert(strict.StrictValidation.StrictValid,strict.StrictValidation.StrictUnsupportedReason);
resources=sixgr.phy.trs.generateTRSSymbolsAndIndices(strict);
rows=resources.ResourceMappingTable;
assert(numel(resources.SlotResources)==2 && ...
    isequal(unique(rows.Symbol0Based).',[6 10]) && ...
    isequal(unique(rows.Slot).',[1 2]) && ...
    all(rows.NumCSIRSPorts==1) && all(rows.Density=="three"));
expectedRB=min(52,scenario.bwp.dl.n_size_bwp);
assert(strict.NumRB==expectedRB && height(rows)==2*2*3*expectedRB && ...
    all(rows.Subcarrier0Based<12*expectedRB));
window=sixgr.truth.resolveTRSObservationWindow(cfg,2);
assert(window.ObservationStarts && isequal(window.AbsoluteSlotNumbers,[1 2]));
window=sixgr.truth.resolveTRSObservationWindow(cfg,3);
assert(window.ResourceActive && ~window.ObservationStarts);
% Keep explicit rejection of the original incomplete tracking resource set.
bad=cfg; bad.phy.trs.slotNumbers=2;
invalid=sixgr.phy.trs.buildTRSConfigFromScenario(bad);
assert(~invalid.StrictValidation.StrictValid);
bad=cfg; bad.phy.trs.symbolLocation=6;
rejected=false;
try
    sixgr.phy.trs.buildTRSConfigFromScenario(bad);
catch ME
    assert(strcmp(ME.identifier,'sixgr:phy:trs:UnsupportedTrackingSymbolPair'));
    rejected=true;
end
assert(rejected,'An incomplete symbol pair must not silently gain a second resource.');
fprintf('LLS_REPORT_TRS_CONFIGURATION_PASS slots=2 resources=4 native_re=%d\n',height(rows));
end
% Report-richness requests actual nonzero impairments. A nonzero configured
% value is not an enable flag: verify both the enabled and explicitly ideal
% branches through the production builder before launching the report run.
richness=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/lls_result_richness.yaml');
impaired=sixgr.lls6g.buildInternalConfig(richness,tempname);
assert(impaired.phy.impairments.cfoEnabled && impaired.phy.impairments.cfoHz==40);
assert(impaired.phy.impairments.timingOffsetEnabled && ...
    impaired.phy.impairments.timingOffsetSamples==16);
ideal=richness.toStruct();
ideal.impairments.cfo_enabled=false;
ideal.impairments.cfo.enabled=false;
ideal.impairments.timing_offset_enabled=false;
ideal.impairments.to.enabled=false;
ideal=sixgr.lls6g.buildInternalConfig(ideal,tempname);
assert(~ideal.phy.impairments.cfoEnabled && ideal.phy.impairments.cfoHz==0 && ...
    ~ideal.phy.impairments.timingOffsetEnabled && ...
    ideal.phy.impairments.timingOffsetSamples==0, ...
    'Disabling an impairment must remain effective even with a nonzero configured value.');
fprintf('LLS_REPORT_IMPAIRMENT_PREFLIGHT_PASS enabled_and_disabled_branches=1\n');
ok=true;
end
