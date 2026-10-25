function ok=testMixedSSBNativeResources()
% Actual mixed broadcast producer/clock/CSV checks, not channel qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_n40_ssb30_common15_regression.yaml');
parent=fullfile(pwd,'results','validation','mixed_ssb_native');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); cfg=sixgr.lls6g.buildInternalConfig(s,folder);
% The production runner binds the resolved scenario hash before execution.
% Exercise publication with that same authority, not an unscoped fixture.
cfg.meta.configHash=char(string(s.ConfigHash));
[planned,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels','SSB_PBCH');
assert(all(checks.resolved(checks.enabled)),strjoin(string(checks.detail(~checks.resolved)),newline));
[commonPlan,prachPlan,ssbPlan]=sixgr.truth.splitREAllocationDomains(planned);
assert(isempty(commonPlan) && isempty(prachPlan) && ~isempty(ssbPlan) && ...
    all(ssbPlan.grid_subcarrier_spacing_hz==30000) && ...
    all(ssbPlan.evidence_scope=="planned_config_not_runtime_observation"));
assert(sum(ssbPlan.native_mapped_re_count)==830*4*3, ...
    'Sixty ms with a 20-ms period has three four-beam native SSB bursts.');
p=sixgr.link.prepareCellSearchBroadcast(cfg,true,'RuntimeSlot',20);
origin=p.BroadcastStartSample;
assert(origin==sixgr.phy.frame.slotStartSample(p.Tx.Carrier,20,p.SampleRateHz));
o=sixgr.phy.waveform.WaveformObservationBuffer(origin,origin+p.NumSamples, ...
    p.SampleRateHz,size(p.TransmitSamples,2));
o.append(sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,origin),p.SampleRateHz);
T=sixgr.truth.buildObservedBroadcastREAllocation(p,o,1);
[common,prach,native]=sixgr.truth.splitREAllocationDomains(T);
assert(isempty(prach) && ~isempty(native) && ~isempty(common) && ...
    all(common.channel~="SSB") && all(common.grid_domain=="carrier_cp_ofdm"));
grid=p.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid;
assert(sum(native.native_mapped_re_count)==nnz(grid) && ...
    all(native.grid_subcarrier_count==240) && all(native.grid_subcarrier_spacing_hz==30000));
assert(all(native.useful_end_sample_exclusive-native.useful_start_sample==1024) && ...
    all(native.carrier_origin_slot0==20) && all(native.native_absolute_slot0>=40) && ...
    all(native.sfn==mod(floor(native.native_absolute_slot0/20),1024)));
assert(all(native.emitted_symbol_count==252) && all(native.grid_symbol_count==280), ...
    'The 9-ms emitted waveform must not acquire the Toolbox grid''s zero frame padding.');
bad=p;
bad.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid(1,280,1)=1;
bad.Tx.SSBWaveInfo.ResourceGridSSBurst.ResourceGrid(1,280)=1;
localReject(@()sixgr.truth.buildObservedSSBNativeAllocation(bad,o,1), ...
    'sixgr:truth:SSBNativeSampleClockMismatch');
clear bad
bad=p; bad.Tx.SSBWaveform=bad.Tx.SSBWaveform(1:end-1,:);
localReject(@()sixgr.truth.buildObservedSSBNativeAllocation(bad,o,1), ...
    'sixgr:truth:SSBNativeSampleClockMismatch');
clear bad
starts=[2208 8784 17568 24144]; ends=[6592 13168 21952 28528]; lastSymbols=[5 11 19 25];
for beam=0:3
    N=native(native.ssb_index0==beam,:);
    assert(min(N.cp_start_sample)-origin==starts(beam+1) && ...
        min(N.useful_end_sample_exclusive(N.native_symbol_index_from_burst==lastSymbols(beam+1)))-origin==ends(beam+1));
    energy=sixgr.truth.ssbNativeSampleIntervals(N,cfg.phy.carrier);
    intervals=jsondecode(energy.ExecutedSampleIntervalsJSON);
    assert(numel(intervals)==4 && intervals(1).StartSample==origin+starts(beam+1) && ...
        intervals(end).EndSampleExclusive==origin+ends(beam+1));
