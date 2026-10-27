function [ok,evidence]=testSharedCSIRSMultiportReferenceIntegration()
% Actual queued, cell-common 2-resource/4-port CSI through native CDL and
% retained RF. Two UEs subscribe to one parent; only port 3000 per resource
% is retained as a fixed first-order linear-model reference. This is a
% measured-component gate with the production post-receiver model scorer
% and public projection, not canonical multiport feedback, unique nonlinear
% port attribution, standardized accuracy or an n40 campaign.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; restore=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
parent=fullfile(pwd,'logs','shared_csirs_multiport_reference');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('SHARED_CSIRS_MULTIPORT_REFERENCE_AUDIT %s\n',folder);
cfg=configuration(folder);
carrier=sixgr.phy.grid.makeCarrier(cfg); nativeInfo=nrOFDMInfo(carrier);
fs=double(nativeInfo.SampleRate); slotSamples=sixgr.phy.frame.slotStartSample(carrier,1,fs);
assert(carrier.NSizeGrid>=24 && carrier.SubcarrierSpacing==15 && ...
    cfg.channel.perSampleFadingEnabled && ~cfg.channel.normalizeChannelOutputs);
for slot=[1 2 3 6 7]
    [dl,~,~,p]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    assert(dl && isequal(double(p.DLSymbolAllocation),[0 14]));
end
[~,ul]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,5); assert(ul);

originals=cell(2,1); reports=cell(2,1); checkpointEvidence=struct();
for pass=1:2
    enabled=pass==2;
    current=cfg; current.rf.txLinearReference.Enabled=enabled;
    current.run.rootRunFolder=fullfile(folder,char("enabled_"+string(enabled)));
    mkdir(current.run.rootRunFolder);
    multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
    % The ordinary scenario initializer samples UE positions/indoor status,
    % speed and heading with the global stream. Give both independent arms
    % the EXACT same original starting state and compare its resulting state
    % and geometry; do not claim this physical setup makes no random draws.
    rng(savedRNG); setupRNGBefore=rng;
    state=sixgr.truth.CoupledTruthRuntime.initialize(current,current.run.rootRunFolder,multi,struct(),1);
    % API order after direction: sweep index/count, canonical slot, total
    % canonical slots, SNR. The slot is NOT the sweep index.
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,current,'DL',1,1,1,7,30);
    state.CurrentServingIdx(:)=1;
    assert(isempty(fieldnames(state.LargeScaleState)),'test:SharedPropagationAuthority', ...
        'This regression requires the original empty propagation-cache boundary.');
    [state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,current,{current,current});
    assert(isfield(state.LargeScaleState,'LOS'),'test:SharedPropagationAuthority', ...
        'The owner must retain the original context-created propagation realization.');
    retainedPropagation=state.LargeScaleState; propagationRNG=rng;
    for ue=1:state.NumUsers
        originalIdentity=owner.broadcastReceiveIdentity(ue);
        assert(originalIdentity.ServingCell==state.CurrentServingIdx(ue));
        for direction=["DL","UL"]
            [bound,reusedState]=sixgr.truth.CoupledTruthRuntime.applyUserContext(current,state,ue,direction);
            cellIndex=state.CurrentServingIdx(ue);
            u=bound.lls6g.userContext;
            observed=[double(bound.channel.runtimeLOS),double(u.RuntimeServingCell), ...
                u.RuntimePropagationPathloss_dB,u.RuntimeServingPropagationDelay_s];
            expected=[double(retainedPropagation.LOS(ue,cellIndex)),double(cellIndex), ...
                retainedPropagation.Pathloss_dB(ue,cellIndex),retainedPropagation.PropagationDelay_s(ue,cellIndex)];
            fprintf('ORIGINAL_PROPAGATION_BINDING UE=%d direction=%s observed=%s expected=%s\n', ...
                ue,direction,mat2str(observed,17),mat2str(expected,17));
            assert(isequaln(observed,expected),'test:SharedPropagationAuthority', ...
                'Original propagation fields (including explicitly unavailable values) must be retained exactly.');
            assert(isequaln(reusedState.LargeScaleState,retainedPropagation) && isequal(rng,propagationRNG), ...
                'test:SharedPropagationAuthority','Reusing original propagation must not redraw its realization.');
        end
    end
    assert(state.NumUsers==2,'The declared broadcast fixture requires exactly two original UEs.');
    slotClocks=cell(0,1); retainSlotClock("initial",1);
    before=rng;
    initialization=struct('RNGBefore',setupRNGBefore,'RNGAfter',before, ...
        'OriginalLayout',state.Layout,'OriginalUE',state.UE);
    if pass==2
        assert(isequaln(initialization,originals{1}.Initialization), ...
            'Optional recording must not alter original initialization draws or UE/layout realization.');
    end
    channels=owner.Physical.channelStates();
    initialChannels=cellfun(@initialChannelReceipt,channels,'UniformOutput',false);
    save(fullfile(current.run.rootRunFolder,'original_initial_channels.mat'), ...
        'initialChannels','initialization');
    assert(numel(channels)==2);
    for k=1:numel(channels)
        s=channels{k}; r=initialChannels{k};
        fprintf('CSIRS_MULTIPORT_ORIGINAL_CHANNEL link=%d class=%s TX=%g RX=%g clock=%g density=%g doppler=%g fresh=%d\n', ...
            k,r.NativeClass,r.NumTxAnt,r.NumRxAnt,r.CurrentSampleIndex, ...
            r.SampleDensity,r.MaximumDopplerShift,r.FreshInitializationApplied);
        assert(isa(s.Obj,'nrCDLChannel'),'test:CSIReferenceNativeClass', ...
            'Declared dynamic fixture produced %s; original receipt was saved.',r.NativeClass);
        assert(s.Obj.SampleDensity==Inf && s.Obj.MaximumDopplerShift==50, ...
            'test:CSIReferenceNativeSampling','Require original configured 50-Hz per-sample CDL.');
        assert(s.NumTxAnt==4 && s.NumRxAnt==2,'test:CSIReferenceNativeDimensions', ...
            'Require original installed 4-TX/2-RX element columns.');
        assert(s.CurrentSampleIndex==0 && s.Meta.NativeReciprocalFilterInitialization.Applied, ...
            'test:CSIReferenceNativeOrigin','Require original fresh reciprocal filter initialization at sample0.');
    end
    captures=cell(0,1); queued=cell(0,1); registrations=cell(0,1);
    sourceIDs=["gnb_1","ue_1","ue_2"];
    % Original aggregate history is nonzero before reference registration.
    % No native state is copied into a component, reset or re-executed.
    prior=.02*exp(1i*reshape(1:37*4,37,4)/19);
    owner.Events.enqueue("gnb_1","declared_preexisting_input", ...
        sixgr.phy.waveform.WaveformChunk(prior,0));
    consumePrefix(37);
    assert(owner.Events.NextSampleIndex==37);
    queueParent(2);
    consumePrefix(slotSamples);
    if enabled
        assertRegistrationAndConsumptionGuards(owner,current.run.rootRunFolder);
    end
    for slot=2:7
        state=sixgr.truth.CoupledTruthRuntime.startSlot(state,current,'DL',1,1,slot,7,30);
        state.CurrentServingIdx(:)=1;
        retainSlotClock("before_advance",slot);
        assert(state.CurrentSlot==slot && state.CurrentSweepPointIndex==1 && ...
            state.CurrentSNR_dB==30 && owner.Events.NextSampleIndex== ...
            sixgr.phy.frame.slotStartSample(carrier,slot-1,fs), ...
            'test:CSIReferenceSlotEntry','Original scheduler and physical slot-entry clocks must agree.');
        if slot==5
            % The original link is UL here. Queue a future DL parent, then
            % require its channel birth to use the later actual DL reset.
            directions=owner.Physical.channelStates();
            assert(all(cellfun(@(x)string(x.Direction)=="UL",directions)));
            queueParent(6);
        end
        if enabled && slot==3
            % Preserve the ORIGINAL completed observations from this one
            % practical reception. The restored branch below performs no
            % second receiver estimation or measurement publication.
            [state,originalCompleted]=owner.advanceSlot(state,current,@receive);
        else
            state=owner.advanceSlot(state,current,@receive);
        end
        retainSlotClock("after_advance",slot);
        assert(owner.Events.NextSampleIndex==sixgr.phy.frame.slotStartSample(carrier,slot,fs) && ...
            owner.Events.NextSampleIndex==owner.Physical.NextSampleIndex);
        assert(isequal(before,rng),'Reference recording must not consume global RNG.');
        if enabled && slot==2
            assert(numel(owner.Pending)==2 && isempty(captures) && ...
                numel(owner.CSIRSTransmissions)==1 && ...
                all(arrayfun(@(p)p.Context.Prepared.ReceiveTimingSearchGuardSamples==64,owner.Pending)), ...
                'Checkpoint the actual committed parent with both UE receive tails still pending.');
            checkpointPath=fullfile(current.run.rootRunFolder,'original_slot2_pending_tail_checkpoint.mat');
            checkpointBefore=checkpointOwnerValues(owner,state);
            assert(state.SharedWaveformStream==owner);
            % Save the original connected handle graph in ONE operation.
            % Do not clone/requeue buffers, RF state or native channel state.
            save(checkpointPath,'owner','state','-v7.3');
            checkpointSHA=string(sixgr.util.sha256File(checkpointPath));
            assert(isequaln(checkpointBefore,checkpointOwnerValues(owner,state)) && isequal(before,rng));
        elseif enabled && slot==3
            checkpointEvidence=assertCheckpointContinuation(checkpointPath,checkpointSHA, ...
                checkpointBefore,owner,state,current,originalCompleted);
            clear originalCompleted
        end
    end
    assert(numel(captures)==4 && isempty(owner.Pending) && numel(owner.CSIRSTransmissions)==2);
    trace=owner.Events.ExecutionTrace;
    assert(~isempty(trace));
    for k=1:numel(trace)
        x=trace{k}.Execution;
        assert(numel(x.ExecutedContributors)==3 && ...
            all(arrayfun(@(a)a.Receipt.CompleteContributorList,x.ExecutedContributors)));
    end
    finalChannels=owner.Physical.channelStates();
    if enabled
        assertReferenceChronology(trace,owner.Physical.readCSIRSPortReferenceRegistrations(),slotSamples);
    end
    clocks=cellfun(@nativeClock,finalChannels,'UniformOutput',false);
    originals{pass}=struct('Captures',{captures},'Trace',{trace},'NativeClocks',{clocks}, ...
        'Initialization',initialization,'RNGAfterPhysicalExecution',rng, ...
        'InitialChannels',{initialChannels},'SlotClocks',{slotClocks}, ...
        'Queued',{queued},'Registrations',{registrations},'EndSample',owner.Events.NextSampleIndex, ...
        'ActualCSIRSTransmissions',owner.CSIRSTransmissions);
    reports{pass}=scopeRows(captures,enabled);
    local=originals{pass}; %#ok<NASGU>
    save(fullfile(current.run.rootRunFolder,'original_component_execution.mat'),'local','current','-v7.3');
    fprintf('SHARED_CSIRS_MULTIPORT_PASS_ARM enabled=%d callbacks=%d parents=%d intervals=%d\n', ...
        enabled,numel(captures),numel(owner.CSIRSTransmissions),numel(trace));
