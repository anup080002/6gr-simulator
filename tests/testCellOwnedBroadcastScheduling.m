function ok=testCellOwnedBroadcastScheduling()
% Actual cell TX/shared RF with zero or two observers; native BCH completion.
% Explicit component configuration: SSB40ms, SI20ms, later-slot beam2 only.
% No full runner, RA, delivered SI, beam optimum or statistical qualification.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','cell_owned_broadcast',char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('CELL_OWNED_BROADCAST_EVIDENCE %s\n',folder);
savedRNG=rng; restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
initialRNG=rng;
without=runArm(scenario,fullfile(folder,'no_observers'),false,initialRNG);
with=runArm(scenario,fullfile(folder,'two_observers'),true,initialRNG);
assert(isequaln(without.OriginalExecution,with.OriginalExecution), ...
    'Observations must not change original TX/RX sample hashes or physical clocks.');
assert(isequaln(without.TransmitSamples,with.TransmitSamples) && ...
    isequaln(without.PreparedSamples,with.PreparedSamples) && ...
    isequaln(without.FinalRNG,with.FinalRNG));
assert(isequal(without.SSBSlots,[0 40]) && isequal(with.SSBSlots,[0 40]) && ...
    isequal(without.SISlots,[7 27 47]) && isequal(with.SISlots,[7 27 47]));
assert(without.ReceiverCalls==0 && with.ReceiverCalls==4 && ...
    without.ArchiveCompletions==0 && with.ArchiveCompletions==4 && ...
    without.NeutralBoundaryCount==2 && with.NeutralBoundaryCount==2 && ...
    without.EndSample==with.EndSample && without.PreparedCount==with.PreparedCount && ...
    without.PreparedCount==5);

% Wrong installed same-cell TX is rejected before original preparation.
negativeFolder=fullfile(folder,'mismatched_cell');
[cfg,state]=makeState(scenario,negativeFolder);
other=cfg; other.phy.mib.cellBarred=~logical(sixgr.util.structGet(cfg,'phy.mib.cellBarred',false));
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg,other}); %#ok<ASGLU>
before=rng;
reject(@()owner.queueDueCellBroadcasts(0),'sixgr:truth:CellBroadcastConfigurationMismatch');
assert(owner.Events.NextSampleIndex==0 && isempty(owner.Pending) && ...
    isempty(owner.SSBTransmissions) && isempty(owner.SIB1Transmissions) && isequal(before,rng));

% Installation after an actual consumed idle slot cannot reconstruct origin.
[cfg,state]=makeState(scenario,fullfile(folder,'late_installation'));
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg,cfg});
[state,items]=owner.advanceSlot(state,cfg); assert(isempty(items)); %#ok<ASGLU>
reject(@()owner.queueDueCellBroadcasts(1),'sixgr:truth:CellBroadcastOriginRequired');
assert(isempty(owner.Pending) && isempty(owner.SSBTransmissions));
save(fullfile(folder,'paired_original_execution.mat'),'without','with','-v7.3');
fprintf('CELL_OWNED_BROADCAST_PASS arms=2 original_SSB=4 original_SI=6 BCH_receivers=4\n');
ok=true;
end

function evidence=runArm(scenario,folder,observe,initialRNG)
rng(initialRNG);
[cfg,state]=makeState(scenario,folder);
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg,cfg});
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
initialAcquisition=state.CellAcquisitionState;
evidence=struct('OriginalExecution',{{}},'TransmitSamples',{{}},'PreparedSamples',{{}}, ...
    'FinalRNG',struct(),'SSBSlots',[],'SISlots',[],'ReceiverCalls',0, ...
    'EndSample',NaN,'PreparedCount',0,'ArchiveCompletions',0, ...
    'AcquisitionWindows',{{}},'NeutralBoundaryCount',0);
