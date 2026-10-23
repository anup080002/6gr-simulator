function ok=testSSBNativeEnergyIntervals()
% Deterministic accounting fixture; not a physical receiver qualification.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier.NSizeGrid=106; cfg.phy.carrier.SubcarrierSpacing=15;
cfg.phy.ssb.scs_kHz=30; cfg.meta.configHash="native_ssb_accounting_fixture";
N=localNative(cfg.meta.configHash);
e=sixgr.truth.ssbNativeSampleIntervals(N,cfg.phy.carrier);
v=jsondecode(e.ExecutedSampleIntervalsJSON);
assert(numel(v)==4 && sum([v.EndSampleExclusive]-[v.StartSample])==4384 && ...
    v(1).StartSample==614400+2208 && v(end).EndSampleExclusive==614400+6592);
assert(isequal(reshape(v(2).CarrierPRBIntersectionSet0Based,1,[]),32:72), ...
    'Native 7.2-MHz bin envelope must intersect the common carrier PRBs, not reuse native PRB indices.');
T=table("native_ssb_accounting_fixture",1,1,21,0,NaN,0,614400,890880,30720000, ...
    'VariableNames',{'ConfigHash','CellID','UEIndex','Slot','RequestedSSBOccasionIndex', ...
    'SSBIndex','CRCPass','ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz'});
hash=string(repmat('b',1,64));
[bound,a]=sixgr.truth.bindSSBNativeResourcesToTrials(T,cfg,N,cfg.meta.configHash,hash);
assert(a.NativeRows==height(N) && bound.CRCPass==0 && isnan(bound.SSBIndex), ...
    'Failed PBCH reception still consumes its monitored transmitted SSB; no decoded beam may be invented.');
expanded=sixgr.truth.expandExecutedSampleIntervals(bound,cfg);
assert(height(expanded)==4 && all(expanded.CRCPass==0) && ...
    all(expanded.EnergyIntervalSampleRateHz==30720000) && ...
    sum(expanded.EnergyIntervalEndSampleExclusive-expanded.EnergyIntervalStartSample)==4384);
wrong=T; wrong.ObservationStartSample=wrong.ObservationStartSample+1;
[~,a]=sixgr.truth.bindSSBNativeResourcesToTrials(wrong,cfg,N,cfg.meta.configHash,hash);
assert(a.NativeRows==0,'Do not attach a nearby burst to a receiver trial.');
wrong=T; wrong.RequestedSSBOccasionIndex=NaN; wrong.SSBIndex=0;
[~,a]=sixgr.truth.bindSSBNativeResourcesToTrials(wrong,cfg,N,cfg.meta.configHash,hash);
assert(a.NativeRows==0,'Decoded identity cannot replace missing monitored-occasion identity.');
bad=N; bad.useful_end_sample_exclusive(1)=bad.useful_end_sample_exclusive(1)+1;
localReject(@()sixgr.truth.ssbNativeSampleIntervals(bad,cfg.phy.carrier),'sixgr:truth:SSBIntervalClock');
bad=N; bad.frequency_last_hz(1)=bad.frequency_last_hz(1)+15000;
localReject(@()sixgr.truth.ssbNativeSampleIntervals(bad,cfg.phy.carrier),'sixgr:truth:SSBIntervalFrequency');
bad=N; bad.ConfigHash(:)="different";
localReject(@()sixgr.truth.bindSSBNativeResourcesToTrials(T,cfg,bad,cfg.meta.configHash,hash), ...
    'sixgr:truth:SSBBindingAuthority');
bad=N; bad.evidence_scope(:)="planned_config_not_runtime_observation";
localReject(@()sixgr.truth.ssbNativeSampleIntervals(bad,cfg.phy.carrier),'sixgr:truth:SSBIntervalAuthority');
% A native-only retained snapshot must load even before a carrier-grid CSV
% exists. This tests I/O wiring, not completeness of the whole simulation.
folder=tempname; layout=sixgr.report.resultLayout(folder);
path=fullfile(layout.ComponentCSVDirs.frame_grid,'observed_ssb_native_allocation.csv');
sixgr.util.csvWriteTable(path,N);
[loaded,~,audit]=sixgr.truth.loadLLSEnergyResourceEvidence(cfg,fullfile(folder,'air_interface'),struct('PBCH',T));
assert(isempty(loaded.Intervals) && isequaln(loaded.NativeSSB,N) && audit.ResourceLedgerAvailable && ...
    loaded.NativeSSBSourceSHA256==sixgr.util.sha256File(path));
fprintf('NATIVE_SSB_ENERGY_INTERVALS_PASS: 4 native symbols, 4384 samples, exact capture/beam join; negative guards pass.\n');
ok=true;
end

function N=localNative(configHash)
% Union of the actual SS/PBCH support: 127+240+(48+127+48)+240=830 RE.
coords=[2 56 127;3 0 240;4 0 48;4 56 127;4 192 48;5 0 240];
coords=[coords;coords]; n=size(coords,1);
N=table();
N.channel=repmat("SSB",n,1); N.grid_domain=repmat("ssb_native_cp_ofdm",n,1);
N.evidence_scope=repmat("runtime_observed_tx_occupancy",n,1); N.active_flag=ones(n,1);
N.allocation_id=repmat("ssb_cell_1_burst_20_index_0_cycle_0",n,1);
N.native_symbol_index_from_burst=coords(:,1); N.native_subcarrier_start=coords(:,2);
N.native_subcarrier_count=coords(:,3); N.grid_subcarrier_spacing_hz=repmat(30000,n,1);
N.grid_subcarrier_count=repmat(240,n,1); N.grid_symbol_count=repmat(280,n,1);
N.observation_sample_rate_hz=repmat(30720000,n,1);
N.cp_start_sample=614400+2208+(coords(:,1)-2)*1096;
N.useful_start_sample=N.cp_start_sample+72;
N.useful_end_sample_exclusive=N.useful_start_sample+1024;
N.broadcast_start_sample=repmat(614400,n,1); N.broadcast_end_sample_exclusive=repmat(890880,n,1);
N.frequency_first_hz=-3750000+coords(:,2)*30000;
N.frequency_last_hz=N.frequency_first_hz+(coords(:,3)-1)*30000;
N.transmit_grid_sha256=repmat(string(repmat('a',1,64)),n,1);
N.ssb_index0=zeros(n,1); N.cell_id=ones(n,1); N.port_index=[zeros(6,1);ones(6,1)];
N.ConfigHash=repmat(configHash,n,1);
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