end

assertOriginalEquivalence(originals{1},originals{2});
combined=[reports{1};reports{2}];
path=fullfile(folder,'multiport_component_observations.csv');
sixgr.util.csvWriteTable(path,combined,'PreserveSchema',true,'RoundTripNumericText',true);
types=struct('ReferenceReceiptJSON','string','ReferenceReceiptSHA256','string', ...
    'OriginalReceiveSHA256','string','OriginalParentSHA256','string');
modelNames=string(fieldnames(originals{2}.Captures{1}.ModelComparison)).';
modelTypes=struct();
for name=modelNames
    modelTypes.(name)=class(combined.(name)); types.(name)=modelTypes.(name);
end
readback=sixgr.util.csvReadTable(path,'TextType','string','ColumnTypes',types);
for name=string(fieldnames(types)).'
    if ~isstring(combined.(name)), continue; end
    actual=fillmissing(string(readback.(name)),'constant',"");
    assert(isequal(actual,combined.(name)),'Original component receipt changed at CSV boundary.');
end
for name=modelNames
    if isstring(combined.(name))
        actual=fillmissing(string(readback.(name)),'constant',"");
    else
        actual=readback.(name);
    end
    assert(isequaln(actual,combined.(name)), ...
        'test:CSIModelScoreCSV','Original optional model field %s changed at the CSV boundary.',name);
end
public=sixgr.truth.buildLLSPublicOutputTables(struct('csi_rs_table',combined), ...
    sixgr.truth.llsOutputContract(),struct('logical_run_id',"actual_multiport_model_component",'run_id',1));
published=public.csi_rs_runtime_event_table;
assert(height(published)==height(combined));
for name=modelNames, assert(isequaln(published.(name),combined.(name))); end
publicPath=fullfile(folder,'csi_rs_runtime_event_table.csv');
sixgr.util.csvWriteTable(publicPath,published,'PreserveSchema',true,'RoundTripNumericText',true);
publicRead=sixgr.util.csvReadTable(publicPath,'TextType','string','ColumnTypes',modelTypes);
for name=modelNames
    actual=publicRead.(name);
    if isstring(combined.(name)), actual=fillmissing(actual,'constant',""); end
    assert(isequaln(actual,combined.(name)),'test:CSIModelScorePublicCSV', ...
        'Actual optional model comparison changed through public projection/CSV: %s.',name);
end
assert(isequal(rng,originals{2}.Initialization.RNGAfter) && ...
    isequal(originals{1}.RNGAfterPhysicalExecution,originals{2}.RNGAfterPhysicalExecution));
% Restore only the fixture's documented scenario-initialization draws.
% Every original physical/model/receiver interval was checked before this.
clear restore
assert(isequal(savedRNG,rng));
evidence=struct('SourceFolder',string(folder),'ActualParentCountPerArm',2, ...
    'ActualResourceCountPerParent',2,'LogicalPortsPerResource',4, ...
    'ObservedTargetPort',3000,'UECount',2,'ActualCallbackCountPerArm',4, ...
    'OriginalPhysicalSamplesAndMeasurementsCompared',true,'NativeTDDRetargetCountPerLink',2, ...
    'OriginalMeasuredCallbackModelScoring',true,'CanonicalCompletionExecuted',false, ...
    'CanonicalMultiportFeedbackQualified',false,'UniqueNonlinearPortTruthQualified',false, ...
    'StandardizedPowerAccuracyQualified',false,'HardwareQualified',false, ...
    'AttachedOwnerCheckpointContinuation',checkpointEvidence, ...
    'PublicCSVFile',string(publicPath),'PublicCSVFileSHA256',string(sixgr.util.sha256File(publicPath)), ...
    'CSVFile',string(path),'CSVFileSHA256',string(sixgr.util.sha256File(path)));