traceCursor=0; preparedCount=0;
for slot0=0:47
    state.CurrentSlot=slot0+1;
    [bursts,si]=owner.queueDueCellBroadcasts(slot0);
    beforeRNG=rng; beforePending=owner.Pending; beforeClock=owner.Events.NextSampleIndex;
    [again,sameSI]=owner.queueDueCellBroadcasts(slot0);
    assert(isequaln(again,bursts) && isequal(si,sameSI) && ...
        isequaln(beforePending,owner.Pending) && beforeClock==owner.Events.NextSampleIndex && isequal(beforeRNG,rng));
    if ~isempty(bursts)
        assert(isscalar(bursts) && bursts.ServingCell==1 && bursts.AbsoluteSlot==slot0);
        parent=owner.Pending(string({owner.Pending.Kind})=="CellSSBTX");
        assert(isscalar(parent)); p=parent.Context.Prepared;
        assert(p.Content=="SSB_MIB" && p.Tx.SSBEmissionIncluded && ~p.Tx.SIB1EmissionIncluded && ...
            isempty(p.Tx.SIB1Transmissions) && p.NumSamples==round(0.006*fs) && ...
            bursts.EndSampleExclusive-bursts.StartSample==p.NumSamples, ...
            'Use the configured six-subframe original capture, not the public option default10.');
        timing=p.Tx.SSBInfo.SSBTiming; burst=p.Tx.SSBInfo.SSBBurstPlan;
        assert(isequal(double(burst.ActiveSSBIndices0Based(:)),2) && ...
            timing.CandidateStartSymbols(3)>=double(carrier.SymbolsPerSlot), ...
            'A later-only candidate must still be observed from the queued burst origin.');
        assert(isfield(parent.Context,'CellBroadcastConfigurationSHA256'));
        reject(@()owner.queueDownlink('PBCH',1,p,struct()),'sixgr:truth:MixedCellBroadcastOwnership');
        % Explicit test-only decision timer in BOTH arms. The public queue
        % method registers a boundary only; this component harness consumes
        % it as a no-op and never calls UL preparation or creates a grant.
        % Matching segment boundaries preserve exact original TX/RX hash
        % comparison while zero vs two UE observers remains the sole change.
        window=sixgr.phy.frame.SSBAcquisitionWindow.create(p.ReceiverConfig, ...
            fs,double(p.BroadcastStartSample),double(p.NumSamples));
        owner.queueULDataPreparation(1,window.EndSampleExclusive, ...
            struct('TestOnlyNeutralBoundary',true,'ExpectedSample',window.EndSampleExclusive));
        if observe
            for ue=1:2
                [rxCfg,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,ue,'DL');
                % These are legitimate per-UE receiver overlays, not TX input.
                rxCfg.lls6g.userContext.MeasuredPathloss_dB=70+ue;
                context=struct('Config',rxCfg,'Slot',slot0+1, ...
                    'Frame',floor(slot0/double(carrier.SlotsPerFrame))+1,'RNTI',ue, ...
                    'ServingCell',1,'SNR',20,'TrackingOnly',false);
                before=rng; count=numel(owner.Pending);
                [id,armed]=owner.armCellSSBObservation(ue,context);
                [duplicate,repeated]=owner.armCellSSBObservation(ue,context);
                assert(id==duplicate && isequaln(armed,repeated) && numel(owner.Pending)==count+2 && ...
                    isequal(before,rng) && owner.Events.NextSampleIndex==beforeClock && ...
                    armed.CellOwnedBroadcast && all(isfield(armed.Prototype,{'Ok','BLER','FailureReason'})) && ...
                    isequal(armed.Prepared.TransmitSamples,p.TransmitSamples));
                assert(isequal(armed.AcquisitionWindowContract.CandidateIndices,0:3) && ...
                    isequaln(armed.AcquisitionWindowContract,window) && ...
                    numel(burst.ActiveSSBIndices0Based)==1, ...
                    'Receiver searches all four legal candidates, not the single active TX bitmap.');
                bad=context; bad.Config.phy.carrier.NCellID=carrier.NCellID+1;
                reject(@()owner.armCellSSBObservation(ue,bad),'sixgr:truth:CellBroadcastReceiverMismatch');
                bad=context; bad.SNR=19;
                reject(@()owner.armCellSSBObservation(ue,bad),'sixgr:truth:ChangedCellSSBObservation');
            end
        end
        preparedCount=preparedCount+1;
        reject(@()owner.queueDueCellBroadcasts(slot0+1),'sixgr:truth:CellBroadcastSchedulingClock');
    end
    preparedCount=preparedCount+numel(si);
    [state,completed]=owner.advanceSlot(state,cfg);
    assert(owner.Events.NextSampleIndex==sixgr.phy.frame.slotStartSample(carrier,slot0+1,fs));
    if slot0==0 && observe
        reject(@()owner.armCellSSBObservation(1,context),'sixgr:truth:LateCellSSBObservation');
    end
    for item=completed
        if item.Kind=="PrepareULData"
            assert(item.Context.TestOnlyNeutralBoundary && isempty(item.Planes) && ...
                item.Context.ExpectedSample<=owner.Events.NextSampleIndex && isempty(owner.DataTransmissions));
            evidence.NeutralBoundaryCount=evidence.NeutralBoundaryCount+1;
        elseif any(item.Kind==["CellSSBTX","CellSIB1TX"])
            assert(item.UE==0 && numel(item.Planes)==1);
            evidence.TransmitSamples{end+1}=item.Planes.Observation.readComplete();
            evidence.PreparedSamples{end+1}=item.Context.Prepared.TransmitSamples;
            if item.Kind=="CellSSBTX"
                record=owner.SSBTransmissions(end);
                assert(record.ExecutionProof.PhysicalTransmissionVerified && ...
                    ~record.ExecutionProof.ReceiverExecutionClaimed && ...
                    record.TransmitSampleSHA256==item.Planes.Observation.sampleHash());
                evidence.SSBSlots(end+1)=record.AbsoluteSlot;
            else
                assertSIB1TransmissionCompletion(owner,item);
                record=owner.SIB1Transmissions(end);
                assert(record.SSBIndex==2);
                evidence.SISlots(end+1)=record.AbsoluteSlot;
            end
        elseif item.Kind=="PBCH"
            assert(observe && numel(item.Planes)==4 && item.Context.CellOwnedBroadcast);
            [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
            prototype=item.Context.Prototype;
            prototype.RuntimeChannelReplay=replay;
            prototype.RuntimeDLChannelState=owner.channelState(item.UE,'DL');
            prototype.PowerContext=item.Context.Prepared.PowerContext;
            prototype.RuntimeChannelStateUsed=true;
            options=struct('UseRuntimeChannel',true,'RuntimeSlot',item.Context.Slot-1, ...
                'CandidateSSBIndices',item.Context.AcquisitionWindowContract.CandidateIndices, ...
                'AcquisitionWindowContract',item.Context.AcquisitionWindowContract, ...
                'SSBIndex',[],'WriteArtifacts',false, ...
                'RunFolder','','RunId','cell_owned_broadcast', ...
                'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
            before=rng; beforeClock=owner.Events.NextSampleIndex;
            [received,mib]=sixgr.link.completeCellSearchBroadcast(item.Context.Prepared,post,prototype,options,tic);
            admitted=sixgr.truth.validateReceivedSSBBurst(item.Context.Config,item.Context.Slot,received);
            assert(isequal(admitted,0:3));
            owner.validateCompletedBroadcastObservation(item);
            assert(post.EndSampleExclusive==item.Context.AcquisitionWindowContract.EndSampleExclusive && ...
                post.EndSampleExclusive<item.Context.Prepared.BroadcastStartSample+item.Context.Prepared.NumSamples);
            observed=struct('ID',string(item.ID),'StartSample',post.StartSample, ...
                'EndSampleExclusive',post.EndSampleExclusive,'Planes',{{}});
            for plane=item.Planes
                observed.Planes{end+1}=struct('ID',string(plane.ReceiverID), ...
                    'SampleSHA256',plane.Observation.sampleHash());
            end
            evidence.AcquisitionWindows{end+1}=observed;
            % The production collector calls this same admission helper.
            % Reject copied population/clock corruption without another RX.
            bad=received; bad.CandidateSSBIndices=0;
            reject(@()sixgr.truth.validateReceivedSSBBurst(item.Context.Config,item.Context.Slot,bad), ...
                'sixgr:truth:ReceivedSSBBurstIdentity');
            bad=received; bad.CandidateResults={};
            reject(@()sixgr.truth.validateReceivedSSBBurst(item.Context.Config,item.Context.Slot,bad), ...
                'sixgr:truth:ReceivedSSBBurstIdentity');
            bad=received; bad.CandidateResults{1}.RequestedSSBOccasionIndex=4;
            reject(@()sixgr.truth.validateReceivedSSBBurst(item.Context.Config,item.Context.Slot,bad), ...
                'sixgr:truth:ReceivedSSBBurstIdentity');
            bad=received; bad.CandidateResults{1}.ObservationStartSample=post.StartSample+1;
            reject(@()sixgr.truth.validateReceivedSSBBurst(item.Context.Config,item.Context.Slot,bad), ...
                'sixgr:truth:ReceivedSSBBurstClock');
            bad=received; bad.CandidateResults{1}.ReceiverObservationSHA256=string(repmat('0',1,64));
            reject(@()sixgr.truth.validateReceivedSSBBurst(item.Context.Config,item.Context.Slot,bad), ...
                'sixgr:truth:ReceivedSSBBurstClock');
            reject(@()sixgr.truth.validateReceivedSSBBurst(item.Context.Config,item.Context.Slot+1,received), ...
                'sixgr:truth:ReceivedSSBBurstClock');
            bad=item; bad.Context.AcquisitionWindowContract.CandidateIndices=2;
            reject(@()owner.validateCompletedBroadcastObservation(bad), ...
                'sixgr:phy:frame:ChangedAcquisitionWindow');
            save(fullfile(folder,sprintf('original_BCH_ue%d_slot%d.mat',item.UE,item.Context.Slot)), ...
                'received','mib','item','-v7.3');
            measured=received.CandidateResults{3};
            assert(measured.PBCH.Ok && measured.SIB1.BCHCRCValid && measured.SIB1.MIBDecoded && ...
                measured.SIB1.CandidateIdentityConsistent && ~measured.SIB1.SIB1ReceptionAttempted && ...
                measured.SSBIndex==2 && isa(mib{3},'sixgr.phy.broadcast.ReceivedMIBContext') && ...
                all(cellfun(@(r)~r.PBCH.Ok,received.CandidateResults([1 2 4]))) && ...
                owner.Events.NextSampleIndex==beforeClock && isequal(before,rng));
            evidence.ReceiverCalls=evidence.ReceiverCalls+1;
        elseif item.Kind=="SSBArchive"
            assert(observe && numel(item.Planes)==4 && item.Context.CellOwnedBroadcast);
            prior=find(cellfun(@(r)r.ID==item.Context.AcquisitionObservationID,evidence.AcquisitionWindows));
            assert(isscalar(prior),'Original prefix must complete before its independent archive.');
            original=evidence.AcquisitionWindows{prior};
            for plane=item.Planes
                buffer=plane.Observation;
                assert(buffer.isComplete() && buffer.StartSample==original.StartSample && ...
                    buffer.EndSampleExclusive==item.Context.Prepared.BroadcastStartSample+item.Context.Prepared.NumSamples);
                samples=buffer.readComplete();
                count=original.EndSampleExclusive-original.StartSample;
                reference=original.Planes(cellfun(@(r)r.ID==string(plane.ReceiverID),original.Planes));
                assert(isscalar(reference) && ...
                    sixgr.phy.waveform.WaveformHash.runtimeArray(samples(1:count,:))==reference{1}.SampleSHA256, ...
                    'Early acquisition must be the exact original full-archive prefix, not regenerated samples.');
            end
            evidence.ArchiveCompletions=evidence.ArchiveCompletions+1;
        else
            error('test:UnexpectedCellCompletion','Unexpected completion %s',item.Kind);
        end
    end
    traces=owner.Events.ExecutionTrace;
    for n=traceCursor+1:numel(traces)
        e=traces{n}.Execution;
        q=struct('StartSample',e.StartSample,'EndSampleExclusive',e.EndSampleExclusive, ...
            'SampleRateHz',e.SampleRateHz,'ConfigurationEpoch',e.ConfigurationEpoch,'TX',{{}},'RX',{{}});
        for k=1:numel(e.TX)
            q.TX{k}=struct('ID',e.TX(k).ID,'Input',e.TX(k).Replay.RFInputWaveformSHA256, ...
                'Output',e.TX(k).Replay.RFOutputWaveformSHA256);
        end
        for k=1:numel(e.RX)
            q.RX{k}=struct('ID',e.RX(k).ID,'Input',e.RX(k).Replay.RFInputWaveformSHA256, ...
                'Output',e.RX(k).Replay.RFOutputWaveformSHA256);
        end
        evidence.OriginalExecution{end+1}=q;
    end
    traceCursor=numel(traces);
end
assert(isempty(owner.Pending) && isequaln(state.CellAcquisitionState,initialAcquisition));
evidence.FinalRNG=rng; evidence.EndSample=owner.Events.NextSampleIndex; evidence.PreparedCount=preparedCount;
save(fullfile(folder,'cell_transmission_receipts.mat'),'evidence','-v7.3');
end

function [cfg,state]=makeState(scenario,folder)
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder); cfg.run.rootRunFolder=folder;
% Declared component-test changes precede installation of either owner.
% They do not alter the production scenario or claim an authored YAML test.
cfg.phy.ssb.periodicity_ms=40; cfg.phy.ssb.period_ms=40; cfg.phy.ssb.period_slots=40;
cfg.phy.pbch.period_slots=40; cfg.phy.ssb.runtimeSSBIndex=2;
cfg.phy.ssb.activeBitmap=[false false true false]; cfg.phy.ssb.positionsInBurst="0010";
cfg.phy.ssb.activeCandidateIndices0Based=2;
cfg.initial_access.ssb.periodicity_ms=40; cfg.initial_access.ssb.selected_ssb_index=2;
cfg.initial_access.ssb.positions_in_burst="00100000";
cfg.phy.sib1.transmissionScope="selected_ssb_occasion";
cfg.initial_access.sib1_transmission_scope="selected_ssb_occasion";
cfg.phy.ssb.pbchObservationSubframes=6; cfg.phy.sib1.ssbObservationSubframes=6;
cfg.initial_access.ssb.observation_subframes=6; cfg.lls6g.control.pbchObservationSubframes=6;
cfg.phy.ssb.timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
rows=plan.sib1TransmissionOccasions(0,48);
assert(isequal(rows.AbsoluteSlot,[7;27;47]) && all(rows.SSBIndex==2));
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),48);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
end

function reject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s',identifier,cause.identifier,cause.message); return;
end
error('test:MissingCellBroadcastRejection','Expected %s',identifier);
end
