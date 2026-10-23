function [ok,state]=testSharedPeriodicCSIProducer(producerMode,withReceivedClock)
% Actual periodic PUCCH and CSI-RS-bearing DL IQ/CDL/RF/thermal noise.
% UE CSI values/access timing remain declared component-boundary inputs,
% not end-to-end CSI measurement or access qualification.
if nargin<2, withReceivedClock=false; end
if nargin==0
    [ok,state]=testSharedPeriodicCSIProducer("present");
    [removedOK,removed]=testSharedPeriodicCSIProducer("remove_after_tx");
    [absentOK,~]=testSharedPeriodicCSIProducer("absent");
    a=removevars(state.SharedGNBCSIReportTable,'UEReferenceRecordJSON');
    b=removevars(removed.SharedGNBCSIReportTable,'UEReferenceRecordJSON');
    assert(isequaln(state.TestPeriodicCSICaptures,removed.TestPeriodicCSICaptures), ...
        'test:CSIProducerAuditCounterfactualChanged', ...
        'Removing optional producer audit must preserve exact receiver samples and capture clocks.');
    assert(isequaln(a,b),'Removing optional UE producer audit must not change gNB CSI publication.');
    ok=ok && removedOK && absentOK;
    fprintf('INDEPENDENT_PERIODIC_CSI_RECEPTION_PASS present_removed_absent=3 calendar_arms_without_producer=1\n');
    return;
end
assert(any(producerMode==["present","remove_after_tx","absent"]));
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmpi(which('sixgr.truth.CoupledTruthRuntime'), ...
    fullfile(root,'+sixgr','+truth','CoupledTruthRuntime.m')));
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
cfg.phy.csirs.period_slots=5; cfg.phy.csirs.offset_slots=0;
% This test isolates CSI transport. The shared queue YAML now also installs
% an SR calendar; absent-SR and installed-SR are explicitly exercised
% separately by verifyInstallationBoundary below. Do not disable production
% SR or mistake its legitimate receive window for premature CSI reception.
cfg.validation.pucch_resources.scheduling_request_resources=struct([]);
cfg.validation.pucch_resources.sr_resource_ids=[];
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
% Direct component initialization generates layout using the global stream
% before the link runner seeds its own work. Freeze that earlier boundary so
% present/removed producer cases compare identical channels and RX samples.
callerRNG=rng; restoreRNG=onCleanup(@()rng(callerRNG)); %#ok<NASGU>
rng(cfg.run.seed,'twister');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,cfg.channel.snr_dB);
state.CurrentServingIdx(:)=1;
% Explicit already-connected component boundary. This test does not execute
% random access; the production access gate remains enabled and unchanged.
% Timing, CSI input and access are declared fixtures; only transport is PHY.
assert(~sixgr.truth.CoupledRadioIdentity.connectedReady(state,1), ...
    'The cold fixture must not implicitly qualify connected CSI reception.');
state.AccessState(1)="succeeded";
state.TestAccessBoundary="declared_preconnected_component_fixture_not_physical_RA";
assert(sixgr.truth.CoupledRadioIdentity.connectedReady(state,1));
state.TestCSIProducerMode=producerMode;
state.TestCSIWithReceivedClock=logical(withReceivedClock);
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
if producerMode=="present", verifyInstallationBoundary(state,cfg); end
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
% The gNB receive obligation requires actual reference TX independently of
% the declared UE measurement below, including the absent-producer episode.
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,1);
dl=sixgr.truth.bindSharedDataOccasion(dl,1,1,fs);
g=sixgr.link.resolveWaveformGrant(dl,'DL',1,'Slot',1,'SFN',0,'ControlAbsoluteSlot',0);
allocated=state.DLHarq.allocate(g.RNTI,1,g.TBSBytes,'NewData',true);
g=sixgr.link.resolveWaveformGrant(dl,'DL',1,'Slot',1,'SFN',0,'ControlAbsoluteSlot',0, ...
    'HARQProcess',allocated.HARQ.HarqID);
