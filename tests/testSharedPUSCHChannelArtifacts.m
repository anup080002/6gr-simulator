function [ok,state]=testSharedPUSCHChannelArtifacts(mode,withCoincidentSRS,deferUCIDelivery,withCSI,twoPortUL,receivedAuthority,withHARQ,outputRoot,configPath,independentEmptyUCI,independentSharedHARQ,forgetCSIProducer,unconsumedULCommand,pucchOnlyCompletion,expectedULPorts,separatePUCCH,withPacketAccounting,withReceivedCSIContinuation,withReceivedSRSContinuation,withRankTransitions,withPreparedCSIAcquisitionLoss,withMissingSelectedSSBReference,withDAIMonitorOmission,withSelectedPUSCHRecovery)
% Actual shared SRS -> received UL DCI -> coded PUSCH with HARQ-ACK UCI.
% Initial TAG remains an explicit component input. In a configured-Es/N0
% fixture, geometry/pathloss are deliberately not applicable. The two UCI bits
% use isolated coded DL receptions in legacy modes. independentSharedHARQ
% instead produces its feedback through this same shared CDL owner.
% One grant does not qualify access or adaptation.
if nargin>=1 && string(mode)=="integration_hooks"
    % Test-only entry points reuse the existing actual receiver assertions.
    % The caller owns its scenario, calendar and declared component boundary.
    ok=true;
    state=struct('CompleteEvents',@localCompleteEvents, ...
        'DeliverReceivedSIB1',@localDeliverReceivedSIB1, ...
        'DeliverReferences',@localDeliverContinuationReferences, ...
        'QueueTRS',@localQueueContinuationTRS, ...
        'QueueSRS',@localQueueSRS, ...
        'AssertSRSGrant',@localAssertSRSContinuationGrant, ...
        'VerifySRSEmission',@localVerifySRSApplicationEmission, ...
        'DrainData',@localDrainContinuationData, ...
        'ControlLog',@localContinuationControlLog, ...
        'QueueCSIGrant',@localQueueCSIApplicationGrant, ...
        'CompleteCSIControl',@localCompleteCSIApplicationControl, ...
        'CompleteCSIData',@localCompleteCSIApplicationPDSCH, ...
        'CompletedPlan',@localContinuationCompletedPlan, ...
        'AssertReceiverPublication',@localAssertContinuationReceiverPublication, ...
        'AssertDLSCHOutcome',@localAssertSharedDLSCHOutcome, ...
        'VerifyMatrices',@localVerifyCSIApplicationMatrices, ...
        'AssertCFO',@localAssertReceiverCFOEvidence, ...
        'CurrentCSIReport',@localCurrentContinuationReport, ...
        'AssertCSICapsule',@localAssertContinuationCapsule, ...
        'SaveScenario',@localSaveScenarioEvidence);
    return;
end
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
if nargin<18, withReceivedCSIContinuation=false; end
if nargin<19, withReceivedSRSContinuation=false; end
if nargin<20, withRankTransitions=false; end
if nargin<21, withPreparedCSIAcquisitionLoss=false; end
if nargin<22, withMissingSelectedSSBReference=false; end
if nargin<23, withDAIMonitorOmission=false; end
if nargin<24, withSelectedPUSCHRecovery=false; end
assert(islogical(withSelectedPUSCHRecovery)&&isscalar(withSelectedPUSCHRecovery));
assert(~withSelectedPUSCHRecovery || (withMissingSelectedSSBReference && ~withDAIMonitorOmission));
assert(islogical(withDAIMonitorOmission) && isscalar(withDAIMonitorOmission));
assert(~withDAIMonitorOmission || (independentSharedHARQ && withCSI && ...
    ~pucchOnlyCompletion && ~forgetCSIProducer && ~unconsumedULCommand && ...
    ~separatePUCCH && ~withPacketAccounting && ~withPreparedCSIAcquisitionLoss));
assert(islogical(withMissingSelectedSSBReference) && isscalar(withMissingSelectedSSBReference));
assert(~withMissingSelectedSSBReference || (pucchOnlyCompletion && ~withHARQ && ...
    ~withReceivedCSIContinuation && ~withReceivedSRSContinuation && ~withPreparedCSIAcquisitionLoss));
assert(islogical(withPreparedCSIAcquisitionLoss) && isscalar(withPreparedCSIAcquisitionLoss));
assert(~withPreparedCSIAcquisitionLoss || (independentSharedHARQ && withCSI && ...
    ~forgetCSIProducer && ~unconsumedULCommand && ~pucchOnlyCompletion && ...
    ~withReceivedCSIContinuation && ~withReceivedSRSContinuation));
assert(islogical(withRankTransitions) && isscalar(withRankTransitions));
assert(islogical(withReceivedCSIContinuation) && isscalar(withReceivedCSIContinuation));
assert(islogical(withReceivedSRSContinuation) && isscalar(withReceivedSRSContinuation));
assert(~(withReceivedCSIContinuation && withReceivedSRSContinuation));
withReferenceContinuation=withReceivedCSIContinuation || withReceivedSRSContinuation;
assert(~withRankTransitions || (withReferenceContinuation && expectedULPorts==4));
assert(~withReceivedCSIContinuation || (pucchOnlyCompletion && ~withPacketAccounting));
assert(~withReceivedSRSContinuation || (pucchOnlyCompletion && ~withPacketAccounting));
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
retainedPower=sixgr.phy.refsig.pathlossReferenceLifetime(cfg)=="retained_filtered_reference";
assert(~withMissingSelectedSSBReference || retainedPower);
assert(~retainedPower || (pucchOnlyCompletion && ~withReferenceContinuation && ...
    ~sixgr.rf.isNormalizedFixedSNRPowerReference(cfg)), ...
    'test:RetainedPowerScope','Retained-power variant requires actual absolute-power combined PUCCH.');
if withReferenceContinuation
    % Mint and persist this component's real lifecycle before any physical
    % observation. Do not backfill identities into an old unbound capture.
    [~,componentTag]=fileparts(root);
    componentKind="received_csi_application_component_";
    if withReceivedSRSContinuation, componentKind="received_srs_application_component_"; end
    executionIdentity=sixgr.runtime.resolveExecutionIdentity(root, ...
        componentKind+string(componentTag),string(s.ConfigHash));
    cfg.run.rootRunFolder=root;
    cfg.run.runTag=char(executionIdentity.RunID);
    cfg.run.executionID=char(executionIdentity.ExecutionID);
    cfg.run.scenarioID=char(string(s.ScenarioID));
    cfg.meta.executionID=char(executionIdentity.ExecutionID);
    cfg.meta.configHash=char(executionIdentity.ConfigHash);
    cfg.meta.scenarioID=char(string(s.ScenarioID));
end
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
if (withCSI || withHARQ) && ~independentCompletion
    if withCSI
        localSaveScenarioEvidence(s,cfg,root, ...
            'component: actual shared SSB/MIB/SIB1 and CSI-RS; configured periodic CSI/HARQ-coded PUSCH with deferred receiver delivery; isolated coded DL HARQ donors; declared initial connected RA/TAG; not full access, RRC or integrated 12 dB qualification');
    else
        localSaveScenarioEvidence(s,cfg,root);
    end
end
if independentCompletion
    scope='component: actual shared SS/PBCH timing, SRS, UL DCI and PUSCH; independent UCI receive/commit; selected DL source explicitly retained; not full coordinator or 12 dB qualification';
    if unconsumedULCommand
        scope='component: actual shared DL DCI/PDSCH reception and PUCCH TX; gNB UL command transmitted but UE UL decoder deliberately unexecuted; scheduled PUSCH capture; NOT physical missed-DCI probability or full coordinator qualification';
    end
    if pucchOnlyCompletion
        scope='component: actual shared DL reception and combined HARQ/CSI/SR PUCCH; independent gNB layout and common completion; no scheduled UL command; not 12 dB or missing-DCI-rate qualification';
    end
    if withReceivedCSIContinuation
        scope=[scope '; optional later PF-scheduled PDCCH/PDSCH after real PBCH/SRS/TRS gate delivery; declared initial TAG; installed absent-TCI CORESET Type-A association; not full access, n40, RR, or statistical qualification'];
    end
    if withReceivedSRSContinuation
        scope=[scope '; optional accepted-SRS normal future-UL planner, canonical received PDCCH and deferred PUSCH completion; declared initial TAG; not full access, n40, all-rank or natural HARQ-retry qualification'];
    end
    if withRankTransitions
        scope=[scope '; finite sustained four-port channel-stimulus component; initial TAG equals configured duration, never refreshed; observed rank coverage only, no natural-retry or random-access qualification'];
    end
    if withCSI
        scope=[scope '; actual full SSB/MIB/SIB1 receiver and causal measurement installation; initial RA/TAG remains declared, no full RRC/RA qualification'];
    end
    if withMissingSelectedSSBReference
        scope=[scope '; original unmeasured selected SSB-1 withholds slot-10 PUCCH while the real receiver runs; later original SSB-1 reception admits a distinct slot-15 CSI/SR obligation retaining source-6 CSI; no new CSI measurement or second full-SI decode claim'];
    end
    localSaveScenarioEvidence(s,cfg,root, ...
        scope);
end
% This component bypasses runSingle, which normally initializes the run
% RNG. Bind the UE drop to the resolved YAML seed, not the preceding test.
priorRNG=rng;
rngCleanup=onCleanup(@()rng(priorRNG)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
multi=sixgr.truth.resolveMultiUserSpec(cfg);
assert(multi.Enabled && multi.NumUsers==1 && multi.RNTIStart==1 && ...
    multi.ExecutionModel=="slot_coupled_truth" && ...
    multi.BeamSelectionStrategy~="missing_from_config", ...
    'The component must retain the complete resolved user policy, not a test-authored subset.');
lastSlot=11+10*logical(withHARQ);
if withMissingSelectedSSBReference
    % The second real burst and following configured report remain inside
    % the original declared 20-ms TAG. No timer refresh or clock jump.
    reference=sixgr.phy.refsig.resolveConfiguredPathlossReference(cfg,"PUCCH");
    assert(reference.ReferenceSignalId==1 && cfg.phy.ssb.period_slots==10 && ...
        cfg.phy.csi.reportPeriodicitySlots==5 && cfg.phy.carrier.SubcarrierSpacing==15);
    recoveryBurstSlot=1+cfg.phy.ssb.period_slots;
    recoveryReportSlot=10+cfg.phy.csi.reportPeriodicitySlots;
    lastSlot=recoveryReportSlot+1;
end
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),lastSlot);
if ~independentCompletion
    % The legacy transport component advances the shared samples directly,
    % but periodic reporting still requires the normal initial calendar
    % binding. Bind the actual configured component horizon before any
    % physical owner, received observation or pending feedback exists.
    assert(isempty(sixgr.util.structGet(state,'SharedWaveformStream',[])) && ...
        isempty(state.PendingFeedbackTable) && isempty(state.PendingCSITable));
    originalControl=state.ControlTrials;
    originalLatestDL=state.LatestDLFeedback; originalLatestUL=state.LatestULFeedback;
    originalDLHARQ=state.DLHarq.Stats; originalULHARQ=state.ULHarq.Stats;
    originalRNG=rng;
    state=sixgr.truth.CoupledTruthRuntime.beginSlot( ...
        state,cfg,cfg,1,'UL',1,1,1,lastSlot,cfg.channel.snr_dB);
    assert(state.CurrentSlot==1 && state.CurrentCanonicalSlot==1 && ...
        state.SweepPointStartSlot==1 && state.CanonicalSlotsPerSweepPoint==lastSlot && ...
        state.CompletedCanonicalSlots==0 && ...
        isempty(sixgr.util.structGet(state,'SharedWaveformStream',[])) && ...
        isempty(state.PendingFeedbackTable) && isempty(state.PendingCSITable) && ...
        isequaln(state.ControlTrials,originalControl) && ...
        isequaln(state.LatestDLFeedback,originalLatestDL) && ...
        isequaln(state.LatestULFeedback,originalLatestUL) && ...
        isequaln(state.DLHarq.Stats,originalDLHARQ) && ...
        isequaln(state.ULHarq.Stats,originalULHARQ) && isequal(rng,originalRNG), ...
        'test:SharedFixtureInitialCalendar', ...
        'Initial calendar binding must not advance PHY, invent feedback or alter receiver evidence.');
end
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
state.TestDAIMonitorOmission=withDAIMonitorOmission;
state.TestSelectedPUSCHRecovery=withSelectedPUSCHRecovery;
state.TestSharedDLControlByGrant=struct();
state.TestForgetCSIProducer=logical(forgetCSIProducer);
state.TestUnconsumedULCommand=logical(unconsumedULCommand);
state.TestPUCCHOnlyCompletion=logical(pucchOnlyCompletion);
state.TestSeparatePUCCH=logical(separatePUCCH);
state.TestReceivedCSIContinuation=withReceivedCSIContinuation;
state.TestReceivedSRSContinuation=withReceivedSRSContinuation;
state.TestReferenceContinuation=withReferenceContinuation;
state.TestRankTransitions=withRankTransitions;
state.TestPreparedCSIAcquisitionLoss=withPreparedCSIAcquisitionLoss;
state.TestRetainedPower=retainedPower;
state.TestMissingSelectedSSBReference=withMissingSelectedSSBReference;
if withMissingSelectedSSBReference
    state.TestSSBRecoveryBurstSlot=recoveryBurstSlot;
    state.TestSSBRecoveryReportSlot=recoveryReportSlot;
end
% CSI installation must consume received SI, not the codec-only common
% configuration used below for this component's declared initial TAG.
state.TestReceiveSIB1=withCSI && logical(state.ControlGating.PBCHRequired);
if withRankTransitions
    state.TestRankTransitionApplications=cell(0,1);
    state.TestRankTransitionAttemptOrdinal=0;
    state.TestRankTransitionTermination="configured_horizon";
    state.TestRankTransitionLastSourceSlot=-Inf;
    state.TestRankTransitionTRSSlots=zeros(0,1);
    state.TestRankTransitionCSIRSSlots=zeros(0,1);
    state.TestPeriodicCSIRefreshSnapshots=cell(0,1);
end
if withReferenceContinuation
    % This optional test uses the resolved YAML scheduler and all of its
    % original gates; no authored replacement later grant or access bypass.
    if withReceivedCSIContinuation, assert(isa(state.DLSchedulers{1},'sixgr.l2.mac.SchedulerPF')); end
    state.TestContinuationReferences=cell(0,1);
    state.TestContinuationTRSQueued=false;
    state.TestContinuationQueuedSRSSlots=zeros(0,1);
    state.TestContinuationCompleted=false;
    state.TestContinuationRejected=false;
    state.TestExecutionIdentity=executionIdentity;
end
if withReceivedSRSContinuation
    state.TestSRSContinuationStarted=false;
    state.TestSRSContinuationCompleted=false;
end
if separatePUCCH
    assert(isequal(double(cfg.phy.pusch.symbolAllocation),[0 11]), ...
        'The separate-transport fixture must use the retained H4 11-symbol allocation.');
end
% One ledger owns every actual prefix and later control issuance. Never
% copy/reset DAI when the optional normal-scheduler continuation starts.
state.ScheduledDLDAILedger=struct();
if independentCompletion, assert(logical(cfg.phy.csi.reportCSI)==logical(withCSI)); end
if withCSI
    assert(~cfg.run.controlGating.prachRequired && ...
        state.AccessState(1)=="not_required", ...
        'test:SharedCSIAccessScope', ...
        'The CSI component installs connected RA/TAG explicitly; it does not execute or qualify random access.');
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
    if state.TestReceiveSIB1
        firstCSI=lateCSIProducerSlot;
        if independentSharedHARQ, firstCSI=6; end
        capture=prototype.PreparedBroadcast;
        boundary=sixgr.phy.frame.slotStartSample( ...
            sixgr.phy.grid.makeCarrier(dl),firstCSI-1,owner.SampleRateHz);
        assert(capture.NumSamples<=boundary, ...
            'test:SharedSIB1BeforeCSIFixture', ...
            ['Original full broadcast ends at %.0f but configured CSI starts at %.0f; ' ...
             'retain this failure rather than truncate SI or backdate installation.'],capture.NumSamples,boundary);
        fprintf('SHARED_SIB1_CAPTURE_PLAN samples=%d Fs=%g SI_slots0=%s first_CSI_slot=%d extra_TX=0\n', ...
            capture.NumSamples,capture.SampleRateHz,mat2str([capture.Tx.SIB1Transmissions.SIB1AbsoluteSlot]),firstCSI);
    end
    owner.queueDownlink('PBCH',1,prototype.PreparedBroadcast, ...
        struct('Config',dl,'Slot',1,'ServingCell',1,'TrackingOnly',true,'Prototype',prototype));
end
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',0);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
tagExpiry=round(.02*fs);
if withRankTransitions
    % A NEW declared component input, installed once before any TX; not a
    % received RAR or a refresh of the old twenty-millisecond fixture.
    tagExpiry=sixgr.phy.frame.slotStartSample(carrier,cfg.run.totalSlots,fs);
    state.TestRankTransitionInitialTAGExpiry=tagExpiry;
