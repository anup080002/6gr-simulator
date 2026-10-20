function [ok,state]=testSharedPUSCHChannelArtifacts(mode,withCoincidentSRS,deferUCIDelivery,withCSI,twoPortUL,receivedAuthority,withHARQ,outputRoot,configPath,independentEmptyUCI,independentSharedHARQ,forgetCSIProducer,unconsumedULCommand,pucchOnlyCompletion,expectedULPorts,separatePUCCH,withPacketAccounting)
% Actual shared SRS -> received UL DCI -> coded PUSCH with HARQ-ACK UCI.
% Initial TAG remains an explicit component input. In a configured-Es/N0
% fixture, geometry/pathloss are deliberately not applicable. The two UCI bits
% use isolated coded DL receptions in legacy modes. independentSharedHARQ
% instead produces its feedback through this same shared CDL owner.
% One grant does not qualify access or adaptation.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
if nargin<2, withCoincidentSRS=false; end
if nargin<3, deferUCIDelivery=false; end
if nargin<4, withCSI=false; end
if nargin<5, twoPortUL=false; end
if nargin<6, receivedAuthority=false; end
if nargin<7, withHARQ=false; end
if nargin<10, independentEmptyUCI=false; end
if nargin<11, independentSharedHARQ=false; end
if nargin<12, forgetCSIProducer=false; end
if nargin<13, unconsumedULCommand=false; end
if nargin<14, pucchOnlyCompletion=false; end
if nargin<15, expectedULPorts=2; end
if nargin<16, separatePUCCH=false; end
if nargin<17, withPacketAccounting=false; end
assert(~withPacketAccounting || (independentSharedHARQ && ~withHARQ && ~unconsumedULCommand));
assert(~separatePUCCH || (independentSharedHARQ && ~withCSI && ...
    ~pucchOnlyCompletion && ~unconsumedULCommand && ~forgetCSIProducer));
assert(isscalar(expectedULPorts) && any(expectedULPorts==[2 4]));
assert(~pucchOnlyCompletion || (independentSharedHARQ && withCSI && ...
    ~unconsumedULCommand && ~forgetCSIProducer));
assert(~unconsumedULCommand || (independentSharedHARQ && ~forgetCSIProducer));
assert(~forgetCSIProducer || (independentSharedHARQ && withCSI));
assert(~(independentEmptyUCI && independentSharedHARQ));
independentCompletion=independentEmptyUCI || independentSharedHARQ;
if independentCompletion
    assert(string(mode)=="TDD" && receivedAuthority && twoPortUL && ...
        (~withCSI || independentSharedHARQ) && ~withHARQ && ~deferUCIDelivery && ~withCoincidentSRS);
end
assert(any(string(mode)==["TDD","FDD"]));
fixture='lls_pdcch_shared_queue_fixture.yaml';
if string(mode)=="FDD", fixture='lls_pusch_shared_queue_fdd_fixture.yaml'; end
if withCSI
    assert(string(mode)=="TDD",'The deferred CSI component scenario is authored for TDD.');
    fixture='lls_pusch_csi_delivery_fixture.yaml';
end
if twoPortUL
    assert(string(mode)=="TDD" && (~withCSI || independentSharedHARQ));
    fixture='lls_two_port_ul_shared_queue_fixture.yaml';
end
if receivedAuthority
    assert(twoPortUL && (~withCSI || independentSharedHARQ));
    fixture='lls_received_ul_shared_queue_fixture.yaml';
end
if withHARQ
    assert(receivedAuthority && ~withCoincidentSRS && ~deferUCIDelivery && ~withCSI);
    fixture='lls_received_ul_harq_shared_fixture.yaml';
end
if nargin<9, configPath=fullfile('simulator','configs','scenarios',fixture); end
s=sixgr.lls6g.config.loadScenarioConfig(configPath);
if nargin<8, outputRoot=tempname; end
root=outputRoot; mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
% Installed blind monitoring needs an actually received DL clock even when
% this helper's legacy caller did not request the two-port authority case.
% Run the existing physical SS/PBCH producer/receiver; do not set zero phase
% or promote the analytical TAG setup below into acquisition evidence.
acquireDLClock=receivedAuthority || logical(cfg.phy.pdcch.blindSearch);
if independentCompletion && ~withCSI
    for name=["csi","cqi","pmi","ri","cri"]
        assert(~s.get("reference_signals."+name+"_reporting_enabled"), ...
            'test:IndependentPUSCHReportingAuthority', ...
            'The inherited no-report fixture must keep %s reporting disabled.',name);
    end
    for name=["cqi","pmi","ri","cri"]
        assert(string(s.get("csi_acquisition_and_reporting."+name+"_policy"))=="disabled");
    end
end
if twoPortUL
    assert(cfg.phy.srs.nPorts==expectedULPorts && ...
        cfg.phy.pusch.NumAntennaPorts==expectedULPorts && cfg.phy.pusch.numLayers==1);
end
if (withCSI || withHARQ) && ~independentCompletion, localSaveScenarioEvidence(s,cfg,root); end
if independentCompletion
    scope='component: actual shared SS/PBCH timing, SRS, UL DCI and PUSCH; independent UCI receive/commit; selected DL source explicitly retained; not full coordinator or 12 dB qualification';
    if unconsumedULCommand
        scope='component: actual shared DL DCI/PDSCH reception and PUCCH TX; gNB UL command transmitted but UE UL decoder deliberately unexecuted; scheduled PUSCH capture; NOT physical missed-DCI probability or full coordinator qualification';
    end
    if pucchOnlyCompletion
        scope='component: actual shared DL reception and combined HARQ/CSI/SR PUCCH; independent gNB layout and common completion; no scheduled UL command; not 12 dB or missing-DCI-rate qualification';
    end
    localSaveScenarioEvidence(s,cfg,root, ...
        scope);
end
% This component bypasses runSingle, which normally initializes the run
% RNG. Bind the UE drop to the resolved YAML seed, not the preceding test.
priorRNG=rng;
rngCleanup=onCleanup(@()rng(priorRNG)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
lastSlot=11+10*logical(withHARQ);
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),lastSlot);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1; state.TestRoot=root;
state.TestPacketAccounting=logical(withPacketAccounting);
if withPacketAccounting
    assert(~state.ProtocolWaveformEnabled, ...
        'This fixture verifies CRC-backed metadata mapping, not protocol-byte reassembly.');
    state.Traffic.OfferedBitsDL=zeros(lastSlot,1);
    state.Traffic.OfferedBitsUL=zeros(lastSlot,1);
end
state.TestDeferUCIDelivery=logical(deferUCIDelivery);
state.TestWithCSI=logical(withCSI);
state.TestWithHARQ=logical(withHARQ);
state.TestIndependentCompletion=logical(independentCompletion);
state.TestIndependentSharedHARQ=logical(independentSharedHARQ);
state.TestForgetCSIProducer=logical(forgetCSIProducer);
state.TestUnconsumedULCommand=logical(unconsumedULCommand);
state.TestPUCCHOnlyCompletion=logical(pucchOnlyCompletion);
state.TestSeparatePUCCH=logical(separatePUCCH);
if separatePUCCH
    assert(isequal(double(cfg.phy.pusch.symbolAllocation),[0 11]), ...
        'The separate-transport fixture must use the retained H4 11-symbol allocation.');
end
state.TestScheduledDLDAILedger=struct();
if independentCompletion, assert(logical(cfg.phy.csi.reportCSI)==logical(withCSI)); end
if independentCompletion && withCSI
    assert(~cfg.run.controlGating.prachRequired && ...
        state.AccessState(1)=="not_required", ...
        'test:SharedCSIAccessScope', ...
        'The component installs connected context explicitly; it does not execute or qualify random access.');
    assert(sixgr.truth.periodicCSIReportSlotMask(10,cfg.phy.csi.reportPeriodicitySlots, ...
        cfg.phy.csi.reportOffsetSlots) && sixgr.truth.periodicCSIReferenceSlot(cfg,10)==6);
end
state.TestPUSCHRows=table();
[lateCSIProducerSlot,~]=localLateCSIProducerSlot(cfg,10);
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
if acquireDLClock
    % Retain the real large-scale/serving-cell state created by the normal
    % user-context bind; completion telemetry consumes that same state.
    [dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
    prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
        'UseRuntimeChannel',true,'RuntimeSlot',0);
    assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
    owner.queueDownlink('PBCH',1,prototype.PreparedBroadcast, ...
        struct('Config',dl,'Slot',1,'ServingCell',1,'TrackingOnly',true));
end
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',0);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
state.ConnectedULTimingByUE={struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.02*fs))};
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=carrier.SubcarrierSpacing;
[~,link]=sixgr.link.applyWaveformImpairments(complex(zeros(1,1)),ul,fs,'ApplyRFChain',false);
loss=double(link.AppliedLargeScaleLoss_dB);
measurement=table(0,loss,"SSB-0","analytic_component_pathloss_selector_fixture", ...
    1,-loss,0,'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB', ...
    'PathlossReferenceRS','MeasuredReferenceSignalPathlossSource','ServingCell', ...
    'SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,measurement,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','analytic_component_selector_fixture');
