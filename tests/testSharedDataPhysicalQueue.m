function [ok,state]=testSharedDataPhysicalQueue(mode)
% Actual coded DL through the same CDL/RF/thermal-noise owner as PDCCH.
% No access or main-scheduler qualification is claimed by this fixture.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
assert(any(string(mode)==["TDD","FDD"]),'test:BadDuplexFixture','Use an explicit duplex fixture.');
fixture='lls_pdcch_shared_queue_fixture.yaml';
if string(mode)=="FDD", fixture='lls_trs_shared_scoring_fdd_fixture.yaml'; end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios',fixture));
[~,captureID]=fileparts(tempname);
captureRoot=fullfile(pwd,'logs','shared_data_receive_tail',captureID);
cfg=sixgr.lls6g.buildInternalConfig(s,captureRoot);
cfg.run.rootRunFolder=captureRoot;
% Explicit component capture policy: the RX tail must not grow the fixed
% scheduled TX stream or alter its bytes/slot accounting.
cfg.outputs.continuousRawIQCaptureEnabled=true;
% This fixture validates the shared data queue in isolation.  Common DL
% scheduling collisions are covered separately; do not request a PDSCH in
% the configured slot-0 SS/PBCH rectangle.
cfg.phy.ssb.enable=false;
cfg.phy.sib1.enable=false;
cfg.phy.trs.enable=false;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),2);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,1);
dl=sixgr.util.structSet(dl,'lls6g.userContext.RuntimeSlotStartTime_s',0);
grant=sixgr.link.resolveWaveformGrant(dl,'DL',1,'Slot',1,'SFN',0,'ControlAbsoluteSlot',0);
allocated=state.DLHarq.allocate(grant.RNTI,1,grant.TBSBits/8,'NewData',true);
assert(allocated.HARQ.HarqID==grant.HARQ.HarqID && allocated.HARQ.NDI==grant.HARQ.NDI);
grant.ControlDecodeOk=false; grant.PDCCHGrantBindingOk=false;
context=struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true);
job=sixgr.truth.buildGrantPHYJob(dl,'DL',cfg.channel.snr_dB,1,[],context);
job.StartSlotIndex=1;
result=sixgr.truth.executeGrantPHYJob(job);
p=result.Result.PreparedTransmission;
assert(~result.ReadyForReceiverCommit && isempty(result.Result.TrialTable));
before=owner.Events.NextSampleIndex;
owner.queueData(1,p,struct('Purpose',"physical_queue_not_control_qualification"));
assert(owner.Events.NextSampleIndex==before && owner.hasPending('PDSCH',1));
assert(isempty(owner.DataTransmissions),'Enqueueing is not transmission.');
if cfg.outputs.antennaPatternSamplesEnabled
    localReject(@()sixgr.truth.buildExecutedDataPrecoderEvidence(owner,p,1), ...
        'sixgr:truth:PrecoderTransmissionNotExecuted');
end
localReject(@()owner.queueData(1,p,struct()),'sixgr:truth:DuplicatePendingData');
% A second same-UE grant can be enqueued before the first RX tail ends.
% Preserve the exact new slot/grant identity, not a duplicated TB record.
dl2=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,2);
dl2=sixgr.util.structSet(dl2,'lls6g.userContext.RuntimeSlotStartTime_s',p.EndSampleExclusive/p.SampleRateHz);
g2=sixgr.link.resolveWaveformGrant(dl2,'DL',1,'Slot',2,'SFN',0,'ControlAbsoluteSlot',1);
allocated2=state.DLHarq.allocate(g2.RNTI,2,g2.TBSBits/8,'NewData',true);
g2=sixgr.link.resolveWaveformGrant(dl2,'DL',1,'Slot',2,'SFN',0,'ControlAbsoluteSlot',1,'HARQProcess',allocated2.HARQ.HarqID);
assert(allocated2.HARQ.NDI==g2.HARQ.NDI);
g2.ControlDecodeOk=false; g2.PDCCHGrantBindingOk=false;
j2=sixgr.truth.buildGrantPHYJob(dl2,'DL',cfg.channel.snr_dB,1,[], ...
    struct('GrantSnapshot',g2,'PHYGrant',g2.PHYGrant,'PrepareOnly',true));