end
state.ConnectedULTimingByUE={struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',tagExpiry)};
if retainedPower
    % This component does not execute RA. Install its declared TAG only
    % after the actual SIB1 common BWP exists; no codec-only power source.
    state.TestDeclaredTAG=state.ConnectedULTimingByUE{1};
    state.ConnectedULTimingByUE={[]};
end
if ~retainedPower
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
end
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
    if state.TestReceiveSIB1
        state=localDeliverReceivedSIB1(state,cfg);
    end
    if withMissingSelectedSSBReference
        state=sixgr.truth.SSBOccasionResultDelivery.deliver(state);
        if slot==state.TestSSBRecoveryBurstSlot
            state=localQueueRecoverySSB(state,cfg,slot);
        end
    end
    if withReferenceContinuation
        state=localDeliverContinuationReferences(state);
        state=localQueueContinuationTRS(state,cfg,slot);
    end
    if withSelectedPUSCHRecovery && slot==8
        % Authored SRS special-slot9/symbol13 follows actual SI installation.
        % It does not overlap the original withheld slot10 PUCCH capture.
        assert(state.TestActualSIB1DeliveredSlot==6 && ...
            state.TestReceivedDLClock.AvailableAtSample<=owner.Events.NextSampleIndex);
        localQueueSRS(state,cfg,slot+1);
    end
    if acquireDLClock && slot==4 && ~retainedPower
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
    if independentSharedHARQ && (slot==6 || (withDAIMonitorOmission && slot==7))
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
    recoveryControl=withSelectedPUSCHRecovery && slot==state.TestSSBRecoveryReportSlot-1;
    if ((slot==9 || (withHARQ && slot==19)) && ~pucchOnlyCompletion) || recoveryControl
        assert(isfield(state,'TestSRS') && state.TestSRS.AvailableAtSample<=owner.Events.NextSampleIndex);
        if recoveryControl
            assert(state.TestSRS.Slot==9);
            state.TestRecoveryGrantOriginalSRS=state.TestSRS;
        end
        if independentCompletion && withCSI
            reports=state.PendingCSITable;
            due=10; reference=6;
            if recoveryControl
                due=state.TestSSBRecoveryReportSlot;
                reference=sixgr.truth.periodicCSIReferenceSlot(cfg,due);
                reports=reports(reports.DueSlot==due & string(reports.Direction)=="DL",:);
                assert(state.TestWithheldPUCCH.ReceiverCompleted && state.TestSharedCSIReceived);
                assert(reports.ReportIdentity~=state.TestWithheldPUCCH.OriginalReport.ReportIdentity);
                state.TestRecoveryPUSCHOriginalReport=reports;
            end
            assert(height(reports)==1 && reports.SourceSlot==6 && reports.CSIReferenceSlot==reference && ...
                reports.DueSlot==due && ~reports.Processed && state.TestSharedCSIReceived);
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
            grant=sixgr.truth.prepareScheduledULDAI(state.ScheduledDLDAILedger,ul,grant);
            expectedAssignments=double(independentSharedHARQ)+double(withDAIMonitorOmission);
            if recoveryControl,expectedAssignments=0;end
            assert(grant.ULTotalDAIAuthority.ScheduledDLAssignmentCount==expectedAssignments);
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
            soundingContext=struct('Config',sounding,'Arguments',{soundingArgs}, ...
                'ServingCell',double(state.CurrentServingIdx(1)));
            % Freeze the original preparation's serving link before enqueue;
            % completion must never substitute the then-current association.
            preparedContext=soundingTX.PreparedTransmission.ReceiverConfig.lls6g.userContext;
            assert(soundingContext.ServingCell==sounding.lls6g.userContext.RuntimeServingCell && ...
                soundingContext.ServingCell==preparedContext.RuntimeServingCell && ...
                sounding.lls6g.userContext.RuntimeUEIndex==1 && preparedContext.RuntimeUEIndex==1, ...
                'test:SharedSRSFrozenServingCell', ...
                'Queued coincident SRS must retain the actual UE/serving-cell preparation identity.');
            pendingBefore=owner.Pending;
            dataBefore=owner.DataTransmissions;
            pucchBefore=owner.PUCCHTransmissions;
            suppressionBefore=owner.SRSSuppressionLedger;
            sampleBefore=owner.Events.NextSampleIndex;
            traceBefore=owner.Events.ExecutionTrace;
            stop=soundingTX.PreparedTransmission.ReceiveEndSampleExclusive;
            nextBefore=owner.Events.nextEventSample(stop);
            rngBefore=rng;
            missing=soundingContext; missing=rmfield(missing,'ServingCell');
            wrong=soundingContext; wrong.ServingCell=soundingContext.ServingCell+1;
            nonfinite=soundingContext; nonfinite.ServingCell=NaN;
            for invalid={missing,wrong,nonfinite}
                localReject(@()owner.queueUplinkControl(1,soundingTX.PreparedTransmission,invalid{1}), ...
                    'sixgr:truth:SharedSRSCellContext');
                assert(isequaln(owner.Pending,pendingBefore)&& ...
                    isequaln(owner.DataTransmissions,dataBefore)&& ...
                    isequaln(owner.PUCCHTransmissions,pucchBefore)&& ...
                    isequaln(owner.SRSSuppressionLedger,suppressionBefore)&& ...
                    owner.Events.NextSampleIndex==sampleBefore&& ...
                    isequaln(owner.Events.ExecutionTrace,traceBefore)&& ...
                    owner.Events.nextEventSample(stop)==nextBefore&&isequal(rng,rngBefore), ...
                    'test:SharedSRSCellContextMutation', ...
                    'Rejected SRS contexts must leave original public queue/clock/ledger/event state unchanged.');
            end
            fprintf('SHARED_SRS_CELL_CONTEXT_GUARD_PASS cases=3 enqueued=0 samples_executed=0\n');
            owner.queueUplinkControl(1,soundingTX.PreparedTransmission,soundingContext);
        end
        allocation=state.ULHarq.allocate(grant.RNTI,slot,grant.TBSBytes,'NewData',true);
        assert(isequaln(allocation.HARQ.HarqID,grant.HARQ.HarqID) && ...
            allocation.HARQ.NDI==grant.HARQ.NDI && allocation.HARQ.RV==grant.HARQ.RV);
        if slot==9 || recoveryControl
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
        controlID=owner.queuePDCCH(1,p,controlContext);
    if withSelectedPUSCHRecovery && recoveryControl
        % Original accepted control contribution, not inferred execution.
        assert(slot==14 && p.RuntimeStartSample>=state.TestRecoveryBroadcast.StartSample);
        state.TestRecoveryPDCCHComponent=struct('ComponentID',string(controlID), ...
            'OriginalSampleSHA256',sixgr.phy.waveform.WaveformHash.numeric(p.TransmitSamples), ...
            'StartSample',p.RuntimeStartSample,'EndSampleExclusive',p.RuntimeStartSample+size(p.TransmitSamples,1), ...
            'TransmitterID',"gnb_"+string(grant.ServingCell),'ControlSlot',slot, ...
            'PhysicalExecutionClaimed',false);
        registration=state.TestRecoveryPDCCHComponent;
        save(fullfile(state.TestRoot,'recovery_original_pdcch_registration.mat'),'registration');
    end
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
    if withMissingSelectedSSBReference
        if withSelectedPUSCHRecovery
            state=localVerifySelectedPUSCHRecovery(state);
        else
            state=localVerifyWithheldPUCCHRecovery(state);
        end
        ok=true; return;
    end
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
    if withReceivedCSIContinuation
        state=localContinueReceivedCSIToPDSCH(state,cfg,report,lastSlot);
    end
    if withReceivedSRSContinuation
        state=localContinueReceivedSRSToPUSCH(state,cfg,lastSlot);
    end
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
assert(numel(owner.DataTransmissions)==attempts+logical(withCSI && ~independentCompletion)+logical(independentSharedHARQ)+double(withDAIMonitorOmission) && ~owner.hasPending('PUSCH',1));
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
if independentSharedHARQ && ~separatePUCCH && ~withDAIMonitorOmission
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
if withDAIMonitorOmission
    assert(state.TestOmittedControl.Grant.Slot==7 && state.TestOmittedDataCaptured);
    assert(numel(state.SharedUEHARQACKEvents)==1 && state.DLHarq.Stats.Tx==2);
    assert(height(state.SharedGNBUCIHARQTable)==2 && numel(state.SharedPUSCHHARQFeedbackReceipts)==1);
    feedback=state.SharedGNBUCIHARQTable;
    assert(isequal(sort(feedback.SourceSlot),[6;7]) && all(feedback.ReceiverUsable));
    omitted=feedback(feedback.SourceSlot==7,:);
    assert(height(omitted)==1 && ~omitted.ObservedAck && omitted.HARQFeedbackApplied);
    assert(height(state.SharedPUSCHHARQDecisionAuditTable)==1 && ...
        state.SharedPUSCHHARQDecisionAuditTable.ReceiverUsable);
    assert(state.DLHarq.Stats.Ack==double(state.TestExpectedSharedACK) && ...
        state.DLHarq.Stats.Nack==1+double(~state.TestExpectedSharedACK));
    assert(state.TestSharedCSIReceived && height(state.SharedGNBCSIReportTable)==1);
    assert(~any(cellfun(@(x)x.Grant.Slot==7,state.SharedReceivedGrantControls)));
    assert(all(state.PendingFeedbackTable.Processed) && state.PendingFeedbackTable.SourceSlot==6);
    receipt=struct('Scope',"actual_shared_waveforms_declared_UE_monitor_omission", ...
        'ScheduledDLAssignments',2,'UEAdmittedAssignments',1,'ActualPUSCHHARQBits',2, ...
        'RFDecoderMissClaimed',false,'OriginalCSIProducerSlot',6,'OnceOnlyFeedbackReceipts',1);
    sixgr.util.jsonWrite(fullfile(root,'shared_dai_monitor_omission.json'),receipt);
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

function before=localWithheldPreparationSnapshot(state,item,cfg,decision)
owner=state.SharedWaveformStream;
id=string(item.Context.ObservationID);
hit=find(string({owner.Pending.ID})==id); assert(isscalar(hit));
trace=state.PUCCHGrantTraceTable;
rows=trace(trace.UEIndex==item.UE & trace.ScheduledAbsoluteSlot==item.Context.Slot,:);
rows=rows(sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey(rows)==item.Context.Key,:);
assert(height(rows)==2 && any(contains(lower(string(rows.UCIType)),"harq")) && ...
    any(startsWith(string(rows.PUCCHGrantId),"PUCCH-CSI-")));
reports=state.PendingCSITable;
report=reports(reports.UEIndex==item.UE & reports.DueSlot==item.Context.Slot,:);
assert(height(report)==1 && ~report.Processed && report.SourceSlot==6 && ...
    report.CSIReferenceSlot==6 && report.MeasurementAvailableAtSample<=owner.Events.NextSampleIndex);
before=struct('Observation',owner.Pending(hit),'Rows',rows,'Report',report, ...
    'Feedback',state.PendingFeedbackTable,'Trace',trace,'Trials',state.ControlTrials.PUCCH, ...
    'LatestDL',state.LatestDLFeedback,'HARQ',state.DLHarq.Stats, ...
    'MeasurementTable',state.ReferenceSignalMeasurementTable, ...
    'Common',state.UECommonCellConfigurationByUE{item.UE}, ...
    'Lifecycle',state.SSBPowerReferenceLifecycleByUE{item.UE}, ...
    'Sample',owner.Events.NextSampleIndex,'RNG',rng, ...
    'PUCCHTransmissionCount',numel(owner.PUCCHTransmissions));
assert(before.PUCCHTransmissionCount==0 && ...
    isempty(sixgr.truth.scheduledHARQExpectationsForOccasion(state,item.UE,15)) && ...
    cfg.lls6g.userContext.RuntimeServingCell==state.CurrentServingIdx(item.UE) && ...
    ~decision.PreparationAdmitted);
end

function state=localCheckWithheldPreparation(state,item,cfg,decision,before)
owner=state.SharedWaveformStream; id=string(item.Context.ObservationID);
hit=find(string({owner.Pending.ID})==id); assert(isscalar(hit));
bound=owner.Pending(hit); audit=state.SharedPUCCHPowerAdmissionTable;
audit=audit(string(audit.ObservationID)==id,:);
assert(height(audit)==1 && bound.Kind=="PUCCHReceiveOnly" && ...
    ~isfield(bound.Context,'Prepared') && ~bound.Context.AwaitingPreparation && ...
    ~isempty(bound.Context.GNBReception.Mapping) && ...
    isequaln(bound.Planes,before.Observation.Planes) && ...
    numel(owner.PUCCHTransmissions)==before.PUCCHTransmissionCount && ...
    owner.Events.NextSampleIndex==before.Sample && isequal(rng,before.RNG) && ...
    isequaln(state.DLHarq.Stats,before.HARQ) && ...
    isequaln(state.ControlTrials.PUCCH,before.Trials) && ...
    isequaln(state.LatestDLFeedback,before.LatestDL) && ...
    isequaln(state.ReferenceSignalMeasurementTable,before.MeasurementTable));
ids=string(before.Rows.PUCCHGrantId);
trace=state.PUCCHGrantTraceTable;
trace=trace(ismember(string(trace.PUCCHGrantId),ids),:);
disposition="closed_untransmitted_missing_measured_power_reference";
assert(height(trace)==2 && all(trace.UETransmissionSuppressed) && ...
    all(~trace.GrantExecutedFlag & ~trace.MultiplexedOnPUSCH) && ...
    all(string(trace.UEProducerDisposition)==disposition) && ...
    all(string(trace.PowerAdmissionObservationID)==id));
feedback=state.PendingFeedbackTable;
assert(height(feedback)==1 && feedback.Processed && ...
    feedback.Ack==before.Feedback.Ack && string(feedback.UEProducerDisposition)==disposition);
report=state.PendingCSITable;
report=report(string(report.ReportIdentity)==string(before.Report.ReportIdentity),:);
assert(height(report)==1 && report.Processed && ~report.UECSIPayloadRetired && ...
    string(report.UEProducerDisposition)==disposition && ...
    string(report.DeliveryStatus)=="not_transmitted_missing_measured_power_reference" && ...
    ~report.CSIUCIDecodeOk && isnan(report.DeliveredSlot) && ...
    isequaln(report.CSIPart1BitsToken,before.Report.CSIPart1BitsToken) && ...
    isequaln(report.CSIPart2BitsToken,before.Report.CSIPart2BitsToken));
unresolved=sixgr.truth.classifyPUCCHGrantDisposition(trace,table());
assert(unresolved.UnresolvedCount==2 && unresolved.ReceiverOnlyObservedCount==0);
pending=owner.Pending; random=rng;
localReject(@()sixgr.truth.CoupledTruthRuntime.deferSharedPUCCHPowerRuntime( ...
    state,item,cfg,bound.Context.GNBReception,before.Rows,decision), ...
    'sixgr:truth:PUCCHPowerAdmissionBinding');
assert(isequaln(owner.Pending,pending) && isequal(rng,random) && ...
    owner.Events.NextSampleIndex==before.Sample && isequaln(state.DLHarq.Stats,before.HARQ));
state.TestWithheldPUCCH=struct('ObservationID',id,'Key',string(item.Context.Key), ...
    'Admission',audit,'OriginalReport',before.Report,'OriginalFeedback',before.Feedback, ...
    'OriginalGrantIDs',ids,'PreparedDisposition',trace,'HARQBefore',before.HARQ, ...
    'Common',before.Common,'Lifecycle',before.Lifecycle,'ReceiverCompleted',false, ...
    'SourceCSI',state.ControlTrials.CSIRS,'DecisionSample',before.Sample);
receipt=state.TestWithheldPUCCH;
save(fullfile(state.TestRoot,'withheld_preparation_original.mat'),'receipt','-v7.3');
sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(state,state.TestRoot);
fprintf('PUCCH_WITHHELD_PREPARATION_PASS slot=10 actual_DL_HARQ=1 actual_CSI=1 TX=0 receiver_not_yet_complete=1 expiry_once=1\n');
end

function state=localCompleteWithheldPUCCH(state,item)
owner=state.SharedWaveformStream; original=state.TestWithheldPUCCH;
assert(~original.ReceiverCompleted && string(item.Context.ObservationID)==original.ObservationID && ...
    string(item.Context.Key)==original.Key && ~isfield(item.Context,'Prepared') && ...
    ~isempty(item.Context.GNBReception.Mapping) && isempty(owner.PUCCHTransmissions));
beforeHARQ=state.DLHarq.Stats;
assert(isequaln(beforeHARQ,original.HARQBefore));
state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,item);
receipts=state.SharedGNBUCIReceptions;
hit=find(cellfun(@(r)string(r.ObservationID)==original.ObservationID,receipts));
assert(isscalar(hit)); reception=receipts{hit}; rx=reception.Receiver;
trial=state.ControlTrials.PUCCH;
trial=trial(string(trial.PowerAdmissionObservationID)==original.ObservationID,:);
harq=state.SharedGNBUCIHARQTable;
harq=harq(string(harq.ObservationID)==original.ObservationID,:);
assert(height(trial)==1 && trial.ReceiverOnlyAssignment==1 && trial.PUCCHTransmissionPrepared==0 && ...
    trial.ExecutionBackend=="pucch_shared_gnb_receive_only" && ...
    trial.DTXFlag==rx.DTX && trial.ReceiverUsable==rx.ReceiverUsable && ...
    height(harq)==1 && harq.HARQFeedbackApplied && ~harq.StaleFeedbackIgnored && ...
    numel(state.SharedHARQFeedbackCommittedMappings)==1 && ...
    nnz(state.SharedPUCCHRXCommittedIDs==original.Key)==1 && isempty(owner.PUCCHTransmissions));
% Expected state is computed from the actual normalized receiver decision,
% not the missing transmitter. A noise false detection remains evidence.
outcome=string(harq.FeedbackOutcome);
assert(state.DLHarq.Stats.Ack-beforeHARQ.Ack==double(outcome=="ACK") && ...
    state.DLHarq.Stats.Nack-beforeHARQ.Nack==double(outcome=="NACK") && ...
    state.DLHarq.Stats.Dtx-beforeHARQ.Dtx==double(outcome=="DTX"));
trace=state.PUCCHGrantTraceTable;
trace=trace(ismember(string(trace.PUCCHGrantId),original.OriginalGrantIDs),:);
classified=sixgr.truth.classifyPUCCHGrantDisposition(trace,trial);
% Preserve the original live producer/consumer contract BEFORE acceptance.
% A later writer must not be needed to make an actual completed RX visible.
admission=original.Admission;
receiverOutcome=struct('DTX',rx.DTX,'ReceiverUsable',rx.ReceiverUsable, ...
    'CRCPassed',rx.CRCPassed,'DecodedFields',rx.DecodedFields);
diagnosticPath=fullfile(state.TestRoot,'withheld_receiver_disposition_original.mat');
save(diagnosticPath,'trace','trial','classified','harq','admission','receiverOutcome','-v7.3');
sixgr.util.csvWriteTable(fullfile(state.TestRoot,'withheld_receiver_disposition.csv'), ...
    classified.Rows,'PreserveSchema',true);
identityFields=["PUCCHGrantId","LogicalPUCCHGrantIdSet","PowerAdmissionObservationID", ...
    "UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier","ActiveULBWP", ...
    "SweepPointIndex","RunUUID","ConfigHash","FinalizedFlag","ControlObservationAvailable"];
grantIdentity=trace(:,cellstr(identityFields(ismember(identityFields,string(trace.Properties.VariableNames)))));
receiverIdentity=trial(:,cellstr(identityFields(ismember(identityFields,string(trial.Properties.VariableNames)))));
assert(classified.ReceiverOnlyObservedCount==2 && classified.UnresolvedCount==0 && ...
    classified.StandaloneTrialCount==0 && ~any(trace.GrantExecutedFlag), ...
    'test:WithheldPUCCHDisposition', ...
    ['Actual no-TX RX disposition mismatch: observed=%d unresolved=%d transmittedSuccess=%d. ' ...
     'Original grants=%s; actual receiver=%s. Inputs/result retained at %s.'], ...
    classified.ReceiverOnlyObservedCount,classified.UnresolvedCount,classified.StandaloneTrialCount, ...
    jsonencode(table2struct(grantIdentity)),jsonencode(table2struct(receiverIdentity)),diagnosticPath);
assert(islogical(trial.FinalizedFlag) && trial.FinalizedFlag && ...
    islogical(trial.ControlObservationAvailable) && trial.ControlObservationAvailable, ...
    'The actual completion owner must publish typed availability/finalization before export.');
committed=state.SharedHARQFeedbackCommittedMappings; trials=state.ControlTrials.PUCCH;
afterHARQ=state.DLHarq.Stats; random=rng;
localReject(@()sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,item), ...
    'sixgr:truth:InvalidPUCCHReceiveOnlyCompletion');
assert(isequaln(state.DLHarq.Stats,afterHARQ) && isequaln(state.ControlTrials.PUCCH,trials) && ...
    isequaln(state.SharedHARQFeedbackCommittedMappings,committed) && isequal(rng,random));
original.ReceiverCompleted=true;
original.ReceiverAvailableAtSample=owner.Events.NextSampleIndex;
original.ReceiverTrial=trial; original.HARQOutcome=harq;
original.HARQAfter=afterHARQ; original.FinalTrace=trace;
original.FinalReport=state.PendingCSITable( ...
    string(state.PendingCSITable.ReportIdentity)==string(original.OriginalReport.ReportIdentity),:);
assert(height(original.FinalReport)==1 && original.FinalReport.Processed && ...
    original.FinalReport.UEProducerDisposition=="closed_untransmitted_missing_measured_power_reference");
state.TestWithheldPUCCH=original;
save(fullfile(state.TestRoot,'withheld_receiver_terminal.mat'), ...
    'item','reception','original','classified','-v7.3');
sixgr.util.csvWriteTable(fullfile(state.TestRoot,'withheld_receiver_terminal.csv'),trial,'PreserveSchema',true);
fprintf('PUCCH_WITHHELD_RECEIVER_PASS slot=10 actual_RX=1 TX=0 DTX=%d outcome=%s HARQ_commits=1 duplicate_rejected=1\n', ...
    rx.DTX,outcome);
end

function state=localQueueRecoverySSB(state,cfg,slot)
owner=state.SharedWaveformStream; carrier=sixgr.phy.grid.makeCarrier(cfg);
assert(isfield(state,'TestWithheldPUCCH') && slot==state.TestSSBRecoveryBurstSlot && ...
    mod(slot-1,carrier.SlotsPerFrame)==0 && sixgr.truth.isActiveSSBOccasion(cfg,slot));
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',slot-1);
assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
p=prototype.PreparedBroadcast;
first=sixgr.phy.frame.slotStartSample(carrier,slot-1,owner.SampleRateHz);
assert(p.BroadcastStartSample==first && p.BroadcastStartAbsoluteSlot==slot-1 && ...
    first==owner.Events.NextSampleIndex);
beforeIDs=string({owner.Pending.ID});
firstExecutionSegment=numel(owner.Events.ExecutionTrace)+1;
owner.queueDownlink('PBCH',1,p,struct('Config',dl,'Slot',slot,'ServingCell',1, ...
    'TrackingOnly',true,'Prototype',prototype));
pending=owner.Pending;
added=pending(~ismember(string({pending.ID}),beforeIDs));
parents=added(string({added.Kind})=="PBCH");
parent=parents(arrayfun(@(x)x.Context.Slot==slot,parents));
assert(isscalar(parent) && numel(parents)==1 && ...
    isequaln(parent.Context.Prepared.TransmitSamples,p.TransmitSamples) && ...
    parent.Context.Prepared.BroadcastStartSample==first && ...
    owner.Events.NextSampleIndex==first && numel(owner.Events.ExecutionTrace)+1==firstExecutionSegment, ...
    'Queue one original parent observation without claiming physical execution.');
occasions=added(string({added.Kind})=="SSBOccasion");
assert(~isempty(occasions) && numel(added)==1+numel(occasions) && ...
    numel(unique(arrayfun(@(x)x.Context.SSBOccasionHorizon.SSBIndex,occasions)))==numel(occasions) && ...
    all(arrayfun(@(x)x.Context.BroadcastStartSample==first && ...
        isequaln(x.Context.Prepared.TransmitSamples,p.TransmitSamples),occasions)), ...
    'Per-SSB receive windows must retain the same original prepared broadcast.');
state.TestRecoveryBroadcast=struct('ObservationID',string(parent.ID),'Slot',slot, ...
    'StartSample',first,'EndSampleExclusive',first+p.NumSamples, ...
    'PreparedWaveformSHA256',sixgr.phy.waveform.WaveformHash.numeric(p.TransmitSamples), ...
    'RadioFrame',p.Config.phy.carrier.NFrame,'QueuedParentObservationsAdded',numel(parents), ...
    'QueuedSSBOccasionObservationsAdded',numel(occasions), ...
    'TransmitterID',"gnb_"+string(parent.Context.ServingCell), ...
    'FirstExecutionTraceIndex',firstExecutionSegment,'PhysicalExecutionVerified',false, ...
    'FullSIReceiverExecuted',false);
state.TestRecoveryBroadcastFullCaptureCompleted=false;
plan=state.TestRecoveryBroadcast;
save(fullfile(state.TestRoot,'recovery_broadcast_original_plan.mat'),'plan');
fprintf('PUCCH_RECOVERY_SSB_QUEUED slot=%d frame=%d start=%d end=%d parent_observations=1 physical_execution_verified=0\n', ...
    slot,plan.RadioFrame,first,plan.EndSampleExclusive);
end

function evidence=localRecoveryBroadcastExecution(state)
% Original successful physical intervals, not the private enqueue cache.
owner=state.SharedWaveformStream; plan=state.TestRecoveryBroadcast;
stop=min(plan.EndSampleExclusive,owner.Events.NextSampleIndex);
next=plan.StartSample; ids=strings(0,1); receipts=cell(0,1); nonzero=0;
% Preserve original successful composite evidence BEFORE any assertion.
trace=owner.Events.ExecutionTrace(plan.FirstExecutionTraceIndex:end);
originalIntervals=cellfun(@(x)struct('StartSample',x.StartSample, ...
    'EndSampleExclusive',x.EndSampleExclusive,'ExecutedContributors',x.Execution.ExecutedContributors), ...
    trace,'UniformOutput',false);
registration=sixgr.util.structGet(state,'TestRecoveryPDCCHComponent',struct());
save(fullfile(state.TestRoot,sprintf('recovery_original_contributors_through_%d.mat',stop)), ...
    'plan','registration','originalIntervals','-v7.3');
for k=plan.FirstExecutionTraceIndex:numel(owner.Events.ExecutionTrace)
    segment=owner.Events.ExecutionTrace{k};
    if segment.StartSample>=stop, break; end
    assert(segment.StartSample==next && segment.EndSampleExclusive<=stop);
    consumed=segment.Execution.ExecutedContributors;
    original=consumed(string({consumed.TransmitterID})==plan.TransmitterID);
    assert(isscalar(original) && original.Receipt.CompleteContributorList && ...
        original.Receipt.StartSample==segment.StartSample && ...
        original.Receipt.EndSampleExclusive==segment.EndSampleExclusive);
    components=original.Receipt.Components;
    isBroadcast=string({components.OriginalSampleSHA256})==plan.PreparedWaveformSHA256;
    assert(nnz(isBroadcast)==1, ...
        'Exactly one original gNB broadcast component must supply this executed recovery interval.');
    component=components(isBroadcast);
    assert(component.StartSample==segment.StartSample && ...
        component.EndSampleExclusive==segment.EndSampleExclusive);
    % A real UL DCI is transmitted by the SAME gNB during this long broadcast
    % buffer. Require its exact original registration, not a family whitelist.
    extra=components(~isBroadcast);expectedControl=false;
    if ~isempty(fieldnames(registration))
        lo=max(segment.StartSample,registration.StartSample);
        hi=min(segment.EndSampleExclusive,registration.EndSampleExclusive);
        expectedControl=hi>lo;
    end
    assert(numel(extra)==double(expectedControl), ...
        'test:RecoveryBroadcastContributorPopulation','Unexpected or missing original gNB contribution.');
    if expectedControl
        assert(registration.TransmitterID==plan.TransmitterID&& ...
            extra.ComponentID==registration.ComponentID&& ...
            extra.OriginalSampleSHA256==registration.OriginalSampleSHA256&& ...
            extra.StartSample==lo&&extra.EndSampleExclusive==hi, ...
            'test:RecoveryBroadcastControlIdentity','Original overlapping control identity/support changed.');
    end
    ids(end+1,1)=string(component.ComponentID); %#ok<AGROW>
    nonzero=nonzero+component.NonzeroSampleCount;
    receipts{end+1,1}=original; %#ok<AGROW>
    next=segment.EndSampleExclusive;
end
assert(next==stop && stop>plan.StartSample && numel(unique(ids))==1 && nonzero>0);
evidence=struct('TransmitterID',plan.TransmitterID,'ComponentID',unique(ids), ...
    'OriginalSampleSHA256',plan.PreparedWaveformSHA256,'StartSample',plan.StartSample, ...
    'ExecutedThroughSample',stop,'ExecutedParentComponentCount',numel(unique(ids)), ...
    'NonzeroSampleCount',nonzero,'OriginalExecutedContributors',{receipts}, ...
    'Source',"original_successful_event_runtime_executed_contributors");
end

function state=localCheckRecoveryPreparation(state,item,decision)
owner=state.SharedWaveformStream; old=state.TestWithheldPUCCH;
assert(old.ReceiverCompleted && decision.PowerReferenceProducerSlot==state.TestSSBRecoveryBurstSlot && ...
    decision.PowerReferenceAvailableSlot>state.TestSSBRecoveryBurstSlot && ...
    decision.PowerReferenceAvailableSlot<=decision.DecisionSlot && ...
    isequaln(state.UECommonCellConfigurationByUE{item.UE},old.Common) && ...
    isequaln(state.SSBPowerReferenceLifecycleByUE{item.UE},old.Lifecycle) && ...
    isequaln(state.ControlTrials.CSIRS,old.SourceCSI));
measurements=state.ReferenceSignalMeasurementTable;
selected=measurements(string(measurements.MeasurementId)==decision.PowerReferenceMeasurementID,:);
assert(height(selected)==1 && selected.ResourceId==1 && ...
    selected.ProducerSlot==state.TestSSBRecoveryBurstSlot && ...
    selected.AvailableSlot==decision.PowerReferenceAvailableSlot && ...
    selected.ObservationStartSample==state.TestRecoveryBroadcast.StartSample && ...
    selected.ObservationEndSampleExclusive<=owner.Events.NextSampleIndex && ...
    selected.ObservationStartSample>=old.DecisionSample && selected.SSBOccasionBCHCRCPass==1 && ...
    string(selected.MeasurementSource)=="actual_shared_ssb_occasion_pre_rx_rf_measurement");
reports=state.PendingCSITable;
report=reports(reports.UEIndex==item.UE & reports.DueSlot==item.Context.Slot,:);
assert(height(report)==1 && ~report.Processed && ...
    report.ReportIdentity~=old.OriginalReport.ReportIdentity && ...
    report.SourceSlot==old.OriginalReport.SourceSlot && report.SourceSlot==6 && ...
    report.MeasurementAvailableAtSample==old.OriginalReport.MeasurementAvailableAtSample && ...
    report.CSIReferenceSlot==state.TestSSBRecoveryBurstSlot && ...
    isempty(sixgr.truth.scheduledHARQExpectationsForOccasion(state,item.UE,item.Context.Slot)));
expired=reports(string(reports.ReportIdentity)==string(old.FinalReport.ReportIdentity),:);
assert(isequaln(expired(:,old.FinalReport.Properties.VariableNames),old.FinalReport));
broadcastExecution=localRecoveryBroadcastExecution(state);
state.TestRecoveredPUCCHPreparation=struct('Decision',decision,'SelectedMeasurement',selected, ...
    'OriginalReport',report,'PreparedAtSample',owner.Events.NextSampleIndex, ...
    'OriginalBroadcastExecution',broadcastExecution, ...
    'CSIObservationReused',true,'CSIObservationSourceSlot',6, ...
    'CSIObservationAgeAtReportSlots',item.Context.Slot-6, ...
    'NewCSIObservationClaimed',false,'OldObligationReplayed',false);
receipt=state.TestRecoveredPUCCHPreparation;
save(fullfile(state.TestRoot,'recovery_preparation_original.mat'),'receipt','-v7.3');
end

function state=localVerifyWithheldPUCCHRecovery(state)
owner=state.SharedWaveformStream; old=state.TestWithheldPUCCH;
prepared=state.TestRecoveredPUCCHPreparation; slot=state.TestSSBRecoveryReportSlot;
assert(old.ReceiverCompleted && numel(owner.PUCCHTransmissions)==1 && ...
    numel(owner.DataTransmissions)==1 && state.ULHarq.Stats.Tx==0 && ...
    numel(state.SharedPUCCHTXLedger)==1 && height(state.SharedGNBUCIHARQTable)==1 && ...
    numel(state.SharedHARQFeedbackCommittedMappings)==1 && isequaln(state.DLHarq.Stats,old.HARQAfter));
trial=state.ControlTrials.PUCCH(state.ControlTrials.PUCCH.Slot==slot,:);
received=state.SharedGNBCSIReportTable(state.SharedGNBCSIReportTable.DueSlot==slot,:);
assert(height(trial)==1 && trial.PUCCHDecodeOk && trial.ReceiverExpectedHARQBitCount==0 && ...
    trial.ReceiverExpectedCSIPart1BitCount>0 && height(received)==1 && received.CSIUCIDecodeOk && ...
    string(received.ReportIdentity)==string(prepared.OriginalReport.ReportIdentity));
oldReport=state.PendingCSITable( ...
    string(state.PendingCSITable.ReportIdentity)==string(old.FinalReport.ReportIdentity),:);
oldTrace=state.PUCCHGrantTraceTable( ...
    ismember(string(state.PUCCHGrantTraceTable.PUCCHGrantId),old.OriginalGrantIDs),:);
assert(isequaln(oldReport(:,old.FinalReport.Properties.VariableNames),old.FinalReport) && ...
    isequaln(oldTrace(:,old.FinalTrace.Properties.VariableNames),old.FinalTrace));