save(fullfile(folder,'summary.mat'),'evidence','combined','-v7.3');
ok=true;
fprintf('SHARED_CSIRS_MULTIPORT_REFERENCE_PASS parents=2 resources=2 ports=4 UEs=2 canonical_feedback=0 standardized_accuracy=0\n');

    function consumePrefix(stop)
        for tx=sourceIDs, owner.Events.commitTransmissionsThrough(tx,stop); end
        event=owner.Events.advanceUntilEvent(stop);
        assert(event.PhysicalExecutionPerformed && isempty(event.Completed) && ...
            owner.Events.NextSampleIndex==stop && owner.Physical.NextSampleIndex==stop);
    end
    function retainSlotClock(phase,requestedSlot)
        clock=struct('Phase',string(phase),'RequestedSlot',requestedSlot, ...
            'CurrentSlot',state.CurrentSlot,'SweepIndex',state.CurrentSweepPointIndex, ...
            'CurrentSNR_dB',state.CurrentSNR_dB,'EventSample',owner.Events.NextSampleIndex, ...
            'PhysicalSample',owner.Physical.NextSampleIndex, ...
            'ExpectedStartSample',sixgr.phy.frame.slotStartSample(carrier,requestedSlot-1,fs), ...
            'ExpectedEndSampleExclusive',sixgr.phy.frame.slotStartSample(carrier,requestedSlot,fs));
        slotClocks{end+1}=clock;
        save(fullfile(current.run.rootRunFolder,'original_slot_clocks.mat'),'slotClocks');
        fprintf('CSIRS_MULTIPORT_ORIGINAL_CLOCK phase=%s requested=%g current=%g sweep=%g Event=%g Physical=%g expected=[%g,%g)\n', ...
            clock.Phase,clock.RequestedSlot,clock.CurrentSlot,clock.SweepIndex, ...
            clock.EventSample,clock.PhysicalSample,clock.ExpectedStartSample,clock.ExpectedEndSampleExclusive);
    end
    function queueParent(slot)
        parentIDs=strings(2,1); parentSHAs=strings(2,1);
        for ue=1:2
            [user,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(current,state,ue,'DL');
            prepared=sixgr.link.prepareCSIRSTransmission(user,30,'RuntimeSlot',slot,'Frame',1);
            assert(numel(prepared.Tx.CSIRSInfo.Resources)==2 && ...
                all([prepared.Tx.CSIRSInfo.Resources.NumPorts]==4) && ...
                size(prepared.Tx.CSIRSRuntimeEvent.ResourceEvents(1).WaveformPrecoderMatrix,2)==4);
            context=struct('Config',user,'Slot',slot,'Frame',1,'RNTI',ue, ...
                'ServingCell',1,'SNR',30,'UEIndex',ue);
            owner.queueDownlink("CSIRS",ue,prepared,context);
            item=owner.Pending(end); parentIDs(ue)=string(item.Context.ComponentID);
            q=owner.Events.originalEnqueueReceipt("gnb_1",parentIDs(ue));
            parentSHAs(ue)=q.OriginalSampleSHA256;
            assert(~q.PhysicalExecutionPerformed && q.StartSample==(slot-1)*slotSamples && ...
                q.EnqueuedAtSample<q.StartSample);
            queued{end+1}=struct('UE',ue,'Slot',slot,'Receipt',q); %#ok<AGROW>
            if enabled
                planes=item.Context.CSIRSPortReferencePlanes;
                assert(numel(planes)==2 && isequal(sort([planes.ResourceID]),[17 29]) && ...
                    all([planes.LogicalPortIndex0]==0) && all([planes.ReferencePortNumber]==3000));
                registrations{end+1}=planes; %#ok<AGROW>
            else
                assert(~isfield(item.Context,'CSIRSPortReferencePlanes') || ...
                    isempty(item.Context.CSIRSPortReferencePlanes));
            end
        end
        assert(parentIDs(1)==parentIDs(2) && parentSHAs(1)==parentSHAs(2), ...
            'Two UE subscriptions must retain one original cell-common emitted parent.');
        if enabled
            a=registrations{end-1}; b=registrations{end};
            assert(isequal(string({a.RegistrationSHA256}),string({b.RegistrationSHA256})) && ...
                ~any(string({a.PlaneID})==string({b.PlaneID})), ...
                'Deduplicate TX registration, not distinct propagation/receive observations.');
        end
    end
    function next=receive(next,items)
        for item=reshape(items,1,[])
            assert(item.Kind=="CSIRS"); p=item.Context.Prepared;
            [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
            [desired,source]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,item.Context.DesiredReferencePlane);
            beforeRX=rng; physicalClock=owner.Events.NextSampleIndex;
            rx=sixgr.phy.refsig.receiveCSIRSWaveform(p.Carrier,p.ReceiverConfig, ...
                post.readComplete(),pre.readComplete(),[0 p.ReceiveTimingSearchGuardSamples],replay);
            assert(isequal(beforeRX,rng) && physicalClock==owner.Events.NextSampleIndex && ...
                rx.PhysicalMeasurementDemodulationReceiptAvailable);
            original=struct('UE',item.UE,'Slot',item.Context.Slot,'ParentID',string(item.Context.ComponentID), ...
                'SFN',mod(double(p.Carrier.NFrame),1024),'ReceiverWindowID',string(item.ID), ...
                'ResourceID',double(rx.CSIRSObservation.ResourceID), ...
                'TX',tx.readComplete(),'PreRF',pre.readComplete(),'PostRF',post.readComplete(), ...
                'Desired',desired.readComplete(),'OriginalReceiveSHA256',pre.sampleHash(), ...
                'OriginalParentSHA256',sixgr.phy.waveform.WaveformHash.numeric(p.TransmitSamples), ...
                'MeasuredH',rx.CSIRSChannelEstimate,'MeasuredResources',{rx.CSIRSObservation.MeasurementPhysicalResources}, ...
                'DemodulationJSON',rx.PhysicalMeasurementDemodulationReceiptJSON, ...
                'StartSample',pre.StartSample,'EndSampleExclusive',pre.EndSampleExclusive, ...
                'ReferenceReceiptJSON',"",'ReferenceReceiptSHA256',"",'ModelPlanes',struct());
            if enabled
                original=assertModelPlanes(original,item,source,owner);
            end
            % Invoke the SAME production post-receiver scorer used by
            % canonical completion, on the actual original measured result.
            % This fixture deliberately has no reporting/UCI configuration;
            % it is not a second receive call or a claimed feedback result.
            unmodifiedRX=rx; beforeScore=rng;
            modelComparison=sixgr.truth.scoreSharedCSIRSLinearPortModel( ...
                item,rx,desired,source,replay,owner);
            receivedEVM=sixgr.truth.scoreSharedCSIRSReceivedEVM( ...
                item,rx,desired,source,replay,owner);
            original.ModelComparison=modelComparison;
            original.ReceivedEVM=receivedEVM.Metrics;
            % Both optional-model arms publish actual aggregate RX pairs.
            assert(receivedEVM.Metrics.Available, ...
                'test:CSIReceivedEVMIntegration','Original aggregate reference unavailable: %s', ...
                string(jsonencode(receivedEVM.Metrics)));
            [txPairs,~]=sixgr.phy.refsig.pairCSIRSTransmitterSymbols(p,tx);
            trial=table("DL",double(item.UE),1,double(item.Context.Slot), ...
                'VariableNames',{'Direction','UEIndex','CellID','Slot'});
            trial=sixgr.report.retainControlEVMPairs(current.run.rootRunFolder,trial,txPairs);
            txNames=string(trial.Properties.VariableNames);
            txNames=txNames(startsWith(txNames,"ControlEVMSamples"));
            originalTX=trial(:,txNames);
            trial=sixgr.report.retainCSIRSReceivedEVMPairs(current.run.rootRunFolder, ...
                trial,receivedEVM.Pairs,receivedEVM.Metrics);
            trial=sixgr.report.exportCSIRSReceivedEVMPairs(current.run.rootRunFolder,trial);
            assert(isequaln(originalTX,trial(:,txNames))&& ...
                trial.CSIRSReceivedEVMSamplesCount==receivedEVM.Metrics.SampleCount&& ...
                ~trial.CSIRSReceivedEVMRFConformanceQualified);
            sixgr.util.csvWriteTable(fullfile(current.run.rootRunFolder, ...
                sprintf('received_csi_evm_slot%d_ue%d.csv',item.Context.Slot,item.UE)),trial, ...
                'PreserveSchema',true);
            bad=trial; bad.CSIRSReceivedEVMIsolationEvidenceSHA256=string(repmat('0',1,64));
            rejected=false;
            try, sixgr.report.exportCSIRSReceivedEVMPairs(current.run.rootRunFolder,bad);
            catch cause, rejected=strcmp(cause.identifier,'sixgr:report:CSIRSReceivedEVMProof'); end
            assert(rejected,'test:CSIReceivedEVMGuard','Reject changed original isolation binding.');
            scorePath=fullfile(current.run.rootRunFolder, ...
                sprintf('original_model_score_slot%d_ue%d.mat',item.Context.Slot,item.UE));
            save(scorePath,'original','rx','modelComparison','-v7.3');
            assert(isequaln(unmodifiedRX,rx) && isequal(beforeScore,rng) && ...
                physicalClock==owner.Events.NextSampleIndex && ...
                physicalClock==owner.Physical.NextSampleIndex, ...
                'Optional model comparison must not alter the original receiver or physical execution.');
            assertModelComparison(modelComparison,original,item,rx,enabled);
            if enabled && item.UE==1 && item.Context.Slot==2
                assertModelComparisonGuards(item,rx,desired,source,replay,owner);
            end
            captures{end+1}=original; %#ok<AGROW>
        end
    end
end

function cfg=configuration(folder)
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
d=s.toStruct();
d.channels.model_type="CDL"; d.channels.profile="CDL-C";
d.channels.delay_spread_ns=100; d.channels.per_sample_fading_enabled=true;
% The AWGN parent authors zero Doppler, which legitimately selects the
% static reciprocal impulse wrapper even after changing its model family.
% This component explicitly exercises dynamic native CDL/Inf in BOTH arms;
% it is not a performance comparison to the inherited zero-Doppler case.
d.channels.doppler_source_mode="configured"; d.channels.doppler_hz=50;
d.channels.normalize_channel_outputs=false; d.channels.normalize_path_gains=true;
d.channels.awgn_beam_failure_recovery_enabled=false;
d.channels.awgn_spatial_matrix_dl_real=[]; d.channels.awgn_spatial_matrix_dl_imag=[];
d.channels.shared_identity_awgn_enabled=false;
d.power_and_rf_frontend.modeled_radiated_power.enabled=false;
d.power_and_rf_frontend.tx_spatial_power_enabled=false;
d.power_and_rf_frontend.tx_linear_reference=struct('enabled',true, ...
    'model',"fixed_first_order_pa_identity_dac",'classification',"optional_research_experiment");
cfg=sixgr.lls6g.buildInternalConfig(d,folder);
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,30);
cfg.run.rootRunFolder=folder;
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
cfg.phy.csirs.period_slots=1; cfg.phy.csirs.offset_slots=0;
cfg.phy.csirs.runtimeChannelEstimator='nr_channel_estimate';
cfg.phy.synchronization=struct('maxTimingUncertaintySamples',64);
cfg.phy.rx.cfoCorrectionEnabled=false;
cfg.phy.csi.reportConfiguration=[];
for name=["reportCSI","reportCQI","reportPMI","reportRI","reportCRI"]
    cfg.phy.csi.(name)=false;