j2.StartSlotIndex=2;
r2=sixgr.truth.executeGrantPHYJob(j2); p2=r2.Result.PreparedTransmission;
owner.queueData(1,p2,struct('Purpose',"adjacent_grant_receive_tail_overlap"));
assert(numel(owner.Pending)==2 && isempty(owner.DataTransmissions));
state.DLQueueBits(1)=grant.TBSBits+g2.TBSBits; % Explicit fixture queue, not a measured application flow.
assert(state.DLHarq.Stats.Tx==0);
[state,~]=owner.advanceSlot(state,cfg,@localReceive);
firstSlotEnd=owner.Events.NextSampleIndex;
localReject(@()owner.drainDataReceiveTail(state,cfg,@localReceive), ...
    'sixgr:truth:ReceiveTailContainsFutureDataTX');
assert(owner.Events.NextSampleIndex==firstSlotEnd && state.DLHarq.Stats.Tx==1, ...
    'Reject future scheduled transmissions before advancing any tail samples.');
state.CurrentSlot=2;
[state,~]=owner.advanceSlot(state,cfg,@localReceive);
assert(owner.hasPending('PDSCH',1),'test:MissingReceiveTail', ...
    'The final coded allocation must reproduce a real receive tail beyond the scheduling horizon.');
tailStart=owner.Events.NextSampleIndex;
channel=owner.channelState(1,'DL');
expectedTailEnd=p2.ReceiveEndSampleExclusive+double(channel.ChannelPadSamples);
[state,tailCompleted]=owner.drainDataReceiveTail(state,cfg,@localReceive);
assert(state.CurrentSlot==2 && owner.Events.NextSampleIndex==expectedTailEnd && ...
    expectedTailEnd>tailStart && ...
    state.SharedReceiveTailTable.StartSample==tailStart && ...
    state.SharedReceiveTailTable.EndSampleExclusive==expectedTailEnd && ...
    all(string({tailCompleted.Kind})=="PDSCH"), ...
    'Only actual receive-tail samples may extend physical time; no extra scheduled slot or TB.');
[state,repeated]=owner.drainDataReceiveTail(state,cfg,@localReceive);
assert(isempty(repeated) && owner.Events.NextSampleIndex==expectedTailEnd, ...
    'Repeated finalization must not execute RF or duplicate received results.');
capture=owner.finalizeContinuousTxIQCapture(tailStart,2);
assert(capture.Ok && all(capture.ManifestTable.SampleCountPerPort==tailStart) && ...
    all(capture.ManifestTable.SchedulerSlotCount==2) && ...
    all(capture.ManifestTable.SegmentCount==2), ...
    'The exact continuous TX capture must end at the scheduling boundary, not the RX tail.');
sixgr.util.csvWriteTable(fullfile(captureRoot,'receive_tail.csv'),state.SharedReceiveTailTable);
disp("RECEIVE_TAIL_COMPONENT_EVIDENCE: "+captureRoot);
assert(~owner.hasPending('PDSCH',1) && state.TestDataObservationCompleted);
assert(numel(owner.DataTransmissions)==2 && state.TestDataTXCount==2 && state.TestDataRXCount==2);
assert(state.DLHarq.Stats.Tx==2 && state.DLQueueBits(1)==0 && numel(state.SharedDataTXLedger)==2);
assert(owner.DataTransmissions(1).Identity.TransmissionID~=owner.DataTransmissions(2).Identity.TransmissionID);
localReject(@()owner.queueData(1,p,struct()),'sixgr:truth:LateSharedDataPreparation');
fprintf('SHARED_DATA_PHYSICAL_QUEUE_PASS: %s TX=[%d,%d) RX=[%d,%d), no decode claimed.\n', ...
    mode,state.TestDataIntervals);
ok=true;
end