tx=owner.PUCCHTransmissions(1);
assert(tx.Identity.ObservationID~=old.ObservationID && ...
    tx.FirstActiveSample>=prepared.PreparedAtSample && ...
    tx.FirstActiveSample<state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive && ...
    state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive== ...
    state.TestDeclaredTAG.TimeAlignmentExpirySampleExclusive);
pending=owner.Pending;
pendingFullCapture=any(string({pending.ID})==state.TestRecoveryBroadcast.ObservationID);
terminal=struct('InitialSIB1Decoded',true,'InitialMeasuredSSBIndex',0,'SelectedPUCCHSSBIndex',1, ...
    'WithheldOriginalSlot',10,'ReceiverOnlyObservationID',old.ObservationID, ...
    'ReceiverDTX',logical(old.ReceiverTrial.DTXFlag),'ReceiverHARQOutcome',string(old.HARQOutcome.FeedbackOutcome), ...
    'RecoveredSlot',slot,'RecoveryPUCCHTransmissionID',string(tx.Identity.TransmissionID), ...
    'RecoveryReportIdentity',string(received.ReportIdentity),'OriginalCSIObservationSlot',6, ...
    'RecoveryExecutedBroadcastComponentCount',prepared.OriginalBroadcastExecution.ExecutedParentComponentCount, ...
    'NewCSIObservationClaimed',false,'OriginalHARQCommitCount',1,'OldObligationReplayed',false, ...
    'RecoveryFullBroadcastCapturePending',pendingFullCapture, ...
    'RecoveryFullBroadcastCaptureCompleted',state.TestRecoveryBroadcastFullCaptureCompleted, ...
    'RecoveryFullSIReceiverExecuted',false,'FinalSample',owner.Events.NextSampleIndex, ...
    'FullAccessQualified',false,'StatisticalQualification',false);
assert(xor(terminal.RecoveryFullBroadcastCapturePending,terminal.RecoveryFullBroadcastCaptureCompleted));
state.TestWithheldRecoveryTerminal=terminal;
sixgr.truth.CoupledTruthRuntime.writeTables(state,state.TestRoot);
save(fullfile(state.TestRoot,'withheld_recovery_terminal.mat'),'terminal','trial','received','-v7.3');
sixgr.util.csvWriteTable(fullfile(state.TestRoot,'withheld_recovery_terminal.csv'), ...
    struct2table(terminal,'AsArray',true),'PreserveSchema',true);
fprintf('PUCCH_WITHHELD_RECOVERY_PASS blocked_slot=10 actual_RX=1 expiry_once=1 fresh_SSB=1 recovered_slot=%d CSI_source_slot=6 new_CSI_observation=0 full_SI_pending=%d root=%s\n', ...
    slot,pendingFullCapture,state.TestRoot);
end

function row=localContinuationReferenceRow(out,receiver,state,sourceSlot)
% Lossless scalar projection of this completed receiver, not authored PASS.
% Large arrays remain in the separately saved receiver artifact.
r=struct();
for name=string(fieldnames(out)).'
    value=out.(name);
    if (isnumeric(value) || islogical(value)) && isscalar(value) && isreal(value)
        r.(name)=value;
    elseif isstring(value) && isscalar(value)
        r.(name)=value;
    elseif ischar(value) && (isrow(value) || isempty(value))
        r.(name)=string(value);
    end
end
r.Slot=double(sourceSlot); r.Frame=floor((sourceSlot-1)/state.SlotsPerFrame)+1;
r.UEIndex=1; r.ServingCell=double(state.CurrentServingIdx(1));
r.ObservationStartSample=receiver.StartSample;
r.ObservationEndSampleExclusive=receiver.EndSampleExclusive;
r.ObservationSampleRateHz=receiver.SampleRateHz;
r.ObservationCompletionTime_s=receiver.EndSampleExclusive/receiver.SampleRateHz;
r.ObservationCoverageSource="complete_contiguous_received_sample_buffer";
r.MeasurementClockEpoch=state.SharedWaveformStream.Physical.ConfigurationEpoch;
r.ResultCompletedAtSample=state.SharedWaveformStream.Events.NextSampleIndex;
r.RuntimeIntegrationMode="coupled_slot_runtime";
row=struct2table(r,'AsArray',true);
end

function state=localDeliverReceivedSIB1(state,cfg)
% The same causal queue and original decoded-tree installation as the
% coordinator. No codec fixture, SSB-only result, or configured tree can
% satisfy this receiver boundary. Initial RA/TAG remains a declared input.
[state,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
for item=reshape(ready,1,[])
    recovered=item.Recovery;
    assert(~item.TrackingOnly && recovered.StrictOk && recovered.BCHCrcPass && ...
        recovered.DCICrcPass && recovered.DLSCHCrcPass && recovered.SIB1ASN1DecodeOk && ...
        recovered.SIB1TreeEqual && recovered.RecoveryScope=="SSB_MIB_SIB1", ...
        'test:SharedSIB1NotDecoded','Only the actual full SI receiver may install measurement authority.');
    state=sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state,item.UEIndex,item.Trial);
    state=sixgr.truth.installReceivedSIB1Recovery(state,item.UEIndex,recovered,state.CurrentSlot);
    common=state.UECommonCellConfigurationByUE{item.UEIndex};
    if state.TestRetainedPower
        tag=state.TestDeclaredTAG;
        tag.DLReference=state.TestReceivedDLClock;
        tag.Offset=common.ULTimingAdvanceOffset;
        tag.TimingAdvanceAvailableAtSample=state.SharedWaveformStream.Events.NextSampleIndex;
        tag.TimingAdvanceEffectiveAtSample=tag.TimingAdvanceAvailableAtSample;
        state.ConnectedULTimingByUE{item.UEIndex}=tag;
    end
    receipt=state.PreconfiguredDLMeasurementInstallationByUE{item.UEIndex};
    assert(receipt.EffectiveSample==state.SharedWaveformStream.Events.NextSampleIndex && ...
        receipt.EffectiveSample>=item.Trial.ObservationEndSampleExclusive && ...
        receipt.SIB1TreeHash==string(common.TreeHash) && ~receipt.DecodedDedicatedRRC);
    state.TestActualSIB1Installation=receipt;
    state.TestActualSIB1DeliveredSlot=double(state.CurrentSlot);
    state.TestContinuationPBCH=item.Trial;
    trial=item.Trial;
    sixgr.util.csvWriteTable(fullfile(state.TestRoot,'shared_received_sib1.csv'),trial,'PreserveSchema',true);
    save(fullfile(state.TestRoot,'shared_received_sib1_installation.mat'),'recovered','common','receipt','trial','-v7.3');
    fprintf('SHARED_RECEIVED_SIB1_INSTALLATION_PASS delivery_slot=%d sample=%d SI_DCI_CRC=%d SI_TB_CRC=%d dedicated_RRC=0 RA_TAG=declared_component\n', ...
        state.CurrentSlot,receipt.EffectiveSample,recovered.DCICrcPass,recovered.DLSCHCrcPass);
end
end

function state=localDeliverContinuationReferences(state)
% Use the production queues/reducers at actual canonical slot boundaries.
[state,broadcast]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
for item=reshape(broadcast,1,[])
    state=sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state,item.UEIndex,item.Trial);
    state.TestContinuationPBCH=item.Trial;
end
pending=state.TestContinuationReferences; keep=true(numel(pending),1);
now=(state.CurrentSlot-1)*state.SlotDuration_s;
for k=1:numel(pending)
    row=pending{k};
    if row.ObservationCompletionTime_s>now, continue; end
    row.ObservationDeliverySlot=double(state.CurrentSlot);
    row.ObservationDeliveryTime_s=now;
    row.ObservationDeliverySource="canonical_slot_start_after_complete_received_window";
    row=sixgr.truth.bindDeliveredReferenceClock(state,row);
    previous=sixgr.util.structGet(state.LatestULFeedback(1),'AcceptedSRSSpatialDecision',struct());
    state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,row);
    accepted=state.LatestULFeedback(1).AcceptedSRSSpatialDecision;
    raw=state.ReferenceSignalMeasurementTable;
    selected=upper(string(raw.SignalType))=="SRS" & raw.TargetId==1 & raw.ProducerSlot==row.Slot;
    assert(nnz(selected)==1 && ...
        string(raw.SRSConfigurationContextID(selected))==string(row.SRSConfigurationContextID) && ...
        raw.SRSNumPorts(selected)==row.SRSNumPorts && ...
        raw.MeasurementClockEpoch(selected)==row.MeasurementClockEpoch, ...
        'The raw delivered SRS must retain its original producer configuration and clock.');
    if ~isempty(fieldnames(accepted)) && accepted.ProducerSlot==row.Slot
        for field=["SRSConfigurationContextID","SRSNumPorts","SRSConfigurationContextVersion", ...
                "SRSConfigurationEpoch","SRSResourceID","SRSResourceIDsJSON","MeasurementClockDomain", ...
                "MeasurementClockEpoch","ObservationStartSample","ObservationEndSampleExclusive", ...
                "ObservationSampleRateHz","ResultCompletedAtSample","ResultAvailableAtSample"]
            assert(isequaln(accepted.(field),row.(field)), ...
                'Accepted SRS lost its actual producer %s.',field);
        end
        assert(string(accepted.MeasurementId)==string(raw.MeasurementId(selected)) && ...
            accepted.AvailableSlot==state.CurrentSlot && accepted.RI==row.EstimatedRI && ...
            accepted.PMI==row.EstimatedTPMI);
    else
        assert(isequaln(accepted,previous), ...
            'A held SRS report cannot relabel the previously accepted spatial decision.');
    end
    % Retain the actual accepted source; later scheduling may use a newer
    % accepted decision, but a held raw report never relabels this capsule.
    state.TestContinuationAcceptedSRS=accepted;
    state.TestContinuationDeliveredSRS=row;
    keep(k)=false;
end
state.TestContinuationReferences=pending(keep);
[state,tracking]=sixgr.truth.TRSResultDelivery.takeAvailable(state);
for item=reshape(tracking,1,[])
    row=sixgr.truth.bindDeliveredReferenceClock(state,item.Trial);
    state=sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,item.ServingCell,row);
    state.TestContinuationDeliveredTRS=row;
end
end

function state=localQueueContinuationTRS(state,cfg,slot)
rankMode=logical(sixgr.util.structGet(state,'TestRankTransitions',false));
if state.TestContinuationTRSQueued && ~rankMode, return; end
window=sixgr.truth.resolveTRSObservationWindow(cfg,slot);
if ~window.ObservationStarts, return; end
if rankMode
    if ismember(slot,state.TestRankTransitionTRSSlots) || ...
            any(window.AbsoluteSlotNumbers>=cfg.run.totalSlots), return; end
    assert(~state.SharedWaveformStream.hasPending("TRS",1), ...
        'A configured TRS observation cannot overwrite an incomplete capture.');
end
[dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
p=sixgr.link.prepareTRSTransmission(dl,cfg.channel.snr_dB,'RuntimeSlot',slot);
context=struct('Config',dl,'Slot',slot,'Frame',state.CurrentFrame, ...
    'ServingCell',state.CurrentServingIdx(1));
state.SharedWaveformStream.queueDownlink('TRS',1,p,context);
state.TestContinuationTRSQueued=true;
if rankMode, state.TestRankTransitionTRSSlots(end+1,1)=slot; end
end

function state=localQueueRankTransitionCSI(state,cfg,slot)
if ~state.TestRankTransitions, return; end
% Reuse the real independent pilot producer/receiver. Periodic UCI alone
% can otherwise repeat an old data-derived measurement through this episode.
[active,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
active=sixgr.phy.grid.applyRuntimeCarrierTimeline(active,slot);
[state,queued]=sixgr.truth.queueSharedPeriodicCSIRS(state,active,1,slot, ...
    state.CurrentFrame,sixgr.truth.CoupledRadioIdentity.dataRNTI(active,1,'DL'), ...
    state.CurrentServingIdx(1),cfg.channel.snr_dB);
if queued, state.TestRankTransitionCSIRSSlots(end+1,1)=slot; end
end

function path=localContinuationArtifact(state,name)
folder=state.TestRoot;
if logical(sixgr.util.structGet(state,'TestRankTransitions',false))
    folder=fullfile(folder,sprintf('application_%03d',state.TestRankTransitionAttemptOrdinal));
    if ~isfolder(folder), mkdir(folder); end
end
path=fullfile(folder,name);
end

function ready=localRankTransitionSourceReady(state,direction)
ready=true;
if ~state.TestRankTransitions, return; end
if direction=="DL"
    a=sixgr.util.structGet(state.LatestDLFeedback(1),'CSIReportProvenance',struct());
    ready=state.LatestDLFeedback(1).Valid && isstruct(a) && ...
        isfield(a,'SourceSlot') && a.SourceSlot>state.TestRankTransitionLastSourceSlot;
else
    a=sixgr.util.structGet(state.LatestULFeedback(1),'AcceptedSRSSpatialDecision',struct());
    ready=state.LatestULFeedback(1).Valid && isstruct(a) && ...
        isfield(a,'ProducerSlot') && a.ProducerSlot>state.TestRankTransitionLastSourceSlot;
end
end

function [state,stop,rearm]=localRankTransitionAfterSlot(state,direction)
% Only Test* bookkeeping changes here. Actual HARQ/feedback/CSI/channel
% owners remain untouched. No forced retry or success after a physical miss.
stop=false; rearm=false;
if ~state.TestRankTransitions, return; end
prefix="TestContinuation"; harq=state.DLHarq;
if direction=="UL", prefix="TestSRSContinuation"; harq=state.ULHarq; end
if direction=="UL"
    state.TestPeriodicCSIRefreshSnapshots{end+1,1}=PeriodicCSIRefreshAudit.capture(state);
end
if state.(prefix+"Rejected")
    state.TestRankTransitionTermination="actual_control_not_admitted"; stop=true; return;
end
if ~state.(prefix+"Completed"), return; end
a=state.(prefix+"Application");
id=string(a.TransmissionReceipt.Identity.TransmissionID);
apps=state.TestRankTransitionApplications;
seen=cellfun(@(x)string(x.TransmissionReceipt.Identity.TransmissionID)==id,apps);
if ~any(seen), state.TestRankTransitionApplications{end+1,1}=a; end
if double(a.CRCPass)~=1
    state.TestRankTransitionTermination="actual_data_failure_retry_population_unexercised";
    stop=true; return;
end
if direction=="UL"
    g=a.ScheduledGrant; sourceSlot=a.AcceptedSRS.ProducerSlot;
else
    g=a.Grant; sourceSlot=a.OriginalProvenance.SourceSlot;
end
slot=g.Slot;
if direction=="UL", slot=sixgr.truth.runtimeULGrantSlot(g); end
if direction=="DL"
    pending=state.PendingFeedbackTable;
    hit=find(string(pending.Direction)==direction & pending.RNTI==g.RNTI & pending.SourceSlot==slot);
    assert(isscalar(hit),'test:RankTransitionFeedbackIdentity', ...
        'A completed DL application must retain its original feedback obligation.');
    assert(pending.HarqID(hit)==a.ReceivedControl.ReceivedAssignment.HARQProcess && ...
        pending.NDI(hit)==a.ReceivedControl.ReceivedAssignment.NDI && ...
        pending.RV(hit)==a.ReceivedControl.ReceivedAssignment.RV);
    if ~pending.Processed(hit), return; end
else
    % UL ACK/NACK is the gNB's actual PUSCH decoder outcome, not a made-up
    % UE PUCCH obligation. The canonical completion owns its consumption.
    timeline=state.HARQTimelineTable;
    hit=find(string(timeline.Direction)=="UL" & ...
        string(timeline.PHYGrantContextId)==string(g.PHYGrant.GrantContextId));
    assert(isscalar(hit) && timeline.Slot(hit)==slot && ...
        timeline.RNTI(hit)==g.RNTI && ...
        timeline.HarqID(hit)==a.ReceivedControl.ReceivedAssignment.HARQProcess && ...
        timeline.NDI(hit)==a.ReceivedControl.ReceivedAssignment.NDI && ...
        timeline.RV(hit)==a.ReceivedControl.ReceivedAssignment.RV && ...
        string(timeline.FeedbackMechanism(hit))=="gnb_pusch_decoder" && ...
        string(timeline.FeedbackEvidenceSource(hit))=="same_waveform_pusch_rx_crc" && ...
        timeline.CombinedDecodeOK(hit)==1 && ...
        timeline.DataDecodeAvailableAtSample(hit)<=a.CompletedAtSample, ...
        'test:RankTransitionFeedbackIdentity','UL rearming requires its consumed original gNB decoder outcome.');
end
before=state.TestRankTransitionAttemptHARQ;
if harq.Stats.Ack~=before.Ack+1 || harq.Stats.Nack~=before.Nack
    state.TestRankTransitionTermination="received_feedback_not_ack_retry_population_unexercised";
    stop=true; return;
end
state.TestRankTransitionLastSourceSlot=sourceSlot;
state.(prefix+"Completed")=false;
state.(prefix+"Rejected")=false;
if direction=="UL", state.TestSRSContinuationIssued=false; end
rearm=true;
end

function state=localContinueReceivedSRSToPUSCH(state,cfg,prefixLastSlot)
% The prefix supplied real reference receptions. Nothing below authors an
% accepted spatial decision, DCI, HARQ allocation or future data grant.
owner=state.SharedWaveformStream;
assert(~state.ProtocolWaveformEnabled, ...
    'This component offers metadata traffic, not full protocol-byte reassembly.');
assert(sixgr.truth.isPUSCHUCIAvailable(cfg) && ...
    cfg.run.controlGating.pbchRequired && cfg.run.controlGating.srsRequired && ...
    cfg.run.controlGating.trsRequired && ~cfg.run.controlGating.prachRequired);
carrier=sixgr.phy.grid.makeCarrier(cfg);
expiry=state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive;
cycle=max([state.SlotsPerFrame,state.SRSSlotPeriod,cfg.phy.csi.reportPeriodicitySlots]);
horizon=min(prefixLastSlot+2*cycle,floor(expiry/(owner.SampleRateHz*state.SlotDuration_s)));
if state.TestRankTransitions, horizon=cfg.run.totalSlots; end
assert(horizon>prefixLastSlot,'test:SRSContinuationNoTimingHorizon', ...
    'Do not extend the original component TAG to force a scheduling opportunity.');
state.TestSRSContinuationStarted=true;
state.TestSRSContinuationInitialTXCount=numel(owner.DataTransmissions);
state.TestSRSContinuationInitialHARQ=state.ULHarq.Stats;
state.TestSRSContinuationExpiry=expiry;
state.TestSRSContinuationIssued=false;
state.TestSRSContinuationRejected=false;
state.TestSRSContinuationAttempts=cell(0,1);
% Explicit finite test traffic is an input, not a measured result. Use the
% ordinary arrival reducer and never derive demand from the later grant TBS.
arrivalSlot=prefixLastSlot+1; offeredBits=8*1024;
if state.TestRankTransitions
    offeredBits=cfg.traffic.fullBufferBitsPerTTI*(horizon-prefixLastSlot);
end
for field=["OfferedBitsDL","OfferedBitsUL"]
    state.Traffic.(field)(arrivalSlot:horizon,1:state.NumUsers)=0;
end
state.Traffic.OfferedBitsUL(arrivalSlot,1)=offeredBits;
state.TestSRSContinuationOfferedBits=offeredBits;
offeredBefore=state.ULOfferedBits(1);
for slot=arrivalSlot:horizon
    [allowDL,allowUL]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    assert(allowDL || allowUL);
    direction="UL"; if allowDL, direction="DL"; end
    pending=sixgr.util.structGet(state,'SharedPendingULGrants',repmat(struct(),0,1));
    [state,pending,blocked]=sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
        state,cfg,direction,1,1,slot,horizon,cfg.channel.snr_dB,pending, ...
        sixgr.truth.isPUSCHUCIAvailable(cfg));
    assert(isempty(blocked),'test:SRSContinuationUnexpectedCollision', ...
        'The native disjoint allocation must not require a collision-policy override.');
    state.SharedPendingULGrants=pending;
    state=sixgr.truth.CoupledTruthRuntime.enqueueTrafficForFrameRuntime(state,slot);
    assert(state.LastTrafficFrameApplied==slot && ...
        state.ULOfferedBits(1)==offeredBefore+offeredBits);
    state=localDeliverContinuationReferences(state);
    state=localQueueContinuationTRS(state,cfg,slot);
    state=localQueueRankTransitionCSI(state,cfg,slot);
    if (state.TestRankTransitions || ~state.TestSRSContinuationIssued) && ~owner.hasPending("SRS",1) && ...
            isempty(state.TestContinuationReferences)
        for source=slot+1:horizon
            if ismember(source,state.TestContinuationQueuedSRSSlots), continue; end
            if ~sixgr.truth.coupledSRSResourceOpportunity(cfg,source,1,1, ...
                    state.SRSSlotPeriod,cfg.phy.srs.schedulingPolicy,cfg.phy.srs.maxUEsPerSlot)
                continue;
            end
            [~,allowed]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,source);
            if ~allowed, continue; end
            localQueueSRS(state,cfg,source);
            state.TestContinuationQueuedSRSSlots(end+1,1)=source;
            break;
        end
    end
    if ~state.TestSRSContinuationIssued && allowDL && localRankTransitionSourceReady(state,"UL")
        atSample=owner.Events.NextSampleIndex;
        assert(atSample==sixgr.phy.frame.slotStartSample(carrier,slot-1,owner.SampleRateHz));
        [state,planned,info]=sixgr.truth.planFutureULGrants( ...
            state,cfg,{cfg},state.SharedPendingULGrants,1,horizon);
        assert(owner.Events.NextSampleIndex==atSample);
        emptyDL=repmat(struct(),0,1);
        [state,emptyDL,planned]=sixgr.truth.planJointHARQPUSCHTiming(state,{cfg},emptyDL,planned);
        [emptyDL,planned]=sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg},emptyDL,planned);
        assert(isempty(emptyDL));
        state.TestSRSContinuationAttempts{end+1,1}=struct('ControlSlot',slot, ...
            'AtSample',atSample,'Planning',info,'Candidates',planned);
        if ~isempty(planned)
            assert(isscalar(planned) && ~sixgr.phy.grant.isExplicitHARQRetransmission(planned), ...
                'test:SRSContinuationNeedsNewData','This bounded case starts with one new-data decision.');
            localAssertSRSContinuationGrant(state,cfg,planned,atSample);
            beforePending=state.SharedPendingULGrants; beforeTX=state.ULHarq.Stats.Tx;
            [state,qualified,queued]=sixgr.truth.PDCCHControlRuntime.queueShared( ...
                state,{cfg},planned,'UL',cfg.channel.snr_dB,@localContinuationControlLog);
            assert(isempty(qualified) && isequaln(state.SharedPendingULGrants,beforePending) && ...
                state.ULHarq.Stats.Tx==beforeTX, ...
                'Queued control is neither a received UL grant nor an emitted data TB.');
            if ~isempty(queued)
                assert(isscalar(queued));
                state.TestSRSContinuationIssued=true;
                state.TestSRSContinuationGrant=queued;
                state.TestSRSContinuationAccepted=planned.AcceptedSRSSpatialDecision;
                state.TestSRSContinuationDecisionSample=atSample;
                if state.TestRankTransitions
                    state.TestRankTransitionAttemptOrdinal=state.TestRankTransitionAttemptOrdinal+1;
                    state.TestRankTransitionAttemptHARQ=state.ULHarq.Stats;
                    state.TestSRSContinuationInitialHARQ=state.ULHarq.Stats;
                end
                fprintf('SRS_APPLICATION_QUEUED_CONTROL slot=%d target=%d source=%s rank=%d TPMI=%d\n', ...
                    slot,sixgr.truth.runtimeULGrantSlot(queued), ...
                    string(planned.AcceptedSRSSpatialDecision.MeasurementId),planned.NumLayers,planned.TPMI);
            end
        end
    end
    % Only the completed control callback can populate this calendar.
    pending=state.SharedPendingULGrants;
    slots=arrayfun(@sixgr.truth.runtimeULGrantSlot,pending);
    assert(all(slots>=slot),'No stale received grant may be hidden by a test-side filter.');
    if allowUL
        state=sixgr.truth.SharedDataCompletionRuntime.recordQueuedULSchedule(state,pending(slots==slot));
    end
    state=sixgr.truth.advanceSharedSlotWithULGrants( ...
        state,cfg,pending(slots>slot),pending(slots==slot),@localEvents);
    state=localDrainContinuationData(state);
    if state.TestRankTransitions
        [state,stop]=localRankTransitionAfterSlot(state,"UL");
        if stop, break; end
    elseif state.TestSRSContinuationCompleted || state.TestSRSContinuationRejected
        break;
    end