if ~acquireDLClock, localQueueSRS(state,cfg,5); end
for slot=1:lastSlot
    if independentCompletion
        % Real slot entry retains the source-slot trace required by the
        % normal completion reducer. No caller-created completed trace row.
        state=sixgr.truth.CoupledTruthRuntime.beginSlot( ...
            state,cfg,cfg,1,'UL',1,1,slot,lastSlot,cfg.channel.snr_dB);
    end
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    if acquireDLClock && slot==4
        % Freeze the slot-5 sounding only after real SS/PBCH acquisition.
        % Preparing it at initialization retained the declared phase=6
        % clock even after actual SS/PBCH established phase=0. Preparation
        % in slot 4 still precedes the timing-advanced slot-5 transmission.
        assert(isfield(state,'TestReceivedDLClock') && ...
            state.TestReceivedDLClock.AvailableAtSample<=owner.Events.NextSampleIndex && ...
            isequaln(state.ConnectedULTimingByUE{1}.DLReference,state.TestReceivedDLClock));
        localQueueSRS(state,cfg,5);
    end
    if independentCompletion && (withCSI || separatePUCCH)
        if unconsumedULCommand && slot==11
            held=state.PUCCHGrantTraceTable;
            completed=state.SharedUnselectedPUCCHObservations;
            assert(numel(completed)==1);
            key=completed{1}.Context.Key;
            assert(sixgr.truth.awaitingUnselectedPUCCHDisposition(state,held,key) && ...
                all(~held.GrantExecutedFlag) && all(~state.PendingFeedbackTable.Processed));
            late=held; late.PUCCHGrantId(1)="late_not_in_frozen_waveform";
            assert(~sixgr.truth.awaitingUnselectedPUCCHDisposition(state,late,key));
            missing=state; missing.SharedUnselectedPUCCHObservations={};
            assert(~sixgr.truth.awaitingUnselectedPUCCHDisposition(missing,held,key));
            localReject(@()sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(missing), ...
                'sixgr:truth:LateSharedPUCCHFeedback');
            lateState=state; lateState.PUCCHGrantTraceTable=late;
            localReject(@()sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(lateState), ...
                'sixgr:truth:LateSharedPUCCHFeedback');
            fprintf('UNSELECTED_PUCCH_PENDING_PUSCH_GUARD_PASS no_early_completion=1 late_producer_rejected=1\n');
        end
        try
            state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
        catch cause
            % Preserve the actual ownership boundary; never repair or skip
            % a failed occasion inside the test fixture.
            failedArming=struct('Slot',slot,'NextSampleIndex',owner.Events.NextSampleIndex, ...
                'GrantTrace',state.PUCCHGrantTraceTable, ...
                'ArmedOccasions',state.SharedArmedPUCCHOccasions, ...
                'PendingObservations',owner.Pending);
            save(fullfile(root,'feedback_arming_failure.mat'),'failedArming','-v7.3');
            rethrow(cause);
        end
    end
    if independentSharedHARQ && slot==6
        state=localQueueSharedCSISource(state,cfg,slot,true);
    end
    if withCSI && ~independentCompletion && slot==lateCSIProducerSlot
        state=localQueueSharedCSISource(state,cfg,slot);
    end
    if withHARQ && slot==11, localQueueSRS(state,cfg,15); end
    if slot==11 && isfield(state,'TestDeferredUCI')
        h=state.TestDeferredUCI;
        assert(sixgr.truth.receivedPUSCHUCIOccasion(owner,h,h.GrantSnapshot)==10 && ...
            state.CurrentSlot==11 && all(~state.PendingFeedbackTable.Processed));
        % Exercise compatibility with pre-field trace schemas. In the CSI
        % case, HARQ-only processing must not zero-fill the unobserved row.
        state.PUCCHGrantTraceTable(:,{'PUSCHUCITransmissionSlot','PUSCHUCIDeliverySlot'})=[];
        state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHUCIRuntime(state,h);
        assert(all(state.PendingFeedbackTable.Processed) && ...
            state.DLHarq.Stats.Ack==1 && state.DLHarq.Stats.Nack==1);
        ackRows=startsWith(string(state.PUCCHGrantTraceTable.PUCCHGrantId),"shared_pusch_actual_dl_");
        assert(all(state.PUCCHGrantTraceTable.PUSCHUCITransmissionSlot(ackRows)==10) && ...
            all(state.PUCCHGrantTraceTable.PUSCHUCIDeliverySlot(ackRows)==11));
        path=fullfile(root,'late_uci_delivery.csv');
        sixgr.util.csvWriteTable(path,state.PUCCHGrantTraceTable,'PreserveSchema',true);
        saved=sixgr.util.csvReadTable(path,'TextType','string');
        assert(all(saved.PUSCHUCITransmissionSlot(ackRows)==10) && all(saved.PUSCHUCIDeliverySlot(ackRows)==11));
        if state.TestWithCSI, localVerifyCSI(state); end
        disp('SHARED_PUSCH_LATE_UCI_DELIVERY_PASS: actual slot-10 reception delivered in slot 11.');
    end
    if (slot==9 || (withHARQ && slot==19)) && ~pucchOnlyCompletion
        assert(isfield(state,'TestSRS') && state.TestSRS.AvailableAtSample<=owner.Events.NextSampleIndex);
        if independentCompletion && withCSI
            reports=state.PendingCSITable;
            assert(height(reports)==1 && reports.SourceSlot==6 && reports.CSIReferenceSlot==6 && ...
                reports.DueSlot==10 && ~reports.Processed && state.TestSharedCSIReceived);
            state.TestExpectedCSI=reports;
        end
        if slot==9 && ~independentCompletion, state=localReceivedDLReservations(state,cfg,10); end
        if slot==19
            assert(~state.TestLastULHARQ.CombinedDecodeOK && state.ULHarq.hasPendingRetx(cfg.phy.pusch.RNTI,slot), ...
                'This fixture requires a real receiver NACK; never manufacture retransmission feedback.');
        end
        [ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
        ul=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,slot);
        ul.lls6g.userContext.RuntimeSlotStartTime_s=(slot-1)*sixgr.time.slotDurationSec(cfg);
        [grant,ul]=localGrant(state,ul,slot-1);
        if independentCompletion
            % No isolated DL donor or fabricated HARQ row. Encode the actual
            % accepted shared DL schedule into the ordinary UL DCI.
            grant=sixgr.truth.prepareScheduledULDAI(state.TestScheduledDLDAILedger,ul,grant);
            assert(grant.ULTotalDAIAuthority.ScheduledDLAssignmentCount==double(independentSharedHARQ));
        end
        if withCoincidentSRS
            % The authored TDD allocation ends before the configured SRS
            % symbol. Exercise both actual contributions and one shared
            % channel observation; never erase an overlapping allocation.
            puschSymbols=grant.SymbolAllocation(1)+(0:grant.SymbolAllocation(2)-1);
            assert(~ismember(13,puschSymbols),'test:FixtureSRSDataOverlap', ...
                'This coexistence fixture requires nonoverlapping authored PUSCH/SRS symbols.');
            sounding=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,10);
            sounding.lls6g.userContext.RuntimeSlotStartTime_s=9*sixgr.time.slotDurationSec(cfg);
            soundingArgs={'SlotIndex',10,'SNR_dB',cfg.channel.snr_dB,'TimingAdvanceSamples',0};
            soundingTX=sixgr.link.runSRSChannelEstimation(sounding,soundingArgs{:},'PrepareOnly',true);
            owner.queueUplinkControl(1,soundingTX.PreparedTransmission, ...
                struct('Config',sounding,'Arguments',{soundingArgs}));
        end
        allocation=state.ULHarq.allocate(grant.RNTI,slot,grant.TBSBytes,'NewData',true);
        assert(isequaln(allocation.HARQ.HarqID,grant.HARQ.HarqID) && ...
            allocation.HARQ.NDI==grant.HARQ.NDI && allocation.HARQ.RV==grant.HARQ.RV);
        if slot==9
            if state.TestPacketAccounting
                state=localOfferPacket(state,'UL',grant.TBSBits);
            else
                state.ULQueueBits(1)=grant.TBSBits;
            end
        end % No new bytes for a retransmission.
        [dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
        dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
        dl.lls6g.userContext.RuntimeSlotStartTime_s=(slot-1)*sixgr.time.slotDurationSec(cfg);
        p=sixgr.link.prepareSharedPDCCHTransmission(dl,'Grant',grant,'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
        controlContext=struct('Grant',grant,'ULConfig',ul);
        if independentCompletion, controlContext.ScheduledULHARQConfig=ul; end
        if acquireDLClock
            assert(isfield(state,'TestReceivedDLClock'),'Actual received SS/PBCH clock is required.');
            controlContext.ReceivedDLTimingReference=state.TestReceivedDLClock;
        end
        owner.queuePDCCH(1,p,controlContext);
    end
    if independentCompletion
        % Match the production lifetime: consuming the due scheduling queue
        % must not hide an encoded PUSCH from a later PUCCH callback.
        pending=sixgr.util.structGet(state,'SharedPendingULGrants',repmat(struct(),0,1));
        slots=arrayfun(@sixgr.truth.runtimeULGrantSlot,pending);
        [state,~]=sixgr.truth.advanceSharedSlotWithULGrants( ...
            state,cfg,pending(slots>slot),pending(slots==slot),@localEvents);
    else
        [state,~]=owner.advanceSlot(state,cfg,@localEvents);
    end
end
if pucchOnlyCompletion
    assert(state.TestSharedHARQReceived && state.TestSharedCSIReceived && ...
        numel(owner.PUCCHTransmissions)==1 && numel(owner.DataTransmissions)==1 && ...
        isempty(owner.readTransmittedULControls(1,10)) && state.ULHarq.Stats.Tx==0 && ...
        height(state.SharedGNBUCIHARQTable)==1 && all(state.PendingFeedbackTable.Processed));
    receipts=state.SharedGNBUCIReceptions;
    trial=state.ControlTrials.PUCCH(state.ControlTrials.PUCCH.Slot==10,:);
    report=state.SharedGNBCSIReportTable(state.SharedGNBCSIReportTable.DueSlot==10,:);
    assert(height(trial)==1 && trial.IndependentReceiverAssignment && ...
        trial.ReceiverExpectedHARQBitCount==1 && trial.ReceiverExpectedSRBitCount==1 && ...
        trial.ReceiverExpectedCSIPart1BitCount>0 && height(report)==1 && report.CSIUCIDecodeOk && ...
        state.DLHarq.Stats.Ack==double(state.TestExpectedSharedACK) && ...
        state.DLHarq.Stats.Nack==double(~state.TestExpectedSharedACK));
    sixgr.util.csvWriteTable(fullfile(root,'combined_pucch_trial.csv'),trial,'PreserveSchema',true);
    sixgr.util.csvWriteTable(fullfile(root,'combined_pucch_csi.csv'),report,'PreserveSchema',true);
    save(fullfile(root,'combined_pucch_completion.mat'),'trial','report','receipts');
    fprintf('TDD_INDEPENDENT_COMBINED_PUCCH_PASS actual_DL_RX=1 HARQ=1 SR=1 CSI=1 UL_command=0 root=%s\n',root);
    ok=true; return;
end
if unconsumedULCommand
    audit=state.SharedUnselectedPUCCHAuditTable;
    assert(state.TestSharedHARQReceived && height(audit)==1 && audit.PUCCHTransmissionExecuted && ...
        ~audit.PUCCHDecoderInvoked && ~audit.PUCCHFeedbackCommitted && ...
        numel(owner.PUCCHTransmissions)==1 && numel(state.SharedPUCCHTXLedger)==1 && ...
        numel(owner.DataTransmissions)==1 && owner.DataTransmissions.Identity.Direction=="DL" && ...
        state.ULHarq.Stats.Tx==0 && isempty(state.ULHarq.getDeliveryLedger()) && ...
        all(state.PendingFeedbackTable.Processed) && ~any(state.PUCCHGrantTraceTable.MultiplexedOnPUSCH) && ...
        all(state.PUCCHGrantTraceTable.Status=="TX_ONLY") && ...
        localNoPUCCHTrialAtSlot(state.ControlTrials.PUCCH,10) && ...
        height(state.SharedGNBUCIHARQTable)==1);
    if withCSI
        reports=state.PendingCSITable;
        received=state.SharedGNBCSIReportTable;
        received=received(received.DueSlot==10,:);
        assert(height(reports)==1 && reports.Processed && ...
            string(reports.CSIUCITransport)=="pucch_transmitted_unselected" && ...
            ~reports.CSIUCIMultiplexedOnPUSCH && ~reports.CSIUCIDecodeOk && ...
            isnan(reports.DeliveredSlot) && isnan(reports.CSIUCICRCPass) && ...
            height(received)==1 && received.CSIUCIChannel=="PUSCH" && ...
            nnz(contains(lower(string(state.PUCCHGrantTraceTable.UCIType)),"harq"))==1 && ...
            height(state.PUCCHGrantTraceTable)==2);
        sixgr.util.csvWriteTable(fullfile(root,'unselected_csi_tx_only.csv'),reports,'PreserveSchema',true);
        sixgr.util.csvWriteTable(fullfile(root,'independent_pusch_csi_reception.csv'),received,'PreserveSchema',true);
    end
    sixgr.util.csvWriteTable(fullfile(root,'unselected_pucch_capture_audit.csv'),audit,'PreserveSchema',true);
    sixgr.util.csvWriteTable(fullfile(root,'pucch_tx_only_trace.csv'),state.PUCCHGrantTraceTable,'PreserveSchema',true);
    fprintf('SHARED_UNSELECTED_PUCCH_PRODUCER_PASS actual_DL_RX=1 actual_PUCCH_TX=1 PUSCH_TX=0 gNB_PUSCH_RX=1 UL_DCI_decoder_unexecuted=1 root=%s\n',root);
    ok=true; return;
end
attempts=1+logical(withHARQ);
assert(state.TestPUSCHReceived && state.ULHarq.Stats.Tx==attempts && state.ULQueueBits(1)==0);
assert(numel(owner.DataTransmissions)==attempts+logical(withCSI && ~independentCompletion)+logical(independentSharedHARQ) && ~owner.hasPending('PUSCH',1));
if withCSI && ~independentCompletion
    assert(state.TestSharedCSIReceived && state.DLHarq.Stats.Tx==3 && ...
        ~owner.hasPending('PDSCH',1));
end
if withHARQ
    assert(state.ULHarq.Stats.Retx==1 && height(state.TestPUSCHRows)==2 && ...
        state.TestPUSCHRows.CRCPass(1)==0 && state.TestLastULHARQ.HARQCombiningApplied && ...
        state.TestLastULHARQ.HARQSoftCombiningPositionAware && state.TestLastULHARQ.PreviousLLRCount>0 && ...
        state.TestPUSCHRows.CRCPass(2)==1 && state.TestLastULHARQ.CombinedDecodeOK && ...
        isequal(state.TestLastULHARQ.DecodedTransportBlockBits,state.TestLastULHARQ.TransportBlockBits), ...
        'Shared HARQ must recover the actual original payload, not merely report that combining was invoked.');
    fprintf('SHARED_RECEIVED_UL_HARQ_PASS: first CRC=%d final CRC=%d two-port TPMI=%d root=%s\n', ...
        state.TestPUSCHRows.CRCPass(1),state.TestPUSCHRows.CRCPass(2),state.TestSRS.TPMI,root);
end
if withCoincidentSRS
    assert(state.TestLastSRSObservationID==state.TestPUSCHObservationID, ...
        'Coincident SRS and PUSCH must share one verified immutable channel artifact.');
end
if independentEmptyUCI
    assert(isempty(state.SharedPUSCHHARQDecisionAuditTable),'Empty UCI has no fabricated HARQ decision audit.');
    assert(state.DLHarq.Stats.Tx==0 && state.DLHarq.Stats.Ack==0 && state.DLHarq.Stats.Nack==0);
    assert(numel(state.SharedPUSCHHARQFeedbackReceipts)==1 && ...
        isempty(sixgr.util.structGet(state,'SharedGNBUCIHARQTable',table())));
    fprintf('TDD_INDEPENDENT_PUSCH_EMPTY_UCI_PASS actual_UL_TX=1 DL_TX=0 HARQ_updates=0 common_commit_receipts=1\n');
end
if independentSharedHARQ && ~separatePUCCH
    decisions=state.SharedPUSCHHARQDecisionAuditTable;
    assert(height(decisions)==1 && decisions.ReceiverUsable && ~decisions.ReceiverErasure && ...
        decisions.ShortConfidenceAttempted && decisions.ConfidenceAccepted==1 && ...
        decisions.SelectedPosterior>=decisions.MinimumPosterior);
    sixgr.util.csvWriteTable(fullfile(root,'pusch_harq_receiver_decisions.csv'),decisions, ...
        'PreserveSchema',true,'RoundTripNumericText',true);
    assert(state.TestSharedHARQReceived && state.DLHarq.Stats.Tx==1 && ...
        numel(state.SharedUEHARQACKEvents)==1 && height(state.SharedGNBUCIHARQTable)==1 && ...
        numel(state.SharedPUSCHHARQFeedbackReceipts)==1 && ...
        state.DLHarq.Stats.Ack==double(state.TestExpectedSharedACK) && ...
        state.DLHarq.Stats.Nack==double(~state.TestExpectedSharedACK) && ...
        state.DLCompletedSlots==6 && state.ULCompletedSlots==10 && ...
        numel(unique(state.SharedDataRXCommittedIDs))==2);
    fprintf('TDD_INDEPENDENT_SHARED_HARQ_PASS actual_DL_TX=1 actual_UL_TX=1 common_commit_receipts=1 ACK=%d\n', ...
        state.TestExpectedSharedACK);
end
if separatePUCCH
    assert(isfield(state,'TestCoincidentCompletionBatch') && state.TestCoincidentCompletionBatch, ...
        'test:MissingSameDeadlineTransportCoverage', ...
        'The regression must actually complete PUSCH and PUCCH in one callback batch.');
    assert(isempty(state.SharedPUSCHHARQDecisionAuditTable) && ...
        numel(state.SharedPUSCHHARQFeedbackReceipts)==1 && ...
        state.TestSharedHARQReceived && state.DLHarq.Stats.Tx==1 && ...
        state.DLHarq.Stats.Ack==double(state.TestExpectedSharedACK) && ...
        state.DLHarq.Stats.Nack==double(~state.TestExpectedSharedACK));
    rows=state.PUCCHGrantTraceTable;
    rows=rows(contains(lower(string(rows.UCIType)),"harq"),:);
    assert(height(rows)==1 && rows.GrantExecutedFlag && ...
        ~rows.MultiplexedOnPUSCH && rows.Status=="PASS" && ...
        rows.PUCCHSymbolStart==12 && rows.PUCCHNumSymbols==2);
    assert(height(state.TestPUSCHRows)==1 && state.TestPUSCHRows.CRCPass==1);
    sixgr.util.csvWriteTable(fullfile(root,'separate_pucch_grants.csv'),rows,'PreserveSchema',true);
    fprintf('SHARED_SEPARATE_PUCCH_PUSCH_PASS actual_DL_RX=1 PUSCH_symbols=0:10 PUCCH_symbols=12:13 independent_RX=1 DL_HARQ_updates=1\n');
end
fprintf('SHARED_PUSCH_CHANNEL_ARTIFACTS_PASS: %s actual SRS/DCI/PUSCH/UCI, seed=%g root=%s\n',mode,cfg.run.seed,root);
ok=true;
end

function localQueueSRS(state,cfg,srsSlot)
[srsCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
srsCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(srsCfg,srsSlot);
srsCfg.lls6g.userContext.RuntimeSlotStartTime_s=(srsSlot-1)*sixgr.time.slotDurationSec(cfg);
args={'SlotIndex',srsSlot,'SNR_dB',cfg.channel.snr_dB,'TimingAdvanceSamples',0};
prepared=sixgr.link.runSRSChannelEstimation(srsCfg,args{:},'PrepareOnly',true);
assert(prepared.PreparedTransmission.NumReceiveAntennas== ...
    srsCfg.lls6g.userContext.RuntimeServingBSAntenna.NumElements, ...
    'SRS reception must bind physical gNB branches, not logical CSI port count.');
state.SharedWaveformStream.queueUplinkControl(1,prepared.PreparedTransmission,struct('Config',srsCfg,'Arguments',{args}));
end

function [grant,cfg]=localGrant(state,cfg,slot0)
measured=state.TestSRS;
ports=double(cfg.phy.pusch.NumAntennaPorts);
assert(isfinite(measured.RI) && isfinite(measured.TPMI) && ports<=measured.NumSRSPorts);
cfg.phy.pusch.TPMI=measured.TPMI;
cfg.phy.pusch.srsDecision=struct('Authoritative',true,'MeasurementID',measured.ID, ...
    'MeasurementSlot',measured.Slot,'RI',measured.RI,'TPMI',measured.TPMI,'NumPorts',ports);
p=cfg.phy.pusch;
grant=struct('Direction','UL','Frame',0,'Slot',slot0,'RNTI',p.RNTI,'UEIndex',1, ...
    'BaseStationID',1,'ServingCell',1,'PRBSet',p.prbSet,'SymbolAllocation',p.symbolAllocation, ...
    'Modulation',p.modulation,'TargetCodeRate',p.codeRate,'MCSIndex',p.mcsIndex,'MCS',p.mcsIndex, ...
    'RV',0,'Layers',measured.RI,'NumLayers',measured.RI,'RI',measured.RI, ...
    'NumLogicalPorts',ports,'TPMI',measured.TPMI,'SRSCausalUsable',true,'SRSValid',true, ...
    'SRSCausalMeasurementId',measured.ID,'LastSuccessfulSRSSlot',measured.Slot, ...
    'HARQ',struct('HarqID',0,'NDI',true,'NDIEpoch',1,'RV',0,'IsRetransmission',false));
if state.TestWithHARQ && slot0==18
    prior=state.ULHarq.peekRetx(p.RNTI,slot0+1);
    assert(~isempty(prior));
    grant.HARQ=prior.HARQ; grant.RV=prior.HARQ.RV;
    grant.IsRetransmission=true; grant.HARQTBContext=prior.TBContext;
    grant.TBSBytes=prior.TBSBytes; grant.TBSBits=8*prior.TBSBytes;
end
grant.TimingAdvanceTicks=cfg.SharedULTimingContext.ReceivedRARTiming.NTA_Tc+cfg.SharedULTimingContext.Offset.NTAOffset_Tc;
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
grant=scheduler.attachCanonicalTimingDecision(grant);
grant=scheduler.finalizeExactPHYFeasibility(grant);
grant.DCI=scheduler.buildDCIBitfield(grant);
grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,'UL',grant,'Frame',0,'Slot',slot0,'HARQContext',grant.HARQ);
grant.PHYGrantContextId=grant.PHYGrant.GrantContextId;
if state.TestIndependentCompletion
    % This fixture bypasses buildTrialContextFromGrant's new-TB identity
    % binding. Assign the actual first grant identity before encoding, never
    % manufacture a missing identity after reception/completion.
    grant.TransportBlockId=char(grant.PHYGrantContextId);
    grant.TBId=grant.TransportBlockId;
end
end

function state=localEvents(state,items)
if state.TestIndependentCompletion
    if state.TestSeparatePUCCH && any(string({items.Kind})=="PUSCH") && ...
            any(string({items.Kind})=="PUCCH")
        state.TestCoincidentCompletionBatch=true;
        fprintf('SEPARATE_TRANSPORT_SAME_DEADLINE_BATCH sample=%d kinds=%s\n', ...
            state.SharedWaveformStream.Events.NextSampleIndex, ...
            strjoin(string({items.Kind}),','));
    end
    % Use the SAME post-batch re-arming boundary as the full coordinator.
    state=sixgr.truth.completeSharedReceiverBatch(state,items,@localCompleteEvents);
else
    state=localCompleteEvents(state,sixgr.truth.orderSharedReceiverCompletions(items));
end
end

function state=localCompleteEvents(state,items)
owner=state.SharedWaveformStream;
for item=items
    if item.Kind=="PUSCHReceiveOnly"
        assert(state.TestUnconsumedULCommand);
        state=localCompleteUnselectedProducer(state,item);
        continue;
    end
    if item.Kind=="PUCCHTX"
        state=sixgr.truth.commitSharedPUCCHTransmission(state,item);
        continue;
    end
    if item.Kind=="DataTX"
        state=sixgr.truth.commitSharedDataTransmission(state,item);
        if state.TestIndependentCompletion
            executed=state.SharedDataTXLedger{end};
            assert(strlength(string(executed.Grant.HARQTBContext.TBId))>0 && ...
                string(executed.Grant.HARQTBContext.TBId)== ...
                string(item.Context.Prepared.RequestBinding.Grant.TransportBlockId));
        end
        if item.Context.Prepared.Direction=="UL", localVerifyAppliedULWeights(state,item); end
        if state.TestIndependentSharedHARQ && item.Context.Prepared.Direction=="DL"
            state=sixgr.truth.CoupledTruthRuntime.armSharedDLHARQOccasionFromGrantRuntime( ...
                state,state.SharedDataTXLedger{end}.Grant,item.UE);
        end
        continue;
    end
    if item.Kind=="PreparePUCCH"
        if state.TestPUCCHOnlyCompletion
            preparation=struct('CurrentSlot',state.CurrentSlot, ...
                'NextSampleIndex',owner.Events.NextSampleIndex,'Occasion',item.Context, ...
                'PendingCSI',state.PendingCSITable, ...
                'CSIObligations',sixgr.util.structGet(state,'CSIReportObligationTable',table()), ...
                'ReceivedCSIRS',sixgr.util.structGet(state,'ControlTrials.CSIRS',table()), ...
                'GrantTrace',state.PUCCHGrantTraceTable);
            save(fullfile(state.TestRoot,sprintf('pucch_preparation_slot_%d.mat',item.Context.Slot)), ...
                'preparation','-v7.3');
        end
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        continue;
    end
    if item.Kind=="PUCCHReceiveOnly"
        % Before actual CSI-RS TX, only an installed SR remains applicable.
        % Keep its actual capture and do not manufacture a CSI observation.
        assert(state.TestWithCSI && isempty(item.Context.GNBReception.Mapping) && ...
            ~isfield(item.Context,'Prepared'));
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,item);
        observationID=string(item.Context.ObservationID);
        if isempty(item.Context.GNBReception.CSIReportConfiguration)
            rows=state.SharedGNBSRReceptionTable;
            row=rows(rows.ObservationID==observationID,:);
            assert(height(row)==1 && row.AvailableAtSample==owner.Events.NextSampleIndex && ...
                ~row.UETransmissionExecuted && isempty(sixgr.util.structGet(state,'SharedGNBCSIReportTable',table())));
            fprintf('PUSCH_FIXTURE_SR_RX_ONLY slot=%g CSI_bits=0 detected=%d no_PUCCH_prepared=1\n',row.Slot,row.PositiveSRDetected);
            continue;
        end
        reports=state.SharedGNBCSIReportTable;
        row=reports(string(reports.ObservationID)==observationID,:);
        assert(height(row)==1 && row.AvailableAtSample==owner.Events.NextSampleIndex);
        receipt=state.SharedGNBUCIReceptions{end};
        assert(receipt.ObservationID==observationID && isempty(receipt.Mapping));
        % Retain the actual detector decision even when no PUCCH was prepared.
        % A usable decode here is false-report evidence, not a TX claim and
        % not permission to force DTX using transmitter-side knowledge.
        receiver=receipt.Receiver;
        save(fullfile(state.TestRoot,char(observationID+"_CSI_receive_only.mat")), ...
            'item','row','receiver','-v7.3');
        fprintf('PUSCH_FIXTURE_PERIODIC_CSI_RX_ONLY slot=%g decoded=%d no_PUCCH_prepared=1\n',row.DueSlot,row.CSIUCIDecodeOk);
        continue;
    end
    if item.Kind=="PUCCHNotSelected"
        state=sixgr.truth.completeUnselectedPUCCHObservation(state,item);
        continue;
    end
    if item.Kind=="PUCCH"
        if state.TestSeparatePUCCH
            fprintf('SEPARATE_PUCCH_COMPLETION boundary=%d kinds=%s\n', ...
                owner.Events.NextSampleIndex,strjoin(string({items.Kind}),','));
        end
        if state.TestPUCCHOnlyCompletion
            % Same actual IQ with UE bookkeeping removed and optional TX
            % references poisoned. No new RF/channel execution or forced DTX.
            observer=state; observer.PendingFeedbackTable=table();
            observer.PUCCHGrantTraceTable=table(); observer.PendingCSITable=table();
            observer.SharedUEHARQACKEvents={}; observer.SharedReceivedGrantControls={};
            observer.ExpectedHARQACKBits=int8([0;0;0;0]);
            observer.ExpectedCSIPart1Bits=int8(ones(19,1));
            c=item.Context; original=c.GNBReception;
            independent=sixgr.truth.buildScheduledPUCCHHARQReception( ...
                observer,c.Config,item.UE,c.Slot,c.ObservationID);
            assert(independent.Mapping.Digest==original.Mapping.Digest && ...
                independent.Assignment.Digest==original.Assignment.Digest && ...
                independent.Context.Digest==original.Context.Digest, ...
                'UE bookkeeping or TX references must not own the combined receive schema.');
            [~,~,~,~,capture]=sixgr.truth.sharedObservationEvidence(item.Planes,c.Prepared);
            replay=sixgr.link.receivePUCCHObservation(c.Config,independent.Assignment, ...
                independent.Context,capture,state.ReceivedULTimingReferences{item.UE});
        end
        previousOccasions=strings(0,1);
        if ~isempty(state.ControlTrials.PUCCH)
            previousOccasions=string(state.ControlTrials.PUCCH.PhysicalPUCCHOccasionId);
        end
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(state,item);
        completed=state.ControlTrials.PUCCH;
        % Registration keys and physical-occasion identities are different
        % contracts. Select the newly completed physical trial, then verify
        % its actual observation clock; do not equate the two strings.
        selected=find(~ismember(string(completed.PhysicalPUCCHOccasionId),previousOccasions));
        assert(isscalar(selected),'One completion must add exactly one physical PUCCH trial.');
        postPlane=item.Planes(endsWith(string({item.Planes.ReceiverID}),':post_rf'));
        assert(isscalar(postPlane) && completed.Slot(selected)==item.Context.Slot && ...
            completed.ObservationStartSample(selected)==postPlane.Observation.StartSample && ...
            completed.ObservationEndSampleExclusive(selected)==postPlane.Observation.EndSampleExclusive, ...
            'The RF export assertion must use the exact newly received PUCCH capture.');
        rfFields=["ADCClippedSampleCount","ADCClippingSampleCount","ADCErrorEnergy", ...
            "DACClippedSampleCount","DACClippingSampleCount","DACErrorEnergy", ...
            "TxRFEndpointMetadataJSON","RxRFEndpointMetadataJSON"];
        assert(all(ismember(rfFields,string(completed.Properties.VariableNames))), ...
            'Measured PUCCH RF columns must survive compatible row replacement.');
        rf=sixgr.truth.bindSharedRFExecutionEvidence(completed(selected,:),item.Planes,true);
        assert(isequaln(completed(selected,cellstr(rfFields)),rf(:,cellstr(rfFields))), ...
            'PUCCH must retain its own executed RF capture, not preparation defaults.');
        if state.TestPUCCHOnlyCompletion
            actual=state.SharedGNBUCIReceptions{end}.Receiver;
            % Preserve failed captures too: distinguish an observer mismatch
            % from an identical physical decoding failure before repairing RX.
            save(fullfile(state.TestRoot,'combined_pucch_independent_replay.mat'), ...
                'item','independent','actual','replay','-v7.3');
            assert(isequaln(actual.DecodedFields,replay.DecodedFields) && ...
                actual.ReceiverUsable==replay.ReceiverUsable && actual.DTX==replay.DTX && ...
                actual.CRCPassed==replay.CRCPassed, ...
                'Retained-IQ independent reception must preserve HARQ/CSI/SR fields and decisions.');
            assert(isequal(actual.DecodedFields.SR,int8(0)), ...
                'test:CombinedPUCCHNegativeSRRecovery', ...
                'Combined reception did not recover negative SR: DTX=%d CRC=%d SR=%s.', ...
                actual.DTX,actual.CRCPassed,mat2str(actual.DecodedFields.SR));
            fprintf('COMBINED_PUCCH_OBSERVER_REMOVAL_REPLAY_PASS additional_RF_executions=0 negative_SR_exact=1\n');
        end
        continue;
    end
    c=item.Context; p=c.Prepared;
    if any(item.Kind==["PBCH","SSBOccasion"])
        [~,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes);
    else
        [~,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
    end
    assert(all(cellfun(@(s)~isfield(s.Execution,'ChannelReferences'),replay.ReceiveStreamExecutionSegments)));
    if item.Kind=="PBCH"
        % This component qualifies SS/PBCH timing, not full SIB1 recovery.
        continue;
    elseif item.Kind=="SSBOccasion"
        if isfield(state,'TestReceivedDLClock'), continue; end
        ch=owner.channelState(item.UE,'DL');
        recovered=sixgr.phy.broadcast.recoverSIB1FromWaveform(receiver,p.ReceiverConfig, ...
            'RecoveryScope','SSB_MIB','CandidateSSBIndex',c.SSBOccasionHorizon.SSBIndex, ...
            'PhysicalMeasurementObservation',pre);
        if recovered.BCHCrcPass && recovered.MIBDecoded
                state.TestReceivedDLClock=sixgr.phy.frame.receivedDLTimingReference( ...
                    p.ReceiverConfig,recovered,receiver,ch.ChannelTrimSamples);
                state.ConnectedULTimingByUE{1}.DLReference=state.TestReceivedDLClock;
                fprintf('RECEIVED_UL_SHARED_DL_CLOCK_PASS: sample=%d phase=%d\n', ...
                    receiver.EndSampleExclusive,state.TestReceivedDLClock.DLPhaseOffsetSamples);
        end
    elseif item.Kind=="SRS"
        [~,e,refs]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        assert(e.ChannelReferenceCoverageComplete);
        input=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ScoringChannelReferences',{refs}, ...
            'ChannelState',owner.directionalChannelState(1,'UL'));
        out=sixgr.link.runSRSChannelEstimation(c.Config,c.Arguments{:},'ReceivedContext',input);
        assert(out.RuntimeNoiseVarianceMean==out.NoiseVariance && ...
            out.RuntimeNoiseVarianceDomain==out.NoiseVarianceDomain && ...
            string(out.RuntimeNoiseVarianceSource)==string(out.NoiseVarianceSource), ...
            'SRS receiver variance aliases must retain the same measured domain and source.');
        if ~out.Ok
            save(fullfile(state.TestRoot,'srs_receiver_failure.mat'),'out','input','c','-v7.3');
        end
        assert(out.Ok,'test:SharedSRSFailed', ...
            'Actual SRS receiver must pass before a sounded grant: %s; %s',out.FailureReason,out.Notes);
        state.TestSRS=struct('RI',out.EstimatedRI,'TPMI',out.EstimatedTPMI, ...
            'Slot',double(c.Arguments{2}), ...
            'ID',sixgr.phy.waveform.WaveformHash.numeric(receiver.readComplete()), ...
            'NumSRSPorts',p.Tx.SRS.NumSRSPorts,'AvailableAtSample',receiver.EndSampleExclusive);
        state.ReceivedULTimingReferences={sixgr.phy.sync.ReceivedULTimingReference(p,receiver,out.ReceiveTiming)};
        row=table(double(c.Arguments{2}),"SRS",'VariableNames',{'Slot','Channel'});
        row=sixgr.truth.exportSharedChannelObservation(state.TestRoot,row,item.Planes,p,c.DesiredReferencePlane);
        sixgr.channel.validateSharedChannelObservationArtifact(state.TestRoot,row);
        state.TestLastSRSObservationID=row.ChannelObservationID;
    elseif item.Kind=="PDCCH"
        if state.TestIndependentCompletion && string(c.Grant.Direction)=="UL"
            assert(any(cellfun(@(x)x.GrantContextID==string(c.Grant.PHYGrant.GrantContextId), ...
                state.SharedGNBULHARQCommands)), ...
                'The gNB command is committed at transmission, before UE reception.');
        end
        if state.TestUnconsumedULCommand && string(c.Grant.Direction)=="UL"
            % Declared unreceived-command boundary: do not execute a UE
            % decoder or fabricate a CRC rejection/received assignment.
            g=c.Grant; t=g.TimingDecision; target=double(t.DataAbsoluteSlot)+1;
            g=sixgr.truth.bindQueuedULGrantOccasion(g,double(t.ControlAbsoluteSlot)+1,target, ...
                floor(double(t.ControlAbsoluteSlot)/state.SlotsPerFrame)+1, ...
                floor((target-1)/state.SlotsPerFrame)+1,t.K2);
            cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(c.ULConfig,target,g.Frame);
            cfg=sixgr.truth.bindSharedDataOccasion(cfg,target,g.Frame,owner.SampleRateHz);
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            guard=sixgr.phy.sync.resolveTimingSearchGuard(cfg,owner.SampleRateHz);
            first=sixgr.phy.frame.slotStartSample(carrier,target-1,owner.SampleRateHz)-guard;
            stop=sixgr.phy.frame.slotStartSample(carrier,target,owner.SampleRateHz)+guard;
            owner.queuePUSCHReceiveOnly(item.UE,cfg,g,first,stop);
            save(fullfile(state.TestRoot,'unconsumed_UL_control_capture.mat'),'item','g','-v7.3');
            continue;
        end
        [rx,rxInfo]=sixgr.link.completePDCCHReception(p,receiver);
        receivedAssignment=struct();
        if isfield(sixgr.util.structGet(p.ReceiverConfig,'phy.pdcch.operatorControl',struct()),'connected_dci')
            receivedAssignment=sixgr.phy.pdcch.materializeConnectedDCI(rx,rxInfo,p.ReceiverConfig);
        end
        grant=c.Grant;
        assert(rx.Ok && rx.CausalGrantDecodeOk && isequal(rx.DCIBits(:),grant.DCI.Bits(:)));
        decoded=sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
        authored=sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,grant.DCI.Format,grant.DCI.ContextData);
        assert(isequaln(decoded.Fields,authored.Fields));
        if string(grant.DCI.Format)=="0_1" && isfield(grant.DCI.ContextData,'ULPrecoding')
            assert(decoded.Fields.precoding_information_and_number_of_layers_tpmi==grant.TPMI && ...
                decoded.Fields.precoding_information_and_number_of_layers_rank_minus1==grant.NumLayers-1);
        end
        if string(grant.DCI.Format)=="0_1" && isfield(grant.DCI.ContextData,'ULReferenceSignaling')
            assert(~isfield(decoded.Fields,'srs_resource_indicator') && decoded.Fields.srs_resource_index0based==0);
            state.TestDecodedULReferenceFields=decoded.Fields;
        end
        grant.ControlDecodeOk=logical(rx.CausalGrantDecodeOk); grant.PDCCHGrantBindingOk=logical(rx.CausalGrantDecodeOk);
        grant.PDCCHGrantDCIId=decoded.PayloadHash; grant.PDCCHGrantDCIFormat=decoded.Format;
        hash=@(v)sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(orderfields(v)),'UTF-8')));
        grant.PDCCHGrantDCIFieldsHash=hash(decoded.Fields); grant.PDCCHGrantFieldsHash=hash(authored.Fields);
        grant.PDCCHGrantBindingRequired=true; grant.DCICrcPass=logical(rx.Ok);
        grant.PDCCHPayloadMatch=isequal(rx.DCIBits(:),grant.DCI.Bits(:)); grant.DecodedDCIFields=decoded.Fields;
        if isfield(c,'SharedCSISource') && (c.SharedCSISource || ...
                logical(sixgr.util.structGet(c,'SharedHARQSource',false)))
            grant.PDCCHCausalGrantDecodeOk=logical(rx.CausalGrantDecodeOk);
            state.TestCSIReceivedControl=struct('Grant',grant, ...
                'ReceivedAssignment',receivedAssignment,'AvailableAtSample',owner.Events.NextSampleIndex);
            if state.TestIndependentSharedHARQ
                assert(decoded.Fields.pucch_resource_indicator==grant.PUCCHResourceIndicator && ...
                    receivedAssignment.PUCCHResourceIndicator==grant.PUCCHResourceIndicator && ...
                    strlength(string(grant.PUCCHResourceIndicatorSource))>0, ...
                    'test:SharedHARQPRI','Actual received DL DCI must retain the configured scheduler PRI.');
                key="DL_ue_"+grant.UEIndex+"_rnti_"+grant.RNTI+ ...
                    "_control_"+(grant.TimingDecision.ControlAbsoluteSlot+1)+"_data_"+grant.Slot;
                control=struct('Key',key,'Grant',grant,'Allowed',logical(rx.CausalGrantDecodeOk), ...
                    'ReceivedAssignment',receivedAssignment,'AvailableAtSample',owner.Events.NextSampleIndex);
                controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
                state.SharedReceivedGrantControls=[controls;{control}];
                state.TestSharedDLControl=control;
            end
            controlArtifact='shared_csi_control.mat';
            if state.TestIndependentSharedHARQ, controlArtifact='shared_dl_harq_control.mat'; end
            save(fullfile(state.TestRoot,controlArtifact),'item','rx','rxInfo','grant');
            continue;
        end
        slot=double(grant.ScheduledAbsoluteSlot)+1;
        frame=floor((slot-1)/state.SlotsPerFrame)+1;
        % Cross the same scheduler-zero/runtime-one boundary as the main
        % received-DCI queue. Direct multiplex(...,slot) previously hid the
        % late-feedback reconciler's off-by-one ScheduledAbsoluteSlot read.
        controlSlot=double(grant.TimingDecision.ControlAbsoluteSlot)+1;
        controlFrame=floor((controlSlot-1)/state.SlotsPerFrame)+1;
        grant=sixgr.truth.bindQueuedULGrantOccasion( ...
            grant,controlSlot,slot,controlFrame,frame,grant.K2);
        if state.TestIndependentCompletion
            assert(~isempty(fieldnames(receivedAssignment)));
            key="UL_ue_"+grant.UEIndex+"_rnti_"+grant.RNTI+ ...
                "_control_"+controlSlot+"_data_"+grant.Slot;
            controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
            state.SharedReceivedGrantControls=[controls;{struct('Key',key,'Grant',grant, ...
                'Allowed',logical(rx.CausalGrantDecodeOk),'ReceivedAssignment',receivedAssignment, ...
                'AvailableAtSample',owner.Events.NextSampleIndex)}];
        end
        [cfg,~]=sixgr.truth.bindSharedDataOccasion(c.ULConfig,slot,frame,owner.SampleRateHz);
        hasDueACK=any(~state.PendingFeedbackTable.Processed);
        if hasDueACK && ~state.TestSeparatePUCCH
        future=state;
        lateTiming=jsondecode(future.PendingFeedbackTable.DataReceiveTimingEvidenceJSON(1));
        lateTiming.ResultAvailableAtSample=owner.Events.NextSampleIndex+1;
        future.PendingFeedbackTable.DataDecodeAvailableAtSample(1)=lateTiming.ResultAvailableAtSample;
        future.PendingFeedbackTable.DataReceiveTimingEvidenceJSON(1)=string(jsonencode(lateTiming));
        localReject(@()sixgr.truth.CoupledTruthRuntime.multiplexDueHARQACKOnPUSCHRuntime(future,grant,slot), ...
            'sixgr:truth:FutureHARQFeedbackAtUCIEncoding');
        missing=state; missing.PendingFeedbackTable.DataReceiveTimingEvidenceJSON(1)="";
        localReject(@()sixgr.truth.CoupledTruthRuntime.multiplexDueHARQACKOnPUSCHRuntime(missing,grant,slot), ...
            'sixgr:truth:MissingUCIReceiveTiming');
        end
        [state,grant,blocked]=sixgr.truth.CoupledTruthRuntime. ...
            reconcileQueuedPUSCHAfterDLFeedbackRuntime(state,grant,true);
        assert(isempty(blocked) && numel(grant)==1, ...
            'Canonical queued PUSCH must retain its actual due slot during late UCI reconciliation.');
        uci=sixgr.util.structGet(grant,'ExpectedUCIPayload',sixgr.phy.ul.pusch.PUSCHUCIPayload());
        if hasDueACK && ~state.TestSeparatePUCCH
        expectedACK=int8([1;0]);
        if state.TestIndependentSharedHARQ, expectedACK=int8(state.TestExpectedSharedACK); end
        assert(isequal(int8(uci.HARQACK(:)),expectedACK) && ...
            all(string(state.PendingFeedbackTable.DeliveryMechanism)=="pusch_uci") && ...
            all(state.PUCCHGrantTraceTable.MultiplexedOnPUSCH));
        elseif state.TestSeparatePUCCH
            assert(~uci.hasPayload() && ...
                ~any(state.PUCCHGrantTraceTable.MultiplexedOnPUSCH), ...
                'A received DL event in the same slot must stay on its disjoint PUCCH.');
            missing=state; missing.PUCCHGrantTraceTable=table();
            localReject(@()sixgr.truth.receivedPUSCHCodebookForGrant(missing,grant,false), ...
                'sixgr:truth:ReceivedPUCCHProducerMismatch');
        else
            assert(~uci.hasPayload(),'Already delivered ACKs must not be remultiplexed on the retransmission.');
        end
        context=struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true, ...
            'ExpectedUCIPayload',uci,'HARQContext',grant.HARQ);
        isRetx=logical(grant.HARQ.IsRetransmission);
        if isRetx
            context.HARQContext.TransportBlockContext=state.TestLastULHARQ.TransportBlockContext;
            context.PreviousCombinedLLR=state.ULHarq.getSoftBuffer(grant.RNTI,grant.HARQ.HarqID);
            context.RV=grant.HARQ.RV;
        end
        if ~isempty(fieldnames(receivedAssignment))
            cfg.phy.pusch.receivedDCIAssignment=receivedAssignment;
            if isRetx
                cfg.phy.pusch.receivedHARQState=state.TestUEHARQState;
            else
                cfg.phy.pusch.receivedHARQState=sixgr.link.ReceivedULHARQState(cfg);
                receivedAllocation=sixgr.phy.pdcch.connectedDataAllocation(cfg,receivedAssignment);
                context.TransportBlockBits=int8(randi([0 1],receivedAllocation.NominalTBSBits,1));
            end
        end
        job=sixgr.truth.buildGrantPHYJob(cfg,'UL',cfg.channel.snr_dB,frame,[],context); job.StartSlotIndex=slot;
        result=sixgr.truth.executeGrantPHYJob(job);
        assert(~result.ReadyForReceiverCommit && isempty(result.Result.TrialTable));
        if ~isempty(fieldnames(receivedAssignment))
            actual=result.Result.PreparedTransmission.Tx;
            authority="received_dci_and_ue_new_tb_payload";
            if isRetx, authority="received_dci_and_ue_harq_buffer"; end
            assert(actual.TransmissionAuthority==authority && ...
                actual.PrecodeInfo.AuthoritativeDCIDecisionUsed && ~actual.PrecodeInfo.AuthoritativeSRSDecisionUsed);
            retained=result.Result.UEHARQState.Processes{receivedAssignment.HARQProcess+1};
            assert(actual.UEHARQAttempt==1+isRetx && actual.UEHARQIsRetransmission==isRetx && ...
                isequal(retained.TransportBlockBits,actual.TransportBlock));
            if isRetx
                assert(retained.InitialAssignmentDigest~=receivedAssignment.AssignmentDigest && ...
                    isequal(actual.TransportBlock,state.TestLastULHARQ.TransportBlockBits));
            else
                assert(retained.InitialAssignmentDigest==receivedAssignment.AssignmentDigest);
            end
            state.TestUEHARQState=result.Result.UEHARQState;
        end
        owner.queueData(1,result.Result.PreparedTransmission,struct('Job',job));
        if state.TestIndependentCompletion
            % Actual encoded PUSCH and its exact pending producer ledgers.
            state.SharedPendingULGrants=grant;
            beforeFeedback=state.PendingFeedbackTable;
            beforeCSI=state.PendingCSITable;
            beforeTrace=state.PUCCHGrantTraceTable;
            [state,repeated,blocked]=sixgr.truth.CoupledTruthRuntime. ...
                reconcileQueuedPUSCHAfterDLFeedbackRuntime(state,grant,true);
            assert(isempty(blocked) && isequaln(repeated,grant) && ...
                isequaln(state.PendingFeedbackTable,beforeFeedback) && ...
                isequaln(state.PendingCSITable,beforeCSI) && ...
                isequaln(state.PUCCHGrantTraceTable,beforeTrace), ...
                'An encoded physical PUSCH must preserve both UCI and its exact producer reservations.');
            if state.TestIndependentSharedHARQ && ~state.TestSeparatePUCCH && ~state.TestWithCSI
                late=state;
                late.PendingFeedbackTable.DeliveryMechanism(:)="pucch";
                late.PUCCHGrantTraceTable.MultiplexedOnPUSCH(:)=false;
                localReject(@()sixgr.truth.CoupledTruthRuntime. ...
                    reconcileQueuedPUSCHAfterDLFeedbackRuntime(late,grant,true), ...
                    'sixgr:truth:LateSharedPUSCHUCIChange');
                assert(isequaln(state.PendingFeedbackTable,beforeFeedback) && ...
                    isequaln(state.PUCCHGrantTraceTable,beforeTrace));
            end
            fprintf('SHARED_ENCODED_PUSCH_RECONCILIATION_PASS actual_coded_TX=1 immutable_binding=1 separate_PUCCH=%d\n', ...
                state.TestSeparatePUCCH);
        end
    elseif item.Kind=="PDSCH"
        if state.TestIndependentSharedHARQ
            state=localCompleteSharedHARQSource(state,item,p,pre,tx,replay,receiver);
            continue;
        end
        assert(state.TestWithCSI && c.SharedCSISource && isfield(state,'TestCSIReceivedControl'));
        control=state.TestCSIReceivedControl;
        assert(control.AvailableAtSample<=receiver.EndSampleExclusive);
        job=c.Job; job.PrepareOnly=false;
        job.GrantSnapshot=sixgr.truth.bindReceivedPDCCHGrantEvidence(job.GrantSnapshot,control.Grant);
        replay=sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,c.DesiredReferencePlane,replay);
        job.ReceivedContext=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ChannelState',owner.directionalChannelState(1,'DL'), ...
            'ReceivedAssignment',control.ReceivedAssignment,'UEIndex',1);
        if isfield(sixgr.util.structGet(job.Cfg,'phy.pdcch.operatorControl',struct()),'connected_dci')
            job.ReceivedContext.ReceivedHARQState=sixgr.link.ReceivedDLHARQState(job.Cfg,1);
        end
        result=sixgr.truth.executeGrantPHYJob(job); out=result.Result;
        assert(result.ReadyForReceiverCommit && height(out.TrialTable)==1);
        localAssertReceiverCFOEvidence(out.TrialTable);
        assert(ismember('AppliedAWGNSNRSource',out.TrialTable.Properties.VariableNames) && ...
            out.TrialTable.AppliedAWGNSNRSource==string(sixgr.util.structGet(replay,'AppliedAWGNSNRSource',"")), ...
            'The DL trial must retain the actual executed noise-calibration source.');
        out=sixgr.truth.bindSharedDLCSICompletion(out,p,receiver,owner);
        csi=out.CSIRSTrialTable;
        assert(height(csi)==1 && csi.Observed && csi.CSIMeasurementAvailable && ...
            csi.ResultAvailableAtSample==owner.Events.NextSampleIndex && ...
            csi.ObservationEndSampleExclusive==receiver.EndSampleExclusive);
        state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,csi);
        state.TestSharedCSIReceived=true; state.TestCSISource=out;
        sourceRow=sixgr.truth.exportSharedChannelObservation(state.TestRoot,out.TrialTable, ...
            item.Planes,p,c.DesiredReferencePlane);
        sixgr.channel.validateSharedChannelObservationArtifact(state.TestRoot,sourceRow);
        sixgr.util.csvWriteTable(fullfile(state.TestRoot,'shared_received_csirs.csv'),csi,'PreserveSchema',true);
        save(fullfile(state.TestRoot,'shared_received_csirs.mat'),'item','out','sourceRow','-v7.3');
        fprintf('SHARED_CSI_SOURCE_RECEIVED slot=%d completed_sample=%d CQI=%g RI=%g PMI=%g\n', ...
            csi.Slot,csi.ResultAvailableAtSample,csi.CQI,csi.RI,csi.PMI);
    elseif item.Kind=="PUSCH"
        job=c.Job; job.PrepareOnly=false;
        if isfield(state,'TestDecodedULReferenceFields')
            actual=p.Tx.PUSCH.DMRS; received=state.TestDecodedULReferenceFields;
            assert(isequal(double(actual.DMRSPortSet(:).'),double(received.dmrs_port_set(:).')) && ...
                actual.NumCDMGroupsWithoutData==received.dmrs_num_cdm_groups_without_data && ...
                actual.DMRSLength==received.dmrs_front_load_symbols, ...
                'Received DCI reference indication must match the actual transmitted PUSCH DMRS, not rank-only planning fields.');
        end
        replay=sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,c.DesiredReferencePlane,replay);
        expectedTiming=(p.StartSample-p.ReceiveStartSample) + ...
            replay.RuntimeChannelFilterDelay_samples + ...
            replay.RuntimeChannelMinimumPathDelay_samples + ...
            replay.InjectedTimingOffset_samples;
        assert(replay.TrueReceiverTimingOffset_samples==expectedTiming && ...
            ~replay.TimingTruthReceiverEstimatorInput, ...
            'UL timing truth must include the shared-clock observation displacement and executed channel delay.');
        job.ReceivedContext=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ChannelState',owner.directionalChannelState(1,'UL'));
        if state.TestIndependentCompletion
            job=sixgr.truth.bindSharedPUSCHReceiverContext(state,job);
            assert(job.ReceivedContext.UCIReceiveContext.Data.HARQACKBitCount==double(state.TestIndependentSharedHARQ && ~state.TestSeparatePUCCH) && ...
                isempty(job.ReceivedContext.UCIReportConfiguration)==~state.TestWithCSI);
            binding=sixgr.truth.puschUCIObservationBinding(job.GrantSnapshot,receiver);
            assert(job.ReceivedContext.UCIReceiveContext.Data.AssignmentDigest==binding.AssignmentDigest && ...
                job.ReceivedContext.UCIReceiveContext.Data.ObservationID==binding.ObservationID, ...
                'Changing UCI transport must preserve the exact scheduled UL grant and receive-window identity.');
            poisoned=state; poisoned.PendingFeedbackTable=table(true,'VariableNames',{'Ack'});
            poison=job; poison.ExpectedUCIBits=ones(99,1,'int8');
            poison.PreviousCombinedLLR=ones(99,1);
            same=sixgr.truth.bindSharedPUSCHReceiverContext(poisoned,poison);
            assert(isequaln(same.ReceivedContext.UCIReceiveContext,job.ReceivedContext.UCIReceiveContext));
            assert(same.ReceivedContext.ULHARQReceiverKey==job.ReceivedContext.ULHARQReceiverKey, ...
                'UE payload/audit poisoning cannot change the scheduled gNB HARQ identity.');
            assert(isequaln(same.PreviousCombinedLLR,job.PreviousCombinedLLR) && ...
                isequaln(same.ReceivedContext.ULHARQReceiverAttempt,job.ReceivedContext.ULHARQReceiverAttempt), ...
                'Transmit-preparation cache poisoning cannot replace gNB-owned prior soft state.');
            changedEpoch=job.GrantSnapshot;
            changedEpoch.HARQ.NDIEpoch=changedEpoch.HARQ.NDIEpoch+1;
            assert(sixgr.truth.scheduledULHARQReceiverKey(job.Cfg,changedEpoch)~= ...
                job.ReceivedContext.ULHARQReceiverKey, ...
                'The same NDI bit in another epoch must not reuse the retained gNB soft-buffer key.');
        end
        result=sixgr.truth.executeGrantPHYJob(job); out=result.Result;
        assert(result.ReadyForReceiverCommit && height(out.TrialTable)==1);
        if out.TrialTable.CRCPass(end)==1
            % Same production rule as localCompleteSharedDataPlan: only an
            % actual received PUSCH timing result can refresh the gNB clock.
            state=sixgr.truth.storeReceivedULTimingReference(state,item.UE, ...
                sixgr.phy.sync.ReceivedULTimingReference(p,receiver,out.ReceiveTiming));
        end
        localAssertReceiverCFOEvidence(out.TrialTable);
        assert(ismember('AppliedAWGNSNRSource',out.TrialTable.Properties.VariableNames) && ...
            out.TrialTable.AppliedAWGNSNRSource==string(sixgr.util.structGet(replay,'AppliedAWGNSNRSource',"")), ...
            'The UL trial must retain the actual executed noise-calibration source.');
        if ~state.TestWithHARQ, assert(out.TrialTable.CRCPass==1); end
        if state.TestIndependentCompletion
            assert(out.HARQ.ReceiverHARQKey==job.ReceivedContext.ULHARQReceiverKey && ...
                string(out.HARQ.SoftBuffer.HARQKey)==job.ReceivedContext.ULHARQReceiverKey, ...
                'Normal shared UL decoding must retain its scheduled receiver identity with actual soft state.');
            assert(string(out.HARQ.GrantSnapshot.HARQTBContext.TBId)== ...
                string(p.RequestBinding.Grant.TransportBlockId) && ...
                string(out.HARQ.Context.TransportBlockContext.TBId)== ...
                string(p.RequestBinding.Grant.TransportBlockId), ...
                'test:SharedPUSCHTransportIdentityLost', ...
                'Receiver completion must retain the identity assigned before actual encoding.');
            for field=["DCI","ULTotalDAIAuthority","UCIOnPUSCHFeedbackBitIndices", ...
                    "UCIOnPUSCHFeedbackGrantIds","ExpectedUCIBits"]
                present=isfield(job.GrantSnapshot,field);
                assert(isfield(out.HARQ.GrantSnapshot,field)==present, ...
                    'test:PUSCHReceiveGrantAuthorityLost', ...
                    'PUSCH completion must preserve presence/absence of scheduled authority: %s.',field);
                if present
                    assert(isequaln(out.HARQ.GrantSnapshot.(field),job.GrantSnapshot.(field)), ...
                        'test:PUSCHReceiveGrantAuthorityLost', ...
                        'PUSCH completion must preserve scheduled/producer authority exactly: %s.',field);
                else
                    assert(state.TestSeparatePUCCH && ~any(field==["DCI","ULTotalDAIAuthority"]), ...
                        'test:PUSCHReceiveGrantAuthorityLost', ...
                        'Only the disjoint no-UCI case may lack producer-specific fields.');
                end
            end
        end
        assert(out.TrialTable.TrueTimingOffset_samples==expectedTiming && ...
            abs(out.TrialTable.ResidualTimingError_PostCorrection_samples)<=1, ...
            'The practical PUSCH timing estimate must reconcile against receiver-arrival truth within one sample.');
        verifyReceivedConstellationCapture(out,job.Cfg,item.UE, ...
            fullfile(state.TestRoot,'received_constellation', ...
            sprintf('ul_slot_%d',job.StartSlotIndex)));
        assert(string(out.TrialTable.NoiseVarSource)=="runtime_channel_estimate", ...
            'Shared PUSCH must estimate disturbance from received reference REs, not injected-noise metadata.');
        hasUCI=job.ExpectedUCIPayload.hasPayload();
        if hasUCI
            expectedACK=int8([1;0]);
            if state.TestIndependentSharedHARQ, expectedACK=int8(state.TestExpectedSharedACK); end
            assert(out.HARQ.HARQACKContentMatch && isequal(out.HARQ.DecodedHARQACKBits,expectedACK));
        else
            assert(isempty(out.HARQ.DecodedHARQACKBits));
        end
        assert(string(out.HARQ.GrantSnapshot.GrantContextId)==string(job.GrantContextId), ...
            'The actual decoded grant must retain the same PHY-job identity used for UCI reservation.');
        % Exercise the main shared completion's receive-event handoff on
        % actual CDL/SRS/PUSCH captures, without a known-delay/oracle input.
        out.HARQ.ReceivedTimingEvidence=sixgr.truth.receivedDataSymbolTiming( ...
            p,receiver,out.ReceiveTiming,owner.Events.NextSampleIndex);
        if state.TestIndependentCompletion
            priorTimeline=state.HARQTimelineTable;
            priorPending=state.PendingFeedbackTable;
            if state.TestWithCSI
                beforeCSI=state.DLHarq.Stats;
                bad=out.HARQ; bad.DecodedCSIPart1Bits=NaN;
                localReject(@()sixgr.truth.CoupledTruthRuntime.completeSharedPUSCHHARQFeedbackRuntime( ...
                    state,job.Cfg,bad,receiver,job.ReceivedContext.UCIReceiveContext), ...
                    'sixgr:truth:InvalidReceivedCSIBit');
                assert(isequaln(state.DLHarq.Stats,beforeCSI), ...
                    'Malformed CSI must reject before shared HARQ handle mutation.');
                if state.TestForgetCSIProducer
                    % Delete only test-side UE bookkeeping AFTER the actual
                    % on-air CSI was generated and independently decoded.
                    % This is not a no-transmitter/noise-only RF episode.
                    state.PendingCSITable=state.PendingCSITable([],:);
                    out.HARQ.GrantSnapshot.UCIOnPUSCHCSIReportIdentity="poisoned_TX_identity";
                    out.HARQ.ExpectedCSIPart1Bits=ones(99,1,'int8');
                    out.HARQ.ExpectedCSIPart2Bits=ones(101,1,'int8');
                end
            end
            [state,out.HARQ]=sixgr.truth.CoupledTruthRuntime.completeSharedPUSCHHARQFeedbackRuntime( ...
                state,job.Cfg,out.HARQ,receiver,job.ReceivedContext.UCIReceiveContext);
            ulState=state.SharedGNBULHARQReceivers;
            assert(isscalar(ulState) && ulState{1}.Attempt.ReceiverKey==out.HARQ.ReceiverHARQKey && ...
                ulState{1}.CRCPass==out.HARQ.CombinedDecodeOK && ...
                ulState{1}.Attempt.EndSampleExclusive==receiver.EndSampleExclusive);
            if ulState{1}.CRCPass, assert(isempty(ulState{1}.SoftBuffer)); end
            if state.TestWithCSI
                save(fullfile(state.TestRoot,'independent_csi_completion.mat'),'out','job','receiver','-v7.3');
                allReports=sixgr.util.structGet(state,'SharedGNBCSIReportTable',table());
                observationID=out.HARQ.SharedPUSCHHARQFeedbackReceipt.ObservationID;
                reports=allReports(string(allReports.ObservationID)==observationID,:);
                assert(height(reports)==1 && reports.CSIUCIDecodeOk && state.LatestDLFeedback(1).Valid, ...
                    'test:IndependentCSIPublicationMissing', ...
                    'The common independent receive completion must publish received CSI without the legacy producer-bound adapter.');
                assert(reports.CSIReferenceSlot==6 && reports.SourceSlot==6 && reports.DueSlot==10 && ...
                    reports.SourceSlotAuthority=="configured_CSI_reference_resource_not_UE_measurement_slot" && ...
                    isnan(reports.SINR_dB) && isnan(reports.CRCPass));
                path=fullfile(state.TestRoot,'received_csi_reports.csv');
                sixgr.util.csvWriteTable(path,allReports,'PreserveSchema',true,'RoundTripNumericText',true);
                savedAll=sixgr.util.csvReadTable(path,'TextType','string');
                assert(height(savedAll)==height(allReports));
                saved=savedAll(string(savedAll.ObservationID)==observationID,:);
                assert(height(saved)==1);
                assert(saved.CSIUCIDecodeOk && saved.CQI==reports.CQI && isnan(saved.SINR_dB));
                if state.TestForgetCSIProducer
                    assert(strlength(reports.UEReferenceRecordJSON)==0);
                else
                    assert(strlength(reports.UEReferenceRecordJSON)>0);
                end
            end
            if state.TestSeparatePUCCH
                assert(isequaln(state.HARQTimelineTable,priorTimeline) && ...
                    isequaln(state.PendingFeedbackTable,priorPending), ...
                    'Data-only PUSCH must leave separate PUCCH HARQ obligations untouched.');
            elseif state.TestIndependentSharedHARQ
                timeline=state.HARQTimelineTable;
                assert(height(timeline)==height(priorTimeline) && ...
                    isequaln(timeline(:,{'Direction','RNTI','HarqID','Slot'}), ...
                    priorTimeline(:,{'Direction','RNTI','HarqID','Slot'})) && ...
                    all(string(timeline.FeedbackMechanism)=="pusch_uci") && ...
                    all(string(timeline.FeedbackEvidenceSource)=="independent_scheduled_pusch_rx_uci"), ...
                    'test:SharedPUSCHTimeline','The actual DL row must retain identity and received PUSCH provenance.');
            end
            before=state.DLHarq.Stats;
            state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHUCIRuntime(state,out.HARQ);
            assert(isequaln(state.DLHarq.Stats,before));
            localReject(@()sixgr.truth.CoupledTruthRuntime.completeSharedPUSCHHARQFeedbackRuntime( ...
                state,job.Cfg,out.HARQ,receiver,job.ReceivedContext.UCIReceiveContext), ...
                'sixgr:truth:DuplicateSharedPUSCHHARQReception');
            out.HARQ.SharedTransmissionID=c.TransmissionIdentity.TransmissionID;
            % Exercise the normal reducer after the common feedback commit,
            % including the no-CSI UL branch and its once-only TX/RX ledger.
            beforeUL=state.ULHarq.Stats;
            absent=state; absent.SlotTraceTable=state.SlotTraceTable([],:);
            localReject(@()sixgr.truth.CoupledTruthRuntime.completeSlot( ...
                absent,job.Cfg,1,'UL',out.TrialTable,out), ...
                'sixgr:truth:MissingSharedSourceSlotTrace');
            for invalidSlot=[NaN state.CurrentSlot+1]
                bad=out.TrialTable; bad.Slot(:)=invalidSlot;
                localReject(@()sixgr.truth.CoupledTruthRuntime.completeSlot( ...
                    state,job.Cfg,1,'UL',bad,out),'sixgr:truth:InvalidSharedSourceSlot');
            end
            assert(isequaln(state.ULHarq.Stats,beforeUL), ...
                'Invalid source-slot metadata must fail before shared HARQ handle mutation.');
            [state,out.TrialTable]=sixgr.truth.CoupledTruthRuntime.completeSlot( ...
                state,job.Cfg,1,'UL',out.TrialTable,out);
            assert(isequaln(state.DLHarq.Stats,before) && ...
                state.ULHarq.Stats.Tx==1 && state.ULHarq.Stats.Ack==1 && ...
                state.ULCompletedSlots==job.StartSlotIndex && ...
                nnz(state.SharedDataRXCommittedIDs==out.HARQ.SharedTransmissionID)==1);
        end
        assert(sixgr.truth.receivedPUSCHUCIOccasion(owner,out.HARQ,out.HARQ.GrantSnapshot)==job.StartSlotIndex);
        missing=rmfield(out.HARQ,'ReceivedTimingEvidence');
        localReject(@()sixgr.truth.receivedPUSCHUCIOccasion(owner,missing,out.HARQ.GrantSnapshot), ...
            'sixgr:truth:MissingSharedHARQReceiveTiming');
        future=out.HARQ; future.ReceivedTimingEvidence.ResultAvailableAtSample=owner.Events.NextSampleIndex+1;
        localReject(@()sixgr.truth.receivedPUSCHUCIOccasion(owner,future,out.HARQ.GrantSnapshot), ...
            'sixgr:truth:FuturePUSCHUCIDelivery');
        if state.TestDeferUCIDelivery
            % An explicit one-slot receiver-to-scheduler delivery delay;
            % do not change the captured waveform or its availability time.
            state.TestDeferredUCI=out.HARQ;
            assert(all(~state.PendingFeedbackTable.Processed));
        elseif hasUCI && ~state.TestIndependentCompletion
            state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHUCIRuntime(state,out.HARQ);
            assert(all(state.PendingFeedbackTable.Processed) && ...
                state.DLHarq.Stats.Ack==1 && state.DLHarq.Stats.Nack==1);
        end
        timingFields=sixgr.truth.harqFeedbackReceiveTimingFields( ...
            out.HARQ,out.HARQ.GrantSnapshot,true);
        for name=string(fieldnames(timingFields)).'
            out.TrialTable.(name)=timingFields.(name);
        end
        row=sixgr.truth.bindSharedLargeScaleEvidence(out.TrialTable,item.Planes);
        if isfield(job.Cfg.phy.pusch,'receivedDCIAssignment')
            isRetx=logical(job.GrantSnapshot.HARQ.IsRetransmission);
            authority="received_dci_and_ue_new_tb_payload";
            if isRetx, authority="received_dci_and_ue_harq_buffer"; end
            assert(all(row.ULTransmissionAuthority==authority) && ...
                all(row.ULReceiveAllocationAuthority=="gnb_own_scheduled_grant") && ...
                all(row.ULReceivedAssignmentDigest==job.Cfg.phy.pusch.receivedDCIAssignment.AssignmentDigest));
            assert(row.UEHARQAttempt==1+isRetx);
            if ~isRetx, assert(row.UEHARQInitialAssignmentDigest==row.ULReceivedAssignmentDigest); end
            if hasUCI
            assert(row.PUSCHUCIInitialMCS==job.GrantSnapshot.MCSIndex && ...
                row.PUSCHUCIInitialMCSSource=="current_new_tb_mcs");
            end
        end
        row=sixgr.truth.bindSharedRFExecutionEvidence(row,item.Planes);
        localVerifyEffectiveLinkDiagnostic(state.TestRoot,job.Cfg,"UL",out,item.Planes,p,c.DesiredReferencePlane);
        [row,~,channelCaptures,channelReplays]=sixgr.truth.exportSharedChannelObservation( ...
            state.TestRoot,row,item.Planes,p,c.DesiredReferencePlane);
        assert(numel(out.ChannelEstimateSnapshots)==1 && ~isempty(out.ChannelEstimateSnapshots{1}), ...
            'The actual shared decoder must retain its pilot channel estimates.');
        beforeHARQ=out.HARQ;
        row=sixgr.truth.exportSharedPUSCHChannelEstimate(state.TestRoot,row, ...
            out.ChannelEstimateSnapshots{1},p,channelCaptures,channelReplays,c.WaveformToElementMatrix);
        assert(isequaln(beforeHARQ,out.HARQ) && isfinite(row.NMSE_dB) && ...
            ~row.ChannelEstimateReferenceUsedByReceiver && ...
            isfile(fullfile(state.TestRoot,row.ChannelEstimateResourcesCSV)));
        measured=readtable(fullfile(state.TestRoot,row.ChannelEstimateResourcesCSV));
        localVerifyChannelResourceArchive(state.TestRoot,row);
        assert(height(measured)==row.ChannelEstimateComparedValues && ...
            abs(10*log10(sum(measured.ChannelErrorEnergy)/sum(measured.ReferenceChannelEnergy))-row.NMSE_dB)<1e-10);
        fprintf('SHARED_PUSCH_CHANNEL_NMSE_PASS nmse=%g values=%d folder=%s\n', ...
            row.NMSE_dB,row.ChannelEstimateComparedValues,state.TestRoot);
        path=fullfile(state.TestRoot,'received_pusch.csv');
        powerEvidence=jsondecode(row.AllocationCarrierPowerMeasurementJSON);
        if strcmpi(string(sixgr.util.structGet(job.Cfg,'integration.run_mode','')),'FIXED_SNR_SWEEP') && ...
                logical(sixgr.util.structGet(job.Cfg,'integration.configured_snr_is_link_authority',false))
            assert(powerEvidence.PowerReferencePlane=="normalized_fixed_esn0_unit_occupied_re_es" && ...
                strlength(row.AllocationCarrierRSSIPerReceiveAntenna_dBm)==0 && ...
                ~isfield(powerEvidence,'SymbolPowerPerAntenna_W'));
            expectedPower=10*log10(mean(powerEvidence.SymbolPowerPerAntenna_UnitOccupiedRE_Es,1));
            assert(max(abs(expectedPower(:)-powerEvidence.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es(:)))<1e-10);
            mirroredPower=jsondecode(row.AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es);
            assert(max(abs(expectedPower(:)-mirroredPower(:)))<1e-10);
        else
            assert(powerEvidence.PowerReferencePlane=="receiver_antenna_connector_pre_composite_front_end" && ...
                strlength(row.AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es)==0);
        end
        if logical(sixgr.util.structGet(job.Cfg,'integration.configured_snr_is_link_authority',false))
            assert(isnan(row.RuntimeGeometryDistance2D_m) && ...
                isnan(row.RuntimeGeometryDistance3D_m) && ...
                string(row.RuntimeGeometrySource)=="not_applicable_fixed_configured_esn0", ...
                'Configured-Es/N0 PUSCH must not report dormant geometry as executed pathloss evidence.');
        else
            assert(isfinite(row.RuntimeGeometryDistance2D_m) && ...
                row.RuntimeGeometryDistance2D_m<row.RuntimeGeometryDistance3D_m, ...
                'A geometry-authority PUSCH row must retain distinct executed horizontal/slant ranges.');
        end
        sixgr.util.csvWriteTable(path,row,'PreserveSchema',true);
        columnTypes=struct();
        for name=string(row.Properties.VariableNames)
            value=row.(name);
            if isnumeric(value) || islogical(value) || isstring(value)
                columnTypes.(name)=class(value);
            end
        end
        persisted=sixgr.util.csvReadTable(path,'TextType','string','ColumnTypes',columnTypes);
        assert(string(persisted.AllocationCarrierPowerMeasurementJSON)==row.AllocationCarrierPowerMeasurementJSON, ...
            'Actual received carrier power scope and units must survive CSV unchanged.');
        if isfield(job.Cfg.phy.pusch,'receivedDCIAssignment')
            assert(all(persisted.ULTransmissionAuthority==row.ULTransmissionAuthority) && ...
                all(persisted.ULReceiveAllocationAuthority==row.ULReceiveAllocationAuthority) && ...
                all(persisted.ULReceivedAssignmentDigest==row.ULReceivedAssignmentDigest));
            assert(persisted.UEHARQAttempt==row.UEHARQAttempt && ...
                persisted.UEHARQInitialAssignmentDigest==row.UEHARQInitialAssignmentDigest);
            assert(isequaln(persisted.PUSCHUCIInitialMCS,row.PUSCHUCIInitialMCS) && ...
                persisted.PUSCHUCIInitialMCSSource==row.PUSCHUCIInitialMCSSource);
        end
        assert(persisted.DataDecodeAvailableAtSample==owner.Events.NextSampleIndex && ...
            persisted.DataReceiveSymbolEndSampleExclusive<=receiver.EndSampleExclusive && ...
            persisted.DataReceiveSampleRateHz==owner.SampleRateHz);
        retainedTiming=jsondecode(persisted.DataReceiveTimingEvidenceJSON);
        assert(retainedTiming.DataAbsoluteSlot==out.HARQ.GrantSnapshot.ScheduledAbsoluteSlot && ...
            retainedTiming.RNTI==out.HARQ.GrantSnapshot.RNTI && ...
            retainedTiming.Direction=="UL" && ~retainedTiming.ProcessingBudgetIncluded);
        verified=sixgr.channel.validateSharedChannelObservationArtifact(state.TestRoot,persisted);
        assert(all(verified.Segments.NumTransmitAntennas==p.NumPhysicalTransmitAntennas) && ...
            all(verified.Segments.NumReceiveAntennas==receiver.NumReceiveAntennas));
        state.TestPUSCHReceived=true;
        state.TestPUSCHObservationID=row.ChannelObservationID;
        if state.TestSeparatePUCCH, state.TestPUSCHRows=[state.TestPUSCHRows;row]; end
        if state.TestWithHARQ
            HARQEvidence=out.HARQ; %#ok<NASGU>
            save(fullfile(state.TestRoot,sprintf('received_ul_harq_slot_%d.mat',job.StartSlotIndex)), ...
                'HARQEvidence','-v7.3');
            state.TestPUSCHRows=[state.TestPUSCHRows;row];
            sixgr.util.csvWriteTable(fullfile(state.TestRoot,'received_pusch_harq.csv'),state.TestPUSCHRows,'PreserveSchema',true);
            state.TestLastULHARQ=out.HARQ;
            state.ULHarq.storeSoftBuffer(out.HARQ.GrantSnapshot.RNTI, ...
                out.HARQ.GrantSnapshot.HARQ.HarqID,out.HARQ.SoftBuffer);
            state.ULHarq.onFeedback(out.HARQ.GrantSnapshot.RNTI,out.HARQ.GrantSnapshot.HARQ.HarqID, ...
                logical(out.HARQ.CombinedDecodeOK),'SourceSlot',job.StartSlotIndex,'FeedbackSlot',state.CurrentSlot);
            fprintf('SHARED_UL_HARQ_ATTEMPT: slot=%d CRC=%d current=%d combined=%d\n', ...
                job.StartSlotIndex,row.CRCPass,out.HARQ.CurrentDecodeOK,out.HARQ.HARQCombiningApplied);
        end
    else
        error('test:UnexpectedSharedEvent','Unexpected event %s.',item.Kind);
    end