job=sixgr.truth.buildGrantPHYJob(dl,'DL',cfg.channel.snr_dB,1,[], ...
    struct('GrantSnapshot',g,'PHYGrant',g.PHYGrant,'PrepareOnly',true));
job.StartSlotIndex=1; result=sixgr.truth.executeGrantPHYJob(job);
owner.queueData(1,result.Result.PreparedTransmission,struct('Purpose',"actual_CSI_reference_TX_not_UE_measurement"));
state.DLQueueBits(1)=state.DLQueueBits(1)+g.TBSBits;
[~,fixtureLink]=sixgr.link.applyWaveformImpairments(complex(zeros(1,1)),ul,fs,'ApplyRFChain',false);
pl=double(fixtureLink.AppliedLargeScaleLoss_dB);
ssb=table(0,pl,"SSB-0","analytic_component_pathloss_selector_fixture",1,-pl,0, ...
    'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB','PathlossReferenceRS', ...
    'MeasuredReferenceSignalPathlossSource','ServingCell','SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,ssb,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','analytic_component_selector_fixture');
if withReceivedClock
    % Same real shared-SRS preparation as the HARQ timing fixture. The slot-9
    % CSI receiver must use its completed slot-5 clock, never the UE TX time.
    [srsCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
    srsCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(srsCfg,5);
    srsCfg.lls6g.userContext.RuntimeSlotStartTime_s=4e-3;
    args={'SlotIndex',5,'SNR_dB',cfg.channel.snr_dB,'TimingAdvanceSamples',0};
    prepared=sixgr.link.runSRSChannelEstimation(srsCfg,args{:},'PrepareOnly',true);
    owner.queueUplinkControl(1,prepared.PreparedTransmission,struct('Config',srsCfg,'Arguments',{args}));
end
row=table(1,1,1,true,true,true,true,true,true,10,1,0,0,0,18.5, ...
    "declared_received_CSI_periodic_transport_fixture", ...
    'VariableNames',{'Slot','UEIndex','ServingCell','Transmitted','Observed','Consumed', ...
    'ResourceExtractionAvailable','ChannelEstimateAvailable','CSIMeasurementAvailable', ...
    'CQI','RI','PMI','CRI','LI','SINR_dB','MeasurementSource'});
row.ObservationDeliverySlot=2;
row.RNTI=sixgr.truth.CoupledRadioIdentity.resolve(state,1);
row.ObservationStartSample=0;
row.ObservationEndSampleExclusive=sixgr.phy.frame.slotStartSample(carrier,1,fs);
row.ResultAvailableAtSample=row.ObservationEndSampleExclusive;
row.ObservationSampleRateHz=fs; row.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
row.MeasurementClockDomain="shared_receiver_sample_clock/v1";
% Explicit component-boundary identity, not a claimed physical CSI estimate.
reportCfg=sixgr.phy.mimo.CSIReportConfiguration( ...
    cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfigurationEpoch);
row.CSIReportConfigID=string(reportCfg.ReportConfigID);
row.CSIConfigurationEpoch=double(reportCfg.Epoch);
row.CSIMeasurementID="declared_transport_fixture_CSI1";
row.CSIMeasurementDigest="declared_transport_fixture_not_physical_measurement_digest";
row.DeliverySlotStartSample=row.ResultAvailableAtSample;
row.DeliverySlotEndSampleExclusive=sixgr.phy.frame.slotStartSample(carrier,2,fs);
% Retained future boundary fixture: it must not become usable before the
% real owner reaches its declared completion. No UE PDSCH/CSI decoder is run.
if producerMode~="absent"
    state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,row);