end
if ~state.TestSRSContinuationCompleted && ~state.TestSRSContinuationRejected && ...
        (~state.TestRankTransitions || state.TestSRSContinuationIssued)
    % Real receive tails of already finished TX may cross the final boundary.
    % This production API forbids future data TX and never creates a grant.
    % Check every remaining producer too: a tail must not introduce a new
    % reference/control contribution after the closed scheduling horizon.
    first=owner.Events.NextSampleIndex;
    for pending=owner.Pending
        if isfield(pending.Context,'Prepared')
            prepared=pending.Context.Prepared;
            if isa(prepared,'sixgr.link.PreparedDataTransmission') || ...
                    isa(prepared,'sixgr.link.PreparedUplinkControlTransmission')
                lastTX=prepared.EndSampleExclusive;
            elseif any(pending.Kind==["CSIRS","TRS"])
                lastTX=prepared.TransmitStartSample+prepared.NumSamples;
            elseif pending.Kind=="PDCCH"
                lastTX=prepared.RuntimeStartSample+size(prepared.TransmitSamples,1);
            else
                error('test:SRSContinuationUnknownTailProducer', ...
                    'No closed full-TX interval contract for pending producer %s.',pending.Kind);
            end
            assert(lastTX<=first, ...
                'test:SRSContinuationFutureTailProducer','A receive tail cannot execute a future prepared TX.');
        else
            assert(any(pending.Kind==["PUSCHReceiveOnly","PUCCHReceiveOnly","PUCCHNotSelected"]), ...
                'test:SRSContinuationUnknownTailProducer','Unprepared producer decisions cannot enter the receive tail.');
        end
    end
    before=struct('Slot',state.CurrentSlot,'TX',owner.DataTransmissions, ...
        'PUCCHTX',owner.PUCCHTransmissions,'CSIRSTX',owner.CSIRSTransmissions, ...
        'PendingUL',state.SharedPendingULGrants,'Attempts',{state.TestSRSContinuationAttempts}, ...
        'TraceCount',numel(owner.Events.ExecutionTrace));
    state.TestSRSReceiveTail=true;
    state=owner.drainDataReceiveTail(state,cfg,@localEvents);
    state.TestSRSReceiveTail=false;
    state=localDrainContinuationData(state);
    if state.TestRankTransitions, state=localRankTransitionAfterSlot(state,"UL"); end
    assert(state.CurrentSlot==before.Slot && isequaln(owner.DataTransmissions,before.TX) && ...
        isequaln(owner.PUCCHTransmissions,before.PUCCHTX) && ...
        isequaln(owner.CSIRSTransmissions,before.CSIRSTX) && ...
        isequaln(state.SharedPendingULGrants,before.PendingUL) && ...
        isequaln(state.TestSRSContinuationAttempts,before.Attempts));
    for ti=before.TraceCount+1:numel(owner.Events.ExecutionTrace)
        segment=owner.Events.ExecutionTrace{ti};
        for node=segment.Execution.ExecutedContributors
            assert(node.Receipt.CompleteContributorList && ...
                all([node.Receipt.Components.NonzeroSampleCount]==0), ...
                'test:SRSContinuationTailTransmission','Receive-tail processing must not emit a new contribution.');
        end
    end
end
attempts=state.TestSRSContinuationAttempts;
controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
rejected=sixgr.util.structGet(state,'SharedRejectedULReceiveAuditTable',table());
save(fullfile(state.TestRoot,'received_srs_ul_admission.mat'), ...
    'attempts','controls','rejected','arrivalSlot','offeredBits','horizon','expiry','-v7.3');
assert(state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive==expiry);
if state.TestRankTransitions
    assert(numel(owner.DataTransmissions)>=state.TestSRSContinuationInitialTXCount+ ...
        numel(state.TestRankTransitionApplications));
    return;
end
assert(state.TestSRSContinuationCompleted,'test:SRSContinuationNotExercised', ...
    'No actual accepted-control PUSCH completed within the unchanged gates/TAG; inspect retained outcomes.');
assert(numel(owner.DataTransmissions)==state.TestSRSContinuationInitialTXCount+1);
fprintf('RECEIVED_SRS_TO_SCHEDULED_PUSCH_PASS scheduler=%s normal_planner=1 decoded_DCI=1 completed_PUSCH=1 natural_retry=0 full_scenario=0\n', ...
    class(state.ULSchedulers{1}));
end

function plan=localContinuationCompletedPlan(state,item)
% Inspect the canonical retained result, never synthesize a completion plan.
complete=state.SharedCompletedDataPlans;
assert(iscell(complete) && isscalar(complete));
entry=complete{1}; plan=entry.Plan; c=item.Context;
assert(string(entry.Direction)==string(c.Job.Direction) && ...
    plan.UEIndex==item.UE && ...
    string(plan.Result.HARQ.SharedTransmissionID)==string(c.TransmissionIdentity.TransmissionID) && ...
    string(plan.GrantSnapshot.PHYGrant.GrantContextId)==string(c.Prepared.RequestBinding.PHYGrant.GrantContextId) && ...
    isequaln(plan.LinkAdaptationState,plan.Result.LinkAdaptationState));
trial=plan.TrialTable;
assert(height(trial)==1 && ...
    string(trial.FrozenGrantContextId)==string(c.TransmissionIdentity.PHYGrantContextId) && ...
    string(trial.GrantContextId)==string(c.Plan.GrantRow.GrantContextId), ...
    'Final publication must preserve separate logical and frozen-PHY grant identities.');
controls=state.SharedReceivedGrantControls;
hit=find(cellfun(@(x)string(x.Key)==string(c.Key),controls)); assert(isscalar(hit));
[~,fields]=sixgr.truth.bindReceivedPDCCHGrantEvidence(c.Job.GrantSnapshot,controls{hit}.Grant);
for k=1:numel(fields)
    field=fields{k}; expected=plan.GrantSnapshot.(field);
    if ischar(expected), expected=string(expected); end
    assert(isequaln(trial.(field),repmat(expected,height(trial),1)), ...
        'Receiver-owned control evidence must survive the planning annotation.');
end
end

function localAssertContinuationReceiverPublication(state,item,plan,control)
% Assertion-only projection of the actual completed row and original capture.
% No receiver rerun, inferred detector, configured channel or repaired row.
trial=plan.TrialTable; original=plan.Result.TrialTable;
direction=string(item.Context.Job.Direction);
channel="pdsch"; runner="runDLPDSCHThroughput"; sch="DLSCH";
if direction=="UL", channel="pusch"; runner="runULPUSCHThroughput"; sch="ULSCH"; end
assert(height(trial)==1 && height(original)==1 && ...
    string(trial.RuntimeMaterializationStatus)=="active_waveform_"+channel+"_runtime" && ...
    string(trial.RuntimeEvidenceSource)=="sixgr.link."+runner+"_returned_receiver");
stages=["ReceiverUsable","DecodeAttempted","DecodeUsable","CRCApplicable","CRCPass", ...
    "ChannelEstimateAttempted","ChannelEstimateAvailable","ChannelEstimateSource", ...
    "ResourceExtractionAttempted","ResourceExtractionAvailable", ...
    "EqualizationAttempted","EqualizationAvailable",sch+"DecodeAttempted",sch+"DecodeAvailable", ...
    "LLRAvailable","LLRFinite","PostEqSINRAvailable","PostEqSINRReceiverDerived"];
summaries=["DetectionApplicable","DetectionAttempted","DetectionSuccess","DetectionUsable", ...
    "DetectionStatus","DetectionSource","MeasurementApplicable","MeasurementAttempted", ...
    "MeasurementUsable","MeasurementStatus","MeasurementSource","MeasurementDefinition", ...
    "MeasurementValue_dB","MeasurementValueRole","MeasurementValueStatus", ...
    "MeasurementSummarySource","MeasurementAttemptKnown", ...
    "ChannelModelApplied","ChannelFadingApplied","ChannelFadingExecutionStatus", ...
    "ChannelExecutionEvidenceAvailable","ChannelExecutionEvidenceStatus","ChannelExecutionEvidenceSource", ...
    "ChannelExecutionTransmitterID","ChannelExecutionReceiverID","ChannelExecutionLinkID", ...
    "ChannelExecutionStartSample","ChannelExecutionEndSampleExclusive","ChannelExecutionSampleRateHz", ...
    "ChannelExecutionConfigurationEpoch","ChannelExecutionSegmentCount","ChannelExecutionDesiredSegmentCount", ...
    "RuntimeMaterializationStatus","RuntimeEvidenceSource"];
for name=[stages summaries]
    assert(isequaln(trial.(name),original.(name)), ...
        'Canonical finalization changed original receiver evidence %s.',name);
end
for name=["PDCCHReceiverDecodeOk","PDCCHDataAdmissionOk","PDCCHTCIAdmissionStatus"]
    expected=control.Grant.(name);
    if ischar(expected), expected=string(expected); end
    assert(isequaln(trial.(name),expected), ...
        'The finalized row must retain the actual received-control status %s.',name);
end
decoded=any(double(trial.CRCPass)==[0 1]);
if decoded
    for name=["ChannelEstimateAttempted","ChannelEstimateAvailable", ...
            "ResourceExtractionAttempted","ResourceExtractionAvailable", ...
            "EqualizationAttempted","EqualizationAvailable","LLRAvailable","LLRFinite", ...
            "DecodeAttempted","DecodeUsable",sch+"DecodeAttempted",sch+"DecodeAvailable", ...
            "CRCApplicable","FinalizedFlag","CountsTowardCoverage"]
        assert(trial.(name)==1,'Actual decoded CRC0/1 row lacks qualified stage %s.',name);
    end
    assert(trial.PartialRowFlag==0 && trial.Crash==0 && trial.IsWarmupFrame==0 && ...
        string(trial.RowLifecycleState)=="finalized");
else
    assert(trial.CountsTowardCoverage==0,'Unattempted/unknown CRC is not decode coverage.');
end
% Scheduled data has no separate generic detector; CRC is not a detector.
assert(trial.DetectionApplicable==0 && trial.DetectionAttempted==0 && ...
    trial.DetectionSuccess==0 && trial.DetectionUsable==0 && ...
    string(trial.DetectionStatus)=="not_applicable_scheduled_data_no_generic_detector");
postEqNames=["PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole", ...
    "PostEqSINRValueStatus","SINRComputationMethod"];
postEq=table2struct(original(:,cellstr(postEqNames)));
if direction=="DL"
    check=sixgr.phy.dl.validatePDSCHReceiverEvidence(postEq,'StrictMode',false);
else
    check=sixgr.phy.ul.validatePUSCHReceiverEvidence(postEq,'StrictMode',false);
end
qualified=original.PostEqSINRAvailable==1 && original.PostEqSINRReceiverDerived==1 && ...
    check.PostEqSINRAvailable && check.PostEqSINRReceiverDerived;
assert(trial.MeasurementApplicable==1 && trial.MeasurementUsable==double(qualified) && ...
    string(trial.MeasurementDefinition)=="receiver_post_equalization_SINR_only_not_all_receiver_measurements" && ...
    string(trial.MeasurementSummarySource)=="qualified_original_receiver_post_equalization_SINR" && ...
    string(trial.MeasurementSource)==string(original.PostEqSINRSource) && ...
    string(trial.MeasurementValueRole)==string(original.PostEqSINRValueRole) && ...
    string(trial.MeasurementValueStatus)==string(original.PostEqSINRValueStatus));
if qualified
    assert(trial.MeasurementAttempted==1 && trial.MeasurementAttemptKnown && ...
        trial.MeasurementValue_dB==original.PostEqSINR_dB);
else
    assert(isnan(trial.MeasurementAttempted) && ~trial.MeasurementAttemptKnown && ...
        isnan(trial.MeasurementValue_dB));
end
% Check desired-link closure directly against original post-RF segments,
% not the aggregate fading flag (which may include another transmitter).
ids=string({item.Planes.ReceiverID}); ri=find(endsWith(ids,':post_rf')); ti=find(endsWith(ids,':tx'));
assert(isscalar(ri) && isscalar(ti));
post=item.Planes(ri).Observation; segments=item.Planes(ri).Segments;
txID=extractBefore(ids(ti),':tx'); rxID=extractBefore(ids(ri),':post_rf');
assert(trial.ChannelExecutionEvidenceAvailable==1 && ...
    string(trial.ChannelExecutionEvidenceStatus)=="retained_original_execution_values" && ...
    string(trial.ChannelExecutionEvidenceSource)=="original_shared_execution_desired_TX_RX_link" && ...
    string(trial.ChannelExecutionTransmitterID)==txID && string(trial.ChannelExecutionReceiverID)==rxID && ...
    trial.ChannelExecutionStartSample==post.StartSample && ...
    trial.ChannelExecutionEndSampleExclusive==post.EndSampleExclusive && ...
    trial.ChannelExecutionSampleRateHz==post.SampleRateHz, ...
    'Actual desired-link execution is missing or does not cover the original RX capture.');
cursor=post.StartSample; count=0;
for k=1:numel(segments)
    segment=segments{k}; e=segment.Execution;
    if segment.EndSampleExclusive<=post.StartSample || segment.StartSample>=post.EndSampleExclusive, continue; end
    assert(segment.StartSample==e.StartSample && segment.EndSampleExclusive==e.EndSampleExclusive && ...
        max(segment.StartSample,post.StartSample)==cursor && ...
        e.SampleRateHz==post.SampleRateHz && ...
        string(e.ConfigurationEpoch)==string(trial.ChannelExecutionConfigurationEpoch) && ...
        string(e.Source)=="composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf" && ...
        string(e.ApproximationMode)=="none" && ...
        nnz(string({e.TX.ID})==txID)==1 && nnz(string({e.RX.ID})==rxID)==1);
    hit=find(string({e.Links.TX})==txID & string({e.Links.RX})==rxID); assert(isscalar(hit));
    link=e.Links(hit); replay=link.Replay;
    assert(string(link.ID)==string(trial.ChannelExecutionLinkID) && ...
        replay.RuntimeChannelStartSample==segment.StartSample && ...
        replay.RuntimeChannelEndSample==segment.EndSampleExclusive && ...
        string(replay.ChannelModelApplied)==string(trial.ChannelModelApplied) && ...
        double(replay.ChannelFadingApplied)==double(trial.ChannelFadingApplied) && ...
        string(replay.ChannelFadingExecutionStatus)==string(trial.ChannelFadingExecutionStatus));
    cursor=min(segment.EndSampleExclusive,post.EndSampleExclusive); count=count+1;
end
assert(post.isComplete() && cursor==post.EndSampleExclusive && count>0 && ...
    trial.ChannelExecutionSegmentCount==count && trial.ChannelExecutionDesiredSegmentCount==count);
% Use the real finalized row; the database key is explicitly unavailable.
base=struct(); base.(channel+"_table")=trial;
meta=struct('logical_run_id',string(trial.RunTag),'run_id',NaN);
published=sixgr.truth.buildLLSPublicOutputTables(base,sixgr.truth.llsOutputContract(),meta);
public=published.(channel+"_runtime_event_table");
retained=[stages summaries "Status" "Crash" "FinalizedFlag" "PartialRowFlag" "CountsTowardCoverage" ...
    "PDCCHReceiverDecodeOk" "PDCCHDataAdmissionOk" "PDCCHTCIAdmissionStatus"];
