function ok=testMixedSSBNativeResources()
% Actual mixed broadcast producer/clock/CSV checks, not channel qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_n40_ssb30_common15_regression.yaml');
folder=tempname; cfg=sixgr.lls6g.buildInternalConfig(s,folder);
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
p=sixgr.link.prepareCellSearchBroadcast(cfg,true);
origin=sixgr.phy.frame.slotStartSample(p.Tx.Carrier,20,p.SampleRateHz);
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
    all(native.sfn==floor(native.native_absolute_slot0/20)));
assert(all(native.emitted_symbol_count==252) && all(native.grid_symbol_count==280), ...
    'The 9-ms emitted waveform must not acquire the Toolbox grid''s zero frame padding.');
bad=p;
bad.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid(1,280,1)=1;
bad.Tx.SSBWaveInfo.ResourceGridSSBurst.ResourceGrid(1,280)=1;
localReject(@()sixgr.truth.buildObservedSSBNativeAllocation(bad,o,1), ...
    'sixgr:truth:SSBNativeSampleClockMismatch');
bad=p; bad.Tx.SSBWaveform=bad.Tx.SSBWaveform(1:end-1,:);
localReject(@()sixgr.truth.buildObservedSSBNativeAllocation(bad,o,1), ...
    'sixgr:truth:SSBNativeSampleClockMismatch');
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
other=sixgr.truth.buildObservedSSBNativeAllocation(p,later,1);
assert(isempty(intersect(unique(string(other.allocation_id)),unique(string(T.allocation_id)))));
layout=sixgr.report.resultLayout(folder);
[written,~,writtenNative]=sixgr.truth.writeObservedREAllocationArtifacts(T,cfg,layout);
assert(height(written)==height(common) && height(writtenNative)==height(native));
path=fullfile(layout.ComponentCSVDirs.frame_grid,'observed_ssb_native_allocation.csv');
saved=sixgr.util.csvReadTable(path,'TextType','string');
assert(height(saved)==height(native) && ~ismember('absolute_slot',saved.Properties.VariableNames) && ...
    all(saved.grid_domain=="ssb_native_cp_ofdm") && ...
    sum(saved.native_mapped_re_count)==nnz(grid) && all(string(saved.ConfigHash)==string(s.ConfigHash)));
assert(sixgr.util.sha256File(path)==sixgr.util.sha256File( ...
    fullfile(layout.ReportCSVDir,'live_ssb_native_allocation_snapshot.csv')));
fprintf('MIXED_SSB_NATIVE_RESOURCE_PASS rows=%d native_RE=%d CSV=%s\n',height(native),nnz(grid),path);
ok=true;
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