end
queuedReport=table();
for slot=1:10
    [state,~,blocked]=sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
        state,cfg,'DL',1,1,slot,10,cfg.channel.snr_dB,repmat(struct(),0,1),true);
    assert(isempty(blocked));
    if slot<=4, assert(isempty(state.PendingCSITable)); end
    if ~isempty(state.PendingCSITable) && ~state.PendingCSITable.Processed
        queuedReport=state.PendingCSITable;
        assert(queuedReport.MeasurementAvailableAtSample==row.ResultAvailableAtSample && ...
            queuedReport.MeasurementAvailableSlot==row.ObservationDeliverySlot && ...
            queuedReport.MeasurementClockEpoch==row.MeasurementClockEpoch && ...
            queuedReport.MeasurementClockDomain==row.MeasurementClockDomain, ...
            'The UE queue must retain the actual measurement-completion clock before transmission.');
        assert(queuedReport.MeasurementAvailableAtSample<=owner.Events.NextSampleIndex);
    end
    [state,~]=owner.advanceSlot(state,cfg,@receive);
end
report=sixgr.util.structGet(state,'SharedGNBCSIReportTable',table());
% Retain the actual received fields/clock even when a later assertion fails.
saveEvidence(root,cfg,row,queuedReport,report,struct(),state,fs);
assert(height(report)==1,'test:MissingIndependentCSIReception', ...
    'Expected one configured physical CSI reception; inspect retained obligations and queued input.');
fprintf('PERIODIC_CSI_RECEIVED mode=%s CQI=%g RI=%g PMI=%g due=%g delivered=%g available_sample=%g fs=%g state_slot=%g\n', ...
    producerMode,report.CQI,report.RI,report.PMI,report.DueSlot,report.DeliveredSlot, ...
    report.AvailableAtSample,fs,state.CurrentSlot);
assert(height(report)==1 && report.DueSlot==9 && report.SourceSlot==4 && report.CSIReferenceSlot==4);
assert(report.SourceSlotAuthority=="configured_CSI_reference_resource_not_UE_measurement_slot");
assert(height(state.ControlTrials.PUCCH)==1 && isempty(state.PendingFeedbackTable) && ...
    numel(state.SharedGNBUCIReceptions)==1);
% Publication, not transmitter presence or decoding alone, owns disposition.
% This also covers absent producers and a removed optional UE audit record.
trial=state.ControlTrials.PUCCH;
assert(all(ismember({'RuntimeStateUpdated','ControlStateChanged', ...
    'StateChangeApplied','CSIReportStateChangeApplied'},trial.Properties.VariableNames)), ...
    'test:MissingCSITrialDisposition','Completed CSI reception must export its actual publication disposition.');
delivered=string(report.DeliveryStatus)=="delivered_to_runtime_scheduler";
assert(trial.RuntimeStateUpdated && trial.ControlStateChanged==delivered && ...
    trial.StateChangeApplied==delivered && trial.CSIReportStateChangeApplied==double(delivered), ...
    'test:CSITrialDispositionMismatch','Trial flags must match the completed CSI publication, including rejected reports.');
rx=state.SharedGNBUCIReceptions{1}.Receiver;
assert(rx.IndependentReceiverAssignment && ~rx.PreparedTransmitterConsumed && ~rx.OraclePayloadBitsUsed);
if withReceivedClock
    reference=state.ReceivedULTimingReferences{1};
    assert(isa(reference,'sixgr.phy.sync.ReceivedULTimingReference') && reference.SourceSignal=="SRS");
    assert(isfield(rx.ReceiveTiming,'ReferenceAvailableAtSample') && ...
        rx.ReceiveTiming.ReferenceAvailableAtSample==reference.AvailableAtSample && ...
        rx.ReceiveTiming.ReferenceAgeSlots==4 && ...
        ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed, ...
        'test:ConfiguredCSIReceivedClockBindingMissing', ...
        'Configured CSI PUCCH must retain the causally completed, fresh SRS clock through reception.');