function state=localReceive(state,items)
for item=items
    if item.Kind=="DataTX"
        records=state.SharedWaveformStream.DataTransmissions;
        hit=arrayfun(@(r)r.Identity.TransmissionID==item.Context.TransmissionIdentity.TransmissionID,records);
        assert(nnz(hit)==1 && records(hit).CommittedAtSample==item.Context.FirstActiveSample+1);
        assert(state.SharedWaveformStream.Events.NextSampleIndex==records(hit).CommittedAtSample);
        queueBefore=state.DLQueueBits(1); txBefore=state.DLHarq.Stats.Tx;
        state=sixgr.truth.commitSharedDataTransmission(state,item);
        assert(state.DLHarq.Stats.Tx==txBefore+1 && ...
            state.DLQueueBits(1)==queueBefore-numel(item.Context.Prepared.Tx.TransportBlock));
        localReject(@()sixgr.truth.commitSharedDataTransmission(state,item), ...
            'sixgr:truth:DuplicateSharedDataTXCommit');
        assert(state.DLHarq.Stats.Tx==txBefore+1);
        state.TestDataTXCount=sixgr.util.structGet(state,'TestDataTXCount',0)+1;
        continue;
    end
    assert(item.Kind=="PDSCH");
    p=item.Context.Prepared;
    [post,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
    originalReplay=replay;
    [~,~,channelReferences]=sixgr.truth.sharedLinkScoringObservation( ...
        item.Planes,p,item.Context.DesiredReferencePlane);
    assert(~isempty(channelReferences),'test:MissingDataChannelCapture', ...
        'Each data observation needs its own same-execution channel coefficients.');
    bounds=cell2mat(cellfun(@(c)[c.Reference.StartSample c.Reference.EndSampleExclusive], ...
        channelReferences,'UniformOutput',false));
    assert(bounds(1,1)==post.StartSample && bounds(end,2)==post.EndSampleExclusive && ...
        all(bounds(2:end,1)==bounds(1:end-1,2)), ...
        'Overlapping data tails must have exact, nonduplicated coefficient coverage.');
    for capture=channelReferences.'
        r=capture{1}.Reference;
        assert(r.ObservationStartSample==post.StartSample && ...
            r.ObservationEndSampleExclusive==post.EndSampleExclusive && ...
            r.NumTransmitAntennas==p.NumPhysicalTransmitAntennas && ...
            r.NumReceiveAntennas==post.NumReceiveAntennas && ...
            ~r.ReceiverEstimatorInput && r.AdditionalChannelExecutions==0);
    end
    assert(all(cellfun(@(s)~isfield(s.Execution,'ChannelReferences'), ...
        replay.ReceiveStreamExecutionSegments)), ...
        'Same-execution coefficient tensors must never enter practical receiver replay.');
    scoringIndex=find(string({item.Planes.ReceiverID})==item.Context.DesiredReferencePlane);
    changed=item.Planes;
    for segmentIndex=1:numel(changed(scoringIndex).Segments)
        captures=changed(scoringIndex).Segments{segmentIndex}.Execution.ChannelReferences;
        hit=find(arrayfun(@(c)c.Reference.ObservationStartSample==post.StartSample && ...
            c.Reference.ObservationEndSampleExclusive==post.EndSampleExclusive,captures));
        if isempty(hit), continue; end
        assert(isscalar(hit),'One requested interval cannot appear twice in a processor segment.');
        captures(hit).Reference.PathGains=captures(hit).Reference.PathGains(2:end,:,:,:);
        changed(scoringIndex).Segments{segmentIndex}.Execution.ChannelReferences=captures;
        break;
    end
    localReject(@()sixgr.truth.sharedLinkScoringObservation( ...
        changed,p,item.Context.DesiredReferencePlane),'sixgr:truth:InvalidSharedChannelReference');
    if ~isfield(state,'TestChannelExportRoot')
        state.TestChannelExportRoot=tempname; mkdir(state.TestChannelExportRoot);
    end
    [channelT,diagnosticContext]=sixgr.truth.exportSharedChannelObservation(state.TestChannelExportRoot, ...
        table(1,'VariableNames',{'Slot'}),item.Planes,p,item.Context.DesiredReferencePlane);
    expectedPostChannel=item.Planes(scoringIndex).Observation.readComplete();
    assert(isequal(diagnosticContext.PostChannelWaveform,expectedPostChannel) && ...
        diagnosticContext.PostChannelWaveformSHA256==string( ...
        sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(expectedPostChannel)) && ...
        contains(string(diagnosticContext.PostChannelWaveformSource), ...
        'before_sum_noise_and_rx_rf'), ...
        'Diagnostic post-channel waveform must be the exact desired-link scoring plane, not reconstructed receiver data.');
    captureFile=fullfile(state.TestChannelExportRoot,channelT.ChannelObservationMATFile);
    csvFile=fullfile(state.TestChannelExportRoot,channelT.ChannelObservationSegmentsCSV);
    saved=load(captureFile,'ManifestJSON','Captures');
    savedRows=sixgr.util.csvReadTable(csvFile,'TextType','string');
    verified=sixgr.channel.validateSharedChannelObservationArtifact(state.TestChannelExportRoot,channelT);
    assert(height(verified.Segments)==numel(channelReferences));
    primaryPath=fullfile(state.TestChannelExportRoot,"primary_"+channelT.ChannelObservationID+".csv");
    sixgr.util.csvWriteTable(primaryPath,channelT);
    persisted=sixgr.util.csvReadTable(primaryPath,'TextType','string');
    persistedVerified=sixgr.channel.validateSharedChannelObservationArtifact(state.TestChannelExportRoot,persisted);
    assert(height(persistedVerified.Segments)==height(verified.Segments), ...
        'The validator must also work on the persisted primary-row schema.');
    reportInput=sixgr.truth.bindSharedRFExecutionEvidence(channelT,item.Planes);
    reportCfg=p.ReceiverConfig; reportCfg.run.rootRunFolder=state.TestChannelExportRoot;
    anchor=struct('ConfigValidation',struct('Ok',true),'ConfigStrict',table(),'Geometry',table());
    identity=struct('RunID',"channel_capture_component",'ScenarioID',"channel_capture_component", ...
        'ExecutionID',"component_only",'ConfigHash',sixgr.channel.hashChannelRFConfig(reportCfg));
    report=sixgr.channel.buildInPathChannelRFResult(reportCfg,anchor,struct('DL',reportInput),identity);
    assert(report.ChannelRealizations.StrictOk && ...
        report.ChannelRealizations.ChannelRealizationId==channelT.ChannelObservationID && ...
        report.ChannelRealizations.PathGainsExported && report.ChannelRealizations.ChannelSnapshotExported && ...
        report.ChannelRealizations.ChannelSnapshotHash=="" && ...
        isnan(report.ChannelRealizations.ChannelMatrixRows) && ...
        height(report.ChannelSnapshots)==numel(channelReferences) && ...
        height(report.ChannelPathGains)==numel(channelReferences) && ...
        all(report.ChannelSnapshots.ChannelSnapshotHash==savedRows.PathGainsSHA256) && ...
        all(report.ChannelPathGains.SampleTimeHash==savedRows.SampleTimesSHA256), ...
        'Channel reports must bind verified path-gain snapshots without inventing an aggregate array hash or resource-grid H dimensions.');
    assert(~report.StrictOk,'This queue-only fixture does not supply all received data/measurement qualification evidence.');
    missing=removevars(reportInput,'ChannelObservationManifestJSON');
    localReject(@()sixgr.channel.buildInPathChannelRFResult(reportCfg,anchor,struct('DL',missing),identity), ...
        'sixgr:channel:MissingChannelArtifactBinding');
    wrongProfile=reportCfg; wrongProfile.channel.model='CDL-D';
    if report.ChannelRealizations.AppliedChannelModelType=="CDL-D", wrongProfile.channel.model='CDL-C'; end
    mismatch=sixgr.channel.buildInPathChannelRFResult(wrongProfile,anchor,struct('DL',reportInput),identity);
    assert(~mismatch.ChannelRealizations.StrictOk && ~mismatch.StrictOk && ...
        mismatch.ChannelRealizations.AppliedChannelModelType==report.ChannelRealizations.AppliedChannelModelType, ...
        'A verified file cannot turn a configured/applied channel-profile mismatch into a pass.');
    wrongBinding=channelT; wrongBinding.ChannelObservationStartSample=channelT.ChannelObservationStartSample+1;
    localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(state.TestChannelExportRoot,wrongBinding), ...
        'sixgr:channel:ChannelArtifactObservationMismatch');
    wrongBinding=channelT; wrongBinding.ChannelObservationMATFile="../outside.mat";
    localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(state.TestChannelExportRoot,wrongBinding), ...
        'sixgr:channel:ChannelArtifactPathMismatch');
    corruptRoot=tempname; mkdir(corruptRoot);
    corruptCSV=fullfile(corruptRoot,channelT.ChannelObservationSegmentsCSV);
    sixgr.util.ensureDir(corruptCSV); copyfile(csvFile,corruptCSV);
    corrupt=saved; corrupt.Captures{1}.Reference.PathGains(1)=corrupt.Captures{1}.Reference.PathGains(1)+1;
    corruptMAT=fullfile(corruptRoot,channelT.ChannelObservationMATFile);
    sixgr.util.matSave(corruptMAT,corrupt,'UseArtifactStore',false);
    resealed=channelT; resealed.ChannelObservationMATFileSHA256=sixgr.phy.waveform.WaveformHash.file(corruptMAT);
    localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(corruptRoot,resealed), ...
        'sixgr:channel:ChannelArtifactArrayMismatch');
    assert(isequaln(saved.Captures,channelReferences) && ...
        saved.ManifestJSON==channelT.ChannelObservationManifestJSON && ...
        channelT.ChannelObservationManifestSHA256==sixgr.phy.waveform.WaveformHash.bytes(saved.ManifestJSON) && ...
        channelT.ChannelObservationMATFileSHA256==sixgr.phy.waveform.WaveformHash.file(captureFile) && ...
        channelT.ChannelObservationSegmentsCSVSHA256==sixgr.phy.waveform.WaveformHash.file(csvFile) && ...
        height(savedRows)==numel(channelReferences), ...
        'Published channel files must reload the exact captured arrays and independently verify their hashes.');
    for k=1:numel(channelReferences)
        r=channelReferences{k}.Reference;
        assert(savedRows.PathGainsSHA256(k)==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(r.PathGains)) && ...
            savedRows.SampleTimesSHA256(k)==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(r.SampleTimes_s)) && ...
            savedRows.StartSample(k)==r.StartSample && savedRows.EndSampleExclusive(k)==r.EndSampleExclusive);
    end
    beforeMAT=dir(captureFile); beforeCSV=dir(csvFile);
    reused=sixgr.truth.exportSharedChannelObservation(state.TestChannelExportRoot, ...
        table(1,'VariableNames',{'Slot'}),item.Planes,p,item.Context.DesiredReferencePlane);
    afterMAT=dir(captureFile); afterCSV=dir(csvFile);
    assert(isequaln(reused,channelT) && beforeMAT.datenum==afterMAT.datenum && ...
        beforeCSV.datenum==afterCSV.datenum, ...
        'Shared observation reuse must preserve exact file bytes, bindings and write times.');
    localReject(@()sixgr.truth.exportSharedChannelObservation(corruptRoot, ...
        table(1,'VariableNames',{'Slot'}),item.Planes,p,item.Context.DesiredReferencePlane), ...
        'sixgr:channel:ChannelArtifactArrayMismatch');
    partialRoot=tempname; mkdir(partialRoot);
    partialMAT=fullfile(partialRoot,channelT.ChannelObservationMATFile);
    sixgr.util.ensureDir(partialMAT); copyfile(captureFile,partialMAT);
    localReject(@()sixgr.truth.exportSharedChannelObservation(partialRoot, ...
        table(1,'VariableNames',{'Slot'}),item.Planes,p,item.Context.DesiredReferencePlane), ...
        'sixgr:truth:PartialChannelCapturePublication');
    invalid=item.Planes;
    invalid(scoringIndex).Segments{segmentIndex}.Execution.ChannelReferences(hit).Reference.PathGains(1)=NaN;
    localReject(@()sixgr.truth.exportSharedChannelObservation(state.TestChannelExportRoot, ...
        table(1,'VariableNames',{'Slot'}),invalid,p,item.Context.DesiredReferencePlane), ...
        'sixgr:truth:InvalidSharedChannelCaptureArrays');
    invalid=item.Planes;
    invalid(scoringIndex).Segments{segmentIndex}.Execution.ChannelReferences(hit).Reference.StateKey="wrong_link_state";
    localReject(@()sixgr.truth.exportSharedChannelObservation(state.TestChannelExportRoot, ...
        table(1,'VariableNames',{'Slot'}),invalid,p,item.Context.DesiredReferencePlane), ...
        'sixgr:truth:InvalidSharedChannelCaptureArrays');
    rfEvidence=sixgr.truth.bindSharedRFExecutionEvidence(table(1,'VariableNames',{'Slot'}),item.Planes);
    validation=sixgr.channel.validateSharedRFExecutionEvidence(rfEvidence);
    assert(validation.Ok,'Actual shared RF manifest failed report validation: %s',validation.FailureReason);
    assert(rfEvidence.RFStrictOk && ...
        rfEvidence.RxRFInputWaveformSHA256==string(sixgr.rf.waveformSHA256(pre.readComplete())) && ...
        rfEvidence.RxRFOutputWaveformSHA256==string(sixgr.rf.waveformSHA256(post.readComplete())) && ...
        rfEvidence.TxRFStreamStartSample==tx.StartSample && ...
        rfEvidence.TxRFStreamEndSampleExclusive==tx.EndSampleExclusive && ...
        rfEvidence.RxRFStreamEndSampleExclusive==post.EndSampleExclusive, ...
        'RF evidence must preserve different TX and extended RX observation bounds.');
    gainEvidence=sixgr.truth.bindSharedLargeScaleEvidence(table(1,'VariableNames',{'Slot'}),item.Planes);
    assert(gainEvidence.LargeScaleMeasurementStartSample<=post.StartSample && ...
        gainEvidence.LargeScaleMeasurementEndSampleExclusive>=post.EndSampleExclusive && ...
        abs(gainEvidence.LargeScaleOutputEnergy_mWsample-gainEvidence.LargeScaleExpectedOutputEnergy_mWsample) ...
        <=gainEvidence.LargeScalePowerClosureRelativeTolerance*gainEvidence.LargeScaleExpectedOutputEnergy_mWsample, ...
        'Adjacent data capture tails require sample-backed, explicitly scoped gain evidence.');
    replay=sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,item.Context.DesiredReferencePlane,replay);
    reference=item.Planes(string({item.Planes.ReceiverID})==item.Context.DesiredReferencePlane).Observation.readComplete();
    expected=mean(abs(double(reference(:))).^2);
    assert(replay.DesiredSignalPowerBeforeNoise==expected && ...
        replay.InjectedNoiseVariancePreCompositeFrontEnd==originalReplay.InjectedNoiseVariance);
    assert(replay.RuntimeChannelFilterDelay_samples==7 && ...
        replay.RuntimeChannelMinimumPathDelay_samples==0 && ...
        replay.TrueReceiverTimingOffset_samples==7 && ...
        replay.ReceiveWindowDisplacement_samples==0 && ...
        ~replay.TimingTruthReceiverEstimatorInput, ...
        'DL shared timing truth must come from executed clock/channel metadata without entering the receiver.');
    assert(abs(replay.AppliedNoiseSNR_dB-10*log10(expected/originalReplay.InjectedNoiseVariance))<1e-12);
    assert(isnan(replay.InjectedNoiseVariancePostCompositeFrontEnd), ...
        'Post-front-end injected variance must remain unavailable.');
    assert(isnan(replay.SampleNoiseVariance), ...
        'Digital receiver disturbance variance requires reference-RE estimation.');
    assert(contains(replay.AppliedNoiseSNRSource,'not_data_SINR'), ...
        'Whole-capture noise diagnostic must not be labeled as data SINR.');
    wrong=originalReplay; wrong.InjectedNoiseVariance=2*wrong.InjectedNoiseVariance;
    switch string(originalReplay.NoiseOperatingMode)
        case "standalone_awgn_snr_argument"
            closureID='sixgr:truth:SharedFixedSNRNoiseClosure';
        case "receiver_noise_figure_thermal_noise"
            closureID='sixgr:truth:SharedThermalNoiseClosure';
        otherwise
            error('test:UnknownNoiseFixture','Extend the negative test for the declared noise mode.');
    end
    localReject(@()sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,item.Context.DesiredReferencePlane,wrong), ...
        closureID);
    wrong=originalReplay; wrong.InjectedNoiseVarianceDomain='post_rf';
    localReject(@()sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,item.Context.DesiredReferencePlane,wrong), ...
        'sixgr:truth:SharedInjectedNoisePlaneMismatch');
    assert(tx.StartSample==p.StartSample && tx.EndSampleExclusive==p.EndSampleExclusive && ...
        post.StartSample==p.ReceiveStartSample && post.EndSampleExclusive>=p.ReceiveEndSampleExclusive);
    assert(pre.isComplete() && receiver.isComplete() && replay.RuntimeChannelStateUsed && ...
        replay.ChannelFadingApplied && any(abs(tx.readComplete())>0,'all'));
    % A queue observation is not a decoded DCI, transport block or CRC.
    % Receiver decisions are deliberately excluded from the immutable TX
    % binding because they arrive later. Absence is not decoded authority.
    assert(~isfield(p.RequestBinding.Grant,'ControlDecodeOk') && ...
        ~isfield(p.RequestBinding.Grant,'PDCCHGrantBindingOk'));
    state.TestDataObservationCompleted=true;
    identity=item.Context.TransmissionIdentity;
    committed=state.SharedDataTXLedger{find(cellfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,state.SharedDataTXLedger),1)};
    proof=struct('SharedTransmissionID',identity.TransmissionID);
    sixgr.truth.validateSharedDataReceptionTX(state,proof,committed.Grant, ...
        p.Tx.TransportBlock,item.UE,'DL',committed.Grant.Slot);
    changed=p.Tx.TransportBlock; changed(1)=1-changed(1);
    localReject(@()sixgr.truth.validateSharedDataReceptionTX(state,proof,committed.Grant, ...
        changed,item.UE,'DL',committed.Grant.Slot),'sixgr:truth:SharedDataRXTXBindingMismatch');
    duplicateState=state;
    duplicateState.SharedDataRXCommittedIDs=identity.TransmissionID;
    localReject(@()sixgr.truth.validateSharedDataReceptionTX(duplicateState,proof,committed.Grant, ...
        p.Tx.TransportBlock,item.UE,'DL',committed.Grant.Slot),'sixgr:truth:DuplicateSharedDataRXCommit');
    noDecodeState=state;
    noDecodeState.SharedDataNoDecodeCommittedIDs=identity.TransmissionID;
    localReject(@()sixgr.truth.validateSharedDataReceptionTX(noDecodeState,proof,committed.Grant, ...
        p.Tx.TransportBlock,item.UE,'DL',committed.Grant.Slot),'sixgr:truth:DuplicateSharedDataRXCommit');
    state.TestDataRXCount=sixgr.util.structGet(state,'TestDataRXCount',0)+1;
    state.TestDataIntervals=[tx.StartSample tx.EndSampleExclusive post.StartSample post.EndSampleExclusive];
end
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingError','Expected %s.',id);
end