retained=[retained string(fieldnames(sixgr.truth.projectMCSTransitionEvidence())).'];
retained=[retained "CRCOutcome" "ScheduledMCS" "ScheduledMCSIndex" "ScheduledModulation" ...
    "ScheduledOperatingPointSource" "ScheduledOperatingPointEvidenceStatus" ...
    "ScheduledOperatingPointMatchesTransmitted" "LinkAdaptationScheduled"];
if direction=="DL"
    retained=[retained "DLSCHFinalOutcomeAvailable" "DLSCHFinalOutcomeStage" ...
        "DLSCHFinalOutcomeJSON" "DLSCHFinalOutcomeSHA256" "DLSCHSuccessfulDecodedBits" ...
        "DLSCHSuccessfulDecodedBitsScope" "DLSCHAggregateGoodBitsPolicy" ...
        "SharedDLSCHOutcomeAvailable" "SharedDLSCHOutcomeStage" "SharedDLSCHOutcomeJSON" ...
        "SharedDLSCHOutcomeSHA256" "SharedDLSCHOutcomeTransmissionID" ...
        "SharedDLSCHOutcomeDecoderSHA256" "SharedDLSCHOutcomeTransportCreditBound"];
end
assert(height(public)==1 && public.Slot==trial.Slot);
for name=retained
    assert(isequaln(public.(name),trial.(name)), ...
        'Public projection changed or dropped actual receiver evidence %s.',name);
end
sixgr.util.csvWriteTable(localContinuationArtifact(state,"received_"+lower(direction)+"_public_runtime.csv"), ...
    public,'PreserveSchema',true,'RoundTripNumericText',true);
end

function state=localDrainContinuationData(state)
% Match the production post-batch boundary: no decoder/feedback re-entry.
plans=sixgr.util.structGet(state,'SharedCompletedDataPlans',{});
dl=sixgr.util.structGet(state,'TestPublishedDLTrials',table());
ul=sixgr.util.structGet(state,'TestPublishedULTrials',table());
dc=sixgr.util.structGet(state,'TestPublishedDLConstellations',table());
uc=sixgr.util.structGet(state,'TestPublishedULConstellations',table());
ds=sixgr.util.structGet(state,'TestPublishedDLStates',repmat({struct()},state.NumUsers,1));
us=sixgr.util.structGet(state,'TestPublishedULStates', ...
    sixgr.util.structGet(state,'SharedULLinkAdaptationStates',repmat({struct()},state.NumUsers,1)));
expectedDL=dl; expectedUL=ul; expectedDC=dc; expectedUC=uc; expectedDS=ds; expectedUS=us;
for k=1:numel(plans)
    p=plans{k}.Plan;
    if string(plans{k}.Direction)=="DL"
        expectedDL=sixgr.truth.PDCCHControlRuntime.appendCompatTable(expectedDL,p.TrialTable);
        expectedDC=sixgr.truth.PDCCHControlRuntime.appendCompatTable(expectedDC,p.ConstellationTable);
        expectedDS{p.UEIndex}=p.LinkAdaptationState;
    else
        expectedUL=sixgr.truth.PDCCHControlRuntime.appendCompatTable(expectedUL,p.TrialTable);
        expectedUC=sixgr.truth.PDCCHControlRuntime.appendCompatTable(expectedUC,p.ConstellationTable);
        expectedUS{p.UEIndex}=p.LinkAdaptationState;
    end
end
beforeRX=sixgr.util.structGet(state,'SharedDataRXCommittedIDs',strings(0,1));
beforeFeedback=sixgr.util.structGet(state,'SharedPUSCHHARQFeedbackReceipts',{});
beforeTX=state.SharedWaveformStream.DataTransmissions;
beforeDL=state.DLHarq.Stats; beforeUL=state.ULHarq.Stats;
beforeCredit=sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot( ...
    sixgr.util.structGet(state,'TransportGoodputLedger',[]));
[state,dl,ul,dc,uc,ds,us]=sixgr.truth.SharedDataCompletionRuntime.drain(state,dl,ul,dc,uc,ds,us);
assert(isempty(state.SharedCompletedDataPlans) && ...
    isequaln(dl,expectedDL) && isequaln(ul,expectedUL) && ...
    isequaln(dc,expectedDC) && isequaln(uc,expectedUC) && ...
    isequaln(ds,expectedDS) && isequaln(us,expectedUS) && ...
    isequaln(state.SharedULLinkAdaptationStates,us));
assert(isequaln(sixgr.util.structGet(state,'SharedDataRXCommittedIDs',strings(0,1)),beforeRX) && ...
    isequaln(sixgr.util.structGet(state,'SharedPUSCHHARQFeedbackReceipts',{}),beforeFeedback) && ...
    isequaln(state.SharedWaveformStream.DataTransmissions,beforeTX) && ...
    isequaln(sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot( ...
        sixgr.util.structGet(state,'TransportGoodputLedger',[])),beforeCredit) && ...
    isequaln(state.DLHarq.Stats,beforeDL) && isequaln(state.ULHarq.Stats,beforeUL), ...
    'Draining publication must not repeat TX, RX, HARQ, UCI or unique-TB credit commits.');
state.TestPublishedDLTrials=dl; state.TestPublishedULTrials=ul;
state.TestPublishedDLConstellations=dc; state.TestPublishedULConstellations=uc;
state.TestPublishedDLStates=ds; state.TestPublishedULStates=us;
state.TestCanonicalCompletionDrainVerified=true;
end

function localContinuationControlLog(level,format,varargin)
% Diagnostics only. This callback cannot alter admission or runtime state.
sixgr.util.safeFprintf(1,'CONTINUATION_CONTROL %s %s\n', ...
    char(string(level)),sprintf(char(string(format)),varargin{:}));
end

function localAssertSRSContinuationGrant(state,cfg,g,atSample)
a=g.AcceptedSRSSpatialDecision; context=g.AcceptedSRSDecisionContext;
prec=g.PHYGrant.PrecodingState; owner=state.SharedWaveformStream;
assert(isequaln(a,state.LatestULFeedback(g.UEIndex).AcceptedSRSSpatialDecision) && ...
    isequaln(a,g.PHYGrant.LegacyGrantSnapshot.AcceptedSRSSpatialDecision) && ...
    isequaln(a,prec.AcceptedSRSSpatialDecision) && ...
    isequaln(context,prec.AcceptedSRSDecisionContext));
assert(string(g.Direction)=="UL" && a.TargetId==g.UEIndex && a.RNTI==g.RNTI && ...
    a.ServingCell==g.ServingCell && a.RI==g.NumLayers && a.PMI==g.TPMI && ...
    a.SRSNumPorts==prec.NumLogicalPorts && prec.NumLayers==g.NumLayers && ...
    prec.TPMI==g.TPMI && ~prec.ModeledSRSDecisionUsed && ...
    prec.AuthoritativeSRSDecisionUsed && g.AcceptedSRSCausalUsable);
assert(context.Usable && context.KnownAtSample==atSample && ...
    context.KnownAtSlot==state.CurrentSlot && ...
    context.ConsumerSlot==sixgr.truth.runtimeULGrantSlot(g) && ...
    a.ResultCompletedAtSample<=a.ResultAvailableAtSample && a.ResultAvailableAtSample<=atSample && ...
    a.MeasurementClockEpoch==owner.Physical.ConfigurationEpoch && ...
    a.ObservationSampleRateHz==owner.SampleRateHz && ...
    a.MeasurementClockDomain=="shared_receiver_sample_clock/v1");
raw=state.ReferenceSignalMeasurementTable;
hit=find(string(raw.MeasurementId)==string(a.MeasurementId));
assert(isscalar(hit) && raw.Valid(hit) && raw.ProducerSlot(hit)==a.ProducerSlot && ...
    raw.RI(hit)==a.RI && raw.PMI(hit)==a.PMI, ...
    'The accepted source must join its actual published observation, not simply the newest raw SRS.');
[active,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,g.UEIndex,'UL');
sixgr.truth.validateAcceptedSRSConfiguration(active,a);
assert(string(g.SRSCurrentInstallation.ConfigurationContextID)== ...
    sixgr.truth.srsConfigurationContextID(active,owner.Physical.ConfigurationEpoch,g.UEIndex,g.ServingCell));
end

function state=localCompleteSRSApplicationPUSCH(state,item)
% Invoke the canonical receiver/commit owner once; everything else below
% verifies retained execution and publication, without a second decoder.
owner=state.SharedWaveformStream; c=item.Context; p=c.Prepared; job=c.Job;
controls=state.SharedReceivedGrantControls;
hit=find(cellfun(@(x)string(x.Key)==string(c.Key),controls)); assert(isscalar(hit));
control=controls{hit}; assert(control.Allowed && string(job.Direction)=="UL");
[post,~,tx,~,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
assert(control.AvailableAtSample<=post.EndSampleExclusive && ...
    control.AvailableAtSample<=p.StartSample && ...
    p.EndSampleExclusive<=state.TestSRSContinuationExpiry);
if ~state.TestRankTransitions || state.TestRankTransitionAttemptOrdinal==1
    assert(isempty(sixgr.util.structGet(state,'SharedGNBULHARQReceivers',{})), ...
        'The first normally scheduled UL attempt has no retained gNB prior.');
end
% Rebuild only the independent expectation for an assertion. It is never
% passed to the decoder; canonical complete owns its actual receive context.
[obligation,report,calendar]=sixgr.truth.resolveSharedPUSCHCSIReceiveObligation(state,job.Cfg,job.GrantSnapshot);
binding=sixgr.truth.puschUCIObservationBinding(job.GrantSnapshot,receiver);
expectedContext=sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,job.Cfg,job.GrantSnapshot,binding.ObservationID,obligation,report);
assert(isempty(report) && expectedContext.Data.HARQACKBitCount==0);
if ~isempty(calendar)
    symbols=job.GrantSnapshot.SymbolAllocation;
    assert(all(~calendar.ULResourceAvailable | ...
        symbols(1)>=calendar.StartSymbol+calendar.NumSymbols | ...
        calendar.StartSymbol>=sum(symbols)), ...
        'The configured CSI occasion must be disjoint, not silently removed from the receiver budget.');
end
issued=state.TestSRSContinuationGrant; accepted=state.TestSRSContinuationAccepted;
assert(isequaln(p.RequestBinding.PHYGrant.PrecodingState.AcceptedSRSSpatialDecision,accepted) && ...
    isequaln(job.GrantSnapshot.AcceptedSRSSpatialDecision,accepted) && ...
    isequaln(control.Grant.AcceptedSRSSpatialDecision,accepted) && ...
    string(p.RequestBinding.PHYGrant.GrantContextId)==string(issued.PHYGrant.GrantContextId));
beforeReceipts=numel(sixgr.util.structGet(state,'SharedPUSCHHARQFeedbackReceipts',{}));
beforeRX=sixgr.util.structGet(state,'SharedDataRXCommittedIDs',strings(0,1));
assert(isempty(sixgr.util.structGet(state,'SharedCompletedDataPlans',{})));
state=sixgr.truth.SharedDataCompletionRuntime.complete(state,item,@localContinuationControlLog);
plan=localContinuationCompletedPlan(state,item);
out=plan.Result; trial=plan.TrialTable;
save(localContinuationArtifact(state,'received_srs_ul_decoder.mat'),'item','control','plan','out','trial','-v7.3');
localAssertContinuationReceiverPublication(state,item,plan,control);
assert(height(trial)==1 && ~trial.Crash, ...
    'test:SRSApplicationReceiverCrash','Retained receiver failures are not measured CRC failures.');
assert(out.HARQ.UCIReceiveContextDigest==expectedContext.Digest && ...
    out.HARQ.PreviousLLRCount==0);
identity=c.TransmissionIdentity;
records=owner.DataTransmissions;
hit=arrayfun(@(r)string(r.Identity.TransmissionID)==string(identity.TransmissionID),records);
assert(nnz(hit)==1); receipt=records(hit);
ledger=state.SharedDataTXLedger;
hit=cellfun(@(r)string(r.Identity.TransmissionID)==string(identity.TransmissionID),ledger);
assert(nnz(hit)==1); committed=ledger{hit};
assert(isequaln(receipt.Identity,identity) && isequaln(committed.Identity,identity) && ...
    receipt.FirstActiveSample>=identity.StartSample && receipt.FirstActiveSample<identity.EndSampleExclusive && ...
    receipt.CommittedAtSample==receipt.FirstActiveSample+1 && ...
    committed.FirstActiveSample==receipt.FirstActiveSample && ...
    committed.CommittedAtSample==receipt.CommittedAtSample && ...
    receipt.CommittedAtSample<=owner.Events.NextSampleIndex && ...
    owner.Events.NextSampleIndex>=identity.EndSampleExclusive && tx.isComplete() && receiver.isComplete() && ...
    tx.StartSample==identity.StartSample && tx.EndSampleExclusive==identity.EndSampleExclusive && ...
    tx.SampleRateHz==identity.SampleRateHz && receiver.SampleRateHz==identity.SampleRateHz);
assert(isequaln(committed.Grant.PHYGrant.PrecodingState.AcceptedSRSSpatialDecision,accepted) && ...
    numel(committed.TransportBlockBits)==p.RequestBinding.Grant.TBSBits && ...
    numel(state.SharedDataRXCommittedIDs)==numel(beforeRX)+1 && ...
    nnz(string(state.SharedDataRXCommittedIDs)==string(identity.TransmissionID))==1);
receipts=state.SharedPUSCHHARQFeedbackReceipts;
assert(numel(receipts)==beforeReceipts+1 && ...
    receipts{end}.ObservationID==expectedContext.Data.ObservationID && ...
    receipts{end}.ReceiverContextDigest==expectedContext.Digest && ...
    receipts{end}.AvailableAtSample==owner.Events.NextSampleIndex);
assert(state.ULHarq.Stats.Tx==state.TestSRSContinuationInitialHARQ.Tx+1 && ...
    state.ULCompletedSlots==sixgr.truth.runtimeULGrantSlot(issued));
attempted=logical(trial.ULSCHDecodeAttempted);
crc=double(trial.CRCPass);
assert((attempted && any(crc==[0 1])) || (~attempted && isnan(crc)), ...
    'Unattempted data decoding has no measured CRC verdict.');
assert(out.HARQ.CombinedDecodeOK==(crc==1) && ...
    trial.TBSize_bits==numel(committed.TransportBlockBits) && ...
    trial.Layers==issued.NumLayers && trial.MCS==issued.MCSIndex && ...
    p.Tx.PUSCH.NumLayers==issued.NumLayers && ...
    p.RequestBinding.PHYGrant.CodingLayout.MCSIndex==issued.MCSIndex);
if crc==1
    assert(isequal(int8(out.HARQ.DecodedTransportBlockBits(:)),committed.TransportBlockBits));
end
assert(p.Tx.PrecodeInfo.AuthoritativeDCIDecisionUsed && ...
    ~p.Tx.PrecodeInfo.AuthoritativeSRSDecisionUsed && ...
    string(p.Tx.PrecodeInfo.DecodedDCIAssignmentDigest)== ...
    string(control.ReceivedAssignment.AssignmentDigest), ...
    'The gNB schedules from accepted SRS; the UE actual matrix must come from its decoded DCI.');
projection=double(receipt.WaveformToElementMatrix);
physical=projection*double(p.Tx.PrecodeInfo.MatrixPorts);
frozen=double(p.RequestBinding.PHYGrant.PrecodingState.MatrixPhysicalPorts);
assert(isequal(size(physical),size(frozen)) && ...
    norm(physical-frozen,'fro')<=1e-12*max(1,norm(frozen,'fro')));
actual=double(p.Tx.PUSCHWaveformSymbols)*projection.';
independent=double(p.Tx.PUSCHLayerSymbols)*physical.';
assert(isequal(size(actual),size(independent)) && ...
    norm(actual-independent,'fro')<=1e-10*max(1,norm(actual,'fro')));
componentReceipts=localVerifySRSApplicationEmission(owner,item,receipt);
application=struct('Source',"actual_shared_SRS_normal_UL_planner_received_PDCCH_completed_PUSCH", ...
    'AcceptedSRS',accepted,'ScheduledGrant',issued,'ReceivedControl',control, ...
    'ConfiguredCSICalendar',calendar,'UCIReceiveContext',expectedContext, ...
    'UEPrecodingAuthority',p.Tx.PrecodeInfo, ...
    'TransmissionReceipt',receipt,'LogicalMatrix',p.RequestBinding.PHYGrant.PrecodingState.MatrixLogicalPorts, ...
    'ExecutedComponentReceipts',componentReceipts, ...
    'PhysicalMatrix',physical,'ReceiverObservationID',string(item.ID), ...
    'ReceiverStartSample',receiver.StartSample,'ReceiverEndSampleExclusive',receiver.EndSampleExclusive, ...
    'ReceiverSampleRateHz',receiver.SampleRateHz,'ReceiverSampleSHA256',receiver.sampleHash(), ...
    'CompletedAtSample',owner.Events.NextSampleIndex,'DecodeAttempted',attempted,'CRCPass',crc, ...
    'WaveformApplicationVerified',true,'NaturalSchedulerRetryQualified',false, ...
    'FullScenarioQualified',false,'Scope',"single_coexistence_component_declared_connected_context_and_initial_TAG");
sixgr.util.csvWriteTable(localContinuationArtifact(state,'received_srs_later_pusch.csv'), ...
    trial,'PreserveSchema',true,'RoundTripNumericText',true);
sixgr.util.csvWriteTable(localContinuationArtifact(state,'received_srs_control.csv'), ...
    state.ControlTrials.PDCCH,'PreserveSchema',true,'RoundTripNumericText',true);
save(localContinuationArtifact(state,'received_srs_later_application.mat'), ...
    'application','out','trial','plan','-v7.3');
state.TestSRSContinuationApplication=application;
state.TestSRSContinuationCompleted=true;
state.TestPUSCHReceived=true;
fprintf('RECEIVED_SRS_ACTUAL_DATA_APPLICATION slot=%d source=%s layers=%d MCS=%d decode_attempted=%d CRC=%g\n', ...
    issued.Slot,string(accepted.MeasurementId),issued.NumLayers,issued.MCSIndex,attempted,crc);
end

function receipts=localVerifySRSApplicationEmission(owner,item,receipt)
% Validate existing successful execution; never regenerate a channel, RF
% contribution or decoder result. The TX observation can contain other
% simultaneous channels and is not itself the isolated PUSCH component.
p=item.Context.Prepared; projection=receipt.WaveformToElementMatrix;
assert(isequaln(projection,item.Context.WaveformToElementMatrix));
if string(p.RequestBinding.PHYGrant.AntennaArchitecture.WaveformDomain)=="element"
    assert(isequal(projection,eye(size(projection),'like',projection)));
    mapped=p.Tx.Waveform;
else
    mapped=p.Tx.Waveform*projection.';
end
sha=string(sixgr.phy.waveform.WaveformHash.numeric(mapped));
cursor=p.StartSample;
receipts=struct('StartSample',{},'EndSampleExclusive',{},'ComponentID',{}, ...
    'OriginalSampleSHA256',{},'NonzeroSampleCount',{});
for k=1:numel(owner.Events.ExecutionTrace)
    segment=owner.Events.ExecutionTrace{k};
    if segment.EndSampleExclusive<=p.StartSample || segment.StartSample>=p.EndSampleExclusive
        continue;
    end
    e=segment.Execution;
    assert(string(e.Source)=="composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf" && ...
        string(e.ApproximationMode)=="none" && e.ConfigurationEpoch==owner.Physical.ConfigurationEpoch && ...
        e.SampleRateHz==p.SampleRateHz && segment.StartSample<=cursor);
    roster=e.ExecutedContributors;
    hit=find(string({roster.TransmitterID})=="ue_"+item.UE); assert(isscalar(hit));
    entry=roster(hit); consumed=entry.Receipt;
    assert(consumed.Schema=="consumed_waveform_components/v1" && consumed.CompleteContributorList && ...
        consumed.StartSample==segment.StartSample && consumed.EndSampleExclusive==segment.EndSampleExclusive && ...
        consumed.SampleRateHz==p.SampleRateHz && entry.CommittedThroughSample>=segment.EndSampleExclusive);
    components=consumed.Components;
    hit=find(string({components.ComponentID})==string(item.ID)); assert(isscalar(hit));
    component=components(hit); stop=min(segment.EndSampleExclusive,p.EndSampleExclusive);
    assert(component.StartSample==cursor && component.EndSampleExclusive==stop && stop>cursor && ...
        string(component.OriginalSampleSHA256)==sha && ...
        component.NonzeroSampleCount==nnz(mapped(cursor-p.StartSample+1:stop-p.StartSample,:)), ...
        'test:SRSApplicationIncompleteEmission','Every original mapped component sample must execute exactly once.');
    receipts(end+1)=struct('StartSample',component.StartSample, ...
        'EndSampleExclusive',component.EndSampleExclusive,'ComponentID',string(component.ComponentID), ...
        'OriginalSampleSHA256',string(component.OriginalSampleSHA256), ...
        'NonzeroSampleCount',component.NonzeroSampleCount); %#ok<AGROW>
    cursor=stop;
end
assert(cursor==p.EndSampleExclusive && sum([receipts.NonzeroSampleCount])>0, ...
    'test:SRSApplicationIncompleteEmission','A started receipt cannot stand in for the full emitted PUSCH.');
end

function state=localContinueReceivedCSIToPDSCH(state,cfg,report,prefixLastSlot)
owner=state.SharedWaveformStream;
assert(height(report)==1 && report.CSIUCIDecodeOk && report.Processed);
capsule=sixgr.util.structGet(state.LatestDLFeedback(1),'CSIReportProvenance',struct());
if ~state.TestRankTransitions
    assert(~report.SchedulerSpatialDecisionDeferred && state.LatestDLFeedback(1).Valid, ...
        'test:CSIContinuationNotAdmitted','A decoded but held report cannot authorize this application test.');
    localAssertContinuationCapsule(capsule,report);
    assert(capsule.RunID==state.TestExecutionIdentity.RunID && ...
        capsule.ExecutionID==state.TestExecutionIdentity.ExecutionID && ...
        capsule.ConfigHash==state.TestExecutionIdentity.ConfigHash && ...
        capsule.ScenarioID==string(cfg.run.scenarioID), ...
        'test:CSIContinuationLifecycleMismatch','Keep the lifecycle installed before reception.');
    assert(capsule.ReceiverObservationBound && capsule.AvailableAtSample<=owner.Events.NextSampleIndex);
end
assert(~cfg.phy.pdsch.qclTCI.enabled && ...
    ~cfg.phy.pdcch.operatorControl.connected_dci.tci_present, ...
    'This fixture has received SSB/installed CORESET Type-A association, not activated Type-D TCI.');
state.TestContinuationAdmittedReport=report;
state.TestContinuationAdmittedCapsule=capsule;
if state.TestRankTransitions
    % Preserve the prefix outcome even when two-report confirmation holds
    % it. It is not promoted into authority for a subsequent application.
    state.TestContinuationAdmittedReport=table();
    state.TestContinuationAdmittedCapsule=struct();
end
prefixReport=report; prefixCapsule=capsule;
state.TestContinuationPrefixReport=prefixReport;
state.TestContinuationPrefixCapsule=prefixCapsule;
state.TestContinuationInitialDataCount=numel(owner.DataTransmissions);
% One explicitly offered payload. TBS, rank and MCS still come from MAC.
offeredBits=8*1024;
if state.TestRankTransitions
    offeredBits=cfg.traffic.fullBufferBitsPerTTI*(cfg.run.totalSlots-prefixLastSlot);
end
state.DLQueueBits(1)=state.DLQueueBits(1)+offeredBits;
state.TestContinuationOfferedBits=offeredBits;
carrier=sixgr.phy.grid.makeCarrier(cfg);
cycle=max([state.SlotsPerFrame,state.SRSSlotPeriod,cfg.phy.csi.reportPeriodicitySlots]);
expiry=state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive;
horizon=min(prefixLastSlot+2*cycle,floor(expiry/(owner.SampleRateHz*state.SlotDuration_s)));
if state.TestRankTransitions, horizon=cfg.run.totalSlots; end
assert(horizon>prefixLastSlot,'test:CSIContinuationNoTimingHorizon', ...
    'The declared TAG does not authorize extending this component horizon.');
issued=false; attempts=cell(0,1);
for slot=prefixLastSlot+1:horizon
    state=sixgr.truth.CoupledTruthRuntime.beginSlot( ...
        state,cfg,cfg,1,'DL',1,1,slot,horizon,cfg.channel.snr_dB);
    state=localDeliverContinuationReferences(state);
    state=localQueueContinuationTRS(state,cfg,slot);
    state=localQueueRankTransitionCSI(state,cfg,slot);
    % Replenish configured periodic occasions after completion/suppression,
    % never treating cancellation as a fresh measurement. Keep one prepared
    % SRS at a time and wait for any actual completed result's delivery.
    if (state.TestRankTransitions || ~issued) && ~owner.hasPending("SRS",1) && isempty(state.TestContinuationReferences)
        for source=slot+1:horizon
            if ismember(source,state.TestContinuationQueuedSRSSlots), continue; end
            if ~sixgr.truth.coupledSRSResourceOpportunity(cfg,source,1,1, ...
                    state.SRSSlotPeriod,cfg.phy.srs.schedulingPolicy,cfg.phy.srs.maxUEsPerSlot)
                continue;
            end
            [~,allowed]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,source);
            if ~allowed, continue; end
            localQueueSRS(state,cfg,source);
            state.TestContinuationQueuedSRSSlots(end+1,1)=source;
            break;
        end
    end
    state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
    if ~issued && state.CurrentSlotDLAllowed && localRankTransitionSourceReady(state,"DL")
        probe=struct('Direction',"DL",'ControlAbsoluteSlot',slot-1, ...
            'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
            'SymbolAllocation',cfg.phy.pdsch.symbolAllocation,'HARQProcess',0);
        timing=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
        if timing.Valid && double(timing.DataAbsoluteSlot)==slot-1
            before=owner.Events.NextSampleIndex;
            assert(before==sixgr.phy.frame.slotStartSample(carrier,slot-1,owner.SampleRateHz));
            % Periodic CSI keeps running during the legal/gated wait. Use
            % the actually admitted current capsule, not the prefix report
            % and not simply the newest raw row (which may be deferred).
            [report,capsule]=localCurrentContinuationReport(state,before);
            if isempty(attempts), localVerifyAdmittedCSIReportLookup(state,before); end
            [state,grants,info]=sixgr.truth.CoupledTruthRuntime.scheduleDirection(state,cfg,'DL');
            attempts{end+1,1}=struct('RuntimeSlot',slot,'AtSample',before,'Info',info, ...
                'ReportIdentity',report.ReportIdentity,'ObservationID',report.ObservationID, ...
                'ReportAvailableAtSample',report.AvailableAtSample); %#ok<AGROW>
            assert(owner.Events.NextSampleIndex==before,'Scheduling must not execute the physical channel.');
            if ~isempty(grants)
                assert(isscalar(grants) && ~sixgr.phy.grant.isExplicitHARQRetransmission(grants), ...
                    'test:CSIContinuationNeedsNewData','Do not relabel an old HARQ attempt as new CSI application.');
                g=grants;
                localAssertContinuationCapsule(g.CSIReportProvenance,report);
                assert(g.CSIReportProvenance.ReceiverObservationBound && ...
                    g.CSIReportDecisionContext.AtSample==before && ...
                    report.AvailableAtSample<=before && g.ControlEligible && g.SchedulingEligible && ...
                    g.ControlAbsoluteSlot==slot-1 && g.ScheduledAbsoluteSlot==slot-1 && g.Slot==slot);
                assert(isequaln(g.PHYGrant.LegacyGrantSnapshot.CSIReportProvenance,g.CSIReportProvenance));
                [state,issued]=localQueueCSIApplicationGrant(state,cfg,g);
                if issued
                    state.TestContinuationAdmittedReport=report;
                    state.TestContinuationAdmittedCapsule=capsule;
                    if state.TestRankTransitions
                        state.TestRankTransitionAttemptOrdinal=state.TestRankTransitionAttemptOrdinal+1;
                        state.TestRankTransitionAttemptHARQ=state.DLHarq.Stats;
                    end
                    fprintf('CSI_APPLICATION_SELECTED_REPORT prefix=%s selected=%s available=%g decision=%g\n', ...
                        string(prefixReport.ReportIdentity),string(report.ReportIdentity),report.AvailableAtSample,before);
                end
            end
        end
    end
    state=owner.advanceSlot(state,cfg,@localEvents);
    state=localDrainContinuationData(state);
    if state.TestRankTransitions
        [state,stop,rearm]=localRankTransitionAfterSlot(state,"DL");
        if rearm, issued=false; end
        if stop, break; end
    elseif state.TestContinuationRejected
        break;
    elseif state.TestContinuationCompleted
        if logical(sixgr.util.structGet(cfg,'phy.linkAdaptation.mcsTransition.enabled',false))
            [state,feedbackReceived]=localVerifyMCSTransitionReceivedFeedback(state);
            if feedbackReceived, break; end
        else
            break;
        end
    end
end
state.TestContinuationSchedulingAttempts=attempts;
save(fullfile(state.TestRoot,'received_csi_application_admission.mat'), ...
    'attempts','report','capsule','prefixReport','prefixCapsule','horizon');
if state.TestRankTransitions
    assert(state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive==expiry);
    assert(numel(owner.DataTransmissions)>=state.TestContinuationInitialDataCount+ ...
        numel(state.TestRankTransitionApplications));
    return;
end
assert(issued && state.TestContinuationCompleted,'test:CSIContinuationNotExercised', ...
    'No completed admitted-CSI new-data application in the unchanged legal/gated horizon; inspect admission evidence.');
assert(numel(owner.DataTransmissions)==state.TestContinuationInitialDataCount+1);
assert(state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive==expiry);
if logical(sixgr.util.structGet(cfg,'phy.linkAdaptation.mcsTransition.enabled',false))
    assert(sixgr.util.structGet(state,'TestMCSTransitionFeedbackVerified',false), ...
        'test:MCSFeedbackNotExercised','Require actual received feedback for the bounded-MCS transmission.');
end
fprintf('RECEIVED_CSI_TO_SCHEDULED_PDSCH_PASS scheduler=PF actual_PUCCH=1 actual_PDCCH=1 canonical_control=1 completed_PDSCH=1 activated_TCI=0 full_scenario=0\n');
end

function [state,done]=localVerifyMCSTransitionReceivedFeedback(state)
% Join the policy credit to original transmitted data and independently
% received UCI. Continuing the shared clock never authors an ACK or NACK.
done=false;
F=sixgr.util.structGet(state,'SharedGNBUCIHARQTable',table());
if isempty(F), return; end
g=state.TestContinuationIssuedGrant;
hit=F.SourceSlot==g.Slot & F.RNTI==g.RNTI & F.HarqID==g.HARQ.HarqID & ...
    string(F.PHYGrantContextId)==string(g.PHYGrant.GrantContextId);
if ~any(hit), return; end
assert(nnz(hit)==1); r=F(hit,:);
assert(r.HARQFeedbackApplied && ~r.StaleFeedbackIgnored && r.ReceiverUsable && ...
    any(string(r.FeedbackOutcome)==["ACK","NACK"]) && ...
    r.AvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex);
policy=state.DLSchedulers{1}.getMCSTransitionState();
found=false;
for k=1:numel(policy.Entries)
    entry=policy.Entries{k};
    for j=1:numel(entry.Transmissions)
        tx=entry.Transmissions{j};
        if tx.Slot~=g.Slot || tx.HarqID~=g.HARQ.HarqID, continue; end
        assert(tx.MCS==g.MCSIndex && entry.LastMCS==g.MCSIndex && ...
            any(entry.SeenFeedback==tx.ID));
        if string(r.FeedbackOutcome)=="ACK", assert(any(entry.ACKs==tx.ID));
        else, assert(any(entry.NACKs==tx.ID)); end
        found=true;
    end
end
assert(found,'test:MCSFeedbackPolicyBinding','Actual UCI must update the transmitted operating point.');
state.TestMCSTransitionFeedbackVerified=true;
state.TestMCSTransitionFeedback=table2struct(r);
state.TestMCSTransitionState=policy;
sixgr.util.csvWriteTable(localContinuationArtifact(state,'mcs_transition_received_harq.csv'),r,'PreserveSchema',true);
sixgr.util.jsonWrite(localContinuationArtifact(state,'mcs_transition_committed_state.json'),policy);
fprintf('MCS_TRANSITION_PHYSICAL_FEEDBACK_PASS source_slot=%d outcome=%s actual_MCS=%d\n', ...
    g.Slot,string(r.FeedbackOutcome),g.MCSIndex);
done=true;
end

function [report,capsule]=localCurrentContinuationReport(state,decisionSample)
capsule=state.LatestDLFeedback(1).CSIReportProvenance;
reports=state.SharedGNBCSIReportTable;
hit=find(string(reports.ReportIdentity)==string(capsule.ReportIdentity) & ...
    string(reports.ObservationID)==string(capsule.ObservationID));
assert(isscalar(hit),'test:CSIContinuationNotAdmitted', ...
    'Current scheduler feedback must identify exactly one retained received report.');
report=reports(hit,:);
assert(report.CSIUCIDecodeOk && report.Processed && ...
    ~report.SchedulerSpatialDecisionDeferred && string(report.SourceSignal)=="received_CSI_UCI", ...
    'test:CSIContinuationNotAdmitted','A raw or held report cannot replace accepted feedback.');
owner=state.SharedWaveformStream;
clock=struct('ClockDomain',"shared_receiver_sample_clock/v1", ...
    'ClockEpoch',owner.Physical.ConfigurationEpoch,'SampleRateHz',owner.SampleRateHz, ...
    'AtSample',decisionSample);
checked=sixgr.truth.captureReceivedCSIProvenance(table2struct(report),clock);
assert(isequaln(checked,capsule),'test:CSIContinuationLineageMismatch', ...
    'Keep the exact receiver capsule and causal decision clock; do not reconstruct feedback.');
localAssertContinuationCapsule(capsule,report);
end

function localVerifyAdmittedCSIReportLookup(state,atSample)
% Rejection probes on value copies of the actual admitted state. No physical
% owner/clock mutation, RF execution, or fabricated primary publication.
[report,capsule]=localCurrentContinuationReport(state,atSample);
rows=state.SharedGNBCSIReportTable;
hit=find(string(rows.ReportIdentity)==string(report.ReportIdentity) & ...
    string(rows.ObservationID)==string(report.ObservationID));
bad=state; bad.SharedGNBCSIReportTable(hit,:)=[];
localReject(@()localCurrentContinuationReport(bad,atSample),'test:CSIContinuationNotAdmitted');
bad=state; bad.SharedGNBCSIReportTable=[rows;rows(hit,:)];
localReject(@()localCurrentContinuationReport(bad,atSample),'test:CSIContinuationNotAdmitted');
for field=["Processed","CSIUCIDecodeOk","SchedulerSpatialDecisionDeferred"]
    bad=state;
    bad.SharedGNBCSIReportTable.(field)(hit)=field=="SchedulerSpatialDecisionDeferred";
    localReject(@()localCurrentContinuationReport(bad,atSample),'test:CSIContinuationNotAdmitted');
end
bad=state; bad.SharedGNBCSIReportTable.ReceiverContextDigest(hit)="declared_mismatch_probe";
localReject(@()localCurrentContinuationReport(bad,atSample),'test:CSIContinuationLineageMismatch');
bad=state; bad.SharedGNBCSIReportTable.AvailableAtSample(hit)=atSample+1;
bad.LatestDLFeedback(1).CSIReportProvenance.AvailableAtSample=atSample+1;
localReject(@()localCurrentContinuationReport(bad,atSample),'sixgr:truth:FutureCSIProvenance');
bad=state; bad.SharedGNBCSIReportTable.ReceiverClockEpoch(hit)=capsule.ReceiverClockEpoch+1;
bad.LatestDLFeedback(1).CSIReportProvenance.ReceiverClockEpoch=capsule.ReceiverClockEpoch+1;
localReject(@()localCurrentContinuationReport(bad,atSample),'sixgr:truth:CSIProvenanceClockMismatch');
% A newer raw/deferred row cannot replace the scheduler's admitted capsule.
deferred=rows(hit,:);
deferred.ReportIdentity=string(deferred.ReportIdentity)+"_declared_deferred_probe";
deferred.ObservationID=string(deferred.ObservationID)+"_declared_deferred_probe";
deferred.DueSlot=deferred.DueSlot+1; deferred.SchedulerSpatialDecisionDeferred=true;
probe=state; probe.SharedGNBCSIReportTable=[rows;deferred];
[selected,selectedCapsule]=localCurrentContinuationReport(probe,atSample);
assert(isequaln(selected,report) && isequaln(selectedCapsule,capsule));
fprintf('CSI_ADMITTED_LOOKUP_NEGATIVES_PASS missing_duplicate_raw_future_clock=1 deferred_not_selected=1 additional_RF_executions=0\n');
end