end
% The new callback publishes at completed reception, not the next legacy
% processDueFeedback pass. Check exact CP-OFDM bounds, not a fixed delay.
deliveryStart=sixgr.phy.frame.slotStartSample(carrier,report.DeliveredSlot-1,fs);
deliveryStop=sixgr.phy.frame.slotStartSample(carrier,report.DeliveredSlot,fs);
assert(report.AvailableAtSample==report.ObservationEndSampleExclusive && ...
    report.AvailableAtSample>=deliveryStart && report.AvailableAtSample<deliveryStop);
assert(state.PUCCHFailureCount==double(~report.CSIUCIDecodeOk) && state.PUCCHCrashCount==0);
if report.CSIUCIDecodeOk
    assert(state.LastSuccessfulPUCCHSlotByUE==report.DueSlot);
else
    assert(isnan(state.LastSuccessfulPUCCHSlotByUE));
end
if producerMode=="absent"
    assert(isempty(state.PendingCSITable) && isempty(state.PUCCHGrantTraceTable) && ...
        numel(owner.DataTransmissions)==1 && ~state.ControlTrials.PUCCH.PUCCHTransmissionPrepared);
    assert(report.Processed && state.LatestDLFeedback.Valid==report.CSIUCIDecodeOk);
    % A false CSI detection is retained, not masked using known TX absence.
    assert(report.CSIUCIDecodeOk==state.ControlTrials.PUCCH.PUCCHDecodeOk);
    trial=state.ControlTrials.PUCCH;
    assert(trial.ReceiverUsable==rx.ReceiverUsable && trial.DTXFlag==rx.DTX, ...
        'Receiver-only trial must preserve the independently executed receiver flags.');
    assert(trial.SignalPresent==0 && trial.PresenceTargetNonzeroInputSamples==0 && ...
        trial.TrialType=="no_signal_before_receiver_noise_and_RF" && ...
        trial.FalseAlarmFlag==double(rx.DetectionOutcome=="detected") && ...
        trial.FalseAcceptanceFlag==double(rx.ReceiverUsable && ~rx.DTX && ...
            (~rx.CRCApplicable || rx.CRCPassed)) && ...
        ~trial.PresenceIndependentTrialsEstablished && ~trial.PresenceScoringUsedByReceiver, ...
        'An actual absent-signal observation must retain its false detection, not a reliability PASS.');
    widths=[trial.ReceiverExpectedHARQBitCount trial.ReceiverExpectedSRBitCount ...
        trial.ReceiverExpectedCSIPart1BitCount trial.ReceiverExpectedCSIPart2BitCount];
    assert(all(isfinite(widths)) && sum(widths)==trial.ReceiverExpectedBitCount && ...
        trial.DecodedBitCount==numel(rx.DecodedSequence1)+numel(rx.DecodedSequence2), ...
        'Record all independently scheduled fields, including a zero-length CSI Part 2.');
    exported=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable("PUCCH",trial);
    assert(exported.ReceiverUsable==rx.ReceiverUsable && ...
        exported.DecodeSuccess==trial.PUCCHDecodeOk && ~exported.SuccessFlag, ...
        'Export must retain a false detection without claiming a successful transmission.');
    saveEvidence(root,cfg,row,queuedReport,report,struct(),state,fs);
    fprintf('PERIODIC_CSI_ABSENT_PRODUCER_PASS physical_observations=1 fabricated_TX=0 received_CSI=%d detector_qualified=0\n',report.CSIUCIDecodeOk);
    ok=true; return;
end
assert(report.Processed && report.CSIUCIDecodeOk && report.CSIUCITransport=="pucch_independently_received");
assert(report.CQI==10 && report.RI==1 && report.PMI==0, ...
    'test:IndependentPeriodicCSIFields','Received CQI=%g RI=%g PMI=%g; expected 10,1,0.', ...
    report.CQI,report.RI,report.PMI);