end
end

function state=localCompleteUnselectedProducer(state,item)
owner=state.SharedWaveformStream; g=item.Context.Grant; cfg=item.Context.Config;
result=sixgr.truth.receiveSharedPUSCHWithoutTransmission(state,item.Context.ObservationID);
% Same completed physical samples, no new RF/channel execution. Remove UE
% producer bookkeeping and poison its optional expected payload: gNB field
% ownership and decisions must depend only on its installed schedule/IQ.
observer=state; observer.PendingFeedbackTable=table(); observer.PUCCHGrantTraceTable=table();
observer.SharedUEHARQACKEvents={}; observer.SharedReceivedGrantControls={};
observer.ExpectedHARQACKBits=int8([0;0;0;0]);
observer.PendingCSITable=table(); observer.ExpectedCSIPart1Bits=ones(19,1,'int8');
again=sixgr.truth.receiveSharedPUSCHWithoutTransmission(observer,item.Context.ObservationID);
assert(again.UCIReceiveContext.Digest==result.UCIReceiveContext.Digest && ...
    isequaln(again.HARQMapping,result.HARQMapping) && ...
    isequaln(again.IndependentHARQObservation,result.IndependentHARQObservation) && ...
    isequaln(again.ULHARQReceiverDecision,result.ULHARQReceiverDecision), ...
    'Fixed-IQ gNB ownership/results must not depend on UE producer state.');