end
cfg.phy.csirs.nPorts=4; cfg.phy.csirs.numPorts=4; cfg.phy.csirs.numResources=2;
cfg.phy.csirs.resourceSetID=9; cfg.phy.csirs.resourceID=17; cfg.phy.csirs.resourceIDs=[17 29];
cfg.phy.csirs.rowNumber=4; cfg.phy.csirs.rowNumbers=[4 4];
cfg.phy.csirs.density='one'; cfg.phy.csirs.cdmType='fd-CDM2';
cfg.phy.csirs.symbolLocations=3; cfg.phy.csirs.symbolLocationsByResource=[3 13];
cfg.phy.csirs.subcarrierLocations=0; cfg.phy.csirs.subcarrierLocationsByResource=[0 0];
cfg.phy.csirs.rbOffset=0; cfg.phy.csirs.rbOffsetsByResource=[0 0];
cfg.phy.csirs.numRB=24; cfg.phy.csirs.numRBsByResource=[24 24];
W=exp(1i*2*pi*(0:3).'*(0:3)/4)/2;
cfg.phy.csirs.precoderMatrices=cat(3,W,W*exp(.37i));
cfg.phy.csirs.precoderBeamIndices=repmat(0:3,2,1);
cfg.rf.specification.profile_id='rf_impaired_research'; cfg.rf.pa.enable=true;
cfg.rf.frontend.pa=struct('profile_id','declared_multiport_reference_PA','version','1', ...
    'input_backoff_db',2,'model','memory_polynomial', ...
    'reference_domain','normalized_complex_baseband_full_scale', ...
    'coefficients',[1+.2i .1-.03i;-.08+.015i .02+.006i],'orders',[1 3],'memory_depth',2);
cfg.rf.tx.timingOffsetSamples=3;
cfg.measurements.csiSelectionQuality.Enabled=false;
cfg.lls6g.energy_efficiency.enabled=false;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.outputs.rawIQCaptureEnabled=false; cfg.outputs.saveRawWaveforms=false;
cfg.outputs.continuousRawIQCaptureEnabled=false;
end

function r=initialChannelReceipt(s)
% Original value-only metadata survives a setup failure; no native handle,
% path-gain tensor, waveform or reconstructed initialization is archived.
r=struct('NativeClass',string(class(s.Obj)),'Direction',string(s.Direction), ...
    'NumTxAnt',s.NumTxAnt,'NumRxAnt',s.NumRxAnt, ...
    'CurrentSampleIndex',s.CurrentSampleIndex,'CurrentTime_s',s.CurrentTime_s, ...
    'SampleRateHz',s.SampleRate_Hz,'Seed',s.Seed, ...
    'TotalAppliedSamples',s.TotalAppliedSamples,'TotalObjectInputSamples',s.TotalObjectInputSamples, ...
    'SampleDensity',NaN,'MaximumDopplerShift',NaN,'NativeInitialTime',NaN, ...
    'FreshInitializationApplied',false,'NativeReciprocalFilterInitialization',struct());
for pair={"SampleDensity","SampleDensity";"MaximumDopplerShift","MaximumDopplerShift";"InitialTime","NativeInitialTime"}.'
    property=pair{1}; field=pair{2};
    if isobject(s.Obj)&&isprop(s.Obj,property), r.(field)=s.Obj.(property); end
end
if isfield(s.Meta,'NativeReciprocalFilterInitialization')
    r.NativeReciprocalFilterInitialization=s.Meta.NativeReciprocalFilterInitialization;
    r.FreshInitializationApplied=isequal(r.NativeReciprocalFilterInitialization.Applied,true);
end
end

function c=nativeClock(s)
fields=["Direction","CurrentSampleIndex","TotalAppliedSamples","TotalObjectInputSamples", ...
    "NumTxAnt","NumRxAnt","SampleRate_Hz","Seed"];
c=struct(); for name=fields, c.(name)=s.(name); end
c.NativeTime=s.Obj.InitialTime;
c.NativeSwapped=s.Obj.TransmitAndReceiveSwapped;
end

function assertOriginalEquivalence(a,b)
assert(a.EndSample==b.EndSample && isequaln(a.NativeClocks,b.NativeClocks) && ...
    numel(a.Trace)==numel(b.Trace) && numel(a.Captures)==numel(b.Captures) && ...
    isequaln(a.Initialization,b.Initialization) && ...
    isequaln(a.InitialChannels,b.InitialChannels) && ...
    isequaln(a.SlotClocks,b.SlotClocks) && ...
    isequal(a.RNGAfterPhysicalExecution,b.RNGAfterPhysicalExecution));
for k=1:numel(a.Trace)
    x=a.Trace{k}.Execution; y=b.Trace{k}.Execution;
    assert(x.StartSample==y.StartSample&&x.EndSampleExclusive==y.EndSampleExclusive && ...
        isequaln(x.TX,y.TX)&&isequaln(x.RX,y.RX) && ...
        isequaln(x.ExecutedContributors,y.ExecutedContributors), ...
        'The independent model must preserve every original RF interval/hash/consumed contributor.');
end
for k=1:numel(a.Captures)
    for name=["UE","Slot","ParentID","TX","PreRF","PostRF","Desired", ...
            "OriginalReceiveSHA256","OriginalParentSHA256","MeasuredH","MeasuredResources", ...
            "DemodulationJSON","StartSample","EndSampleExclusive"]
        assert(isequaln(a.Captures{k}.(name),b.Captures{k}.(name)), ...
            'test:CSIReferencePhysicalChange','Reference model changed original %s.',name);
    end
end
end

function rows=scopeRows(captures,enabled)
rows=table();
for k=1:numel(captures)
    c=captures{k};
    row=table(c.UE,c.Slot,enabled,c.StartSample,c.EndSampleExclusive, ...
        c.OriginalReceiveSHA256,c.OriginalParentSHA256,c.ReferenceReceiptJSON,c.ReferenceReceiptSHA256, ...
        false,false,false, ...
        'VariableNames',{'UEIndex','Slot','ModelEnabled','StartSample','EndSampleExclusive', ...
        'OriginalReceiveSHA256','OriginalParentSHA256','ReferenceReceiptJSON','ReferenceReceiptSHA256', ...
        'CanonicalFeedbackQualified','UniqueNonlinearPortTruthQualified','StandardizedAccuracyQualified'});
    row.SFN=c.SFN; row.ResourceID=c.ResourceID; row.ReceiverWindowID=c.ReceiverWindowID;
    for name=string(fieldnames(c.ModelComparison)).'
        row.(name)=c.ModelComparison.(name);
    end
    rows=[rows;row]; %#ok<AGROW>
end
end

function original=assertModelPlanes(original,item,source,owner)
% Inspect receipts already committed BEFORE this actual callback. Model
% buffers are never passed to the practical receiver above.
ids=string({item.Planes.ReceiverID}); refs=item.Context.CSIRSPortReferencePlanes;
assert(numel(refs)==2 && all([refs.ReferencePortNumber]==3000));
total=zeros(size(original.Desired),'like',original.Desired);
registered=owner.Physical.readCSIRSPortReferenceRegistrations();
originalReceipts=cell(0,1);
for ref=reshape(refs,1,[])
    hit=find(ids==string(ref.PlaneID)); assert(isscalar(hit));
    buffer=item.Planes(hit).Observation;
    assert(buffer.isComplete() && buffer.StartSample==original.StartSample && ...
        buffer.EndSampleExclusive==original.EndSampleExclusive && buffer.SampleRateHz==owner.SampleRateHz);
    samples=buffer.readComplete(); total=total+samples;
    original.ModelPlanes.("Resource"+ref.ResourceID)=samples;
    parent=registered.Parents(arrayfun(@(x) ...
        string(x.Parent.Receipt.ComponentID)==string(item.Context.ComponentID),registered.Parents)).Parent;
    assert(isscalar(parent) && parent.RegistrationSHA256==ref.RegistrationSHA256 && ...
        parent.Receipt.OriginalSampleSHA256==original.OriginalParentSHA256);
    segments=item.Planes(hit).Segments;
    cursor=buffer.StartSample;
    for n=1:numel(segments)
        segment=segments{n}; execution=segment.Execution;
        assertCommitted(execution);
        assert(segment.StartSample==cursor && segment.EndSampleExclusive<=buffer.EndSampleExclusive);
        q=execution.CSIRSPortReferences(string({execution.CSIRSPortReferences.PlaneID})==ref.PlaneID);
        assert(isscalar(q) && q.SuccessfulContributorCommit && q.Active && ...
            q.OriginalOwnerOperandsBound && q.ParentComponentID==original.ParentID && ...
            q.RegistrationSHA256==ref.RegistrationSHA256 && q.ResourceID==ref.ResourceID && ...
            q.ResourceSetID==ref.ResourceSetID && q.LogicalPortIndex0==0 && ...
            q.ReferencePortNumber==3000 && q.OriginalParentSampleSHA256==original.OriginalParentSHA256 && ...
            q.OriginalEnqueueReceiptSHA256==parent.Receipt.ReceiptSHA256 && ...
            q.StartSample==segment.StartSample && q.EndSampleExclusive==segment.EndSampleExclusive && ...
            q.ConfigurationEpoch==execution.ConfigurationEpoch && q.SampleRateHz==owner.SampleRateHz && ...
            ~q.ModelSourceSupportEndAppliedAsTrim && ~q.CommonIQDCIncluded && ...
            ~q.ActualNonlinearPortAttribution && ~q.StandardizedPowerAccuracyQualified && ...
            ~q.HardwareQualified && ~q.ReceiverEstimatorInput && ...
            q.AdditionalRFExecutions==0 && q.AdditionalChannelExecutions==0);
        rows=(q.StartSample-buffer.StartSample+1):(q.EndSampleExclusive-buffer.StartSample);
        assert(q.OutputSHA256==sixgr.phy.waveform.WaveformHash.numeric(samples(rows,:)));
        assertOriginalContributor(execution,parent.Receipt);
        if ~isempty(fieldnames(q.OriginalChannelAdapter))
            ch=q.OriginalChannelAdapter; rf=q.OriginalRFAdapter;
            assert(ch.StartSample==q.StartSample && ch.EndSampleExclusive==q.EndSampleExclusive && ...
                ch.TX==q.TransmitterID && ch.LinkID==q.LinkID && ch.Direction=="DL" && ...
                ch.DesiredOutputSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(samples(rows,:)) && ...
                ch.LossApplicationCount==1 && ~ch.AdditionalNormalizationApplied && ...
                ~ch.SourceSupportEndAppliedAsTrim && ~ch.OriginalOwnerVerified && ...
                ch.AdditionalChannelExecutions==0 && ~ch.ReceiverEstimatorInput);
            if isfield(rf,'RetiredAfterFiniteSupport')
                assert(rf.RetiredAfterFiniteSupport && q.StartSample>=rf.RetireAfterSample && ...
                    ch.ComponentInputSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray( ...
                    complex(zeros(numel(rows),size(item.Context.Prepared.TransmitSamples,2)))));
            else
                assert(ch.ComponentInputSHA256==rf.ReferenceOutputSHA256 && ...
                    ~rf.OriginalOwnerVerified && rf.Role=="component" && ...
                    ~rf.AggregateCommonIQDCIncluded && ~rf.ResidualAvailable && ...
                    rf.AdditionalRFExecutions==0 && ~rf.ReceiverEstimatorInput);
            end
        else
            assert(q.StartSample>=q.RetireAfterSample && ~any(samples(rows,:)~=0,'all'), ...
                'Only proved finite-support retirement may omit the active component adapters.');
        end
        originalReceipts{end+1}=q; %#ok<AGROW>
        cursor=segment.EndSampleExclusive;
    end
    assert(cursor==buffer.EndSampleExclusive);
    % Resource 29 occupies the last actual OFDM symbol. Its RF/native FIR
    % tail must be observed beyond the parent's original input support.
    if ref.ResourceID==29
        tail=(parent.Receipt.EndSampleExclusive-buffer.StartSample+1):size(samples,1);
        assert(~isempty(tail) && any(samples(tail,:)~=0,'all'), ...
            'The actual last-symbol component tail must not be trimmed at parent input end.');
    end
end
modelHit=find(ids==string(item.Context.CSIModelAggregatePlane));
residualHit=find(ids==string(item.Context.CSIModelResidualPlane));
assert(isscalar(modelHit)&&isscalar(residualHit));
model=item.Planes(modelHit).Observation.readComplete();
residual=item.Planes(residualHit).Observation.readComplete();
assert(isequal(size(model),size(original.Desired))&&isequal(size(residual),size(model)));
error=norm(original.Desired-model-residual,'fro');
scale=norm(original.Desired,'fro')+norm(model,'fro')+norm(residual,'fro');
assert(error<=16*eps(max(1,scale)), ...
    'Model residual must close against the original desired contribution, not other CSI ports.');
original.ModelPlanes.Aggregate=model; original.ModelPlanes.Residual=residual;
original.ModelPlanes.OtherLinearContribution=model-total;
assert(norm(residual,'fro')>0,'The actual declared nonlinear PA must retain a separate residual.');
aggregateReceipts=cell(0,1);
segments=item.Planes(modelHit).Segments;
for n=1:numel(segments)
    execution=segments{n}.Execution; assertCommitted(execution);
    q=execution.CSIModelReferences(string({execution.CSIModelReferences.AggregatePlaneID})== ...
        string(item.Context.CSIModelAggregatePlane));
    assert(isscalar(q)&&q.SuccessfulContributorCommit&&q.Active&& ...
        q.ResidualPlaneID==string(item.Context.CSIModelResidualPlane)&& ...
        ~q.ActualNonlinearPortAttribution&&~q.StandardizedPowerAccuracyQualified&&~q.ReceiverEstimatorInput);
    rows=(q.StartSample-original.StartSample+1):(q.EndSampleExclusive-original.StartSample);
    assert(q.AggregateSHA256==sixgr.phy.waveform.WaveformHash.numeric(model(rows,:))&& ...
        q.ResidualSHA256==sixgr.phy.waveform.WaveformHash.numeric(residual(rows,:))&& ...
        q.ActualDesiredSHA256==sixgr.phy.waveform.WaveformHash.numeric(original.Desired(rows,:)));
    aggregateReceipts{end+1}=q; %#ok<AGROW>
end
receipt=struct('Scope',"actual_queued_fixed_linear_port_model_component_not_canonical_feedback", ...
    'ParentComponentID',string(item.Context.ComponentID),'Source',source, ...
    'References',refs,'AggregatePlane',string(item.Context.CSIModelAggregatePlane), ...
    'ResidualPlane',string(item.Context.CSIModelResidualPlane), ...
    'OriginalCommittedPortIntervals',{originalReceipts}, ...
    'OriginalCommittedAggregateIntervals',{aggregateReceipts}, ...
    'ReceiverEstimatorInput',false,'UniqueNonlinearPortTruthQualified',false, ...
    'StandardizedAccuracyQualified',false);
original.ReferenceReceiptJSON=string(jsonencode(receipt));
original.ReferenceReceiptSHA256=string(sixgr.util.sha256Hex(char(original.ReferenceReceiptJSON)));
end

function assertCommitted(x)
assert(x.CSIReferenceCommit.Committed && ~x.CSIReferenceCommit.ReceiverEstimatorInput && ...
    x.CSIReferenceCommit.StartSample==x.StartSample && ...
    x.CSIReferenceCommit.EndSampleExclusive==x.EndSampleExclusive && ...
    x.CSIReferenceCommit.Source=="original_event_output_validation_and_exact_contributor_join_before_dispatch");
end

function assertOriginalContributor(x,q)
t=x.ExecutedContributors(string({x.ExecutedContributors.TransmitterID})==q.TransmitterID);
assert(isscalar(t)&&t.Receipt.CompleteContributorList&&t.CommittedThroughSample>=x.EndSampleExclusive);
lo=max(x.StartSample,q.StartSample); hi=min(x.EndSampleExclusive,q.EndSampleExclusive);
components=t.Receipt.Components;
hit=find(string({components.ComponentID})==q.ComponentID);
if lo<hi
    assert(isscalar(hit)&&components(hit).StartSample==lo&&components(hit).EndSampleExclusive==hi && ...
        components(hit).OriginalSampleSHA256==q.OriginalSampleSHA256);
else
    assert(isempty(hit),'RF/channel tails must not be relabelled as new composer input.');
end
end

function assertReferenceChronology(trace,registration,slotSamples)
assert(numel(registration.Parents)==2&&numel(registration.Planes)==8);
seenPreBirth=false; seenReturnedBirth=false; seenRetired=false; seenReverse=false;
for n=1:numel(trace)
    x=trace{n}.Execution;
    if ~isfield(x,'CSIRSPortReferences'), continue; end
    assertCommitted(x);
    for q=x.CSIRSPortReferences
        assert(q.SuccessfulContributorCommit);
        ch=q.OriginalChannelAdapter;
        if ~q.Active, seenReverse=true; continue; end
        if isempty(fieldnames(ch))
            assert(x.StartSample>=q.RetireAfterSample); seenRetired=true; continue;
        end
        plane=registration.Planes(string({registration.Planes.ID})==q.PlaneID);
        assert(isscalar(plane)); birth=plane.Component.Birth;
        if ~isfield(q.OriginalRFAdapter,'RetiredAfterFiniteSupport')
            assert(q.OriginalRFAdapter.OriginSample==0);
        end
        assert( ...
            ch.OriginalBirthSnapshot.TotalObjectInputSamples- ...
            ch.OriginalBirthSnapshot.CurrentSampleIndex==ch.ObjectTimeOffsetSamples && ...
            ch.ModelHistoryStartSample<=birth.ComponentSupportStartSample);
        if birth.ComponentSupportStartSample==slotSamples
            assert(birth.ModelHistoryStartSample==37 && ch.ModelHistoryStartSample==37);
            if x.EndSampleExclusive<=birth.ComponentSupportStartSample
                assert(q.OriginalRFAdapter.ReferenceEnergy==0); seenPreBirth=true;
            end
        else
            assert(birth.ComponentSupportStartSample==5*slotSamples && ...
                birth.ModelHistoryStartSample==4*slotSamples);
            assert(ch.ModelHistoryStartSample==5*slotSamples && ...
                ch.InputHistoryStartSample==5*slotSamples && ~ch.NativeSwapped);
            seenReturnedBirth=true;
        end
    end
end
assert(seenPreBirth&&seenReturnedBirth&&seenRetired&&seenReverse, ...
    'Exercise original late birth, leading zeros, finite retirement and actual TDD return.');
end

function assertRegistrationAndConsumptionGuards(owner,folder)
original=owner.Physical.readCSIRSPortReferenceRegistrations();
p=owner.Pending(1).Context.Prepared; plane=original.Planes(1);
clock=owner.Events.NextSampleIndex; before=rng;
for mutation=1:3
    bad=p;
    switch mutation
        case 1, bad.Tx.CSIRSRuntimeEvent.ResourceEvents(1).ResourceID=bad.Tx.CSIRSRuntimeEvent.ResourceEvents(1).ResourceID+1;
        case 2, bad.Tx.CSIRSRuntimeEvent.ResourceEvents(1).WaveformPrecoderMatrix(1)= ...
                bad.Tx.CSIRSRuntimeEvent.ResourceEvents(1).WaveformPrecoderMatrix(1)+.01;
        case 3, bad.TransmitSamples(1)=bad.TransmitSamples(1)+.01;
    end
    id="RF:TXReferenceBroadcastMismatch";
    if mutation==3, id="RF:TXReferenceComponentOwner"; end
    reject(@()owner.Physical.registerCSIRSPortReferences(owner.Events,plane.LinkID, ...
        "gnb_1","ue_1_rx",plane.Component.ParentComponentID,bad),id);
    assert(isequaln(original,owner.Physical.readCSIRSPortReferenceRegistrations())&& ...
        owner.Events.NextSampleIndex==clock&&isequal(before,rng));
end
% Value checkpoint of the ORIGINAL accepted owner, never reconstructed
% factor authority. Mutations run only on independent restored copies and
% are rejected before original RF/channel execution begins.
path=fullfile(folder,'registered_original_owner_checkpoint.mat');
save(path,'owner','-v7.3'); originalSHA=string(sixgr.util.sha256File(path));
for mode=["cancel","replace"]
    restored=load(path,'owner'); copy=restored.owner;
    if mode=="cancel"
        copy.Events.cancelUnemittedComponent("gnb_1",plane.Component.ParentComponentID);
    else
        copy.Events.replaceUnemittedComponent("gnb_1",plane.Component.ParentComponentID, ...
            sixgr.phy.waveform.WaveformChunk(p.TransmitSamples*1.01,p.TransmitStartSample));
    end
    for tx=["gnb_1","ue_1","ue_2"], copy.Events.commitTransmissionsThrough(tx,clock+1); end
    previous=numel(copy.Events.ExecutionTrace);
    reject(@()copy.Events.advanceUntilEvent(clock+1),"WAVEFORM:CSIReferenceOriginalComponentChanged");
    assert(copy.Events.Faulted&&copy.Physical.NextSampleIndex==clock&& ...
        numel(copy.Events.ExecutionTrace)==previous);
end
assert(owner.Events.NextSampleIndex==clock&&~owner.Events.Faulted&&isequal(before,rng)&& ...
    originalSHA==string(sixgr.util.sha256File(path))&& ...
    isequaln(original,owner.Physical.readCSIRSPortReferenceRegistrations()));
end

function assertModelComparison(result,original,item,rx,enabled)
prefix="CSIRSLinearPortModelComparison";
schema=sixgr.truth.emptyCSIRSTrialTable();
for name=string(fieldnames(result)).'
    assert(ismember(name,string(schema.Properties.VariableNames)) && ...
        strcmp(class(schema.(name)),class(result.(name))), ...
        'test:CSIModelScoreSchema','Original producer field %s must have the canonical declared type.',name);
end
assert(~result.(prefix+"UniqueNonlinearPortAttributionQualified") && ...
    ~result.(prefix+"StandardizedAccuracyQualified") && ~result.(prefix+"HardwareQualified"));
if ~enabled
    assert(~result.(prefix+"Available") && result.(prefix+"ResourceCount")==0 && ...
        result.(prefix+"EvidenceJSON")=="" && result.(prefix+"EvidenceSHA256")=="" && ...
        isnan(result.(prefix+"ReportedPowerError_dB")));
    return;
end
assert(result.(prefix+"Available"),'test:CSIModelScoreUnavailable', ...
    'Original model score unavailable: %s; original measured evidence was saved.',result.(prefix+"ErrorIdentifier"));
token=result.(prefix+"EvidenceJSON");
assert(result.(prefix+"EvidenceSHA256")==string(sixgr.util.sha256Hex(char(token))));
e=jsondecode(token); resources=e.ResourceComparisons;
if iscell(resources), resources=vertcat(resources{:}); end
ids=[item.Context.Prepared.Tx.CSIRSInfo.Resources.ResourceID];
assert(result.(prefix+"ResourceCount")==numel(ids) && isequal([resources.ResourceID],ids) && ...
    all([resources.ReferencePort]==3000) && string(e.ObservationID)==item.ID && ...
    string(e.ParentComponentID)==original.ParentID && ...
    string(e.OriginalDemodulationReceiptSHA256)== ...
        string(rx.PhysicalMeasurementDemodulationReceiptSHA256) && ...
    ~e.ReferenceUsedByReceiver && ~e.UniqueNonlinearPortAttributionQualified && ...
    ~e.StandardizedAccuracyQualified && ~e.StatisticallyQualified && ~e.HardwareQualified && ...
    e.AdditionalTimingAcquisitions==0 && e.AdditionalRFExecutions==0 && e.AdditionalChannelExecutions==0);
for k=1:numel(resources)
    q=resources(k); x=original.ModelPlanes.("Resource"+ids(k));
    assert(string(q.OriginalTargetInputSHA256)==sixgr.phy.waveform.WaveformHash.runtimeArray(x) && ...
        string(q.TargetPlaneID)==item.Context.CSIRSPortReferencePlanes(k).PlaneID && ...
        ~isempty(q.OriginalCommittedIntervals));
    for name=["SignalSupportClosure","DisturbanceSupportClosure"]
        closure=q.(name);
        assert(~closure.PowerAdditivityAssumed && ~closure.PhysicalAccuracyThresholdApplied && ...
            all(abs(closure.PowerClosureResidualPerReceiveColumn)<=closure.NumericalRoundoffBound));
    end
end
selected=rx.CSIRSObservation.MeasurementSelectedResourceOrdinal;
assert(e.SelectedResourceOrdinal1==selected && result.(prefix+"SelectedResourceID")==ids(selected));
q=resources(selected);
% JSON numeric tokens retain NaN/-Inf without creating a finite error score.
assert(isequaln(result.(prefix+"ReportedPowerError_dB"), ...
    str2double(string(q.PowerNumericTokens.ReportedError_dB))) && ...
    isequaln(result.(prefix+"SelectedColumnPowerError_dB"), ...
    str2double(string(q.PowerNumericTokens.MeasuredSelectedColumnError_dB))));
end

function assertModelComparisonGuards(item,rx,desired,source,replay,owner)
prefix="CSIRSLinearPortModelComparison"; before=rng; clock=owner.Events.NextSampleIndex;
originalRX=rx; trace=owner.Events.ExecutionTrace;
target=find(string({item.Planes.ReceiverID})==item.Context.CSIRSPortReferencePlanes(1).PlaneID);
pre=find(string({item.Planes.ReceiverID})==string(source.ReceiverID)+":pre_rf");
assert(isscalar(target)&&isscalar(pre));
for mutation=1:11
    bad=item; received=rx; id="sixgr:truth:CSIRSLinearModelIdentity";
    switch mutation
        case 1 % Dropped original resource, not a new smaller population.
            bad.Context.CSIRSPortReferencePlanes(1)=[];
        case 2 % Same population in the wrong original resource order.
            bad.Context.CSIRSPortReferencePlanes=bad.Context.CSIRSPortReferencePlanes([2 1]);
        case 3
            bad.Context.Prepared.Tx.CSIRSInfo.Resources(1).Indices(1)= ...
                bad.Context.Prepared.Tx.CSIRSInfo.Resources(1).Indices(1)+1;
            id="sixgr:truth:CSIRSLinearModelParent";
        case 4 % Same-length replacement plus a resealed local receipt must
               % still fail its join to the original committed Event trace.
            b=item.Planes(target).Observation; x=b.readComplete(); x(1)=x(1)+.01;
            copy=sixgr.phy.waveform.WaveformObservationBuffer(b.StartSample,b.EndSampleExclusive, ...
                b.SampleRateHz,b.NumReceiveAntennas);
            copy.append(sixgr.phy.waveform.WaveformChunk(x,b.StartSample),b.SampleRateHz);
            bad.Planes(target).Observation=copy;
            q=bad.Planes(target).Segments{1}.Execution.CSIRSPortReferences;
            hit=find(string({q.PlaneID})==bad.Context.CSIRSPortReferencePlanes(1).PlaneID);
            rows=(q(hit).StartSample-b.StartSample+1):(q(hit).EndSampleExclusive-b.StartSample);
            q(hit).OutputSHA256=sixgr.phy.waveform.WaveformHash.numeric(x(rows,:));
            bad.Planes(target).Segments{1}.Execution.CSIRSPortReferences=q;
            id="sixgr:truth:CSIRSLinearModelCommit";
        case 5 % Actual noisy receiver is not a target reference merely
               % because it has the same shape, support and valid hash.
            bad.Planes(target).Observation=item.Planes(pre).Observation;
            id="sixgr:truth:CSIRSLinearModelCommit";
        case 6
            received.CSIRSObservation.MeasurementPhysicalResources{1}.SINR.DesiredPowerPerReceiveAntenna(1)= ...
                received.CSIRSObservation.MeasurementPhysicalResources{1}.SINR.DesiredPowerPerReceiveAntenna(1)+.01;
        case 7
            q=bad.Planes(target).Segments{1}.Execution.CSIRSPortReferences;
            q(1)=[]; bad.Planes(target).Segments{1}.Execution.CSIRSPortReferences=q;
            id="sixgr:truth:CSIRSLinearModelCommit";
        case 8
            received.CSIRSObservation.MeasurementRSRP_dB_re_UnitOccupiedRE_Es= ...
                received.CSIRSObservation.MeasurementRSRP_dB_re_UnitOccupiedRE_Es+1;
        case 9
            bad.Planes(target).Segments{1}.Execution.CSIReferenceCommit.Committed=false;
            id="sixgr:truth:CSIRSLinearModelCommit";
        case 10 % A resealed copied token cannot turn a character code into
                % an original numeric resource identity.
            received.CSIRSObservation.MeasurementPhysicalResources{1}.ResourceID= ...
                char(received.CSIRSObservation.MeasurementPhysicalResources{1}.ResourceID);
            received.CSIRSObservation.MeasurementPhysicalResourcesJSON=string(jsonencode( ...
                sixgr.util.jsonSafeValue(received.CSIRSObservation.MeasurementPhysicalResources)));
        case 11
            bad.Context.CSIRSPortReferencePlanes(1).ResourceID= ...
                char(bad.Context.CSIRSPortReferencePlanes(1).ResourceID);
    end
    result=sixgr.truth.scoreSharedCSIRSLinearPortModel(bad,received,desired,source,replay,owner);
    assert(~result.(prefix+"Available") && result.(prefix+"ErrorIdentifier")==id && ...
        result.(prefix+"ResourceCount")==0 && isnan(result.(prefix+"ReportedPowerError_dB")) && ...
        isnan(result.(prefix+"ReportedSINRError_dB")), ...
        'test:CSIModelScoreMissingRejection','Mutation %d returned %s, expected %s.', ...
        mutation,result.(prefix+"ErrorIdentifier"),id);
end
assert(isequaln(rx,originalRX) && isequal(before,rng) && ...
    owner.Events.NextSampleIndex==clock && owner.Physical.NextSampleIndex==clock && ...
    isequaln(trace,owner.Events.ExecutionTrace));
fprintf('CSIRS_MULTIPORT_ORIGINAL_MODEL_SCORE_GUARDS_PASS negatives=11\n');
end

function evidence=assertCheckpointContinuation(path,digest,before,owner,state,cfg,originalCompleted)
% This is a new physical continuation of an independent restored TEST owner,
% not another channel execution by the diagnostic reference model. Native
% RNG, both model histories and original pending observation objects come
% only from the saved graph. No reset/reseed/re-registration is permitted.
originalAfter=checkpointOwnerValues(owner,state); originalRNG=rng;
assert(numel(originalCompleted)==2 && isempty(owner.Pending) && ...
    originalAfter.EventSample>before.EventSample);
loaded=load(path,'owner','state'); resumed=loaded.owner;
assert(resumed~=owner && loaded.state.SharedWaveformStream==resumed && ...
    isequaln(before,checkpointOwnerValues(resumed,loaded.state)) && isequal(originalRNG,rng), ...
    'test:CSIReferenceCheckpointGraph','Load the exact original attached owner/state graph.');
resumedState=sixgr.truth.CoupledTruthRuntime.startSlot( ...
    loaded.state,cfg,'DL',1,1,3,7,30);
resumedState.CurrentServingIdx(:)=1;
[resumedState,resumedCompleted]=resumed.advanceSlot(resumedState,cfg,[]);
restoredAfter=checkpointOwnerValues(resumed,resumedState);
% Stage compact actual originals before comparing them. The source MAT is
% retained unchanged even if restored commit/dispatch or an equality fails.
diagnosticPath=fullfile(fileparts(path),'original_slot3_checkpoint_comparison.mat');
save(diagnosticPath,'before','originalAfter','restoredAfter','originalRNG','-v7.3');
assert(isequaln(originalAfter,restoredAfter) && isequal(originalRNG,rng), ...
    'test:CSIReferenceCheckpointContinuation','Restored physical/model/ledger clocks or receipts differ.');
assert(numel(resumedCompleted)==numel(originalCompleted));
planeRows=cell(0,1);
for k=1:numel(originalCompleted)
    a=originalCompleted(k); b=resumedCompleted(k);
    assert(a.ID==b.ID && a.Kind==b.Kind && a.UE==b.UE && ...
        isequal(string({a.Planes.ReceiverID}),string({b.Planes.ReceiverID})));
    for name=["ComponentID","Slot","Frame","UEIndex","ServingCell","RNTI", ...
            "DesiredReferencePlane","TransmitterPlane","CSIRSPortReferencePlanes", ...
            "CSIModelAggregatePlane","CSIModelResidualPlane"]
        assert(isequaln(a.Context.(name),b.Context.(name)), ...
            'test:CSIReferenceCheckpointIdentity','Restored original context %s differs.',name);
    end
    for j=1:numel(a.Planes)
        x=a.Planes(j).Observation; y=b.Planes(j).Observation;
        assert(x.isComplete() && y.isComplete() && x.StartSample==y.StartSample && ...
            x.EndSampleExclusive==y.EndSampleExclusive && x.SampleRateHz==y.SampleRateHz && ...
            x.NumReceiveAntennas==y.NumReceiveAntennas && ...
            isequaln(x.readComplete(),y.readComplete()) && x.sampleHash()==y.sampleHash() && ...
            isequaln(a.Planes(j).Segments,b.Planes(j).Segments), ...
            'test:CSIReferenceCheckpointPlane','Original/restored samples or committed segment operands differ.');
        planeRows{end+1,1}=struct('ObservationID',a.ID,'UE',a.UE, ...
            'PlaneID',string(a.Planes(j).ReceiverID),'StartSample',x.StartSample, ...
            'EndSampleExclusive',x.EndSampleExclusive,'SampleSHA256',x.sampleHash()); %#ok<AGROW>
    end
end
newTrace=originalAfter.Trace(numel(before.Trace)+1:end);
assert(~isempty(newTrace) && isequaln(before.Trace,originalAfter.Trace(1:numel(before.Trace))));
for name=["Intervals","ChainPowerIntervals","TXLinearReferenceIntervals"]
    previous=before.Ledger.(name); next=originalAfter.Ledger.(name);
    assert(height(next)>height(previous) && isequaln(previous,next(1:height(previous),:)), ...
        'test:CSIReferenceCheckpointLedgerPrefix','Resume must append once without rewriting original ledger rows.');
end
expectedModelRows=sum(cellfun(@(x)numel(x.Execution.TXLinearReferences),newTrace));
assert(height(originalAfter.Ledger.TXLinearReferenceIntervals)- ...
    height(before.Ledger.TXLinearReferenceIntervals)==expectedModelRows && ...
    originalAfter.Ledger.TXLinearReferenceCompleteFromOrigin);
% Running the restored branch must leave the uninterrupted original graph,
% source file and global RNG untouched. No practical receiver was called.
assert(isequaln(originalAfter,checkpointOwnerValues(owner,state)) && ...
    string(sixgr.util.sha256File(path))==digest && isequal(originalRNG,rng));
evidence=struct('Source',"original_attached_owner_pending_tail_checkpoint", ...
    'CheckpointFile',string(path),'CheckpointSHA256',digest, ...
    'CheckpointSample',before.EventSample,'ContinuedThroughSample',originalAfter.EventSample, ...
    'CompletedOriginalObservations',numel(originalCompleted),'ComparedPlaneCount',numel(planeRows), ...
    'CommittedIntervalCount',numel(newTrace),'AppendedModelReceiptCount',expectedModelRows, ...
    'ExactOriginalAndModelSamples',true,'ExactCommittedReceiptsAndLedger',true, ...
    'RestoredReceiverExecutionCount',0,'PhysicalFeedbackQualified',false, ...
    'PlaneIdentities',{planeRows});
save(diagnosticPath,'before','originalAfter','restoredAfter','originalRNG','evidence','-v7.3');
fprintf('CSIRS_MULTIPORT_ATTACHED_CHECKPOINT_PASS observations=%d planes=%d intervals=%d receiver_reexecutions=0\n', ...
    numel(originalCompleted),numel(planeRows),numel(newTrace));
end

function value=checkpointOwnerValues(owner,state)
% Value-only snapshot. Native objects are represented by their actual public
% clock/direction fields; exact continuation samples test their hidden state.
channels=owner.Physical.channelStates();
value=struct('EventSample',owner.Events.NextSampleIndex, ...
    'PhysicalSample',owner.Physical.NextSampleIndex,'Faulted',owner.Events.Faulted, ...
    'Trace',{owner.Events.ExecutionTrace},'Ledger',owner.Physical.readRFExecutionLedger(), ...
    'Registrations',owner.Physical.readCSIRSPortReferenceRegistrations(), ...
    'NativeClocks',{cellfun(@nativeClock,channels,'UniformOutput',false)}, ...
    'CSIRSTransmissions',owner.CSIRSTransmissions,'DataTransmissions',owner.DataTransmissions, ...
    'CurrentSlot',state.CurrentSlot,'CurrentSweepPointIndex',state.CurrentSweepPointIndex, ...
    'CurrentSNR_dB',state.CurrentSNR_dB,'CurrentServingIdx',state.CurrentServingIdx, ...
    'PendingIDs',string({owner.Pending.ID}),'PendingUEs',[owner.Pending.UE]);
value.StateTables=struct();
for name=string(fieldnames(state)).'
    if istable(state.(name)), value.StateTables.(name)=state.(name); end
end
value.ControlTrials=state.ControlTrials;
value.PendingPlanes=cell(numel(owner.Pending),1);
for k=1:numel(owner.Pending)
    p=owner.Pending(k); rows=cell(numel(p.Planes),1);
    for j=1:numel(p.Planes)
        b=p.Planes(j).Observation;
        rows{j}=struct('ReceiverID',string(p.Planes(j).ReceiverID), ...
            'StartSample',b.StartSample,'EndSampleExclusive',b.EndSampleExclusive, ...
            'ReceivedThroughSample',b.ReceivedThroughSample,'SampleRateHz',b.SampleRateHz);
    end
    value.PendingPlanes{k}=rows;
end
end

function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==string(id),'Unexpected rejection %s instead of %s.',cause.identifier,id);
    return;
end
error('test:CSIReferenceMissingRejection','Expected %s.',id);
end
