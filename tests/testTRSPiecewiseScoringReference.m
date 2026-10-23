function ok=testTRSPiecewiseScoringReference()
% Native TRS IQ -> executed piecewise operator -> post-estimation scoring.
% Declared noiseless component boundary: no shared RF/thermal-noise owner,
% connected scheduling, statistical performance or full-scenario claim.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
% This component declares two complete tracking bursts and a varying lab
% operator. Use the general practical estimator, not the static-AWGN
% shortcut whose shared execution eligibility is a separate contract.
cfg.phy.trs.slotNumbers=0:3;
cfg.phy.trs.burstLengthSlots=2;
% Four slots contain eight distinct tracking resources (two per slot).
% Expanding the bounded capture must also declare its complete ID catalog;
% the inherited two-slot catalog must not be silently repeated or discarded.
resourceIDs=[11 13 17 19 23 29 31 37];
cfg.lls6g.reference_signals.trs.resource_ids=resourceIDs;
cfg.phy.trs.runtimeChannelEstimator="nr_channel_estimate";
cfg.phy.trs.detectionPolicy="fixed_correlation";
cfg.channel.awgnSpatialMatrixDL=[1 .2i .3 0;0 .4 0 .8i];
cfg.channel.awgnBeamFailureMatrixDL=[0 .7 .1i 0;.2i 0 .9 0];
cfg.channel.awgnBeamFailureStartSlot=1;
cfg.channel.awgnBeamFailureEndSlotExclusive=3;
cfg.channel.awgnBeamFailureRecoveryEnabled=true;
p=sixgr.link.prepareTRSTransmission(cfg,-10);
assert(isequal(p.Tx.SlotTable.Slot(:).',0:3) && size(p.TransmitSamples,2)==1);
mapping=unique(p.Tx.ResourceMappingTable(:, ...
    {'Slot','CSIRSResourceWithinSlot0Based','NZPCSIRSResourceID'}),'rows','stable');
assert(isequal(p.StrictConfig.NZPCSIRSResourceIDs,resourceIDs) && ...
    height(mapping)==8 && isequal(mapping.Slot,repelem((0:3).',2)) && ...
    isequal(mapping.CSIRSResourceWithinSlot0Based,repmat([0;1],4,1)) && ...
    isequal(mapping.NZPCSIRSResourceID,resourceIDs.'), ...
    'Declared IDs must bind each actual native tracking resource exactly once.');
array=sixgr.rf.AntennaArrayFactory.build(p.ReceiverConfig,'bs', ...
    'signal','trs','numPorts',1);
W=array.PortToElementMatrix;
assert(isequal(size(W),[4 1]));
p.TransmitStartSample=0;
p.TransmitProjectionMatrix=W;
x=p.TransmitSamples*W.';
initial=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL', ...
    'UEIndex',1,'ServingCell',1);
initial.TargetUEIndex=1; initial.TargetServingCell=1;
initial=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    initial,cfg,zeros(1,4),p.TxInfo,'NumTxAnt',4,'NumRxAnt',2);
[received,replay,state,reference]=localApply(initial,x);
% Use the actual loss-stage receipt expected by the reference adapter.
% This explicit AWGN fixture has unit loss; RF/noise execution remains out
% of scope rather than being manufactured from a channel-only replay.
[receivedAfterLoss,lossReplay]=sixgr.link.applyWaveformImpairments( ...
    received,p.ReceiverConfig,p.SampleRateHz,'ApplyRFChain',false);
assert(lossReplay.AppliedLargeScaleAmplitudeGain==1 && ...
    isequal(receivedAfterLoss,received));
a=initial.Meta.BeamFailureStartSample;
b=initial.Meta.BeamFailureEndSampleExclusive;
n=size(x,1);
assert(0<a && a<b && b<n && ...
    a==p.Tx.SlotTable.StartSample1Based(2)-1 && ...
    b==p.Tx.SlotTable.StartSample1Based(4)-1);
expected=x*cfg.channel.awgnSpatialMatrixDL.';
expected(a+1:b,:)=x(a+1:b,:)*cfg.channel.awgnBeamFailureMatrixDL.';
assert(localSame(received,expected) && state.CurrentSampleIndex==n && ...
    reference.Source=="executed_piecewise_matrix_AWGN_operator" && ...
    sixgr.channel.isAppliedChannelReference(reference) && ...
    numel(reference.OperatorSegments)==3 && ~isfield(reference,'SpatialMatrix'));
assert(string(replay.RuntimeChannelOutputWaveformSHA256)== ...
    string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(received)) && ...
    string(replay.AppliedAWGNSpatialMatrixSHA256)== ...
    string(reference.AppliedAWGNSpatialMatrixSHA256));

% Only actual received IQ and configured pilots enter these practical APIs.
% The retained channel coefficients are not attached to rx or det.
rx=struct('Waveform',received,'NoiseVariance',0, ...
    'InjectedTimingOffset_samples',0,'FaultMode',"normal");
timing=sixgr.phy.trs.estimateTRSTiming(rx,p.StrictConfig,p.Tx);
assert(all(timing.Table.TRSTimingEstimateAvailable));
det=sixgr.phy.trs.detectTRSResources(rx,p.StrictConfig,p.Tx,'Timing',timing);
assert(det.DetectionSuccess && all(det.Table.EstimatedTimingOffset_samples==0), ...
    'This zero-delay positive must acquire its timing from the received TRS.');
ch=sixgr.phy.trs.estimateTRSChannel(rx,p.StrictConfig,p.Tx,det);
assert(ch.EstimateAvailable && ~ch.NMSEScoringAvailable && ...
    ch.HestRxPorts==2 && ch.HestTxPorts==1);
original=ch; originalDet=det; originalTiming=timing;
clock=state.CurrentSampleIndex; randomState=rng;
captures={localCapture(reference)};
[grids,evidence]=sixgr.truth.sharedTRSReferenceGrids(p,captures,lossReplay,det);
source="applied_piecewise_matrix_AWGN_operator_TRS_port_reference";
assert(numel(grids)==4 && all(cellfun(@(e)e.Source==source,evidence)));
for k=1:4
    e=evidence{k}; grid=grids{k};
    H=cfg.channel.awgnSpatialMatrixDL;
    if k==2 || k==3, H=cfg.channel.awgnBeamFailureMatrixDL; end
    response=H*W*double(p.PowerContext.AmplitudeScale)* ...
        10^(double(lossReplay.AppliedLargeScaleGain_dB)/20);
    for r=1:2
        assert(max(abs(grid(:,:,r)-response(r)),[],'all')<1e-12*max(1,abs(response(r))), ...
            'Reference must use the executed episode, original map and scaling.');
    end
    assert(isequal(size(grid),size(ch.ChannelEstimates{k})) && ...
        e.ChannelReferenceSegmentCount==1 && ~e.ReceiverEstimatorInput && ...
        ~e.GainOrPhaseFitted && e.AdditionalChannelExecutions==0 && ...
        ~e.RFImpairmentsIncluded && ...
        e.ReferenceCalculation=="executed_sample_rate_operator_same_symbol_FFT_diagonal");
end
assert(norm(grids{1}(:)-grids{2}(:))>1e-3 && ...
    localSame(grids{1},grids{4}) && localSame(grids{2},grids{3}));
scored=sixgr.phy.trs.scoreTRSChannelEstimates(ch,grids,evidence);
assert(scored.NMSEScoringAvailable && scored.NMSEReferenceSource==source && ...
    all(scored.Table.NMSEScoringAvailable) && ...
    all(scored.Table.ChannelReferenceEnergy>0) && ...
    all(scored.Table.ChannelNMSEQualificationMode== ...
    "independent_complex_pilot_resources_no_gain_or_phase_fit"));
for k=1:4
    metric=sixgr.phy.srs.pilotChannelNMSE( ...
        ch.ChannelEstimates{k},grids{k},ch.PilotIndices{k});
    assert(isequaln(scored.Table.NMSE_dB(k),metric.dB) && ...
        scored.Table.NMSEComparedComplexValues(k)==2*numel(ch.PilotIndices{k}));
end

% Execute the SAME input once on an independent original state, partitioned
% across both episode boundaries. Exact sample coefficients/grid results
% survive processor partitioning; interval signatures need not be equal.
bounds=[0 a-7 a+11 b-9 b+13 n];
splitState=initial; splitCaptures=cell(5,1); chunks=cell(5,1);
for k=1:5
    [chunks{k},partReplay,splitState,part]=localApply( ...
        splitState,x(bounds(k)+1:bounds(k+1),:));
    assert(sixgr.channel.isAppliedChannelReference(part) && ...
        part.OperatorExecutionStartSample==bounds(k) && ...
        part.OperatorExecutionEndSampleExclusive==bounds(k+1) && ...
        part.AppliedAWGNSpatialMatrixSHA256==string(partReplay.AppliedAWGNSpatialMatrixSHA256));
    splitCaptures{k}=localCapture(part);
end
assert(localSame(vertcat(chunks{:}),received) && splitState.CurrentSampleIndex==n);
[splitGrids,splitEvidence]=sixgr.truth.sharedTRSReferenceGrids(p,splitCaptures,lossReplay,det);
for k=1:4
    assert(localSame(splitGrids{k},grids{k}) && ...
        splitEvidence{k}.ChannelReferenceSegmentCount==5);
end
splitScore=sixgr.phy.trs.scoreTRSChannelEstimates(ch,splitGrids,splitEvidence);
assert(isequaln(splitScore.Table.NMSE_dB,scored.Table.NMSE_dB));

% Corrupt actual retained operands/identities, not fabricated oracle grids.
bad=captures; bad{1}.Reference.PathGains(a+1,1,1,1)= ...
    bad{1}.Reference.PathGains(a+1,1,1,1)+.1;
localReject(@()sixgr.truth.sharedTRSReferenceGrids(p,bad,lossReplay,det), ...
    'sixgr:truth:IncompleteTRSChannelScoring');
bad=captures; bad{1}.Reference.OperatorSegments(2).MatrixSHA256=repmat("0",1,64);
localReject(@()sixgr.truth.sharedTRSReferenceGrids(p,bad,lossReplay,det), ...
    'sixgr:truth:IncompleteTRSChannelScoring');
bad=captures; bad{1}.Reference.AppliedAWGNSpatialMatrixSHA256=repmat("0",1,64);
localReject(@()sixgr.truth.sharedTRSReferenceGrids(p,bad,lossReplay,det), ...
    'sixgr:truth:IncompleteTRSChannelScoring');
bad=splitCaptures; bad{2}.RX="other_receiver";
localReject(@()sixgr.truth.sharedTRSReferenceGrids(p,bad,lossReplay,det), ...
    'sixgr:truth:IncompleteTRSChannelScoring');
bad=splitCaptures; bad(3)=[];
localReject(@()sixgr.truth.sharedTRSReferenceGrids(p,bad,lossReplay,det), ...
    'sixgr:truth:IncompleteTRSChannelScoring');
for field=["ReceiverEstimatorInput","GainOrPhaseFitted","AdditionalChannelExecutions"]
    invalid=evidence; invalid{2}.(field)=1;
    localReject(@()sixgr.phy.trs.scoreTRSChannelEstimates(ch,grids,invalid), ...
        'sixgr:phy:trs:InvalidChannelScoringAuthority');
end
badGrids=grids; badGrids{2}=badGrids{2}(:,:,1);
localReject(@()sixgr.phy.trs.scoreTRSChannelEstimates(ch,badGrids,evidence), ...
    'sixgr:srs:ChannelReferenceShapeMismatch');
badGrids=grids; badGrids{2}(ch.PilotIndices{2}(1))=NaN;
localReject(@()sixgr.phy.trs.scoreTRSChannelEstimates(ch,badGrids,evidence), ...
    'sixgr:srs:IncompletePilotChannelReference');
assert(isequaln(ch,original) && isequaln(det,originalDet) && ...
    isequaln(timing,originalTiming) && ...
    isequaln(scored.ChannelEstimates,original.ChannelEstimates) && ...
    state.CurrentSampleIndex==clock && isequal(rng,randomState), ...
    'Post-estimation scoring must not alter RX results, clock or random state.');
fprintf(['TRS_PIECEWISE_SCORING_REFERENCE_PASS native_TRS_slots=4 ' ...
    'actual_operator_segments=3 split_intervals=5 physical_TX=4 RX=2 ' ...
    'receiver_reference_input=0 shared_RF=0 full_scenario=0\n']);
ok=true;
end

function c=localCapture(reference)
c=struct('LinkID',"declared_trs_operator",'TX',"declared_tx", ...
    'RX',"declared_rx",'Reference',reference);
end

function [y,replay,state,reference]=localApply(state,x)
[y,replay,state,reference]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    state,x,'CaptureChannelReference',true,'InputSampleDomain','materialized_channel_ports', ...
    'OutputSampleAlignment','continuous_raw_samples');
end

function localReject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier), ...
        'Expected %s; got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('test:TRSReferenceGuardBypassed','Expected %s.',identifier);
end

function tf=localSame(a,b)
tf=isequal(size(a),size(b)) && ...
    max(abs(a-b),[],'all')<=64*eps(max(1,max(abs(b),[],'all')));
end