if state.TestWithCSI
    [~,report]=sixgr.truth.buildSharedPUSCHCSIReceiveObligation(cfg,g);
    csi=sixgr.truth.normalizeReceivedPUSCHCSI(result.Receiver,result.UCIReceiveContext,report);
    replayCSI=sixgr.truth.normalizeReceivedPUSCHCSI(again.Receiver,again.UCIReceiveContext,report);
    assert(isequaln(csi,replayCSI),'Fixed-IQ CSI reception must not depend on UE report/payload.');
end
[selection,producer]=owner.readUnselectedPUCCHForPUSCH(g);
assert(~isempty(fieldnames(producer)) && numel(producer.UEHARQCodebook.Events)==1);
actual=result.IndependentHARQObservation;
normalized=struct('MappingDigest',result.HARQMapping.Digest,'UEIndex',g.UEIndex, ...
    'RNTI',g.RNTI,'TargetSlot',double(g.Slot),'DecodedBits',actual.DecodedBits, ...
    'DecodeOk',actual.DecodeOk,'DTXFlag',actual.DTXFlag,'Transport',"PUSCH");
dispositions=sixgr.truth.prepareScheduledHARQFeedback(state,cfg,g.UEIndex,double(g.Slot),normalized,g);
for k=1:numel(dispositions), dispositions(k).ObservationID=result.Binding.ObservationID; end
next=sixgr.truth.stageUnselectedPUCCHProducerDisposition(state,selection,producer,result.HARQMapping,dispositions);
broken=state; broken.SharedPUCCHTXLedger={};
localReject(@()sixgr.truth.stageUnselectedPUCCHProducerDisposition(broken,selection,producer,result.HARQMapping,dispositions), ...
    'sixgr:truth:UnselectedPUCCHTXNotExecuted');
