function ok = testPreparedWaveformPAOwnership()
% Real SSB/TRS preparation retains linear TX contributions for composition.
% This does not qualify the main scheduler or composite RF execution.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
s = s.toStruct();
s.impairments.pa_nonlinearity_enabled = true;
if isfield(s,'rf_frontend') && isfield(s.rf_frontend,'pa')
    s.rf_frontend.pa.enabled = true;
end
sixgr.lls6g.config.validateScenarioConfig(s);
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.rf.pa.enable && cfg.phy.impairments.paNonlinearityEnabled);
beforeCfg = cfg;
profile clear;
profile on;
cleanup = onCleanup(@() profile('off')); %#ok<NASGU>
trs = sixgr.link.runTRSTracking(cfg,'SNR_dB',12,'RuntimeSlot',3,'PrepareOnly',true);
ssb = sixgr.link.runCellSearch_MIB_SIB1(cfg,'UseRuntimeChannel',true, ...
    'RuntimeSlot',0,'WriteArtifacts',false,'PrepareOnly',true);
profile off;
stats = profile('info');
assert(~trs.Crash && ~ssb.Crash, 'Preparation failed: TRS %s; SSB %s', ...
    trs.FailureReason,ssb.FailureReason);
assert(isequaln(beforeCfg,cfg),'Deferral must not disable the configured device.');
assert(~trs.DetectionAttempted && ~trs.RuntimeChannelStateUsed && ...
    ~ssb.RuntimeChannelStateUsed);
for prepared = {trs.PreparedTransmission,ssb.PreparedBroadcast}
    p = prepared{1};
    assert(p.RFExecutionDeferred && p.PAExecutionDeferred && ...
        p.PowerContext.PAEnabled && ~p.PowerContext.PAApplied && ...
        p.PowerContext.PAExecutionDeferred);
    assert(string(p.PowerContext.PAExecutionStatus) == ...
        "deferred_until_transmitter_waveform_composition");
    assert(isnan(p.PowerContext.PAOutputTotalPower_mW), ...
        'Unexecuted PA must not publish a measured output power.');
    expected = p.Tx.Waveform .* cast(p.PowerContext.AmplitudeScale,'like',p.Tx.Waveform);
    assert(isequal(expected,p.TransmitSamples), ...
        'A prepared contribution must contain only its exact TX waveform and linear power scaling.');
end
names = string({stats.FunctionTable.FunctionName});
for forbidden = ["PAModel","PAProfile.apply","applyRFImpairmentChain", ...
        "applyRuntimeFadingChannel","applyRuntimeChannelState"]
    assert(~any(contains(names,forbidden)), 'Preparation executed %s.',forbidden);
end
ok = true;
disp('PREPARED_WAVEFORM_PA_OWNERSHIP_PASS');
end