audit=struct();
if producerMode=="present"
audit=jsondecode(report.UEReferenceRecordJSON);
fprintf('PERIODIC_CSI_CLOCK_DIAGNOSTIC measured_available=%g projected_available=%g audit_available=%g audit_epoch=%g expected_epoch=%g audit_domain=%s\n', ...
    row.ResultAvailableAtSample,report.MeasurementAvailableAtSample, ...
    audit.MeasurementAvailableAtSample,audit.MeasurementClockEpoch, ...
    row.MeasurementClockEpoch,string(audit.MeasurementClockDomain));
assert(height(queuedReport)==1 && ...
    audit.MeasurementAvailableAtSample==row.ResultAvailableAtSample && ...
    audit.MeasurementAvailableSlot==row.ObservationDeliverySlot && ...
    audit.MeasurementClockEpoch==row.MeasurementClockEpoch && ...
    string(audit.MeasurementClockDomain)==row.MeasurementClockDomain && ...
    string(audit.ReportIdentity)==report.ReportIdentity && ...
    string(audit.CSIMeasurementID)==row.CSIMeasurementID && ...
    string(audit.CSIMeasurementDigest)==row.CSIMeasurementDigest && ...
    audit.SourceSlot==row.Slot && audit.DueSlot==report.DueSlot, ...
    'UE-only timing must survive publication in the bound audit record.');
else
    assert(isempty(state.PendingCSITable) && strlength(report.UEReferenceRecordJSON)==0);
end
assert(isnan(report.MeasurementAvailableAtSample) && isnan(report.MeasurementAvailableSlot) && ...
    isnan(report.MeasurementClockEpoch) && strlength(report.MeasurementClockDomain)==0 && ...
    strlength(report.CSIMeasurementID)==0 && strlength(report.CSIMeasurementDigest)==0 && ...
    isnan(report.SINR_dB) && report.SourceSignal=="received_CSI_UCI", ...
    'Decoded CSI fields must not masquerade as a reported UE measurement clock or raw SINR.');
assert(report.ReceiverClockEpoch==owner.Physical.ConfigurationEpoch && ...
    report.ReceiverClockDomain=="shared_receiver_sample_clock/v1", ...
    'Received UCI must retain its own clock epoch, not the UE audit clock.');
latency=sixgr.report.collectCSIReportLatency(report,state.ControlTrials.CSIRS);
delivery=sixgr.report.collectCSIReportDeliveryEvidence(report);
assert(height(delivery)==1 && delivery.EmissionVerified && delivery.BitComparisonAvailable && ...
    delivery.BitErrorCount==0 && delivery.CQIDeliveryCorrect==1 && ...
    delivery.RIDeliveryCorrect==1 && delivery.PMIDeliveryCorrect==1 && ...
    delivery.CorrectDeliveredFieldCount==delivery.TransmittedFieldCount, ...
    'Compare emitted serialization with independent decoded fields, not UE recommendations.');
assert(~isfield(state.LatestDLFeedback.ReceivedCSIReport,'CSIDeliveryAuditJSON') || ...
    strlength(state.LatestDLFeedback.ReceivedCSIReport.CSIDeliveryAuditJSON)==0, ...
    'Private TX scoring must not enter scheduler CSI state.');
if producerMode=="present"
    assert(height(latency)==1 && latency.LatencyAvailable && ...
        latency.MeasurementEndToDelivery_ms== ...
        (report.AvailableAtSample-row.ObservationEndSampleExclusive)*1000/fs, ...
        'Measured UCI completion and declared component-boundary CSI input must preserve exact audit timing.');
else
    assert(~any(latency.LatencyAvailable), ...
        'Physical UCI reception without the optional UE audit cannot manufacture end-to-end latency.');
end
assert(height(state.ControlTrials.PUCCH)==1 && state.ControlTrials.PUCCH.Slot==9 && ...
    state.ControlTrials.PUCCH.PUCCHDecodeOk);