wrong=selection; wrong.PUCCHTransmissionID="foreign_transmission";
localReject(@()sixgr.truth.validateUnselectedPUCCHTransmission(state,wrong,producer), ...
    'sixgr:truth:UnselectedPUCCHTXIncomplete');
localReject(@()sixgr.truth.stageUnselectedPUCCHProducerDisposition(next,selection,producer,result.HARQMapping,dispositions), ...
    'sixgr:truth:UnselectedPUCCHProducerAlreadyDisposed');
state=sixgr.truth.CoupledTruthRuntime.stageSharedReceiveOnlyPUSCHCSIRuntime( ...
    state,cfg,g,result.Receiver,result.UCIReceiveContext,result.Observation);
[state,applied]=sixgr.truth.CoupledTruthRuntime.commitScheduledHARQFeedbackRuntime( ...
    state,cfg,g.UEIndex,double(g.Slot),normalized,result.Observation,result.Binding.ObservationID,g);
assert(numel(applied)==1 && applied.HARQFeedbackApplied && applied.ObservedAck==dispositions.ObservedAck);
localReject(@()sixgr.truth.CoupledTruthRuntime.commitScheduledHARQFeedbackRuntime( ...
    state,cfg,g.UEIndex,double(g.Slot),normalized,result.Observation,result.Binding.ObservationID,g), ...
    'sixgr:truth:DuplicateScheduledHARQFeedback');
