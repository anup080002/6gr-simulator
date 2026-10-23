function [ok,folder,row]=testPiecewiseAWGNChannelReference()
% Actual sample-operator/shared-owner evidence, not a decoded PHY scenario.
% The declared complex rectangular lab operator changes at native slot
% boundaries. No receiver estimate, fading execution or HARQ result is made.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.channel.awgnSpatialMatrixDL=[1 .2i .3 0;0 .4 0 .8i];
cfg.channel.awgnBeamFailureMatrixDL=[0 .7 .1i 0;.2i 0 .9 0];
cfg.channel.awgnBeamFailureStartSlot=1;
cfg.channel.awgnBeamFailureEndSlotExclusive=2;
cfg.channel.awgnBeamFailureRecoveryEnabled=true;
fs=7680000; info=struct('OFDM',struct('SampleRate',fs));
initial=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL', ...
    'UEIndex',1,'ServingCell',1);
initial.TargetUEIndex=1; initial.TargetServingCell=1;
initial=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    initial,cfg,zeros(1,4),info,'NumTxAnt',4,'NumRxAnt',2);
a=initial.Meta.BeamFailureStartSample; b=initial.Meta.BeamFailureEndSampleExclusive;
n=b+29; H0=cfg.channel.awgnSpatialMatrixDL; H1=cfg.channel.awgnBeamFailureMatrixDL;
x=reshape(complex(sin(1:4*n),cos(1:4*n)),n,4);
[y,replay,done,r]=localApply(initial,x);
expected=x*H0.'; expected(a+1:b,:)=x(a+1:b,:)*H1.';
assert(localSame(y,expected) && done.CurrentSampleIndex==n && ...
    string(replay.RuntimeChannelOutputWaveformSHA256)== ...
    string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(y)));
assert(r.Source=="executed_piecewise_matrix_AWGN_operator" && ...
    ~isfield(r,'SpatialMatrix') && sixgr.channel.isAppliedChannelReference(r) && ...
    numel(r.OperatorSegments)==3 && r.OperatorExecutionStartSample==0 && ...
    r.OperatorExecutionEndSampleExclusive==n && ...
    string(r.AppliedAWGNSpatialMatrixSHA256)==string(replay.AppliedAWGNSpatialMatrixSHA256));
% Whole vs split application preserves actual samples and coefficients;
% distinct processor partitions intentionally have distinct signatures.
bounds=[0 a-5 a+17 b-7 b+5 n]; state=initial;
chunks=cell(5,1); refs=chunks; signatures=strings(5,1);
for k=1:5
    [chunks{k},rp,state,refs{k}]=localApply(state,x(bounds(k)+1:bounds(k+1),:));
    assert(sixgr.channel.isAppliedChannelReference(refs{k}) && refs{k}.Source==r.Source);
    assert(rp.RuntimeChannelStartSample==bounds(k) && rp.RuntimeChannelEndSample==bounds(k+1));
    signatures(k)=string(rp.AppliedAWGNSpatialMatrixSHA256);
end
assert(localSame(vertcat(chunks{:}),y) && ...
    isequal(cat(1,refs{1}.PathGains,refs{2}.PathGains,refs{3}.PathGains, ...
    refs{4}.PathGains,refs{5}.PathGains),r.PathGains));
assert(~refs{1}.BeamFailureRecoveryEpisodeActive && ...
    refs{2}.BeamFailureRecoverySegmentCount==2 && ...
    refs{3}.BeamFailureRecoveryEpisodeActive && refs{3}.BeamFailureRecoverySegmentCount==1 && ...
    refs{4}.BeamFailureRecoverySegmentCount==2 && ~refs{5}.BeamFailureRecoveryEpisodeActive && ...
    all(signatures~=r.AppliedAWGNSpatialMatrixSHA256));
cropped=r; lo=a-3; hi=b+4;
cropped.StartSample=lo; cropped.EndSampleExclusive=hi;
cropped.PathGains=r.PathGains(lo+1:hi,:,:,:); cropped.SampleTimes_s=r.SampleTimes_s(lo+1:hi);
cropped.ExecutionStartSample=0; cropped.ExecutionEndSampleExclusive=n;
assert(sixgr.channel.isAppliedChannelReference(cropped) && ...
    sixgr.channel.PiecewiseAWGNReference.matchesReplay(cropped,replay) && ...
    cropped.AppliedAWGNSpatialMatrixSHA256==r.AppliedAWGNSpatialMatrixSHA256);
localPoisons(cropped,replay);
localReject(@()sixgr.channel.IdentityAWGNRuntime.reference(initial,n), ...
    'ChannelFactory:MissingExecutedAWGNSegments');