assert(state.ControlTrials.PUCCH.PUCCHTransmissionPrepared && ...
    ~state.ControlTrials.PUCCH.ReceiverOnlyAssignment, ...
    'A real shared PUCCH must not inherit the no-producer union-schema flag.');
assert(state.ControlTrials.PUCCH.SignalPresent==1 && ...
    state.ControlTrials.PUCCH.PresenceTargetNonzeroInputSamples>0 && ...
    isnan(state.ControlTrials.PUCCH.FalseAlarmFlag), ...
    'Actual component consumption must establish H1; H1 is not part of an H0 denominator.');
assert(isempty(state.PendingFeedbackTable) && height(state.PUCCHGrantTraceTable)==1 && ...
    state.PUCCHGrantTraceTable.GrantExecutedFlag && isnan(state.PUCCHGrantTraceTable.HarqID));
assert(state.LatestDLFeedback.Valid && state.LatestDLFeedback.SchedulerCQIRawCQI==10);
verifyPUCCHPowerExport(state.ControlTrials.PUCCH,cfg);
folder=saveEvidence(root,cfg,row,queuedReport,report,audit,state,fs);
fprintf('SHARED_PERIODIC_CSI_PRODUCER_PASS actual_PUCCH_slot=9 delivered=%g CSI_reference=4 CSI_reference_TX=1 UE_CSI_declared_fixture=1 folder=%s\n',report.DeliveredSlot,folder);
ok=true;
end
function folder=saveEvidence(root,cfg,row,queuedReport,report,audit,state,fs)
logsRoot=fullfile(root,'logs'); if ~isfolder(logsRoot), mkdir(logsRoot); end
folder=tempname(logsRoot); mkdir(folder);
writetable(report,fullfile(folder,'periodic_CSI_received_report.csv'));
writetable(state.ControlTrials.PUCCH,fullfile(folder,'actual_PUCCH_trial.csv'));
writetable(sixgr.util.structGet(state,'CSIReportObligationTable',table()),fullfile(folder,'configured_CSI_obligations.csv'));
captures=sixgr.util.structGet(state,'TestPeriodicCSICaptures',struct([]));
timingReferences=sixgr.util.structGet(state,'ReceivedULTimingReferences',{});
save(fullfile(folder,'shared_periodic_CSI.mat'),'cfg','row','queuedReport','report','audit','captures','fs','timingReferences');
fprintf('PERIODIC_CSI_EVIDENCE mode=%s folder=%s\n',state.TestCSIProducerMode,folder);
end
function verifyInstallationBoundary(state,cfg)
% No SR is installed in this CSI-only boundary. No UE procedure state or
% CSI producer is needed to derive this independent gNB receive schema.
h=sixgr.truth.buildConfiguredPUCCHReception(state,cfg,1,9,"installation_boundary");
assert(isempty(h),'A configured CSI calendar without actual reference TX is not an eligible report.');
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_tdd_shared_csi_sr_fixture.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
withSR=sixgr.truth.buildConfiguredPUCCHReception(state,installed,1,9,"installation_boundary");
assert(withSR.Context.SRBits==1 && withSR.Context.CSIPart1Bits==0 && isempty(withSR.Mapping));
poisoned=state; poisoned.UEConfiguredSRProcedures={struct('PendingPositiveSR',true)};
again=sixgr.truth.buildConfiguredPUCCHReception(poisoned,installed,1,9,"installation_boundary");
assert(again.Context.Digest==withSR.Context.Digest && again.Assignment.Digest==withSR.Assignment.Digest);
bad=installed;
bad.validation.pucch_resources.scheduling_request_resources.offset_slots=5;
rejected=false;
try, sixgr.truth.buildConfiguredPUCCHReception(state,bad,1,9,"installation_boundary");
catch cause
    if ~strcmp(cause.identifier,'sixgr:truth:InvalidInstalledSRCalendar'), rethrow(cause); end
    rejected=true;
