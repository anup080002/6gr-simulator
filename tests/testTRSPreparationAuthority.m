function ok=testTRSPreparationAuthority()
% TRS must be schedulable before any RF/channel/receiver execution.
setup6GRSimToolkit("Verbose",false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator","configs", ...
    "scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
initial=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,"DL", ...
    "LinkKey","test_trs_preparation","Seed",cfg.run.seed);
profile clear;
profile on;
cleanup=onCleanup(@()profile('off')); %#ok<NASGU>
out=sixgr.link.runTRSTracking(cfg,"SNR_dB",12, ...
    "ChannelState",initial,"PrepareOnly",true);
profile off;
stats=profile('info');
assert(~out.Ok && ~out.Crash && ~out.Skipped, ...
    "Preparation failed: %s",out.FailureReason);
assert(~out.DetectionAttempted && ~out.ChannelEstimationAttempted && ...
    ~out.RuntimeChannelStateUsed && ~out.TRSRuntimeEvidenceUsable);
assert(isnan(out.TrackingFailure) && isnan(out.RuntimeStageCount));
assert(isequaln(out.ChannelState,initial) && ~initial.Materialized && initial.CurrentSampleIndex==0);
names=string({stats.FunctionTable.FunctionName});
for forbidden=["initWaveformTruthChannelState","applyRuntimeFadingChannel", ...
        "applyRuntimeChannelState","advanceRuntimeChannelState", ...
        "applyRFImpairmentChain","estimateTRSTiming","detectTRSResources", ...
        "estimateTRSChannel","scoreTRSDetection"]
    assert(~any(contains(names,forbidden)),"Preparation executed %s.",forbidden);
end
matches=names=="generateTRSWaveform" | endsWith(names,".generateTRSWaveform");
assert(any(matches) && sum([stats.FunctionTable(matches).NumCalls])==1);
p=out.PreparedTransmission;
assert(p.RFExecutionDeferred && p.ChannelExecutionDeferred);
assert(p.NumSamples==size(p.TransmitSamples,1) && p.SampleRateHz>0);
assert(all(isfinite(p.TransmitSamples(:))) && any(p.TransmitSamples(:)~=0));
assert(p.TxInfo.PowerNormalizationGridSource=="exact_trs_multislot_port_grids");
assert(isequaln(p.PowerContext,p.ReceiverConfig.lls6g.runtimePowerContext));
assert(isequal(p.TxInfo.PortGrid,cat(2,p.Tx.GridSlots.Grid)));
expected=sixgr.rf.applyPowerContext(p.Tx.Waveform,p.ReceiverConfig,"DL",p.TxInfo);
assert(isequal(expected,p.TransmitSamples));
assert(height(p.Tx.SlotTable)==numel(p.Tx.GridSlots));
fprintf('TRS_PREPARATION_AUTHORITY_PASS: %d real TX samples; no channel or receiver execution.\n',p.NumSamples);
ok=true;
end