% Old fixed references retain their original schema and arithmetic.
staticCfg=cfg; staticCfg.channel.awgnBeamFailureRecoveryEnabled=false;
static=sixgr.channel.IdentityAWGNRuntime.materialize(initial,staticCfg,info,4,2);
[sy,~,~,sr]=localApply(static,x(1:21,:));
assert(localSame(sy,x(1:21,:)*H0.') && sr.Source=="executed_fixed_matrix_AWGN_operator" && ...
    isequal(sr.SpatialMatrix,H0) && sixgr.channel.isAppliedChannelReference(sr));
% The same actual owner reverses rectangular complex matrices by .', not '.
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,1);
owner.addTransmitter('gnb',cfg,'DL',4,false); owner.addTransmitter('ue',cfg,'UL',2,false);
owner.addReceiver('ue_rx',cfg,'DL',2,false); owner.addReceiver('gnb_rx',cfg,'UL',4,false);
owner.addLink('piecewise','gnb','ue_rx',initial,cfg);
owner.retargetTDDLink('piecewise','ue','gnb_rx',cfg);
states=owner.channelStates(); ul=states{1};
[uy,~,~,ur]=localApply(ul,x(:,1:2));
uExpected=x(:,1:2)*H0; uExpected(a+1:b,:)=x(a+1:b,1:2)*H1;
assert(localSame(uy,uExpected) && sixgr.channel.isAppliedChannelReference(ur) && ...
    isequal(ur.OperatorSegments(2).Matrix,H1.'));
owner.retargetTDDLink('piecewise','gnb','ue_rx',cfg);
event=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@owner.process,owner);
owner.attach(event,'double'); scoring=owner.registerLinkScoringPlane(event,'piecewise','ue_rx');
first=5; finish=n-5;
owner.requestLinkChannelReference(event,'piecewise','ue_rx',first,finish);
event.enqueue('gnb','declared_operator_samples',sixgr.phy.waveform.WaveformChunk(x,0));
event.commitTransmissionsThrough('gnb',n); event.commitTransmissionsThrough('ue',n);
for plane=["gnb:tx","ue_rx:pre_rf","ue_rx:post_rf",scoring]
    event.observe(plane,'piecewise_observation',first,finish);
end
event.advanceUntilEvent(a-5); event.advanceUntilEvent(a+17);
received=event.advanceUntilEvent(finish);
% This envelope reuses the export API only; the samples are not TRS.
envelope=struct('ExecutionStage',"trs_waveform_prepared_not_received", ...
    'SampleRateHz',fs,'TransmitStartSample',first,'NumSamples',finish-first);
[~,evidence,captures]=sixgr.truth.sharedLinkScoringObservation(received.Completed,envelope,scoring);
assert(evidence.ChannelReferenceCoverageComplete && numel(captures)==3 && ...
    captures{1}.Reference.StartSample==first && captures{1}.Reference.OperatorExecutionStartSample==0);
allGains=cellfun(@(c)c.Reference.PathGains,captures,'UniformOutput',false);
assert(isequal(cat(1,allGains{:}),r.PathGains(first+1:finish,:,:,:)));
bad=received.Completed; idx=find(string({bad.ReceiverID})==scoring);
bad(idx).Segments{1}.Execution.Links(1).Replay.AppliedAWGNSpatialMatrixSHA256=repmat('0',1,64);
localReject(@()sixgr.truth.sharedLinkScoringObservation(bad,envelope,scoring), ...
    'sixgr:truth:SharedOperatorExecutionMismatch');
folder=tempname; mkdir(folder);
[row,~]=sixgr.truth.exportSharedChannelObservation(folder, ...
    table(1,'VariableNames',{'Slot'}),received.Completed,envelope,scoring);
verified=sixgr.channel.validateSharedChannelObservationArtifact(folder,row);
assert(string(verified.Manifest.Source)==r.Source && ...
    verified.Manifest.Segments(1).OperatorExecutionStartSample==0 && ...
    verified.Manifest.Segments(1).StartSample==first && ...
    row.RuntimeChannelAngleEvidenceAvailable==0);
ok=true;
fprintf('PIECEWISE_AWGN_REFERENCE_PASS actual_sample_operator=1 shared_capture=1 cropped=1 decoded_PHY=0 artifact=%s\n',folder);
end

function localPoisons(r,replay)
bad=r; bad.PathGains(1)=bad.PathGains(1)+.1;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.SampleTimes_s(1)=bad.SampleTimes_s(1)+1/r.SampleRateHz;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments(2).Matrix(1)=99;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments(2).MatrixSHA256=repmat("0",1,64);
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments(2).FirstOffset=bad.OperatorSegments(2).FirstOffset+1;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments=bad.OperatorSegments([2 1 3]);
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorExecutionStartSample=1;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.AppliedAWGNSpatialMatrixSHA256="wrong";
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.SpatialMatrix=bad.OperatorSegments(1).Matrix;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.ReceiverEstimatorInput=true;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.NumTransmitAntennas=[4 4];
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments(2).FirstOffset="invalid_index";
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments(2).EndOffsetExclusive=NaN;
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments(2).Matrix="not_numeric";
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.OperatorSegments(2).MatrixSHA256=struct('not','a_hash');
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.SampleRateHz="not_numeric";
assert(~sixgr.channel.isAppliedChannelReference(bad));
bad=r; bad.StateKey=struct('not','a_key');
assert(~sixgr.channel.isAppliedChannelReference(bad));
assert(~sixgr.channel.PiecewiseAWGNReference.blockValid(r,r.PathGains,{.5,1,1,1}));
assert(~sixgr.channel.PiecewiseAWGNReference.blockValid(r,r.PathGains,1));
badReplay=replay; badReplay.RuntimeChannelEndSample=badReplay.RuntimeChannelEndSample-1;
assert(~sixgr.channel.PiecewiseAWGNReference.matchesReplay(r,badReplay));
end

function [y,replay,state,r]=localApply(state,x)
[y,replay,state,r]=sixgr.channel.ChannelFactory.applyRuntimeChannelState(state,x, ...
    'CaptureChannelReference',true,'InputSampleDomain','materialized_channel_ports', ...
    'OutputSampleAlignment','continuous_raw_samples');
end

function localReject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end

function tf=localSame(a,b)
% BLAS call partitioning may change floating-point summation order, not H.
tf=isequal(size(a),size(b)) && max(abs(a-b),[],'all')<=64*eps(max(1,max(abs(b),[],'all')));
end