end
coordinates=sixgr.truth.ssbCandidateCoordinateEvidence(cfg,(0:3)',repmat(origin,4,1),repmat(p.SampleRateHz,4,1));
assert(isequal(coordinates.SSBCandidateCPStartSample,origin+starts') && ...
    isequal(coordinates.SSBCandidateEndSampleExclusive,origin+ends'));
assert(all(native.frequency_first_hz>=-3.75e6) && all(native.frequency_last_hz<=3.42e6));
assert(height(sixgr.truth.deduplicateObservedREAllocation([T;T]))==height(T));
later=sixgr.phy.waveform.WaveformObservationBuffer(origin+p.SampleRateHz*.02, ...
    origin+p.SampleRateHz*.02+p.NumSamples,p.SampleRateHz,size(p.TransmitSamples,2));
later.append(sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,later.StartSample),p.SampleRateHz);
localReject(@()sixgr.truth.buildObservedSSBNativeAllocation(p,later,1), ...
    'sixgr:truth:BroadcastGridOriginMismatch');
localReject(@()sixgr.truth.buildObservedBroadcastREAllocation(p,later,1), ...
    'sixgr:truth:BroadcastGridOriginMismatch');
% Publish and verify this actual frame before allocating the later native
% waveform. Only compact original identities/counts survive the handoff.
originalIDs=unique(string(T.allocation_id));
originalRows=height(native); originalRE=nnz(grid);
originalPath=localPublish(T,cfg,folder,height(common),originalRows,originalRE);
assert(o.sampleHash()==sixgr.phy.waveform.WaveformHash.runtimeArray(p.TransmitSamples));
clear p grid o T common prach native bad later planned checks commonPlan prachPlan ssbPlan N
% A genuinely new native broadcast can cross the SFN wrap, but old bytes
% cannot be relocated to claim that transmission. Preserve exact native
% and carrier clock domains at one common physical origin.
wrapped=sixgr.link.prepareCellSearchBroadcast(cfg,true,'RuntimeSlot',1024*10);
wo=sixgr.phy.waveform.WaveformObservationBuffer(wrapped.BroadcastStartSample, ...
    wrapped.BroadcastStartSample+wrapped.NumSamples,wrapped.SampleRateHz,size(wrapped.TransmitSamples,2));
wo.append(sixgr.phy.waveform.WaveformChunk(wrapped.TransmitSamples,wo.StartSample),wrapped.SampleRateHz);
wrappedRows=sixgr.truth.buildObservedBroadcastREAllocation(wrapped,wo,1);
[wrappedCommon,~,wrappedNative]=sixgr.truth.splitREAllocationDomains(wrappedRows);
assert(~isempty(wrappedCommon) && ~isempty(wrappedNative) && ...
    all(wrappedCommon.sfn==0) && all(wrappedNative.sfn==0) && ...
    all(wrappedCommon.absolute_slot>=1024*10) && ...
    all(wrappedNative.native_absolute_slot0>=1024*20) && ...
    all(wrappedNative.carrier_origin_slot0==1024*10) && ...
    sum(wrappedNative.native_mapped_re_count)==nnz(wrapped.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid));
assert(isempty(intersect(unique(string(wrappedRows.allocation_id)),originalIDs)));
wrappedPath=localPublish(wrappedRows,cfg,fullfile(folder,'frame1024'), ...
    height(wrappedCommon),height(wrappedNative), ...
    nnz(wrapped.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid));
assert(wo.sampleHash()==sixgr.phy.waveform.WaveformHash.runtimeArray(wrapped.TransmitSamples));
fprintf('MIXED_SSB_NATIVE_RESOURCE_PASS original_rows=%d native_RE=%d CSV=%s wrapped_CSV=%s\n', ...
    originalRows,originalRE,originalPath,wrappedPath);
ok=true;
end

function path=localPublish(T,cfg,folder,commonCount,nativeCount,nativeRE)
layout=sixgr.report.resultLayout(folder);
[written,prach,writtenNative]=sixgr.truth.writeObservedREAllocationArtifacts(T,cfg,layout);
assert(isempty(prach) && height(written)==commonCount && height(writtenNative)==nativeCount);
path=fullfile(layout.ComponentCSVDirs.frame_grid,'observed_ssb_native_allocation.csv');
saved=sixgr.util.csvReadTable(path,'TextType','string');
assert(height(saved)==nativeCount && ~ismember('absolute_slot',saved.Properties.VariableNames) && ...
    all(saved.grid_domain=="ssb_native_cp_ofdm") && ...
    sum(saved.native_mapped_re_count)==nativeRE && all(string(saved.ConfigHash)==string(cfg.meta.configHash)));
nativeColumns=["native_absolute_slot0","carrier_origin_slot0","sfn","slot_within_frame", ...
    "native_symbol_index","native_subcarrier_start","native_subcarrier_count", ...
    "port_index","native_mapped_re_count","cp_start_sample","useful_start_sample", ...
    "useful_end_sample_exclusive"];
for name=nativeColumns
    assert(isequal(saved.(name),writtenNative.(name)), ...
        'Native SSB CSV changed original %s.',name);
end
assert(isequal(string(saved.allocation_id),string(writtenNative.allocation_id)) && ...
    isequal(string(saved.transmit_grid_sha256),string(writtenNative.transmit_grid_sha256)) && ...
    sixgr.util.sha256File(path)==sixgr.util.sha256File( ...
    fullfile(layout.ReportCSVDir,'live_ssb_native_allocation_snapshot.csv')));
carrierPath=fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_allocation.csv');
savedCarrier=sixgr.util.csvReadTable(carrierPath,'TextType','string');
for name=["absolute_slot","sfn","slot_within_frame","symbol_index", ...
        "subcarrier_start","subcarrier_count","port_index","re_count"]
    assert(isequal(savedCarrier.(name),written.(name)), ...
        'Carrier SIB1 CSV changed original %s.',name);
end
assert(sixgr.util.sha256File(carrierPath)==sixgr.util.sha256File( ...
    fullfile(layout.ReportCSVDir,'live_re_allocation_snapshot.csv')));
end

function localReject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Unexpected failure: %s %s',cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