other=normalized; other.Transport="PUCCH"; other.MappingDigest=result.HARQMapping.BaseMapping.Digest;
localReject(@()sixgr.truth.CoupledTruthRuntime.commitScheduledHARQFeedbackRuntime( ...
    state,cfg,g.UEIndex,double(g.Slot),other,result.Observation,"unused_PUCCH_decoder"), ...
    'sixgr:truth:DuplicateScheduledHARQFeedback');
state.PendingFeedbackTable=next.PendingFeedbackTable; state.PUCCHGrantTraceTable=next.PUCCHGrantTraceTable;
if isfield(next,'PendingCSITable'), state.PendingCSITable=next.PendingCSITable; end
state=sixgr.truth.stageSharedULHARQReception(state,cfg,g,result.Observation,result.ULHARQReceiverDecision);
event=sixgr.truth.prepareSharedULHARQSchedulerFeedback(state,g,result.ULHARQReceiverDecision);
assert(state.ULHarq.onFeedback(event.RNTI,event.HarqID,event.Outcome, ...
    'SourceSlot',event.SourceSlot,'FeedbackSlot',event.FeedbackSlot));
state=sixgr.truth.CoupledTruthRuntime.updateSchedulerAfterFeedbackRuntime(state,event,'UL');
save(fullfile(state.TestRoot,'unselected_pucch_pusch_receiver.mat'),'result','selection','producer','applied','-v7.3');
end

function localVerifyAppliedULWeights(state,item)
% Compare exported weights with actual mapped symbols, not a PMI label.
p=item.Context.Prepared;
assert(p.Direction=="UL");
records=state.SharedWaveformStream.DataTransmissions;
id=item.Context.TransmissionIdentity.TransmissionID;
hit=arrayfun(@(r)r.Identity.TransmissionID==id,records);
assert(nnz(hit)==1);
projection=records(hit).WaveformToElementMatrix;
W=double(projection)*double(p.Tx.PrecodeInfo.MatrixPorts);
assert(size(W,1)==p.NumPhysicalTransmitAntennas);
actual=double(p.Tx.PUSCHWaveformSymbols)*double(projection).';
fromLayers=double(p.Tx.PUSCHLayerSymbols)*W.';
assert(isequal(size(actual),size(fromLayers)) && ...
    norm(actual-fromLayers,'fro')<=1e-10*max(1,norm(actual,'fro')), ...
    'Exported physical weights must reproduce the actually mapped PUSCH data symbols.');
if ~logical(sixgr.util.structGet(p.ReceiverConfig,'outputs.antennaPatternSamplesEnabled',false)), return; end
r=state.AppliedDataPrecoderWeights;
r=r(r.TransmissionID==id,:);
assert(height(r)==numel(W) && all(r.MatrixSHA256==sixgr.phy.mimo.MatrixContract.digest(W)));
retained=complex(zeros(size(W)));
for j=1:height(r)
    retained(r.ElementIndex0(j)+1,r.LayerIndex0(j)+1)= ...
        complex(str2double(r.WeightReal(j)),str2double(r.WeightImag(j)));
end
assert(isequal(retained,W),'Decimal CSV weights must retain the actual composed matrix exactly.');
end