end
assert(rejected,'Malformed installed SR must not be treated as an absent procedure.');
fprintf('CSI_RX_INSTALLATION_BOUNDARY_PASS absent_SR=1 installed_SR=1 UE_state_not_consumed=1 malformed_rejected=1\n');
end
function state=receive(state,items)
for item=items
    if item.Kind=="DataTX"
        state=sixgr.truth.commitSharedDataTransmission(state,item);
        continue;
    elseif item.Kind=="PDSCH"
        continue; % This transport fixture deliberately does not run a UE DL decoder.
    elseif item.Kind=="SRS"
        c=item.Context; p=c.Prepared;
        [~,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
        [~,~,channelReferences]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        input=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ScoringChannelReferences',{channelReferences}, ...
            'ChannelState',state.SharedWaveformStream.directionalChannelState(item.UE,'UL'));
        output=sixgr.link.runSRSChannelEstimation(c.Config,c.Arguments{:},'ReceivedContext',input);
        reference=sixgr.truth.retainReceivedSRSTimingReference(p,receiver,output);
        assert(isa(reference,'sixgr.phy.sync.ReceivedULTimingReference'), ...
            'test:ConfiguredCSIReceivedClockUnavailable','Actual SRS must establish its received timing.');
        state=sixgr.truth.storeReceivedULTimingReference(state,item.UE,reference);
        fprintf('CONFIGURED_CSI_SRS_CLOCK_RECEIVED nominal=%g available=%g\n', ...
            reference.NominalStartSample,reference.AvailableAtSample);
        continue;
    end
    if item.Kind=="PUCCHTX"
        state=sixgr.truth.commitSharedPUCCHTransmission(state,item);
        if state.TestCSIProducerMode=="remove_after_tx"
            state.PendingCSITable=state.PendingCSITable([],:);
        end
        continue;
    end
    if item.Kind=="PreparePUCCH"
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
    elseif any(item.Kind==["PUCCH","PUCCHReceiveOnly"])
        captures=struct('ReceiverID',{},'Samples',{},'StartSample',{},'EndSampleExclusive',{});
        for i=1:numel(item.Planes)
            plane=item.Planes(i); obs=plane.Observation;
            captures(i)=struct('ReceiverID',plane.ReceiverID,'Samples',obs.readComplete(), ...
                'StartSample',obs.StartSample,'EndSampleExclusive',obs.EndSampleExclusive);
        end
        state.TestPeriodicCSICaptures=captures;
        if state.TestCSIWithReceivedClock, state.TestReceivedPUCCHItem=item; end
        assert(isfield(item.Context,'GNBReception') && isempty(item.Context.GNBReception.Mapping));
        h=item.Context.GNBReception;
        receiverID="gnb_"+h.ServingCell+"_rx";
        postPlane=item.Planes(string({item.Planes.ReceiverID})==receiverID+":post_rf");
        assert(isscalar(postPlane));
        % Wiring reference only: replay the same actual ADC samples using
        % receiver-known applied gain. No TX bits, noiseless grid or injected
        % noise variance may decide whether frontend calibration is applied.
        [receiverInput,gain]=sixgr.phy.rx.compensateReceivedAGC( ...
            postPlane.Observation,postPlane.Segments,receiverID);
        prior=[];
        if state.TestCSIWithReceivedClock
            carrier=sixgr.phy.grid.makeCarrier(item.Context.Config);
            nominal=sixgr.phy.frame.slotStartSample(carrier,item.Context.Slot-1,receiverInput.SampleRateHz);
            prior=sixgr.truth.selectReceivedULTimingReference(state,item.UE,receiverInput.EndSampleExclusive,nominal);
            assert(isa(prior,'sixgr.phy.sync.ReceivedULTimingReference'));
        end
        direct=sixgr.link.receivePUCCHObservation( ...
            item.Context.Config,h.Assignment,h.Context,receiverInput,prior);
        if item.Kind=="PUCCHReceiveOnly"
            tx=find(string({captures.ReceiverID})=="ue_1:tx");
            assert(isscalar(tx) && all(captures(tx).Samples==0,'all'));
            state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,item);
        else
            state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(state,item);
        end
        actual=state.SharedGNBUCIReceptions{end}.Receiver;
        beforePublication=state.SharedGNBCSIReportTable; beforeFeedback=state.LatestDLFeedback;
        audit=sixgr.truth.scoreSharedPUCCHPresence(item,actual,state.SharedWaveformStream.Physical.ConfigurationEpoch);
        assert(audit.SignalPresent==state.ControlTrials.PUCCH.SignalPresent && ...
            state.ControlTrials.PUCCH.DetectionMetricSource==actual.DetectionMetricSource);
        legacy=item;
        for pi=1:numel(legacy.Planes)
            for si=1:numel(legacy.Planes(pi).Segments)
                legacy.Planes(pi).Segments{si}.Execution=rmfield( ...
                    legacy.Planes(pi).Segments{si}.Execution,'ExecutedContributors');
            end
        end
        unavailable=sixgr.truth.scoreSharedPUCCHPresence(legacy,actual, ...
            state.SharedWaveformStream.Physical.ConfigurationEpoch);
        assert(isnan(unavailable.SignalPresent) && isnan(unavailable.FalseAlarmFlag));
        assert(isequaln(beforePublication,state.SharedGNBCSIReportTable) && ...
            isequaln(beforeFeedback,state.LatestDLFeedback), ...
            'Post-hoc presence scoring cannot change receiver publication or scheduler state.');
        fprintf('CSI_FRONTEND_REPLAY mode=%s actual_noise=%g calibrated_noise=%g actual_metric=%g calibrated_metric=%g applied_gain_min_db=%g applied_gain_max_db=%g\n', ...
            state.TestCSIProducerMode,actual.GridNoiseVariance,direct.GridNoiseVariance, ...
            actual.DetectionMetric,direct.DetectionMetric,gain.AppliedGainMin_dB,gain.AppliedGainMax_dB);
        for field=["DecodedSequence1","DecodedSequence2","DetectionMetric", ...
                "GridNoiseVariance","DTX","ReceiverUsable"]
            assert(isequaln(actual.(field),direct.(field)), ...
                'test:CSIReceiverFrontendMismatch', ...
                'Producer mode %s must not change receiver frontend processing: %s.', ...
                state.TestCSIProducerMode,field);
        end
        assert(isfield(actual,'ReceiverGainCompensation') && ...
            isequaln(actual.ReceiverGainCompensation,gain), ...
            'test:CSIReceiverGainEvidence','Retain the actual receiver gain-compensation evidence.');
        report=state.SharedGNBCSIReportTable;
        assert(height(report)==1 && report.AvailableAtSample==state.SharedWaveformStream.Events.NextSampleIndex && ...
            report.AvailableAtSample==report.ObservationEndSampleExclusive, ...
            'CSI must publish in its actual completed-reception callback.');
        before=state.LatestDLFeedback;
        beforeCounts=[state.LastSuccessfulPUCCHSlotByUE state.PUCCHFailureCount state.PUCCHCrashCount];
        rejected=false;
        try, sixgr.truth.CoupledTruthRuntime.completeConfiguredPUCCHCSI(state,item);
        catch cause
            if ~strcmp(cause.identifier,'sixgr:truth:InvalidConfiguredCSICompletion'), rethrow(cause); end
            rejected=true;
        end
        assert(rejected && isequaln(before,state.LatestDLFeedback) && ...
            isequaln(beforeCounts,[state.LastSuccessfulPUCCHSlotByUE state.PUCCHFailureCount state.PUCCHCrashCount]));
    else
        error('test:UnexpectedPeriodicCSIEvent','Unexpected %s.',item.Kind);
    end
end
end