function localAssertContinuationCapsule(capsule,report)
for field=["Direction","UEIndex","RNTI","ServingCell","ReportIdentity","ObservationID", ...
        "CSIReportConfigID","CSIConfigurationEpoch","SourceSlot","DueSlot","DeliveredSlot", ...
        "SourceSlotAuthority", ...
        "ReceiverContextDigest","ReceiverClockEpoch","ReceiverClockDomain", ...
        "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
        "AvailableAtSample","CQI","RI","PMI","LI","CRI", ...
        "PMI_I11","PMI_I12","PMI_I13","PMI_I2","CSIUCIDecodedBitsToken", ...
        "RunID","ExecutionID","ConfigHash","ScenarioID","RandomSeed","ChannelSeed", ...
        "SweepPointIndex","ConfiguredSNR_dB","PopulationIdentitySource"]
    assert(isequaln(capsule.(field),report.(field)), ...
        'test:CSIContinuationLineageMismatch','Later grant lost the admitted receiver %s.',field);
end
for forbidden=["UEReferenceRecordJSON","CSIDeliveryAuditJSON","CSIMeasurementID"]
    assert(~isfield(capsule,forbidden),'Private UE evidence must not enter a scheduled grant.');
end
end

function [state,issued]=localQueueCSIApplicationGrant(state,cfg,g)
owner=state.SharedWaveformStream;
issued=false; beforePHY=g.PHYGrant;
beforeClock=owner.Events.NextSampleIndex;
beforeLedger=state.ScheduledDLDAILedger;
beforeTX=owner.DataTransmissions; beforeHARQTX=state.DLHarq.Stats.Tx;
beforeReceived=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
emptyUL=repmat(struct(),0,1);
[g,emptyUL]=sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg},g,emptyUL);
assert(isempty(emptyUL) && isequaln(state.ScheduledDLDAILedger,beforeLedger));
[state,qualified,queued]=sixgr.truth.PDCCHControlRuntime.queueShared( ...
    state,{cfg},g,'DL',cfg.channel.snr_dB,@localContinuationControlLog);
assert(isempty(qualified) && owner.Events.NextSampleIndex==beforeClock && ...
    isequaln(owner.DataTransmissions,beforeTX) && state.DLHarq.Stats.Tx==beforeHARQTX && ...
    isequaln(sixgr.util.structGet(state,'SharedReceivedGrantControls',{}),beforeReceived), ...
    'Admission/queued control is not a received assignment or emitted data TB.');
if isempty(queued)
    % The canonical owner cancels blocked tentative HARQ grants. Do not
    % queue data or stop seeking a legal opportunity for an unissued DCI.
    return;
end
assert(isscalar(queued) && isequaln(queued.PHYGrant.PrecodingState,beforePHY.PrecodingState) && ...
    isequaln(queued.CSIReportProvenance,g.CSIReportProvenance));
g=queued; % Actual queued DAI/control context, never the tentative grant.
beforeTX=owner.DataTransmissions; beforeHARQ=state.DLHarq.Stats;
beforeReceived=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
la=sixgr.util.structGet(state,'TestPublishedDLStates',repmat({struct()},state.NumUsers,1));
state=sixgr.truth.queueSharedDataPlans(state,cfg,state.MultiUser,{cfg},g, ...
    'DL',cfg.channel.snr_dB,g.Frame,la);
key=sixgr.truth.GrantPreparation.sharedGrantControlKey(g,'DL');
pending=owner.Pending(string({owner.Pending.Kind})=="PDSCH");
hit=find(arrayfun(@(x)string(x.Context.Key)==key,pending)); assert(isscalar(hit));
preparedContext=pending(hit).Context;
assert(isequaln(owner.DataTransmissions,beforeTX) && isequaln(state.DLHarq.Stats,beforeHARQ) && ...
    isequaln(sixgr.util.structGet(state,'SharedReceivedGrantControls',{}),beforeReceived) && ...
    preparedContext.Job.PrepareOnly && ...
    isequaln(beforePHY.PrecodingState,preparedContext.Job.PHYGrant.PrecodingState) && ...
    string(preparedContext.Job.PHYGrant.GrantContextId)==string(g.PHYGrant.GrantContextId), ...
    'Canonical preparation may queue one waveform, not emit a TB or manufacture received control.');
state.TestContinuationIssuedGrant=g;
state.TestContinuationControlKey=key;
issued=true;
end

function state=localCompleteCSIApplicationControl(state,item)
% One canonical decoder, binding/admission reducer and publication. Inspect
% the retained result; never manufacture an Allowed flag or decode again.
c=item.Context; owner=state.SharedWaveformStream;
issued=state.TestContinuationIssuedGrant;
assert(string(c.Key)==string(state.TestContinuationControlKey) && ...
    string(c.Direction)=="DL" && isequaln(c.Grant,issued));
beforeRows=height(state.ControlTrials.PDCCH);
beforeControls=numel(sixgr.util.structGet(state,'SharedReceivedGrantControls',{}));
beforeHARQTX=state.DLHarq.Stats.Tx;
state=sixgr.truth.PDCCHControlRuntime.completeShared(state,item,@localContinuationControlLog);
controls=state.SharedReceivedGrantControls;
hit=find(cellfun(@(x)string(x.Key)==string(c.Key),controls));
assert(isscalar(hit) && numel(controls)==beforeControls+1 && ...
    height(state.ControlTrials.PDCCH)==beforeRows+1 && state.DLHarq.Stats.Tx==beforeHARQTX);
control=controls{hit}; trial=state.ControlTrials.PDCCH(end,:);
[post,~,~,~,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,c.Prepared);
assert(trial.UEIndex==item.UE && trial.RNTI==c.RNTI && ...
    trial.ServingCell==c.ServingCell && string(trial.Direction)=="DL" && ...
    trial.Slot==c.Slot && trial.ObservationStartSample==post.StartSample && ...
    trial.ObservationEndSampleExclusive==post.EndSampleExclusive && ...
    control.AvailableAtSample==post.EndSampleExclusive && ...
    post.EndSampleExclusive<=owner.Events.NextSampleIndex && receiver.isComplete() && ...
    string(control.Grant.PHYGrant.GrantContextId)==string(issued.PHYGrant.GrantContextId) && ...
    isequaln(control.Grant.CSIReportProvenance,issued.CSIReportProvenance));
if control.Allowed
    assert(trial.PDCCHReceiverDecodeOk==1 && trial.PDCCHDataAdmissionOk==1 && ...
        control.Grant.PDCCHGrantBindingOk && control.ReceivedAssignment.Direction=="DL" && ...
        control.ReceivedAssignment.PayloadHash==string(control.Grant.PDCCHGrantDCIId));
    % Received CCE/AL/candidate must form the receiver's own coherent
    % hypothesis; it need not equal the transmitter's candidate or AL.
    received=sixgr.truth.bindReceivedPDCCHGrantContext(control.Grant,trial);
    for name=["PDCCHGrantFirstCCE","PDCCHGrantNumCCE", ...
            "PDCCHGrantAggregationLevel","PDCCHGrantCandidateIndex"]
        assert(isequaln(received.(name),control.Grant.(name)));
    end
end
state.TestContinuationReceivedControl=control;
state.TestContinuationControlTrial=trial;
sixgr.util.csvWriteTable(localContinuationArtifact(state,'received_csi_later_pdcch.csv'), ...
    trial,'PreserveSchema',true);
save(localContinuationArtifact(state,'received_csi_later_pdcch.mat'), ...
    'item','control','trial','issued','-v7.3');
end

function state=localCompleteCSIApplicationPDSCH(state,item)
% Actual later data decode, not a reconstructed or replacement MAC grant.
owner=state.SharedWaveformStream; p=item.Context.Prepared;
[~,~,tx,~,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
control=state.TestContinuationReceivedControl;
issued=state.TestContinuationIssuedGrant;
report=state.TestContinuationAdmittedReport;
if ~control.Allowed
    % Preserve the production distinction between an actual control miss
    % (no PDSCH decode) and a decoded assignment rejected by integration.
    beforeRX=sixgr.util.structGet(state,'SharedDataRXCommittedIDs',strings(0,1));
    beforePlans=sixgr.util.structGet(state,'SharedCompletedDataPlans',{});
    beforeNoDecode=sixgr.util.structGet(state,'SharedDataNoDecodeCommittedIDs',strings(0,1));
    state=sixgr.truth.SharedDataCompletionRuntime.complete(state,item,@localContinuationControlLog);
    assert(isequaln(sixgr.util.structGet(state,'SharedDataRXCommittedIDs',strings(0,1)),beforeRX) && ...
        isequaln(sixgr.util.structGet(state,'SharedCompletedDataPlans',{}),beforePlans) && ...
        numel(state.SharedDataNoDecodeCommittedIDs)==numel(beforeNoDecode)+1 && ...
        nnz(state.SharedDataNoDecodeCommittedIDs==item.Context.TransmissionIdentity.TransmissionID)==1);
    disposition=state.SharedDLNoDecodeDispositionTable(end,:);
    save(localContinuationArtifact(state,'received_csi_later_pdsch_no_decode.mat'), ...
        'item','control','issued','report','disposition','-v7.3');
    state.TestContinuationRejected=true;
    return;
end
assert(~control.ReceivedAssignment.TCIPresent && ...
    isfield(control.ReceivedAssignment,'ReceivedCORESETQCLReference'));
assert(control.ReceivedAssignment.ControlAbsoluteSlot==issued.ControlAbsoluteSlot && ...
    control.ReceivedAssignment.DataAbsoluteSlot==issued.ScheduledAbsoluteSlot && ...
    control.ReceivedAssignment.NumLayers==issued.NumLayers && ...
    control.ReceivedAssignment.MCS==issued.MCSIndex && ...
    string(control.Grant.PHYGrant.GrantContextId)==string(issued.PHYGrant.GrantContextId));
localAssertContinuationCapsule(control.Grant.CSIReportProvenance,report);
assert(report.AvailableAtSample<=issued.CSIReportDecisionContext.AtSample && ...
    issued.CSIReportDecisionContext.AtSample<control.AvailableAtSample && ...
    control.AvailableAtSample<=receiver.EndSampleExclusive && ...
    receiver.EndSampleExclusive<=owner.Events.NextSampleIndex);
assert(iscell(state.SharedUEDLHARQEntities) && ...
    isa(state.SharedUEDLHARQEntities{1},'sixgr.link.ReceivedDLHARQState'), ...
    'Keep the same actual UE HARQ receiver entity across the two data receptions.');
beforeRX=sixgr.util.structGet(state,'SharedDataRXCommittedIDs',strings(0,1));
assert(isempty(sixgr.util.structGet(state,'SharedCompletedDataPlans',{})));
beforeCredit=sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot( ...
    sixgr.util.structGet(state,'TransportGoodputLedger',[]));
state=sixgr.truth.SharedDataCompletionRuntime.complete(state,item,@localContinuationControlLog);
plan=localContinuationCompletedPlan(state,item);
out=plan.Result; trial=plan.TrialTable;
save(localContinuationArtifact(state,'received_csi_later_pdsch_receiver.mat'), ...
    'item','out','trial','plan','control','issued','report','beforeCredit','-v7.3');
localAssertSharedDLSCHOutcome(state,item,control,plan,beforeCredit);
localAssertContinuationReceiverPublication(state,item,plan,control);
assert(height(trial)==1 && ~trial.Crash && string(trial.Status)~="CRASH", ...
    'test:CSIContinuationDataReceiverCrash','A receiver exception is not a measured decoding failure.');
assert(isfinite(trial.CRCPass) && any(trial.CRCPass==[0 1]) && ...
    numel(state.SharedDataRXCommittedIDs)==numel(beforeRX)+1);
localAssertReceiverCFOEvidence(trial);

identity=sixgr.truth.preparedDataTransmissionIdentity(p,item.UE);
records=owner.DataTransmissions;
hit=arrayfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,records);
assert(nnz(hit)==1); receipt=records(hit);
assert(isequaln(identity,item.Context.TransmissionIdentity) && isequaln(receipt.Identity,identity) && ...
    identity.PHYGrantContextId==string(issued.PHYGrant.GrantContextId) && ...
    receipt.FirstActiveSample>=identity.StartSample && ...
    receipt.FirstActiveSample<identity.EndSampleExclusive && ...
    receipt.CommittedAtSample>=receipt.FirstActiveSample+1 && ...
    receipt.CommittedAtSample<=owner.Events.NextSampleIndex && ...
    owner.Events.NextSampleIndex>=identity.EndSampleExclusive && ...
    tx.isComplete() && receiver.isComplete() && ...
    tx.StartSample==identity.StartSample && tx.EndSampleExclusive==identity.EndSampleExclusive && ...
    tx.SampleRateHz==identity.SampleRateHz && receiver.SampleRateHz==identity.SampleRateHz);
ledgers=state.SharedDataTXLedger;
hit=cellfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,ledgers);
assert(nnz(hit)==1); committed=ledgers{hit};
assert(isequaln(committed.Identity,identity) && ...
    isequaln(committed.Grant.PHYGrant.PrecodingState,issued.PHYGrant.PrecodingState) && ...
    isequaln(p.RequestBinding.PHYGrant.PrecodingState,issued.PHYGrant.PrecodingState) && ...
    nnz(state.SharedDataRXCommittedIDs==identity.TransmissionID)==1 && ...
    numel(committed.TransportBlockBits)==issued.TBSBits);
localAssertContinuationCapsule(committed.Grant.CSIReportProvenance,report);
[matrices,weights]=localVerifyCSIApplicationMatrices(state,p,receipt);
completedEvidence=sixgr.truth.buildCompletedCSIApplicationEvidence(state,item,control,out);
assert(testCompletedCSIApplicationEvidence(state,item,control,out));
assert(isequaln(sixgr.truth.bindCompletedCSIApplicationEvidence(trial,completedEvidence),trial), ...
    'The canonical finalized row must already contain this exact completed CSI receipt.');
application=struct('Source',"actual_shared_received_CSI_then_scheduled_control_and_completed_data", ...
    'Scheduler',string(class(state.DLSchedulers{1})), ...
    'Report',table2struct(report),'OriginalProvenance',state.TestContinuationAdmittedCapsule, ...
    'Grant',issued,'ReceivedControl',control, ...
    'ControlTrial',table2struct(state.TestContinuationControlTrial),'TransmissionReceipt',receipt, ...
    'Matrices',matrices,'ReceiverObservationID',string(item.ID), ...
    'ReceiverStartSample',receiver.StartSample,'ReceiverEndSampleExclusive',receiver.EndSampleExclusive, ...
    'ReceiverSampleRateHz',receiver.SampleRateHz,'ReceiverSampleSHA256',receiver.sampleHash(), ...
    'CompletedAtSample',owner.Events.NextSampleIndex, ...
    'CRCPass',logical(trial.CRCPass),'WaveformApplicationVerified',true, ...
    'ActivatedTypeDTCIQualified',false,'FullScenarioQualified',false, ...
    'Scope',"single_PF_component_with_declared_initial_TAG_and_received_absent_TCI_CORESET_association");
% Retain the original frozen-only application capsule without promoting it.
assert(~issued.CSIReportApplication.WaveformApplicationVerified);
sixgr.util.csvWriteTable(localContinuationArtifact(state,'received_csi_later_pdsch.csv'), ...
    trial,'PreserveSchema',true);
sixgr.util.csvWriteTable(localContinuationArtifact(state,'received_csi_later_applied_weights.csv'), ...
    weights,'PreserveSchema',true);
save(localContinuationArtifact(state,'received_csi_later_application.mat'), ...
    'application','completedEvidence','out','trial','plan','-v7.3');
state.TestContinuationApplication=application;
state.TestContinuationCompleted=true;
fprintf('RECEIVED_CSI_ACTUAL_DATA_APPLICATION slot=%d report=%s layers=%d MCS=%d CRC=%d\n', ...
    issued.Slot,char(report.ReportIdentity),issued.NumLayers,issued.MCSIndex,trial.CRCPass);
end

function localAssertSharedDLSCHOutcome(state,item,control,plan,beforeCredit)
% Inspect the completed owner receipt only: no second decoder or credit call.
t=plan.TrialTable; out=plan.Result; p=item.Context.Prepared;
assert(t.SharedDLSCHOutcomeAvailable && t.DLSCHFinalOutcomeAvailable && ...
    string(t.SharedDLSCHOutcomeStage)=="completed_shared_decoder_transport_credit_binding" && ...
    string(t.SharedDLSCHOutcomeSHA256)==string(sixgr.util.sha256Hex(char(t.SharedDLSCHOutcomeJSON))) && ...
    string(t.DLSCHFinalOutcomeSHA256)==string(sixgr.util.sha256Hex(char(t.DLSCHFinalOutcomeJSON))));
for name=["DLSCHFinalOutcomeAvailable","DLSCHFinalOutcomeStage","DLSCHFinalOutcomeJSON", ...
        "DLSCHFinalOutcomeSHA256","DLSCHSuccessfulDecodedBits", ...
        "DLSCHSuccessfulDecodedBitsScope","DLSCHAggregateGoodBitsPolicy"]
    assert(isequaln(t.(name),out.TrialTable.(name)), ...
        'Shared publication must preserve the original decoder capsule, not re-sign final row coordinates.');
end
e=jsondecode(char(t.SharedDLSCHOutcomeJSON)); d=jsondecode(char(t.DLSCHFinalOutcomeJSON));
identity=sixgr.truth.preparedDataTransmissionIdentity(p,item.UE); s=e.SourceIdentity;
assert(string(e.Version)=="shared_dlsch_outcome_binding/v1" && ...
    string(e.DecoderSHA256)==string(t.DLSCHFinalOutcomeSHA256) && ...
    string(t.SharedDLSCHOutcomeDecoderSHA256)==string(t.DLSCHFinalOutcomeSHA256) && ...
    string(s.TransmissionIdentity.TransmissionID)==identity.TransmissionID && ...
    string(t.SharedDLSCHOutcomeTransmissionID)==identity.TransmissionID && ...
    string(s.TransmissionIdentity.PHYGrantContextId)==identity.PHYGrantContextId && ...
    string(s.LogicalGrantContextID)==string(t.GrantContextId) && ...
    string(s.ReceiverWindowID)==string(item.ID) && string(s.ControlKey)==string(control.Key) && ...
    string(s.ReceivedAssignmentDigest)==string(control.ReceivedAssignment.AssignmentDigest) && ...
    s.SourceSlot==p.RequestBinding.StartSlotIndex && s.SourceSlot==t.Slot && ...
    s.SourceFrame==p.RequestBinding.StartFrameIndex && s.SourceFrame==t.Frame && ...
    e.ReceivedTiming.DataAbsoluteSlot==t.Slot-1 && ...
    string(e.ReceiverInput.ReceiverObservationSHA256)==string(t.ReceiverObservationSHA256));
assert(d.NumCodewords==1 && d.Codewords.CodewordIndex==0 && ...
    d.CRCPass==t.CRCPass && e.CRCPass==t.CRCPass && ...
    string(d.Codewords.DecodedTransportBlockSHA256)==string( ...
        sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(int8(out.HARQ.FinalDecodedTransportBlocks{1}(:)))) && ...
    e.SuccessfulDecodedBits==t.DLSCHSuccessfulDecodedBits && ...
    e.OriginalAggregateGoodBits==t.DecodedAttemptBits && ...
    e.OriginalDecoderTokenUnchanged && e.OriginalOwnerJoinVerified && ...
    e.AdditionalDecoderInvocations==0 && e.AdditionalCreditUpdates==0 && ...
    ~e.FeedbackTransmissionQualified && ~e.ApplicationDeliveryQualified && ...
    ~e.FullMACQualified && ~e.StatisticalIndependenceClaimed);
afterCredit=sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot(state.TransportGoodputLedger);
c=e.TransportCredit;
assert(string(c.BeforeLedger.SHA256)==beforeCredit.SHA256 && ...
    c.BeforeLedger.EntryCount==beforeCredit.EntryCount && ...
    string(c.AfterLedger.SHA256)==afterCredit.SHA256 && ...
    c.AfterLedger.EntryCount==afterCredit.EntryCount && ...
    string(c.Contract)==string(t.TransportGoodputContract) && ...
    string(c.Status)==string(t.TransportGoodputStatus) && ...
    string(c.Key)==string(t.TransportGoodputKey) && ...
    isequaln(c.UniqueDeliveredTBBits,double(t.UniqueDeliveredTBBits)) && ...
    isequaln(double(t.GoodBits),double(t.UniqueDeliveredTBBits)) && ...
    c.FirstSuccessfulTBDelivery==t.FirstSuccessfulTBDelivery && ...
    c.Available==t.SharedDLSCHOutcomeTransportCreditBound && ...
    c.AccountingOnly && ~c.ExecutionProof);
end

function [evidence,weights]=localVerifyCSIApplicationMatrices(state,p,receipt)
% Independently multiply the retained data-layer symbols by each actual
% bundle page and the executed waveform-to-physical projection. This is
% pre-node-RF mapping, not a claimed radiated pattern or receiver optimum.
bundle=p.Tx.PrecoderBundle; projection=double(receipt.WaveformToElementMatrix);
prec=p.RequestBinding.PHYGrant.PrecodingState;
assert(isa(bundle,'sixgr.pdsch.PDSCHPrecoderBundle') && prec.WidebandOnly && ...
    bundle.NPRG==1 && bundle.NSymbolGroups==1);
page=projection*double(bundle.W(:,:,1,1));
assert(isequal(size(page),size(prec.MatrixPhysicalPorts)) && ...
    norm(page-double(prec.MatrixPhysicalPorts),'fro')<=1e-12*max(1,norm(page,'fro')));
layers=double(p.Tx.PDSCHLayerSymbols); ports=double(p.Tx.PDSCHPortSymbols);
actual=ports*projection.'; independentlyMapped=layers*page.';
assert(isequal(size(actual),size(independentlyMapped)) && ...
    norm(actual-independentlyMapped,'fro')<=1e-10*max(1,norm(actual,'fro')) && ...
    size(page,2)==p.Tx.PDSCH.NumLayers && size(page,1)==p.NumPhysicalTransmitAntennas);
sha=sixgr.phy.mimo.MatrixContract.digest(page);
weights=state.AppliedDataPrecoderWeights;
weights=weights(weights.TransmissionID==receipt.Identity.TransmissionID,:);
assert(height(weights)==numel(page) && all(weights.MatrixSHA256==sha) && ...
    all(weights.PHYGrantContextId==receipt.Identity.PHYGrantContextId) && ...
    all(weights.PRGIndex0==0 & weights.SymbolGroupIndex0==0));
retained=complex(zeros(size(page)));
for k=1:height(weights)
    retained(weights.ElementIndex0(k)+1,weights.LayerIndex0(k)+1)= ...
        complex(str2double(weights.WeightReal(k)),str2double(weights.WeightImag(k)));
end
assert(isequal(retained,page),'Applied-weight text must retain the exact executed matrix.');
evidence=struct('ReferencePlane',"physical_element_data_grid_before_node_rf", ...
    'FrozenPrecodingState',prec,'BundleMatrix',bundle.W, ...
    'WaveformToElementMatrix',projection,'AppliedPhysicalMatrix',page, ...
    'AppliedPhysicalMatrixSHA256',sha,'BundleDigest',bundle.ImmutableBundleDigest, ...
    'ComparedDataSymbolCount',numel(actual), ...
    'DirectMultiplicationRelativeError',norm(actual-independentlyMapped,'fro')/max(1,norm(actual,'fro')));
end