function state=localReceivedDLReservations(state,cfg,dueSlot)
% Actual isolated source decodes; resource reservation is component setup.
for k=1:2
    sourceSlot=3; variance=1e-13;
    if k==2, sourceSlot=6; variance=1e-4; end
    process=k-1;
    if state.TestWithCSI
        ue=find(state.DLHarq.UEList==cfg.phy.pdsch.RNTI);
        assert(isscalar(ue)); processes=state.DLHarq.UEProcs{ue};
        process=find(~[processes.Active],1)-1;
        assert(isscalar(process),'A real free HARQ process is required for the isolated source.');
    end
    [out,timing]=receivedDLFeedbackFixture(cfg,sourceSlot,process,variance);
    g=out.HARQ.GrantSnapshot; ack=logical(out.TrialTable.CRCPass);
    assert(ack==(k==1) && timing.DataDecodeAvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex);
    a=state.DLHarq.allocate(g.RNTI,sourceSlot,g.TBSBytes,'NewData',true);
    assert(a.HARQ.HarqID==g.HARQ.HarqID && a.HARQ.NDI==g.HARQ.NDI);
    state.DLHarq.onTx(g.RNTI,a.HARQ.HarqID,uint8(out.HARQ.TransportBlockBits),g,sourceSlot);
    f=struct('Direction',"DL",'UEIndex',1,'RNTI',g.RNTI,'HarqID',a.HARQ.HarqID, ...
        'SourceSlot',sourceSlot,'DueSlot',dueSlot,'Ack',ack,'CurrentDecodeOK',ack,'CombinedDecodeOK',ack, ...
        'ServingCell',1,'BaseStationID',1,'TBSBits',g.TBSBits,'UCIBitCount',1, ...
        'RequestedFormat',0,'ResolvedFormat',0,'PUCCHResourceId',"0", ...
        'PUCCHPRBStart',0,'PUCCHPRBCount',1,'PUCCHSymbolStart',12,'PUCCHNumSymbols',2, ...
        'UCIType',"harq_ack",'ControlResourceSource',"declared_component_resource_actual_dl_payload", ...
        'ControlResourceValidity',true,'FormatAdaptationReason',"none_strict_assignment", ...
        'PUCCHGrantId',"shared_pusch_actual_dl_"+k,'DeliveryMechanism',"pucch", ...
        'PUSCHGrantContextId',"",'MultiplexedBitIndex',NaN,'Processed',false, ...
        'RightCensored',false, ...
        'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
        'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
    for name=string(fieldnames(timing)).', f.(name)=timing.(name); end
    if k==1, state.PendingFeedbackTable=struct2table(f);
    else, state.PendingFeedbackTable=[state.PendingFeedbackTable;struct2table(f)]; end
    state=sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,struct2table(f));
end
if state.TestWithCSI
    assert(state.TestSharedCSIReceived,'CSI source must have executed through this shared owner.');
    out=state.TestCSISource;
    csi=out.CSIRSTrialTable;
    assert(height(csi)==1 && csi.Observed && csi.CSIMeasurementAvailable && ...
        csi.ResultAvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex, ...
        'CSI must come from an available, executed CSI-RS receiver.');
    state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',out.TrialTable,cfg,csi);
    assert(height(state.PendingCSITable)==1 && state.PendingCSITable.DueSlot==dueSlot && ...
        string(state.PendingCSITable.SourceSignal)=="CSI-RS" && ...
        state.PendingCSITable.MeasurementAvailableAtSample==csi.ResultAvailableAtSample);
    state.TestExpectedCSI=state.PendingCSITable;
end
end

function state=localQueueSharedCSISource(state,cfg,slot,sharedHARQ)
if nargin<4, sharedHARQ=false; end
owner=state.SharedWaveformStream;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
frame=floor((slot-1)/state.SlotsPerFrame)+1;
dl=sixgr.truth.bindSharedDataOccasion(dl,slot,frame,owner.SampleRateHz);
grant=sixgr.link.resolveWaveformGrant(dl,'DL',frame,'Slot',slot,'SFN',frame-1,'ControlAbsoluteSlot',slot-1);
allocated=state.DLHarq.allocate(grant.RNTI,slot,grant.TBSBytes,'NewData',true);
grant=sixgr.link.resolveWaveformGrant(dl,'DL',frame,'Slot',slot,'SFN',frame-1, ...
    'ControlAbsoluteSlot',slot-1,'HARQProcess',allocated.HARQ.HarqID);
assert(grant.Valid && grant.ExactPHYFeasible && allocated.HARQ.NDI==grant.HARQ.NDI);
% This component bypasses scheduler proposal binding. Retain its actual
% allocator epoch before the grant is frozen or any sample is transmitted.
grant.HARQ.NDIEpoch=allocated.HARQ.NDIEpoch;
if sharedHARQ
    % resolveWaveformGrant carries PHY cell identity, whereas scheduled DAI
    % also requires the runtime serving-cell index from the bound UE view.
    grant.ServingCell=double(dl.lls6g.userContext.RuntimeServingCell);
    % The isolated waveform-grant helper does not run the scheduler's
    % connected PUCCH selection step. Bind that real YAML authority before
    % repacking control and freezing the pre-transmission grant, never at RX.
    scheduler=sixgr.l2.mac.SchedulerPF(dl,'Direction','DL');
    grant=scheduler.attachPUCCHResourceAuthorityToGrant(grant);
    grant.DCI=scheduler.buildDCIBitfield(grant);
    grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(dl,'DL',grant, ...
        'Slot',grant.Slot,'Frame',grant.Frame,'HARQContext',grant.HARQ);
    grant.PHYGrantContextId=char(string(grant.PHYGrant.GrantContextId));
    [grant,candidateLedger]=sixgr.truth.prepareScheduledDLDAI(state.TestScheduledDLDAILedger,dl,grant);
    grant.TransportBlockId=char(grant.PHYGrant.GrantContextId);
    grant.TBId=grant.TransportBlockId;
    assert(grant.TimingDecision.DataAbsoluteSlot==5 && grant.TimingDecision.FeedbackAbsoluteSlot==9, ...
        'test:SharedHARQFixtureTiming','Authored K1 must place slot-6 DL feedback on slot-10 PUSCH.');
end
grant.ControlDecodeOk=false; grant.PDCCHGrantBindingOk=false;
job=sixgr.truth.buildGrantPHYJob(dl,'DL',cfg.channel.snr_dB,frame,[], ...
    struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true));
job.StartSlotIndex=slot;
% The job normalizes the existing frozen PHY identity into GrantContextId.
% Control and data must retain that same grant before either is enqueued.
grant=job.GrantSnapshot;
assert(isequal(grant.GrantContextId,job.GrantContextId) && ...
    string(grant.PHYGrantContextId)==job.GrantContextId);
control=sixgr.link.prepareSharedPDCCHTransmission(dl,'Grant',grant,'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
controlContext=struct('Grant',grant,'SharedCSISource',~sharedHARQ,'SharedHARQSource',sharedHARQ);
if sharedHARQ
    assert(isfield(state,'TestReceivedDLClock'),'Actual shared SS/PBCH timing is required for connected DL control.');
    controlContext.ReceivedDLTimingReference=state.TestReceivedDLClock;
end
owner.queuePDCCH(1,control,controlContext);
if sharedHARQ, state.TestScheduledDLDAILedger=candidateLedger; end
result=sixgr.truth.executeGrantPHYJob(job);
assert(~result.ReadyForReceiverCommit && isempty(result.Result.TrialTable));
owner.queueData(1,result.Result.PreparedTransmission,struct('Job',job,'SharedCSISource',~sharedHARQ,'SharedHARQSource',sharedHARQ));
if state.TestPacketAccounting
    state=localOfferPacket(state,'DL',grant.TBSBits);
else
    state.DLQueueBits(1)=state.DLQueueBits(1)+grant.TBSBits;
end
state.TestSharedCSIReceived=false;
end


function state=localCompleteSharedHARQSource(state,item,p,pre,tx,replay,receiver)
% Same actual shared DCI/decoder/event/slot reducer used by the coordinator.
owner=state.SharedWaveformStream;
control=state.TestSharedDLControl;
assert(control.AvailableAtSample<=receiver.EndSampleExclusive);
job=item.Context.Job; job.PrepareOnly=false;
job.GrantSnapshot=sixgr.truth.bindReceivedPDCCHGrantEvidence(job.GrantSnapshot,control.Grant);
replay=sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,item.Context.DesiredReferencePlane,replay);
job.ReceivedContext=struct('Prepared',p,'Observation',receiver, ...
    'PhysicalMeasurementObservation',pre,'TransmitterObservation',tx,'Replay',replay, ...
    'ChannelState',owner.directionalChannelState(1,'DL'), ...
    'ReceivedAssignment',control.ReceivedAssignment,'UEIndex',1, ...
    'ReceivedHARQState',sixgr.link.ReceivedDLHARQState(job.Cfg,1));
result=sixgr.truth.executeGrantPHYJob(job); out=result.Result;
assert(result.ReadyForReceiverCommit && height(out.TrialTable)==1);
out=sixgr.truth.bindSharedDLCSICompletion(out,p,receiver,owner);
if state.TestWithCSI
    csi=out.CSIRSTrialTable;
    assert(height(csi)==1 && csi.Observed && csi.CSIMeasurementAvailable && ...
        csi.Slot==6 && csi.ResultAvailableAtSample==owner.Events.NextSampleIndex);
    % Exercise the real CSI_Feedback -> throughput-row producer, not a
    % hand-authored report row. Keep the measured wire fields losslessly.
    assert(all(ismember({'CSIReportConfigID','CSIConfigurationEpoch','CSIUCIChannel', ...
        'CSIPart1BitsToken','CSIPart2BitsToken'},csi.Properties.VariableNames)));
    measuredRequest=job.Cfg.phy.csi.reportConfiguration;
    measuredRequest.Rank=csi.RI;
    measuredConfig=sixgr.phy.mimo.CSIReportConfiguration(measuredRequest,measuredRequest.Epoch);
    measuredWire=sixgr.phy.mimo.bindMeasuredCSIWireReport(measuredConfig,table2struct(csi));
    assert(numel(measuredWire.Part1Bits)+numel(measuredWire.Part2Bits)==csi.CSIPayloadBitLength);
    state.TestSharedCSIReceived=true; state.TestCSISource=out;
else
    % Exercise reporting-disabled behavior at normal physical completion.
    % A frozen grant may retain earlier CQI/rank; that is not a new report.
    row=out.TrialTable;
    assert(~job.Cfg.phy.csi.reportCSI && ...
        string(row.CSIComputationStatus)=="disabled_by_configuration" && ...
        ~isfinite(row.CSIPayloadBitLength) && strlength(string(row.CSIPayloadHex))==0 && ...
        strlength(string(row.CSIComputationErrorIdentifier))==0 && ...
        isfinite(row.PostEqSINR_dB) && isfinite(row.EVM_rms), ...
        'Disabled CSI reporting must retain physical data measurements without a report payload.');
    if ~isempty(out.CSIRSTrialTable)
        csi=out.CSIRSTrialTable;
        assert(all(string(csi.CSIComputationStatus)=="disabled_by_configuration") && ...
            all(isnan(csi.CQI) & isnan(csi.RI) & isnan(csi.PMI)), ...
            'A measured CSI-RS does not authorize disabled CQI/RI/PMI reporting.');
    end
end
[state,out.ReceivedHARQACKEvent]=sixgr.truth.commitReceivedDLHARQACKEvent( ...
    state,job.Cfg,control,out.ReceivedHARQDecision,out.ReceivedHARQState,owner.Events.NextSampleIndex);
state.SharedUEDLHARQEntities={out.ReceivedHARQState};
out.HARQ.SharedTransmissionID=item.Context.TransmissionIdentity.TransmissionID;
out.HARQ.ReceivedTimingEvidence=sixgr.truth.receivedDataSymbolTiming( ...
    p,receiver,out.ReceiveTiming,owner.Events.NextSampleIndex);
assert(out.HARQ.GrantSnapshot.PUCCHResourceIndicator==control.ReceivedAssignment.PUCCHResourceIndicator && ...
    string(out.HARQ.GrantSnapshot.PUCCHResourceIndicatorSource)==string(control.Grant.PUCCHResourceIndicatorSource), ...
    'test:SharedHARQPRI','Normal DL completion must retain the pre-transmission PRI and provenance.');
[state,out.TrialTable]=sixgr.truth.CoupledTruthRuntime.completeSlot( ...
    state,job.Cfg,1,'DL',out.TrialTable,out);
state.TestExpectedSharedACK=logical(out.ReceivedHARQDecision.ACK);
state.TestSharedHARQReceived=true;
assert(height(state.PendingFeedbackTable)==1 && state.PendingFeedbackTable.SourceSlot==6 && ...
    state.PendingFeedbackTable.DueSlot==10 && ~state.PendingFeedbackTable.Processed && ...
    state.PendingFeedbackTable.Ack==state.TestExpectedSharedACK && ...
    state.DLHarq.Stats.Ack==0 && state.DLHarq.Stats.Nack==0);
localVerifyEffectiveLinkDiagnostic(state.TestRoot,job.Cfg,"DL",out,item.Planes,p,item.Context.DesiredReferencePlane);
[sourceRow,~,captures,replays]=sixgr.truth.exportSharedChannelObservation(state.TestRoot,out.TrialTable, ...
    item.Planes,p,item.Context.DesiredReferencePlane);
assert(isnan(sourceRow.NMSE_dB) && isfinite(sourceRow.PilotReconstructionResidualRatio_dB), ...
    'Before independent scoring, do not relabel a pilot residual as true channel NMSE.');
assert(numel(out.ChannelEstimateSnapshots)==1 && ~isempty(out.ChannelEstimateSnapshots{1}));
beforeHARQ=out.ReceivedHARQDecision;
sourceRow=sixgr.truth.exportSharedDataChannelEstimate(state.TestRoot,sourceRow, ...
    out.ChannelEstimateSnapshots{1},p,captures,replays,item.Context.WaveformToElementMatrix);
assert(isequaln(beforeHARQ,out.ReceivedHARQDecision) && isfinite(sourceRow.NMSE_dB) && ...
    ~sourceRow.ChannelEstimateReferenceUsedByReceiver);
channelRows=readtable(fullfile(state.TestRoot,sourceRow.ChannelEstimateResourcesCSV));
localVerifyChannelResourceArchive(state.TestRoot,sourceRow);
assert(height(channelRows)==sourceRow.ChannelEstimateComparedValues && ...
    abs(10*log10(sum(channelRows.ChannelErrorEnergy)/sum(channelRows.ReferenceChannelEnergy))-sourceRow.NMSE_dB)<1e-10);
fprintf('SHARED_PDSCH_CHANNEL_NMSE_PASS nmse=%g pilot_residual=%g values=%d folder=%s\n', ...
    sourceRow.NMSE_dB,sourceRow.PilotReconstructionResidualRatio_dB,height(channelRows),state.TestRoot);
sixgr.channel.validateSharedChannelObservationArtifact(state.TestRoot,sourceRow);
sixgr.util.csvWriteTable(fullfile(state.TestRoot,'shared_received_dl_harq.csv'),sourceRow,'PreserveSchema',true);
save(fullfile(state.TestRoot,'shared_received_dl_harq.mat'),'item','out','control','sourceRow','-v7.3');
fprintf('SHARED_DL_HARQ_SOURCE_RECEIVED slot=6 due=10 ACK=%d completed_sample=%d\n', ...
    state.TestExpectedSharedACK,owner.Events.NextSampleIndex);
end

function localVerifyEffectiveLinkDiagnostic(root,cfg,direction,out,planes,prepared,planeID)
% Exercise the normal coordinator's bounded-memory contract using this
% actual completed decode, in addition to the full-tensor archive checks.
% No receiver re-execution and no replacement of the practical Hest.
assert(cfg.outputs.phySignalDiagnosticEnabled && out.SignalDiagnostic.Available, ...
    'test:MissingPhysicalDiagnostic','Actual %s receiver diagnostic is required.',direction);
[row,context]=sixgr.truth.exportSharedScoringWaveformObservation( ...
    root,out.TrialTable,planes,prepared,planeID);
snapshot=sixgr.link.buildPHYSignalDiagnosticSnapshot( ...
    cfg,direction,struct(),[],struct(),table(),context,out.SignalDiagnostic);
assert(snapshot.Available && snapshot.SnapshotID==out.SignalDiagnostic.SnapshotID && ...
    snapshot.Metadata.ExecutedChannelEvidenceRepresentation== ...
    "complete_sample_indexed_desired_link_IQ_not_path_gain_tensor");
T=snapshot.SourceTable;
assert(~any(ismember(T.Panel,["true_channel_impulse_response", ...
    "true_channel_frequency_response","runtime_channel_angles", ...
    "time_varying_channel_impulse_response","doppler_spectrum"])), ...
    'Effective-link IQ must not fabricate a pure channel-coefficient panel.');
