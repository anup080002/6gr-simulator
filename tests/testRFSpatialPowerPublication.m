function ok=testRFSpatialPowerPublication()
% Actual RF samples -> spatial second moment -> lossless CSV -> readback.
% This verifies internal RF power evidence, NOT radiated TRP/EIRP.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','validation','rf_spatial_power', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root); air=fullfile(root,'air_interface'); mkdir(air);
fprintf('RF_SPATIAL_POWER_EVIDENCE=%s\n',root);
fs=30.72e6; epoch=1;
inventory=table("gnb_1","TX","DL",4, ...
    'VariableNames',{'EndpointID','Role','Direction','PhysicalPortCount'});
cfg=struct(); cfg.rf.pa.enable=true; cfg.rf.pa.method='rapp';
cfg.rf.pa.backoff_dB=0;
% The retained streaming owner requires an explicit supported PA contract.
% This is a declared numerical fixture, not calibrated hardware evidence.
cfg.rf.specification.profile_id='rf_impaired_research';
cfg.rf.frontend.pa=struct('profile_id','spatial_power_test_rapp', ...
    'model','rapp','version','1.0.0','reference_domain','sqrt_mW', ...
    'input_backoff_db',0,'smoothness',2,'saturation_amplitude',0.5);
cfg.rf.txSpatialPowerEnabled=true;
cfg.meta.configHash=repmat('b',1,64); cfg.run.executionID='spatial_power_fixture';
cfg.run.scenarioID='spatial_power_fixture'; cfg.run.runTag='spatial_power_fixture';
owner=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,4,0,epoch,false);
ledger=sixgr.truth.RFEndpointExecutionLedger(fs,0,epoch,inventory);
clock=0; waves=cell(3,1);
prior=rng;
for step=1:3
    n=19+step;
    x=(.4+exp(1i*(1:n)'*.17))*[.3 .5i -.1 .2*exp(.7i)];
    if step==2, x(:)=0; end
    rf=owner.apply(sixgr.phy.waveform.WaveformChunk(x,clock),epoch);
    waves{step}=rf.Waveform;
    rf.Replay.WaveformAmplitudeUnit='sqrt_mW';
    rf.Replay.TXSpatialPowerEnabled=true;
    rf.Replay.TXSpatialPower=sixgr.rf.measurePhysicalTXSpatialPower(rf.Waveform);
    expected=zeros(4);
    for i=1:n
        v=rf.Waveform(i,:).'; expected=expected+v*v';
    end
    expected=expected/n;
    measured=rf.Replay.TXSpatialPower.SecondMoment;
    assert(norm(measured-expected,'fro')<1e-13, ...
        'test:SpatialPowerOrientation','Keep the complex coherent cross terms, not conjugated or centered covariance.');
    execution=struct('StartSample',clock,'EndSampleExclusive',clock+n, ...
        'TX',struct('ID',"gnb_1",'Replay',rf.Replay), ...
        'RX',struct('ID',{},'Replay',{}));
    ledger.append(execution); clock=clock+n;
end
assert(isequal(prior,rng),'Power measurement/publication must not draw random values.');
e=ledger.read(); assert(e.TXSpatialPowerCompleteFromOrigin && height(e.TXSpatialPowerIntervals)==3);
save(fullfile(root,'actual_rf_output.mat'),'waves','cfg','e','-v7');
published=sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct('RFEndpointExecutionEvidence',e));
assert(isfield(published,'TXSpatialPowerCSV') && isfile(published.TXSpatialPowerCSV), ...
    'test:MissingSpatialPowerCSV','Enabled measured spatial power needs a dedicated immutable CSV binding.');
read=sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct());
assert(read.Evidence.TXSpatialPowerCompleteFromOrigin && ...
    isequaln(published.Evidence.TXSpatialPowerIntervals,read.Evidence.TXSpatialPowerIntervals));
for k=1:3
    row=read.Evidence.TXSpatialPowerIntervals(k,:);
    matrix=sixgr.runtime.RawCSVArrayCodec.decode(row.SecondMomentArray);
    original=e.TXSpatialPowerIntervals(k,:);
    assert(isequal(matrix,sixgr.runtime.RawCSVArrayCodec.decode(original.SecondMomentArray)) && ...
        row.TXWaveformSHA256==sixgr.rf.waveformSHA256(waves{k}) && ...
        ~row.RadiatedPowerQualified);
end
meta=sixgr.util.jsonRead(published.Manifest);
assert(~isfield(meta,'TXSpatialPowerIntervals') && ...
    string(meta.TXSpatialPowerFileSHA256)==sixgr.util.sha256File(published.TXSpatialPowerCSV));
changed=read.Evidence.TXSpatialPowerIntervals; changed.TotalMeanSquare(1)=42;
sixgr.util.csvWriteTable(published.TXSpatialPowerCSV,changed,'PreserveSchema',true);
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct()), ...
    'sixgr:truth:TXSpatialPowerFileHash');
sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct('RFEndpointExecutionEvidence',e));
wrong=cfg; wrong.run.executionID='other';
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(wrong,air,struct()), ...
    'sixgr:truth:RFExecutionFileScope');
% Missing samples cannot be repaired using diagonal chain powers.
bad=e; bad.TXSpatialPowerIntervals=bad.TXSpatialPowerIntervals(1:2,:);
bad.TXSpatialPowerCompleteFromOrigin=true;
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct('RFEndpointExecutionEvidence',bad)), ...
    'sixgr:truth:TXSpatialPowerCompleteness');
% Preserve final valid artifacts after the deliberately corrupted fixtures.
sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct('RFEndpointExecutionEvidence',e));
fprintf('RF_SPATIAL_POWER_PUBLICATION_PASS intervals=3 exact_matrix_bytes=1 hash_scope_guards=1 TRP_qualified=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s got %s: %s',id,ex.identifier,ex.message); return; end
error('test:SpatialPowerExpectedRejection','Expected %s.',id);
end