function localQueueSRS(state,cfg,srsSlot)
[srsCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
if state.TestSelectedPUSCHRecovery
    reference=srsCfg.lls6g.userContext.RuntimeSRSPowerReference;
    common=state.UECommonCellConfigurationByUE{1};
    assert(reference.Usable && reference.ReferenceSignalId==0 && ...
        reference.ProducerSlot==1 && reference.AvailableSlot==6 && ...
        reference.SIB1RxTreeHash==string(common.TreeHash) && ...
        reference.PathlossReferenceLifetime=="retained_filtered_reference" && ...
        strlength(reference.MeasurementId)>0 && isfinite(reference.Pathloss_dB));
    save(fullfile(state.TestRoot,'recovery_srs_original_power_reference.mat'), ...
        'reference','common','srsSlot','-v7.3');
end
srsCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(srsCfg,srsSlot);
srsCfg.lls6g.userContext.RuntimeSlotStartTime_s=(srsSlot-1)*sixgr.time.slotDurationSec(cfg);
args={'SlotIndex',srsSlot,'SNR_dB',cfg.channel.snr_dB,'TimingAdvanceSamples',0};
prepared=sixgr.link.runSRSChannelEstimation(srsCfg,args{:},'PrepareOnly',true);
assert(prepared.PreparedTransmission.NumReceiveAntennas== ...
    srsCfg.lls6g.userContext.RuntimeServingBSAntenna.NumElements, ...
    'SRS reception must bind physical gNB branches, not logical CSI port count.');
state.SharedWaveformStream.queueUplinkControl(1,prepared.PreparedTransmission, ...
    struct('Config',srsCfg,'Arguments',{args},'ServingCell',state.CurrentServingIdx(1)));
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
    if state.TestRankTransitions && item.Kind=="CSIRS"
        [state,row,~,csi]=sixgr.truth.completeSharedCSIRSReception(state,item);
        % The canonical producer archives the actual captures and operands.
        % Keep every new receiver/report outcome separately for this test.
        save(fullfile(state.TestRoot,sprintf('rank_csirs_slot_%d.mat',item.Context.Slot)), ...
            'row','csi','-v7.3');
        continue;
    end
    if state.TestReceivedCSIContinuation && item.Kind=="PDCCH" && ...
            string(sixgr.util.structGet(item.Context,'Direction',""))=="DL" && ...
            string(sixgr.util.structGet(item.Context,'Key',""))== ...
            string(sixgr.util.structGet(state,'TestContinuationControlKey',""))
        state=localCompleteCSIApplicationControl(state,item);
        continue;
    end
    normalUL=logical(sixgr.util.structGet(state,'TestSRSContinuationStarted',false));
    if normalUL
        inTail=logical(sixgr.util.structGet(state,'TestSRSReceiveTail',false));
        assert(~inTail || ~any(item.Kind==["PrepareULData","PreparePUCCH","BindSRSPower","DataTX","PUCCHTX"]), ...
            'test:SRSContinuationTailProducerDecision','A closed-horizon receive tail cannot prepare or emit a new producer.');
        if item.Kind=="PrepareULData"
            assert(string(item.Context.Key)==sixgr.truth.GrantPreparation.sharedGrantControlKey( ...
                state.TestSRSContinuationGrant,'UL'));
            beforeTX=state.ULHarq.Stats.Tx;
            state=sixgr.truth.prepareSharedScheduledULData(state,item);
            assert(state.ULHarq.Stats.Tx==beforeTX && owner.hasPending("PUSCH",item.UE), ...
                'Deferred preparation queues a real waveform but cannot count an emitted HARQ attempt.');
            continue;
        elseif item.Kind=="BindSRSPower"
            state=sixgr.truth.bindSharedSRSPower(state,item);
            continue;
        elseif item.Kind=="PDCCH" && string(item.Context.Direction)=="UL"
            beforeTX=state.ULHarq.Stats.Tx;
            state=sixgr.truth.PDCCHControlRuntime.completeShared(state,item,@localContinuationControlLog);
            controls=state.SharedReceivedGrantControls;
            hit=find(cellfun(@(x)string(x.Key)==string(item.Context.Key),controls));
            assert(isscalar(hit) && state.ULHarq.Stats.Tx==beforeTX);
            control=controls{hit};
            save(localContinuationArtifact(state,'received_srs_ul_control.mat'),'item','control','-v7.3');
            assert(isequaln(control.Grant.AcceptedSRSSpatialDecision,state.TestSRSContinuationAccepted) && ...
                string(control.Grant.PHYGrant.GrantContextId)== ...
                string(state.TestSRSContinuationGrant.PHYGrant.GrantContextId));
            if control.Allowed
                pending=state.SharedPendingULGrants;
                keys=arrayfun(@(g)sixgr.truth.GrantPreparation.sharedGrantControlKey(g,'UL'),pending);
                assert(nnz(keys==string(item.Context.Key))==1 && ...
                    control.ReceivedAssignment.Direction=="UL" && ...
                    control.ReceivedAssignment.PayloadHash==string(control.Grant.PDCCHGrantDCIId));
            end
            continue;
        elseif item.Kind=="PUSCH"
            state=localCompleteSRSApplicationPUSCH(state,item);
            continue;
        end
    end
    if item.Kind=="SuppressedSRSObservation"
        state=localRecordSuppressedSRS(state,item);
        continue;
    end
    if item.Kind=="PUSCHReceiveOnly"
        if normalUL
            state=sixgr.truth.completeSharedPUSCHAfterRejectedControl(state,item.Context.ObservationID);
            state.TestSRSContinuationRejected=true;
            continue;
        end
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
        withheld=false;
        if state.TestRetainedPower
            [powerCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext( ...
                state.CfgMobility,state,item.UE,'UL');
            [admitted,~,powerDecision]=sixgr.truth.resolveSharedPUCCHPowerAdmission( ...
                state,powerCfg,item.UE,item.Context.Slot);
            assert(powerDecision.MeasuredPowerReferenceRequired && ...
                powerDecision.PathlossReferenceLifetime=="retained_filtered_reference");
            if state.TestMissingSelectedSSBReference
                assert(powerDecision.PowerReferenceSignalID==1);
                withheld=item.Context.Slot==10;
                if withheld
                    assert(~admitted && powerDecision.PowerReferenceStatus=="reference_lifecycle_unavailable" && ...
                        powerDecision.ReferenceLifecycleStatus=="no_observation_for_current_reference_power_generation");
                    measurements=state.ReferenceSignalMeasurementTable;
                    ssb=string(measurements.SignalType)=="SSB" & measurements.TargetId==item.UE;
                    assert(any(ssb & measurements.ResourceId==0) && ~any(ssb & measurements.ResourceId==1), ...
                        'Initial beam-0 reception must not manufacture a selected beam-1 measurement.');
                    before=localWithheldPreparationSnapshot(state,item,powerCfg,powerDecision);
                else
                    assert(item.Context.Slot==state.TestSSBRecoveryReportSlot && admitted && ...
                        isfinite(powerDecision.MeasuredPathloss_dB));
                    state=localCheckRecoveryPreparation(state,item,powerDecision);
                end
            else
                assert(admitted && isfinite(powerDecision.MeasuredPathloss_dB), ...
                    'test:ActualRetainedReferenceMissing','Actual decoded SI and SSB must own PUCCH preparation.');
            end
            state.TestActualPUCCHPowerDecision=powerDecision;
            name='actual_pucch_power_admission.csv';
            if state.TestMissingSelectedSSBReference
                name=sprintf('actual_pucch_power_admission_slot_%d.csv',item.Context.Slot);
            end
            sixgr.util.csvWriteTable(fullfile(state.TestRoot,name), ...
                powerDecision,'PreserveSchema',true);
        end
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
        if withheld
            state=localCheckWithheldPreparation(state,item,powerCfg,powerDecision,before);
        end
        continue;
    end
    if item.Kind=="PUCCHReceiveOnly"
        if state.TestMissingSelectedSSBReference && item.Context.Slot==10
            state=localCompleteWithheldPUCCH(state,item);
            continue;
        end
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
            % A continuation also monitors configured SR/CSI occasions with
            % no transmitted DL HARQ obligation. Derive that distinction
            % from the gNB's executed schedule, never UE pending bits or a
            % test-wide assumption that every later PUCCH repeats the prefix.
            obligations=sixgr.truth.scheduledHARQExpectationsForOccasion(observer,item.UE,c.Slot);
            initialCombined=~isfield(state,'TestContinuationAdmittedReport') && ...
                ~logical(sixgr.util.structGet(state,'TestSRSContinuationStarted',false)) && ...
                ~state.TestMissingSelectedSSBReference;
            if isempty(obligations)
                independent=sixgr.truth.buildConfiguredPUCCHReception( ...
                    observer,c.Config,item.UE,c.Slot,c.ObservationID);
                assert(~isempty(independent) && isempty(independent.Mapping) && ...
                    isempty(original.Mapping) && ~initialCombined, ...
                    'The original combined HARQ prefix cannot be replaced by a configured-only occasion.');
            else
                independent=sixgr.truth.buildScheduledPUCCHHARQReception( ...
                    observer,c.Config,item.UE,c.Slot,c.ObservationID);
                assert(independent.Mapping.Digest==original.Mapping.Digest);
            end
            assert(independent.Assignment.Digest==original.Assignment.Digest && ...
                independent.Context.Digest==original.Context.Digest, ...
                'UE bookkeeping or TX references must not own the combined receive schema.');
            [~,~,~,~,capture]=sixgr.truth.sharedObservationEvidence(item.Planes,c.Prepared);
            % Use the production receiver-history selector for every
            % occasion. Format 2 acquires timing from its actual DM-RS and
            % legitimately needs no earlier SRS. Never manufacture a prior
            % from the prepared TX or require an unrelated SRS in this test.
            % HARQ-bearing Format 0 still enforces its real prior in RX.
            carrier=sixgr.phy.grid.makeCarrier(c.Config);
            nominal=sixgr.phy.frame.slotStartSample(carrier,c.Slot-1,capture.SampleRateHz);
            prior=sixgr.truth.selectReceivedULTimingReference( ...
                observer,item.UE,capture.EndSampleExclusive,nominal);
            replay=sixgr.link.receivePUCCHObservation(c.Config,independent.Assignment, ...
                independent.Context,capture,prior);
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
            receipt=state.SharedGNBUCIReceptions{end};
            assert(receipt.ObservationID==c.ObservationID);
            actual=receipt.Receiver;
            % Preserve failed captures too: distinguish an observer mismatch
            % from an identical physical decoding failure before repairing RX.
            replayName=sprintf('pucch_independent_replay_slot_%d_receipt_%d.mat', ...
                c.Slot,numel(state.SharedGNBUCIReceptions));
            if initialCombined, replayName='combined_pucch_independent_replay.mat'; end
            save(fullfile(state.TestRoot,replayName), ...
                'item','independent','actual','replay','-v7.3');
            assert(isequaln(actual.DecodedFields,replay.DecodedFields) && ...
                actual.ReceiverUsable==replay.ReceiverUsable && actual.DTX==replay.DTX && ...
                actual.CRCPassed==replay.CRCPassed, ...
                'Retained-IQ independent reception must preserve HARQ/CSI/SR fields and decisions.');
            if initialCombined
                assert(isequal(actual.DecodedFields.SR,int8(0)), ...
                    'test:CombinedPUCCHNegativeSRRecovery', ...
                    'Combined reception did not recover negative SR: DTX=%d CRC=%d SR=%s.', ...
                    actual.DTX,actual.CRCPassed,mat2str(actual.DecodedFields.SR));
                fprintf('COMBINED_PUCCH_OBSERVER_REMOVAL_REPLAY_PASS additional_RF_executions=0 negative_SR_exact=1\n');
            else
                fprintf('CONTINUATION_PUCCH_OBSERVER_REMOVAL_REPLAY_PASS slot=%d scheduled_HARQ=%d additional_RF_executions=0\n', ...
                    c.Slot,~isempty(obligations));
            end
        end
        continue;
    end
    if state.TestMissingSelectedSSBReference && item.Kind=="SSBOccasion" && ...
            item.Context.Slot==state.TestSSBRecoveryBurstSlot
        % The real periodic receiver owns these measurements. It neither
        % reruns initial SI nor resets the unchanged common-power lifecycle.
        state=sixgr.truth.SSBOccasionResultDelivery.complete(state,item);
        continue;
    end
    if state.TestMissingSelectedSSBReference && item.Kind=="PBCH" && ...
            item.Context.Slot==state.TestSSBRecoveryBurstSlot
        % An odd radio-frame SI occasion can extend beyond this test. If its
        % full capture finishes, retain that fact without claiming a second
        % full-SI decode. Early periodic SSB reception is a separate owner.
        state.TestRecoveryBroadcastFullCaptureCompleted=true;
        continue;
    end
    c=item.Context; p=c.Prepared;
    if any(item.Kind==["PBCH","SSBOccasion","TRS"])
        [~,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes);
    else
        [~,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
    end
    assert(all(cellfun(@(s)~isfield(s.Execution,'ChannelReferences'),replay.ReceiveStreamExecutionSegments)));
    if item.Kind=="PBCH"
        if state.TestReceiveSIB1
            assert(isfield(state,'TestReceivedDLClock'), ...
                'The full SI receiver uses the already received SS/PBCH candidate.');
            prototype=c.Prototype;
            prototype.RuntimeChannelReplay=replay;
            prototype.RuntimeDLChannelState=owner.channelState(item.UE,'DL');
            prototype.RuntimeChannelStateUsed=true;
            prototype.PowerContext=p.PowerContext;
            options=struct('UseRuntimeChannel',true,'RuntimeSlot',c.Slot-1, ...
                'CandidateSSBIndices',[],'SSBIndex',state.TestReceivedDLClock.SSBIndex, ...
                'WriteArtifacts',false,'RunFolder','','RunId','shared_uci_component_actual_sib1', ...
                'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
            [options.DesiredReferenceObservation,options.DesiredReferenceEvidence]= ...
                sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
            rxID=string(options.DesiredReferenceEvidence.ReceiverID);
            options.ReceiveElementBinding=owner.Physical.receiveElementLayout(rxID);
            options.OriginalSSBPowerObservationBinding=struct('Planes',{item.Planes}, ...
                'DesiredReferencePlaneID',c.DesiredReferencePlane, ...
                'ReceiveBranchBinding',owner.Physical.receiveBranchLayout(rxID));
            output=sixgr.link.completeCellSearchBroadcast(p,receiver,prototype,options,tic);
            save(fullfile(state.TestRoot,'shared_received_sib1_original.mat'),'item','output','-v7.3');
            assert(isfield(output,'SIB1') && output.SIB1.StrictOk, ...
                'test:SharedSIB1Receiver','Actual full SI reception failed: %s',string(output.FailureReason));
            recovered=output.SIB1;
            recovered.ReferenceConfigurationEpoch=c.Config.initial_access.configuration_epoch;
            recovered.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
            recovered.OriginalServingCell=c.ServingCell;
            row=localContinuationReferenceRow(recovered,receiver,state,c.Slot);
            captureFilter=sixgr.rrc.resolvePreconnectionRSRPFilter(c.Config);
            if ~isempty(fieldnames(captureFilter))
                row.SSBPowerReferenceCaptureFilterConfigHash=string(captureFilter.ConfigHash);
            end
            row.CRCPass=logical(recovered.BCHCrcPass && recovered.MIBDecoded && ...
                recovered.DCICrcPass && recovered.DLSCHCrcPass && recovered.SIB1ASN1DecodeOk);
            state=sixgr.truth.BroadcastResultDelivery.enqueue(state,item.UE,row,recovered,false);
        end
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
                if ~state.TestRetainedPower
                    state.ConnectedULTimingByUE{1}.DLReference=state.TestReceivedDLClock;
                end
                if state.TestReferenceContinuation && ~state.TestReceiveSIB1
                    % Retain this actually decoded SS/PBCH for the ordinary
                    % acquisition reducer at its causal delivery boundary.
                    row=localContinuationReferenceRow(recovered,receiver,state,c.Slot);
                    decodedCarrier=sixgr.phy.grid.makeCarrier(p.ReceiverConfig);
                    row.CRCPass=logical(recovered.BCHCrcPass && recovered.MIBDecoded && ...
                        recovered.NCellID==decodedCarrier.NCellID);
                    state=sixgr.truth.BroadcastResultDelivery.enqueue( ...
                        state,item.UE,row,recovered,false);
                end
                fprintf('RECEIVED_UL_SHARED_DL_CLOCK_PASS: sample=%d phase=%d\n', ...
                    receiver.EndSampleExclusive,state.TestReceivedDLClock.DLPhaseOffsetSamples);
        end
    elseif item.Kind=="SRS"
        [desiredReference,referenceEvidence,refs]=sixgr.truth.sharedLinkScoringObservation( ...
            item.Planes,p,c.DesiredReferencePlane);
        assert(referenceEvidence.ChannelReferenceCoverageComplete);
        input=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ScoringChannelReferences',{refs}, ...
            'ChannelState',owner.directionalChannelState(1,'UL'));
        % Match the production SRS completion handoff. These ORIGINAL owner
        % operands qualify post-receiver scoring only, never practical Hest.
        input.DesiredReferenceObservation=desiredReference;
        input.DesiredReferenceEvidence=referenceEvidence;
        [state,out]=sixgr.truth.receiveSharedSRSMeasurement(state,item,input);
        assert(out.RuntimeNoiseVarianceMean==out.NoiseVariance && ...
            out.RuntimeNoiseVarianceDomain==out.NoiseVarianceDomain && ...
            string(out.RuntimeNoiseVarianceSource)==string(out.NoiseVarianceSource), ...
            'SRS receiver variance aliases must retain the same measured domain and source.');
        if ~out.Ok
            save(fullfile(state.TestRoot,'srs_receiver_failure.mat'),'out','input','c','-v7.3');
        end
        assert(out.Ok,'test:SharedSRSFailed', ...
            'Actual SRS receiver must pass before a sounded grant: %s; %s', ...
            char(fillmissing(string(out.FailureReason),"constant","[missing]")), ...
            char(fillmissing(string(out.Notes),"constant","[missing]")));
        state.TestSRS=struct('RI',out.EstimatedRI,'TPMI',out.EstimatedTPMI, ...
            'Slot',double(c.Arguments{2}), ...
            'ID',sixgr.phy.waveform.WaveformHash.numeric(receiver.readComplete()), ...
            'NumSRSPorts',p.Tx.SRS.NumSRSPorts,'AvailableAtSample',receiver.EndSampleExclusive);
        state.ReceivedULTimingReferences={sixgr.phy.sync.ReceivedULTimingReference(p,receiver,out.ReceiveTiming)};
        if state.TestSelectedPUSCHRecovery
            assert(state.TestSRS.Slot==9);
            state.TestRecoverySRSOriginal=struct('Measurement',state.TestSRS, ...
                'ObservationStartSample',receiver.StartSample, ...
                'ObservationEndSampleExclusive',receiver.EndSampleExclusive, ...
                'ReceiveTiming',out.ReceiveTiming,'Trial',out);
        end
        if state.TestReferenceContinuation
            row=localContinuationReferenceRow(out,receiver,state,double(c.Arguments{2}));
            assert(strlength(string(out.SRSConfigurationContextID))>0 && ...
                string(row.SRSConfigurationContextID)==string(out.SRSConfigurationContextID) && ...
                row.SRSNumPorts==out.SRSNumPorts && row.SRSNumPorts==p.Tx.SRS.NumSRSPorts && ...
                row.MeasurementClockEpoch==owner.Physical.ConfigurationEpoch && ...
                string(out.SRSConfigurationContextID)==sixgr.truth.srsConfigurationContextID( ...
                    c.Config,owner.Physical.ConfigurationEpoch,item.UE,c.ServingCell), ...
                'Retain the exact frozen producer context, never reconstruct it from later installed cfg.');
            row.RuntimeTransportMode="shared_physical_stream_SRS_received_completion";
            row=sixgr.truth.bindReceivedSRSTimingEvidence(row,out.ReceiveTiming,p.PhysicalTiming);
            state.TestContinuationReferences{end+1,1}=row;
            state.LastSRSSlotByUE(item.UE)=row.Slot;
        end
        row=table(double(c.Arguments{2}),"SRS",'VariableNames',{'Slot','Channel'});
        row=sixgr.truth.exportSharedChannelObservation(state.TestRoot,row,item.Planes,p,c.DesiredReferencePlane);
        sixgr.channel.validateSharedChannelObservationArtifact(state.TestRoot,row);
        state.TestLastSRSObservationID=row.ChannelObservationID;
    elseif item.Kind=="TRS" && state.TestReferenceContinuation
        reference=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        out=sixgr.link.completeTRSReception(p,receiver,replay, ...
            owner.directionalChannelState(item.UE,'DL'),'DesiredReferenceObservation',reference);
        artifact=fullfile(state.TestRoot,'continuation_trs_receiver.mat');
        if state.TestRankTransitions
            artifact=fullfile(state.TestRoot,sprintf('continuation_trs_slot_%d.mat',c.Slot));
        end
        save(artifact,'item','out','-v7.3');
        assert(~out.Crash,'test:ContinuationTRSReceiverCrash','%s: %s',out.FailureIdentifier,out.FailureReason);
        state=sixgr.truth.recordSharedQCLTimingReference(state,p,receiver,out,item.UE,c.ServingCell);
        row=localContinuationReferenceRow(out,receiver,state,c.Slot);
        row=sixgr.truth.bindTRSFrequencyEvidence(row,out);
        % Match the production completion boundary: the original captured
        % TRS/configuration is stamped before causal delivery, not after an
        % admission failure. No decoder result, clock or validity is changed.
        originalRow=row;
        row=sixgr.truth.DLMeasurementInstallation.stamp(state,row,p.ReceiverConfig,item.UE,"TRS");
        assert(isequaln(row(:,originalRow.Properties.VariableNames),originalRow));
        if state.TestReceiveSIB1
            installed=state.TestActualSIB1Installation;
            assert(row.DLMeasurementAuthorityEligible && ...
                row.DLMeasurementInstallationSHA256==installed.SHA256 && ...
                row.ObservationStartSample>=installed.EffectiveSample && ...
                row.ObservationEndSampleExclusive<=owner.Events.NextSampleIndex, ...
                'test:ContinuationTRSInstallation', ...
                'Only original post-installation TRS may become operational tracking evidence.');
        end
        state=sixgr.truth.TRSResultDelivery.enqueue( ...
            state,c.ServingCell,item.UE,row,c.Config,out.ObservedREAllocationTable);
        sixgr.util.csvWriteTable(fullfile(state.TestRoot, ...
            sprintf('continuation_trs_installation_slot_%d.csv',c.Slot)),row,'PreserveSchema',true);
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
        if state.TestDAIMonitorOmission && string(grant.Direction)=="UL"
            assert(decoded.Fields.first_dai==1 && ...
                receivedAssignment.Fields.first_dai==1 && ...
                isequal(rx.DCIBits(:),grant.DCI.Bits(:)) && ...
                grant.ULTotalDAIAuthority.ScheduledDLAssignmentCount==2, ...
                'test:OriginalReceivedULTotalDAI','Actual bits01 must encode total DAI value2.');
            state.TestActualULTotalDAI=struct('Raw',decoded.Fields.first_dai, ...
                'Value',2,'AssignmentDigest',receivedAssignment.AssignmentDigest, ...
                'OriginalDecodedBits',rx.DCIBits,'OriginalTransmittedBits',grant.DCI.Bits);
        end
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
            if state.TestDAIMonitorOmission && grant.Slot==7
                % Deliberate test-side UE monitor omission, not RF failure.
                % Retain the actual decoded diagnostic result and all original IQ.
                state.TestOmittedControl=struct('Grant',grant,'ReceivedAssignment',receivedAssignment, ...
                    'OriginalDecoderResult',rx,'AvailableAtSample',owner.Events.NextSampleIndex);
                save(fullfile(state.TestRoot,'original_monitor_omitted_control.mat'), ...
                    'item','rx','rxInfo','grant','receivedAssignment','receiver','-v7.3');
                continue;
            end
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
                key=sixgr.util.sha256Hex(uint8(char(string(grant.PHYGrantContextId))));
                state.TestSharedDLControlByGrant.("g_"+extractBefore(key,62))=control;
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
        if state.TestIndependentSharedHARQ
            expectedACK=int8(state.TestExpectedSharedACK);
            if state.TestDAIMonitorOmission, expectedACK=[expectedACK;int8(0)]; end
        end
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
        elseif state.TestSelectedPUSCHRecovery
            % Old HARQ is closed; new due-slot CSI is independently owned.
            % hasPayload includes CSI and cannot stand in for HARQ presence.
            original=state.TestRecoveryPUSCHOriginalReport;
            pending=state.PendingCSITable;
            report=pending(string(pending.ReportIdentity)==string(original.ReportIdentity),:);
            old=state.TestWithheldPUCCH;
            snapshot=struct('Grant',grant,'Payload',uci.toStruct(),'OriginalReport',original, ...
                'PendingReport',report,'PendingFeedback',state.PendingFeedbackTable, ...
                'OriginalWithheld',old,'ReceivedAssignment',receivedAssignment);
            save(fullfile(state.TestRoot,'selected_recovery_original_uci_binding.mat'),'snapshot','-v7.3');
            assert(~hasDueACK && isempty(uci.HARQACK) && isempty(uci.ConfiguredGrantUCI) && ...
                grant.UCIOnPUSCHFeedbackBitCount==0 && ...
                isempty(grant.UCIOnPUSCHFeedbackBitIndices) && ...
                strlength(string(grant.UCIOnPUSCHFeedbackGrantIds))==0, ...
                'test:RecoveryHARQReplay','Completed original HARQ cannot be remultiplexed.');
            part1=int8(sixgr.runtime.RawCSVArrayCodec.decode(original.CSIPart1BitsToken));
            part2=int8(sixgr.runtime.RawCSVArrayCodec.decode(original.CSIPart2BitsToken));
            assert(height(report)==1 && report.DueSlot==15 && report.SourceSlot==6 && ...
                ~report.Processed && report.CSIUCITransport=="pusch_bound" && ...
                string(grant.UCIOnPUSCHCSIReportIdentity)==string(original.ReportIdentity) && ...
                ~isempty(part1) && isequal(uci.CSIPart1(:),part1(:)) && ...
                isequal(uci.CSIPart2(:),part2(:)) && ...
                report.MeasurementAvailableAtSample==original.MeasurementAvailableAtSample, ...
                'test:RecoveryCSIIdentity','Use only the original new periodic report with unchanged measurement age.');
            expired=pending(string(pending.ReportIdentity)==string(old.FinalReport.ReportIdentity),:);
            oldTrace=state.PUCCHGrantTraceTable( ...
                ismember(string(state.PUCCHGrantTraceTable.PUCCHGrantId),old.OriginalGrantIDs),:);
            assert(isequaln(expired(:,old.FinalReport.Properties.VariableNames),old.FinalReport) && ...
                isequaln(oldTrace(:,old.FinalTrace.Properties.VariableNames),old.FinalTrace) && ...
                isequaln(state.DLHarq.Stats,old.HARQAfter), ...
                'test:RecoveryOldObligationChanged','Original no-TX/receiver/expiry disposition must remain unchanged.');
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
        if state.TestPreparedCSIAcquisitionLoss && ~isRetx
            % Inject only a UE-private acquisition-loss transition AFTER
            % genuine encoded IQ is bound. This is not a simulated second
            % SSB acquisition, nor permission to change the gNB hypothesis.
            % A previous power-deferred occasion expands the private table
            % schema. Exercise the next fresh report under that schema. The
            % empty disposition is a DECLARED schema boundary, not evidence
            % that this physically transmitted report was power-withheld.
            assert(~ismember('UEProducerDisposition',state.PendingCSITable.Properties.VariableNames));
            state.PendingCSITable.UEProducerDisposition=strings(height(state.PendingCSITable),1);
            report=table2struct(state.PendingCSITable);
            assert(isscalar(report) && sixgr.truth.DLMeasurementInstallation.required(state) && ...
                sixgr.truth.UEQueuedCSIAdmission.waveformBound(state,report));
            [eligible,~]=sixgr.truth.UEQueuedCSIAdmission.eligible(state,report);
            assert(eligible && state.CellAcquisitionState(1)=="acquired");
            originalPending=owner.Pending; originalRNG=rng;
            originalCSI=state.PendingCSITable; originalFeedback=state.PendingFeedbackTable;
            originalTrace=state.PUCCHGrantTraceTable; originalLatest=state.LatestDLFeedback;
            prepared=result.Result.PreparedTransmission;
            assert(isa(prepared,'sixgr.link.PreparedDataTransmission'));
            beforeHash=sixgr.phy.waveform.WaveformHash.numeric(prepared.Tx.Waveform);
            state.CellAcquisitionState(1)="searching";
            [eligible,status]=sixgr.truth.UEQueuedCSIAdmission.eligible(state,report);
            assert(~eligible);
            state=sixgr.truth.UEQueuedCSIAdmission.reconcile(state);
            assert(isequaln(state.PendingCSITable,originalCSI) && ...
                isequaln(state.PendingFeedbackTable,originalFeedback) && ...
                isequaln(state.PUCCHGrantTraceTable,originalTrace) && ...
                isequaln(state.LatestDLFeedback,originalLatest) && ...
                isequaln(owner.Pending,originalPending) && isequal(originalRNG,rng) && ...
                sixgr.truth.UEQueuedCSIAdmission.waveformBound(state,report));
            hit=find(string({owner.Pending.Kind})=="PUSCH");
            assert(isscalar(hit));
            after=owner.Pending(hit).Context.Prepared;
            assert(isequaln(after.RequestBinding,prepared.RequestBinding) && ...
                isequaln(after.Tx.Waveform,prepared.Tx.Waveform) && ...
                sixgr.phy.waveform.WaveformHash.numeric(after.Tx.Waveform)==beforeHash);
            state.TestPreparedCSITransition=struct('ReportIdentity',string(report.ReportIdentity), ...
                'PreparedWaveformSHA256',beforeHash,'AdmissionStatusAfterLoss',status, ...
                'TransitionSample',owner.Events.NextSampleIndex, ...
                'DeclaredPriorPowerDeferralSchema',true, ...
                'Scope',"injected_UE_private_acquisition_loss_after_actual_IQ_binding_not_new_SSB_reacquisition");
            fprintf('PREPARED_CSI_ACQUISITION_LOSS_BOUNDARY_PASS original_IQ_unchanged=1 gNB_context_unchanged=1 not_retired=1\n');
        end
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
        if state.TestReceivedCSIContinuation && isfield(c,'Plan') && ...
                string(c.Key)==string(state.TestContinuationControlKey)
            state=localCompleteCSIApplicationPDSCH(state,item);
            continue;
        end
        if state.TestIndependentSharedHARQ
            if state.TestDAIMonitorOmission && c.Job.GrantSnapshot.Slot==7
                assert(isfield(state,'TestOmittedControl'));
                state.TestOmittedDataCaptured=true;
                save(fullfile(state.TestRoot,'original_unmonitored_data_capture.mat'), ...
                    'item','p','pre','tx','replay','receiver','-v7.3');
                continue; % No received assignment, hence no UE data decoder/event.
            end
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
        out=localBindAndCheckEmbeddedCSI(state,out,p,receiver,item.UE);
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
            assert(job.ReceivedContext.UCIReceiveContext.Data.HARQACKBitCount==(double(state.TestIndependentSharedHARQ && ~state.TestSeparatePUCCH)+double(state.TestDAIMonitorOmission))*double(~state.TestSelectedPUSCHRecovery) && ...
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
        % Same post-receiver binding as the production coordinator. This
        % proves compact TX occupancy on an actually emitted/received PUSCH,
        % not only the declared-receipt arithmetic fixture.
        decodedBeforeOccupancy=out.HARQ;
        out.TrialTable=sixgr.truth.bindSharedTransmitOccupancy(out.TrialTable,state,item);
        occupancy=jsondecode(out.TrialTable.TransmitOccupancyEvidenceJSON);
        assert(isequaln(out.HARQ,decodedBeforeOccupancy) && ...
            out.TrialTable.TransmitOccupancyStatus=="completed_nonzero_contribution" && ...
            string(occupancy.Identity.ObservationID)==string(item.ID) && ...
            string(occupancy.Identity.TransmissionID)==string(c.TransmissionIdentity.TransmissionID) && ...
            occupancy.ActiveSampleCount>0 && ...
            occupancy.ReceiverBinding.StartSample==receiver.StartSample && ...
            occupancy.ReceiverBinding.EndSampleExclusive==receiver.EndSampleExclusive && ...
            occupancy.ReceiverBinding.SampleRateHz==receiver.SampleRateHz, ...
            'test:SharedPUSCHOccupancyBinding','Bind the actual completed contribution without changing the decoder result.');
        wrongGrant=out.TrialTable; wrongGrant.FrozenGrantContextId="different_grant";
        localReject(@()sixgr.truth.bindSharedTransmitOccupancy(wrongGrant,state,item), ...
            'sixgr:truth:TransmitOccupancyRowIdentity');
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
            if state.TestIndependentSharedHARQ
            expectedACK=int8(state.TestExpectedSharedACK);
            if state.TestDAIMonitorOmission, expectedACK=[expectedACK;int8(0)]; end
        end
            if state.TestSelectedPUSCHRecovery
                assert(isempty(out.HARQ.DecodedHARQACKBits));
            else
                assert(out.HARQ.HARQACKContentMatch && isequal(out.HARQ.DecodedHARQACKBits,expectedACK));
            end
        else
            assert(isempty(out.HARQ.DecodedHARQACKBits));
        end
        assert(string(out.HARQ.GrantSnapshot.GrantContextId)==string(job.GrantContextId), ...
            'The actual decoded grant must retain the same PHY-job identity used for UCI reservation.');
        % Exercise the main shared completion's receive-event handoff on
        % actual CDL/SRS/PUSCH captures, without a known-delay/oracle input.
        out.HARQ.ReceivedTimingEvidence=sixgr.truth.receivedDataSymbolTiming( ...
            p,receiver,out.ReceiveTiming,owner.Events.NextSampleIndex);
        if state.TestSelectedPUSCHRecovery
            assert(job.StartSlotIndex==15 && state.TestRecoveryGrantOriginalSRS.Slot==9);
            state.TestRecoveryPUSCHTiming=struct('OriginalReceiveTiming',out.ReceiveTiming, ...
                'ReceivedTimingEvidence',out.HARQ.ReceivedTimingEvidence, ...
                'ObservationStartSample',receiver.StartSample, ...
                'ObservationEndSampleExclusive',receiver.EndSampleExclusive, ...
                'GrantSnapshot',out.HARQ.GrantSnapshot,'Trial',out.TrialTable);
        end
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
                due=10; reference=6;
                if state.TestSelectedPUSCHRecovery
                    due=state.TestSSBRecoveryReportSlot;
                    reference=sixgr.truth.periodicCSIReferenceSlot(job.Cfg,due);
                end
                assert(reports.CSIReferenceSlot==reference && reports.SourceSlot==reference && reports.DueSlot==due && ...
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
            elseif state.TestSelectedPUSCHRecovery
                assert(isequaln(state.HARQTimelineTable,priorTimeline) && ...
                    isequaln(state.PendingFeedbackTable,priorPending), ...
                    'Recovery CSI-only PUSCH must not replay old HARQ obligations.');
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
        assert(persisted.TransmitOccupancyEvidenceJSON==row.TransmitOccupancyEvidenceJSON && ...
            persisted.TransmitOccupancyEvidenceSHA256==row.TransmitOccupancyEvidenceSHA256 && ...
            persisted.TransmitOccupancyObservationID==string(item.ID), ...
            'test:SharedPUSCHOccupancyPublication','Actual emitted-contribution evidence must survive CSV publication unchanged.');
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

function state=localRecordSuppressedSRS(state,item)
% Match the production completion dispatch: a cancelled SRS still owns
% completed physical windows, but no SRS receiver or measurement is run.
owner=state.SharedWaveformStream;
proof=item.Context.SuppressionProof; p=item.Context.Prepared;
ledger=owner.SRSSuppressionLedger;
hit=string({ledger.SRSObservationID})==string(item.ID);
assert(nnz(hit)==1 && isequaln(ledger(hit),proof) && ...
    proof.UE==item.UE && string(proof.SRSObservationID)==string(item.ID) && ...
    p.Channel=="SRS" && proof.Decision.Collision && ...
    isempty(proof.Decision.RetainedSymbols0Based) && ...
    ~isempty(proof.Decision.DroppedSymbols0Based) && ...
    string(proof.Cancellation.ComponentID)==string(item.ID) && ...
    string(proof.Cancellation.TransmitterID)=="ue_"+item.UE && ...
    proof.Cancellation.EmittedNonzeroSamples==0 && ...
    ~proof.Cancellation.PreviouslyConsumedSamplesChanged && ...
    proof.Cancellation.CancelledAtSample<=owner.Events.NextSampleIndex, ...
    'test:InvalidSRSSuppressionReceipt','Require the exact owner-issued pre-emission suppression proof.');
ids=string({item.Planes.ReceiverID});
tx=find(endsWith(ids,':tx')); pre=find(endsWith(ids,':pre_rf')); post=find(endsWith(ids,':post_rf'));
assert(isscalar(tx) && isscalar(pre) && isscalar(post) && ...
    nnz(ids==string(item.Context.DesiredReferencePlane))==1);
ch=owner.channelState(item.UE,'UL');
planeReceipts=cell(numel(item.Planes),1);
completedAt=owner.Events.NextSampleIndex;
for k=1:numel(item.Planes)
    capture=item.Planes(k).Observation;
    assert(capture.isComplete() && capture.SampleRateHz==owner.SampleRateHz && ...
        capture.EndSampleExclusive<=owner.Events.NextSampleIndex, ...
        'Suppression must retain genuinely completed windows, including noise and other contributors.');
    if k==tx
        assert(capture.StartSample==p.StartSample && capture.EndSampleExclusive==p.EndSampleExclusive);
    else
        assert(capture.StartSample==p.ReceiveStartSample && ...
            capture.EndSampleExclusive==p.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
    end
    % Existing content-addressed backing reads back exact samples before
    % releasing the complete buffer. Retain receipts, not prepared configs
    % or per-segment channel/RF arrays, for this non-receiver decision.
    receipt=capture.archiveCompleted(state.TestRoot);
    assert(sixgr.phy.waveform.CompletedSampleArchive.verifyFile(receipt)==receipt.Manifest.SampleSHA256);
    planeReceipts{k}=struct('ReceiverID',ids(k),'StartSample',capture.StartSample, ...
        'EndSampleExclusive',capture.EndSampleExclusive,'SampleRateHz',capture.SampleRateHz, ...
        'NumReceiveAntennas',capture.NumReceiveAntennas,'Samples',receipt);
end
assert(owner.Events.NextSampleIndex==completedAt,'Evidence archiving cannot advance physical execution.');
preservedFields={'LatestULFeedback','ReferenceSignalMeasurementTable', ...
    'ReceivedULTimingReferences','SRSPilotPhaseHistoryByUE','TestSRS', ...
    'LastSuccessfulSRSSlotByUE','LastSRSObservedSlotByUE','TestContinuationReferences'};
prior=struct();
for name=preservedFields
    if isfield(state,name{1}), prior.(name{1})=state.(name{1}); end
end
% Same decision schema as runWaveformLinkBundle's suppression handler.
decision=table(item.UE,p.ReceiveStartSample,proof.Cancellation.CancelledAtSample, ...
    string(jsonencode(proof.Decision.DroppedSymbols0Based)), ...
    "srs_suppressed_for_actual_same_UE_PUCCH",string(jsonencode(proof)),false, ...
    'VariableNames',{'UEIndex','ReceiveStartSample','DecisionSample', ...
    'DroppedSRSSymbols0Based','Action','PhysicalSuppressionProofJSON','SRSReceiverExecuted'});
previous=sixgr.util.structGet(state.ControlTrials,'SRSResourceDecisions',table());
if isempty(previous)
    state.ControlTrials.SRSResourceDecisions=decision;
else
    % This bounded harness has only completed suppression decisions here.
    % Do not manufacture columns or discard another decision's evidence.
    state.ControlTrials.SRSResourceDecisions=[previous;decision];
end
retained=sixgr.util.structGet(state,'TestSuppressedSRSObservations',{});
snapshot=struct('Version',"suppressed_srs_observation/v1", ...
    'ID',string(item.ID),'UEIndex',item.UE,'SuppressionProof',proof, ...
    'ClockDomain',"shared_physical_sample_clock/v1", ...
    'ClockEpoch',owner.Physical.ConfigurationEpoch,'CompletedAtSample',completedAt, ...
    'SampleRateHz',owner.SampleRateHz,'TransmitStartSample',p.StartSample, ...
    'TransmitEndSampleExclusive',p.EndSampleExclusive, ...
    'ReceiveStartSample',p.ReceiveStartSample,'ReceiveEndSampleExclusive',p.ReceiveEndSampleExclusive, ...
    'DesiredReferencePlane',string(item.Context.DesiredReferencePlane), ...
    'PlaneReceipts',{planeReceipts},'SRSReceiverExecuted',false);
retained{end+1,1}=snapshot;
state.TestSuppressedSRSObservations=retained;
save(fullfile(state.TestRoot,sprintf('suppressed_srs_observation_%d.mat',numel(retained))), ...
    'snapshot','decision','-v7.3');
for name=reshape(fieldnames(prior),1,[])
    assert(isequaln(state.(name{1}),prior.(name{1})), ...
        'Suppression cannot refresh accepted/raw SRS, receiver history or timing.');
end
fprintf('SHARED_SRS_SUPPRESSION_RECORDED UE=%d nonzero_emitted=0 receiver_executed=0 prior_measurement_unchanged=1\n',item.UE);
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
    % The periodic calendar owns this transmission occasion. The separate
    % generic AMC delay must not be repurposed to force source slot + delay
    % onto the PUSCH. Use the already published original receiver row.
    assert(sixgr.truth.periodicCSIReportSlotMask(dueSlot, ...
        cfg.phy.csi.reportPeriodicitySlots,cfg.phy.csi.reportOffsetSlots));
    originalMeasurements=state.ControlTrials.CSIRS;
    state=sixgr.truth.CoupledTruthRuntime.refreshPeriodicCSIReportsRuntime(state);
    obligations=state.CSIReportObligationTable;
    obligation=obligations(obligations.UEIndex==1 & obligations.ReportSlot==dueSlot,:);
    assert(height(obligation)==1 && obligation.ULResourceAvailable && ...
        obligation.CSIReferenceSlot==sixgr.truth.periodicCSIReferenceSlot(cfg,dueSlot) && ...
        csi.Slot<=obligation.CSIReferenceSlot && ...
        isequaln(state.ControlTrials.CSIRS,originalMeasurements));
    assert(height(state.PendingCSITable)==1 && state.PendingCSITable.DueSlot==dueSlot && ...
        string(state.PendingCSITable.ReportIdentity)==string(obligation.ObligationID) && ...
        state.PendingCSITable.CSIReferenceSlot==obligation.CSIReferenceSlot && ...
        state.PendingCSITable.SourceSlot==csi.Slot && ...
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
    [grant,candidateLedger]=sixgr.truth.prepareScheduledDLDAI(state.ScheduledDLDAILedger,dl,grant);
    grant.TransportBlockId=char(grant.PHYGrant.GrantContextId);
    grant.TBId=grant.TransportBlockId;
    assert((grant.TimingDecision.DataAbsoluteSlot==5 || (state.TestDAIMonitorOmission && slot==7 && grant.TimingDecision.DataAbsoluteSlot==6)) && grant.TimingDecision.FeedbackAbsoluteSlot==9, ...
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
assert(isfield(state,'TestReceivedDLClock'),'Actual shared SS/PBCH timing is required for connected DL control.');
controlContext.ReceivedDLTimingReference=state.TestReceivedDLClock;
owner.queuePDCCH(1,control,controlContext);
if sharedHARQ, state.ScheduledDLDAILedger=candidateLedger; end
result=sixgr.truth.executeGrantPHYJob(job);
assert(~result.ReadyForReceiverCommit && isempty(result.Result.TrialTable));
owner.queueData(1,result.Result.PreparedTransmission,struct('Job',job,'SharedCSISource',~sharedHARQ,'SharedHARQSource',sharedHARQ));
if state.TestPacketAccounting
    state=localOfferPacket(state,'DL',grant.TBSBits);
else
    state.DLQueueBits(1)=state.DLQueueBits(1)+grant.TBSBits;
end
if slot==6, state.TestSharedCSIReceived=false; end
end


function out=localBindAndCheckEmbeddedCSI(state,raw,p,receiver,ue)
% No receiver re-execution: bind/check copies of this original completion.
owner=state.SharedWaveformStream;
before=rng;
out=sixgr.truth.bindSharedDLCSICompletion(raw,p,receiver,owner,state,ue);
if ~isfield(raw,'CSIRSTrialTable') || isempty(raw.CSIRSTrialTable), return; end
assert(isequaln(raw.CSIRSTrialTable,out.CSIRSTrialTable(:,raw.CSIRSTrialTable.Properties.VariableNames)), ...
    'Binding installation must preserve every original practical measurement.');
assert(isequaln(out,sixgr.truth.bindSharedDLCSICompletion(out,p,receiver,owner,state,ue)));
localReject(@()sixgr.truth.bindSharedDLCSICompletion(raw,p,receiver,owner), ...
    'sixgr:truth:CSICompletionStateRequired');
bad=raw; bad.CSIRSTrialTable.UEIndex(:)=ue+1;
localReject(@()sixgr.truth.bindSharedDLCSICompletion(bad,p,receiver,owner,state,ue), ...
    'sixgr:truth:CSICompletionReceiverIdentity');
bad=raw; bad.CSIRSTrialTable.ServingCell=repmat(state.CurrentServingIdx(ue)+1,height(bad.CSIRSTrialTable),1);
localReject(@()sixgr.truth.bindSharedDLCSICompletion(bad,p,receiver,owner,state,ue), ...
    'sixgr:truth:CSICompletionReceiverIdentity');
badState=rmfield(state,'SharedWaveformStream');
localReject(@()sixgr.truth.bindSharedDLCSICompletion(raw,p,receiver,owner,badState,ue), ...
    'sixgr:truth:CSICompletionStateRequired');
bad=out; bad.CSIRSTrialTable.DLMeasurementConfigurationSHA256(:)="changed-original-binding";
localReject(@()sixgr.truth.bindSharedDLCSICompletion(bad,p,receiver,owner,state,ue), ...
    'sixgr:truth:CSICompletionInstallationConflict');
if sixgr.truth.DLMeasurementInstallation.required(state)
    assert(isfield(state,'TestActualSIB1Installation') && ...
        all(out.CSIRSTrialTable.DLMeasurementAuthorityEligible) && ...
        all(out.CSIRSTrialTable.DLMeasurementInstallationSHA256==state.TestActualSIB1Installation.SHA256) && ...
        all(out.CSIRSTrialTable.ObservationStartSample>=state.TestActualSIB1Installation.EffectiveSample));
    missing=state; missing.PreconfiguredDLMeasurementInstallationByUE{ue}=[];
    unavailable=sixgr.truth.bindSharedDLCSICompletion(raw,p,receiver,owner,missing,ue);
    assert(all(~unavailable.CSIRSTrialTable.DLMeasurementAuthorityEligible) && ...
        all(unavailable.CSIRSTrialTable.DLMeasurementAuthorityStatus== ...
        "awaiting_received_DL_acquisition_and_configuration"));
    changed=state;
    changed.CfgMobility.phy.csi.reportConfigurationEpoch= ...
        changed.CfgMobility.phy.csi.reportConfigurationEpoch+1;
    unavailable=sixgr.truth.bindSharedDLCSICompletion(raw,p,receiver,owner,changed,ue);
    assert(all(~unavailable.CSIRSTrialTable.DLMeasurementAuthorityEligible) && ...
        isequal(unavailable.CSIRSTrialTable.DLMeasurementConfigurationSHA256, ...
        out.CSIRSTrialTable.DLMeasurementConfigurationSHA256));
end
assert(isequal(before,rng));
fprintf('EMBEDDED_CSI_INSTALLATION_BINDING_PASS rows=%d negative_guards=7 additional_RX=0\n',height(out.CSIRSTrialTable));
end

function state=localCompleteSharedHARQSource(state,item,p,pre,tx,replay,receiver)
% Same actual shared DCI/decoder/event/slot reducer used by the coordinator.
owner=state.SharedWaveformStream;
key=sixgr.util.sha256Hex(uint8(char(string(item.Context.Job.GrantSnapshot.PHYGrantContextId))));
assert(isfield(state.TestSharedDLControlByGrant,"g_"+extractBefore(key,62)));
control=state.TestSharedDLControlByGrant.("g_"+extractBefore(key,62));
assert(string(control.Grant.PHYGrantContextId)==string(item.Context.Job.GrantSnapshot.PHYGrantContextId));
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
out=localBindAndCheckEmbeddedCSI(state,out,p,receiver,item.UE);
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
meta=fullfile(root,'meta'); if ~isfolder(meta), mkdir(meta); end
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

function state=localVerifySelectedPUSCHRecovery(state)
owner=state.SharedWaveformStream;old=state.TestWithheldPUCCH;
due=state.TestSSBRecoveryReportSlot;
assert(old.ReceiverCompleted && state.TestPUSCHReceived && state.ULHarq.Stats.Tx==1);
assert(numel(owner.PUCCHTransmissions)==0 && numel(owner.DataTransmissions)==2);
assert(isequaln(state.DLHarq.Stats,old.HARQAfter) && height(state.SharedGNBUCIHARQTable)==1);
assert(numel(state.SharedPUSCHHARQFeedbackReceipts)==1);
original=state.TestRecoveryPUSCHOriginalReport;
received=state.SharedGNBCSIReportTable(state.SharedGNBCSIReportTable.DueSlot==due,:);
assert(height(original)==1 && original.SourceSlot==6 && height(received)==1 && received.CSIUCIDecodeOk);
assert(received.ReportIdentity==original.ReportIdentity && received.CSIReferenceSlot==original.CSIReferenceSlot);
pending=state.PendingCSITable(string(state.PendingCSITable.ReportIdentity)==string(original.ReportIdentity),:);
assert(height(pending)==1 && pending.Processed && pending.CSIUCIDecodeOk && ...
    pending.SourceSlot==6);
assert(pending.MeasurementAvailableAtSample==original.MeasurementAvailableAtSample && ...
    pending.UECSIMeasurementInstallationSHA256==original.UECSIMeasurementInstallationSHA256);
expired=state.PendingCSITable(string(state.PendingCSITable.ReportIdentity)==string(old.FinalReport.ReportIdentity),:);
assert(isequaln(expired(:,old.FinalReport.Properties.VariableNames),old.FinalReport));
oldTrace=state.PUCCHGrantTraceTable(ismember(string(state.PUCCHGrantTraceTable.PUCCHGrantId),old.OriginalGrantIDs),:);
assert(isequaln(oldTrace(:,old.FinalTrace.Properties.VariableNames),old.FinalTrace));
controls=state.SharedReceivedGrantControls;
ul=controls(cellfun(@(x)string(x.Grant.Direction)=="UL" && x.Grant.Slot==due,controls));
assert(isscalar(ul) && ul{1}.Allowed && ul{1}.ReceivedAssignment.Direction=="UL");
srs=state.TestRecoverySRSOriginal; timing=state.TestRecoveryPUSCHTiming;
assert(isequaln(srs.Measurement,state.TestRecoveryGrantOriginalSRS) && srs.Measurement.Slot==9);
assert(ul{1}.Grant.LastSuccessfulSRSSlot==9 && ...
    string(ul{1}.Grant.SRSCausalMeasurementId)==string(srs.Measurement.ID));
withheld=state.ControlTrials.PUCCH(state.ControlTrials.PUCCH.Slot==10,:);
assert(~isempty(withheld) && ...
    all(srs.ObservationEndSampleExclusive<=withheld.ObservationStartSample));
assert(timing.Trial.CRCPass==1 && ...
    timing.ObservationStartSample>=srs.ObservationEndSampleExclusive);
receipt=struct('OriginalWithheldSlot',10,'RecoverySlot',due,'OriginalCSIProducerSlot',6, ...
    'OriginalMeasurementAvailableAtSample',original.MeasurementAvailableAtSample, ...
    'CSIObservationAgeAtReportSlots',due-6,'NewCSIObservationClaimed',false, ...
    'OldObligationReplayed',false,'SpatialMeasurementSlot',9, ...
    'ReceiverTimingSource','original_PUSCH_DMRS','SRSTimingTransferClaimed',false,'OriginalReportIdentity',original.ReportIdentity, ...
    'ReceivedULAssignmentDigest',ul{1}.ReceivedAssignment.AssignmentDigest, ...
    'ReceivedCSIObservationID',received.ObservationID,'SharedPUSCHReceiptCount',1, ...
    'FullAccessQualified',false,'StatisticalQualification',false);
sixgr.util.jsonWrite(fullfile(state.TestRoot,'selected_pusch_recovery_receipt.json'),receipt);
save(fullfile(state.TestRoot,'selected_pusch_recovery_original.mat'),'original','pending','received','receipt','srs','timing','-v7.3');
state.TestSelectedPUSCHRecoveryReceipt=receipt;
fprintf('SELECTED_PUSCH_RECOVERY_PASS original_noTX_preserved=1 actual_received_UL_DCI=1 original_CSI_source_slot=6 new_CSI_claimed=0\n');
end
