function ok=testCellSearchPreparationAuthority()
% A scheduled broadcast must exist before channel execution or acquisition.
setup6GRSimToolkit("Verbose",false);
root=fileparts(fileparts(mfilename("fullpath")));
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,"simulator", ...
    "configs","scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(tempdir,"sixgr_prepare_broadcast"));
initial=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,"DL", ...
    "LinkKey","test_preparation_only", "Seed",cfg.run.seed);
profile clear;
profile on;
cleanupProfile=onCleanup(@()profile('off')); %#ok<NASGU>
out=sixgr.link.runCellSearch_MIB_SIB1(cfg,"UseRuntimeChannel",true, ...
    "PrepareOnly",true,"RuntimeSlot",0,"InitialDLChannelState",initial);
profile off;
stats=profile('info');
assert(~out.Ok && ~out.Crash && ~out.Skipped && out.Status=="prepared_not_received");
assert(~out.DetectionAttempted && ~out.DecodeAttempted && ...
    ~out.RuntimeChannelStateUsed && isnan(out.BLER));
assert(isempty(fieldnames(out.PBCH)),"Preparation must not create a BCH result.");
assert(initial.CurrentSampleIndex==0 && ~initial.Materialized);
names=string({stats.FunctionTable.FunctionName});
assert(~any(contains(names,"applyRuntimeChannelState") | ...
    contains(names,"advanceRuntimeChannelState") | ...
    contains(names,"materializeRuntimeChannelState") | ...
    contains(names,"recoverSIB1FromWaveform")), ...
    "Preparation must not materialize/advance the channel or decode future samples.");
match=names=="generateSSB_MIB_SIB1_Waveform" | ...
    endsWith(names,".generateSSB_MIB_SIB1_Waveform");
assert(any(match) && sum([stats.FunctionTable(match).NumCalls])==1);
p=out.PreparedBroadcast;
assert(p.RuntimeChannelDeferred && p.NumSamples==size(p.TransmitSamples,1));
assert(isequal(p.TransmitSamples,p.RuntimeTx.Waveform));
assert(all(isfinite(p.TransmitSamples(:))) && any(p.TransmitSamples(:)~=0));
assert(isfield(p.TxInfo,"PortGrid") && ~isempty(p.TxInfo.PortGrid));
assert(~p.Tx.ReferenceNoise.Applied,"Runtime TX must not inject receiver AWGN at preparation.");
assert(isfield(p.Tx,"PDSCHAssignment") && isfield(p.Tx,"SSBBurstPlan"));
assert(isequaln(p.PowerContext,p.ReceiverConfig.lls6g.runtimePowerContext));
% Queue the actual prepared physical samples and consume only the first slot.
stream=sixgr.phy.waveform.WaveformStreamComposer(p.SampleRateHz,size(p.TransmitSamples,2),0);
stream.enqueue("prepared-broadcast", ...
    sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,0),p.SampleRateHz);
n=round(p.SampleRateHz*sixgr.time.slotDurationSec(cfg));
first=stream.readThrough(n);
assert(isequal(first.Samples,p.TransmitSamples(1:n,:)) && stream.NextSampleIndex==n);
assert(n<p.NumSamples,"The regression must exercise a multi-slot capture.");
fprintf('CELL_SEARCH_PREPARATION_AUTHORITY_PASS: %d real TX samples, no channel or decoder execution.\n',p.NumSamples);
ok=true;
end