post=T(T.Panel=="time_domain" & T.Series=="post_channel",:);
assert(~isempty(post) && isequal(complex(post.IValue,post.QValue), ...
    context.PostChannelWaveform(post.SampleIndex,1)));
fields={'Panel','Series','SampleIndex','PointIndex','XValue','YValue', ...
    'IValue','QValue','GridKind','GridSHA256'};
before=out.SignalDiagnostic.SourceTable;
assert(isequaln(before(before.Panel=="channel_estimate",fields), ...
    T(T.Panel=="channel_estimate",fields)));
assert(row.ChannelObservationReceiverEstimatorInput==false && ...
    context.AdditionalChannelExecutions==0 && context.AdditionalRFExecutions==0);
% Normal shared completion must publish the already-captured coefficients,
% not pass this different effective-IQ contract to the coefficient validator.
% Exercise the exact exporter outputs and scoring plane now used there.
coordinatorRoot=fullfile(root,'coordinator_publication',lower(direction));
mkdir(coordinatorRoot);
[coefficientRow,coefficientContext,~,~,scoringObservation,scoringEvidence]= ...
    sixgr.truth.exportSharedChannelObservation(coordinatorRoot,out.TrialTable,planes,prepared,planeID);
verified=sixgr.channel.validateSharedChannelObservationArtifact(coordinatorRoot,coefficientRow);
assert(startsWith(coefficientRow.ChannelObservationID,"chobs_") && ...
    any(verified.Manifest.Contract==["actual_shared_channel_observation/v1", ...
        "actual_shared_channel_observation/v2"]) && ...
    ~scoringEvidence.ReceiverEstimatorInput && ...
    scoringEvidence.AdditionalChannelExecutions==0 && ...
    scoringEvidence.AdditionalRFExecutions==0);
coefficientDiagnostic=sixgr.link.buildPHYSignalDiagnosticSnapshot( ...
    cfg,direction,struct(),[],struct(),table(),coefficientContext,out.SignalDiagnostic);
assert(coefficientDiagnostic.Available && ...
    any(coefficientDiagnostic.SourceTable.Panel=="true_channel_impulse_response"));
assert(isequaln(before(before.Panel=="channel_estimate",fields), ...
    coefficientDiagnostic.SourceTable(coefficientDiagnostic.SourceTable.Panel=="channel_estimate",fields)), ...
    'Publishing executed coefficients must not replace the practical Hest.');
scored=sixgr.truth.exportSharedDataChannelEstimate(coordinatorRoot,coefficientRow, ...
    out.ChannelEstimateSnapshots{1},prepared,scoringObservation,scoringEvidence);
assert(isfinite(scored.NMSE_dB) && ~scored.ChannelEstimateReferenceUsedByReceiver && ...
    scored.CRCPass==out.TrialTable.CRCPass);
localVerifyChannelResourceArchive(coordinatorRoot,scored,true);
fprintf('SHARED_COORDINATOR_CHANNEL_PUBLICATION_PASS direction=%s coefficients=1 actual_scoring_IQ=1 crc=%d nmse=%g\n', ...
    direction,scored.CRCPass,scored.NMSE_dB);
sixgr.util.csvWriteTable(fullfile(root,lower(direction)+"_effective_link_diagnostic.csv"), ...
    T,'PreserveSchema',true);
save(fullfile(root,lower(direction)+"_effective_link_diagnostic.mat"),'row','snapshot','-v7.3');
fprintf('SHARED_EFFECTIVE_LINK_DIAGNOSTIC_PASS direction=%s crc=%d samples=%d root=%s\n', ...
    direction,out.TrialTable.CRCPass,height(post),root);
end

function localVerifyChannelResourceArchive(root,row,requireExecutedReceiverFrequency)
if nargin<3, requireExecutedReceiverFrequency=false; end
archivePath=fullfile(root,row.ChannelEstimateMATFile);
assert(sixgr.phy.waveform.WaveformHash.file(archivePath)==row.ChannelEstimateMATFileSHA256);
archive=load(archivePath);
assert(row.NMSEScoringAvailable && ...
    row.ChannelNMSEErrorEnergy==archive.Score.ErrorEnergy && ...
    row.ChannelNMSEReferenceEnergy==archive.Score.ReferenceEnergy && ...
    row.ChannelNMSEComparedComplexValues==archive.Score.ComparedComplexValueCount && ...
    row.ChannelNMSEPilotResourceCount==numel(archive.Snapshot.PilotIndices) && ...
    row.ChannelNMSEReferencePlane==archive.ReferenceEvidence.ReferencePlane && ...
    ~row.ChannelNMSEGainOrPhaseFitted && ~row.ChannelNMSEReferenceUsedByReceiver, ...
    'Primary DL/UL NMSE operands and plane must match their independently scored archive.');
assert(archive.Contract=="scored_data_channel_resource_archive/v1" && ...
    archive.ResourcesCSVSHA256==row.ChannelEstimateResourcesCSVSHA256 && ...
    height(archive.Resources)==row.ChannelEstimateComparedValues && ...
    ~any(archive.Resources.ReferenceUsedByReceiver) && ...
    ~any(archive.Resources.GainOrPhaseFitted));
replay=string(tempname)+".csv";
cleanup=onCleanup(@()delete(replay)); %#ok<NASGU>
sixgr.util.csvWriteTable(replay,archive.Resources, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
assert(sixgr.phy.waveform.WaveformHash.file(replay)==archive.ResourcesCSVSHA256, ...
    'The MAT archive must reproduce the original resource CSV bytes, not merely its aggregate NMSE.');
if requireExecutedReceiverFrequency
    % The normal coordinator uses the actual noiseless desired-link IQ,
    % not the legacy pure-coefficient reference checked by other callers.
    % Verify the repaired RX-oscillator plane in BOTH persisted formats.
    evidence=archive.ReferenceEvidence;
    assert(evidence.ReceiverCFOIncluded && ...
        evidence.FrequencyEvidence.FrequencySource== ...
        "executed_RX_endpoint_not_configured_or_merged_TX_RX" && ...
        evidence.ExecutedReceiverCFO_Hz==row.ChannelEstimateExecutedReceiverCFO_Hz && ...
        ~evidence.ReceiverEstimatorInput && ~evidence.GainOrPhaseFitted && ...
        evidence.AdditionalChannelExecutions==0 && evidence.AdditionalRFExecutions==0);
    resources=sixgr.util.csvReadTable(fullfile(root,row.ChannelEstimateResourcesCSV), ...
        'TextType','string');
    assert(all(ismember({'FrequencyUnmatchedReferenceHReal','FrequencyUnmatchedReferenceHImag', ...
        'FrequencyUnmatchedErrorEnergy','FrequencyUnmatchedReferenceEnergy', ...
        'FrequencyUnmatchedComparisonRole'},resources.Properties.VariableNames)));
    exact=complex(resources.HReal,resources.HImag);
    matched=complex(resources.ReferenceHReal,resources.ReferenceHImag);
    unmatched=complex(resources.FrequencyUnmatchedReferenceHReal,resources.FrequencyUnmatchedReferenceHImag);
    assert(max(abs(abs(exact-matched).^2-resources.ChannelErrorEnergy))<1e-12 && ...
        max(abs(abs(exact-unmatched).^2-resources.FrequencyUnmatchedErrorEnergy))<1e-12 && ...
        all(resources.FrequencyUnmatchedComparisonRole== ...
        "legacy_frequency_unmatched_comparison_not_channel_estimation_quality"));
    oldScore=10*log10(sum(resources.FrequencyUnmatchedErrorEnergy)/ ...
        sum(resources.FrequencyUnmatchedReferenceEnergy));
    assert(abs(oldScore-row.NMSEFrequencyUnmatchedDiagnostic_dB)<1e-10 && ...
        abs(oldScore-archive.FrequencyUnmatchedScore.dB)<1e-10 && ...
        ~archive.FrequencyUnmatchedReferenceEvidence.ReceiverCFOIncluded);
    % A disabled oscillator legitimately leaves both references identical.
    % Do not manufacture an improvement or require a CRC pass from scoring.
    if evidence.ExecutedReceiverCFO_Hz==0
        assert(isequal(matched,unmatched));
    end
    fprintf('SHARED_RX_CFO_SCORE_ARCHIVE_PASS channel=%s RX_CFO_Hz=%g matched_NMSE=%g old_comparison=%g\n', ...
        resources.Channel(1),evidence.ExecutedReceiverCFO_Hz,row.NMSE_dB,oldScore);
end
fprintf('CHANNEL_RESOURCE_ARCHIVE_ROUNDTRIP_PASS channel=%s values=%d\n', ...
    archive.Resources.Channel(1),height(archive.Resources));
end

function [producerSlot,referenceSlot]=localLateCSIProducerSlot(cfg,reportSlot)
% A periodic report's CSI reference resource is not the link-adaptation
% feedback delay.  Select the newest actually configured CSI-RS occasion
% that is no later than the TS 38.214 reference-resource boundary.
referenceSlot=sixgr.truth.periodicCSIReferenceSlot(cfg,reportSlot);
assert(isfinite(referenceSlot) && referenceSlot>=1, ...
    'test:MissingCSIReferenceResource','A causal CSI reference resource is required.');
producerSlot=NaN;
for candidate=referenceSlot:-1:1
    [scheduled,~]=sixgr.phy.refsig.csirsOccasion(cfg,candidate-1);
    if scheduled
        producerSlot=candidate;
        break;
    end
end
assert(isfinite(producerSlot), ...
    'test:MissingCSIRSProducerOccasion', ...
    'No configured CSI-RS occasion exists before the report reference resource.');
end

function localVerifyCSI(state)
report=state.PendingCSITable; expected=state.TestExpectedCSI;
assert(height(report)==1 && report.Processed && report.DeliveredSlot==state.CurrentSlot && ...
    report.DueSlot==expected.DueSlot && report.CSIUCIDecodeOk && ...
    string(report.CSIUCITransport)=="pusch_decoded");
trace=state.PUCCHGrantTraceTable;
hit=string(trace.PUCCHGrantId)=="PUCCH-CSI-"+string(report.ReportIdentity);
assert(nnz(hit)==1 && trace.PUSCHUCITransmissionSlot(hit)==report.DueSlot && ...
    trace.PUSCHUCIDeliverySlot(hit)==report.DeliveredSlot && ...
    trace.MultiplexedOnPUSCH(hit) && ~trace.GrantExecutedFlag(hit), ...
    'Received CSI on PUSCH must not become a standalone PUCCH execution.');
for field=["CQI","RI","PMI","PMI_I11","PMI_I12","PMI_I13","PMI_I2","CRI"]
    assert(isequaln(report.(field),expected.(field)), ...
        'Received CSI %s must survive actual coded PUSCH transport.',field);
end
path=fullfile(state.TestRoot,'late_csi_delivery.csv');
sixgr.util.csvWriteTable(path,report,'PreserveSchema',true);
saved=sixgr.util.csvReadTable(path,'TextType','string');
assert(saved.SourceSlot==expected.SourceSlot && saved.DueSlot==expected.DueSlot && ...
    saved.DeliveredSlot==state.CurrentSlot && saved.CSIUCIDecodeOk);
% UE completion timing is retained as audit, not transmitted in CSI UCI.
% Check the exact original clock and identity after the CSV round trip.
audit=jsondecode(saved.UEReferenceRecordJSON);
csi=state.TestCSISource.CSIRSTrialTable;
assert(audit.MeasurementAvailableAtSample==csi.ResultAvailableAtSample && ...
    audit.MeasurementAvailableSlot==expected.MeasurementAvailableSlot && ...
    audit.MeasurementClockEpoch==csi.MeasurementClockEpoch && ...
    string(audit.MeasurementClockDomain)=="shared_receiver_sample_clock/v1" && ...
    string(audit.ReportIdentity)==expected.ReportIdentity && ...
    audit.SourceSlot==expected.SourceSlot && audit.DueSlot==expected.DueSlot);
assert(isnan(saved.MeasurementAvailableAtSample) && isnan(saved.MeasurementAvailableSlot) && ...
    isnan(saved.MeasurementClockEpoch) && ...
    (ismissing(saved.MeasurementClockDomain) || strlength(saved.MeasurementClockDomain)==0) && ...
    isnan(saved.SINR_dB) && saved.SourceSignal=="received_CSI_UCI");
disp('SHARED_PUSCH_LATE_CSI_DELIVERY_PASS: measured CSI-RS report retained across actual PUSCH and late delivery.');
end

function localSaveScenarioEvidence(s,cfg,root,scope)
if nargin<4
    scope='component: isolated HARQ source and shared physical transport; CSI source specified by resolved scenario; not full-run qualification';
end
meta=fullfile(root,'meta'); mkdir(meta);
inputs=fullfile(meta,'input_configs'); mkdir(inputs);
for k=1:numel(s.SourceFiles)
    [~,name,ext]=fileparts(s.SourceFiles(k));
    copyfile(s.SourceFiles(k),fullfile(inputs,sprintf('%03d_%s%s',k,name,ext)));
end
sixgr.util.jsonWrite(fullfile(meta,'resolved_config.json'),s.toStruct());
sixgr.lls6g.config.writeYAML(fullfile(meta,'resolved_config.yaml'),s.toStruct());
sixgr.util.jsonWrite(fullfile(meta,'schema_validation_report.json'), ...
    struct('Passed',true,'Validator','loadScenarioConfig/validateScenarioConfig','ConfigHash',s.ConfigHash));
[status,revision]=system('git rev-parse HEAD'); assert(status==0);
[status,changes]=system('git status --porcelain'); assert(status==0);
sixgr.util.jsonWrite(fullfile(meta,'environment_summary.json'),struct( ...
    'MATLABVersion',version,'Platform',computer,'Toolboxes',ver,'GitHash',strtrim(revision), ...
    'WorktreeStatus',changes,'Scope',scope));
sixgr.util.jsonWrite(fullfile(meta,'seeds.json'),struct('RunSeed',cfg.run.seed));
end

function tf=localNoPUCCHTrialAtSlot(trials,slot)
% An unused PUCCH producer is represented by a genuinely empty table. Do
% not require a fabricated Slot column merely to prove that no trial ran.
tf=isempty(trials) || ...
    (~ismember('Slot',trials.Properties.VariableNames) || ~any(trials.Slot==slot));
end

function localAssertReceiverCFOEvidence(T)
% The same core receiver columns must survive shared physical completion.
% An unavailable estimate is allowed; a simulated reference is not a donor.
required=["CFOCorrectionApplied","CFOCorrectionApplied_Hz", ...
    "ResidualCFO_EstimatedPostCorrection_Hz","ResidualCFOEstimateSource", ...
    "ResidualCFOEstimateAvailable","ResidualCFOEstimateDomain"];
assert(all(ismember(required,string(T.Properties.VariableNames))), ...
    'Shared data reception must retain the core receiver CFO evidence schema.');
assert(isequal(logical(T.ResidualCFOEstimateAvailable), ...
    isfinite(T.ResidualCFO_EstimatedPostCorrection_Hz)));
if T.ResidualCFOEstimateAvailable
    assert(strlength(string(T.ResidualCFOEstimateSource))>0 && ...
        T.ResidualCFOEstimateDomain=="receiver_measured_common_frequency_after_correction");
end
if T.CFOCorrectionApplied
    assert(isfinite(T.CFOCorrectionApplied_Hz));
end
end

function state=localOfferPacket(state,direction,bits)
% Explicit finite offered traffic, inserted through the production arrival
% boundary before TX. No ledger rows are created from a later decode result.
slot=state.CurrentSlot;
assert(slot>state.LastTrafficFrameApplied,'One arrival boundary per fixture slot.');
field='OfferedBitsDL'; if string(direction)=="UL", field='OfferedBitsUL'; end
state.Traffic.(field)(slot,1)=bits;
state=sixgr.truth.CoupledTruthRuntime.enqueueTrafficForFrameRuntime(state,slot);
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
