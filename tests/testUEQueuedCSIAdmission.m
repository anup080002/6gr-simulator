function ok=testUEQueuedCSIAdmission()
% Declared received-acquisition/CSI boundaries on the real shared idle clock.
% Exercises actual typed report enqueue/reservation and UE admission, not
% on-air acquisition, CSI reception or a reconfiguration protocol. Existing
% shared UCI waveform regressions separately cover encoded transport paths.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=fullfile(pwd,'results','validation','ue_queued_csi_admission',char(java.util.UUID.randomUUID()));
mkdir(folder); cfg=sixgr.lls6g.buildInternalConfig(s,folder); cfg.run.rootRunFolder=folder;
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,-10); cfg.outputs.continuousRawIQCaptureEnabled=false;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),40);
state.ControlGating.PBCHRequired=true;
state.ControlGating.PRACHRequired=false; state.AccessState(:)="not_required";
state.CellAcquisitionState(:)="searching"; state.CurrentServingIdx(:)=1;
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,40,-10);
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[state,completed]=owner.advanceSlot(state,cfg); assert(isempty(completed));
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,2,40,-10);
fs=owner.SampleRateHz; n=owner.Events.NextSampleIndex;
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
decoded=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
commonCfg=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),decoded);
common=commonCfg.UECommonCellConfiguration;
common.ServingCell=1; common.AvailableSlot=2; common.ConfigurationEpoch=cfg.initial_access.configuration_epoch;
common.ReceivedDLTimingReference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'ObservationStartSample',0,'AvailableAtSample',n, ...
    'NCellID',bound.phy.carrier.NCellID,'SSBIndex',0,'ReceivedSFN',0, ...
    'ReceivedHalfFrame',0,'DLPhaseOffsetSamples',0);
state.UECommonCellConfigurationByUE={common};
state.CellAcquisitionState(:)="acquired"; state.LastSuccessfulPBCHSlotByUE(:)=2;
state=sixgr.truth.DLMeasurementInstallation.install(state,1,bound);
carrier=sixgr.phy.grid.makeCarrier(bound);
state.ConnectedULTimingByUE={struct('DLReference',common.ReceivedDLTimingReference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',n,'TimingAdvanceEffectiveAtSample',n, ...
    'TimeAlignmentExpirySampleExclusive',40*n)};
[state,completed]=owner.advanceSlot(state,cfg); assert(isempty(completed));
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,3,40,-10);
state.CSIFeedbackSlots=10; % Declared long queue delay; not an RF configuration change.
measurement=declaredMeasurement(state,bound,n,2*n,2);
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,measurement);
state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',measurement,bound,measurement);
original=table2struct(state.PendingCSITable(end,:));
[allowed,~]=sixgr.truth.UEQueuedCSIAdmission.eligible(state,original);
assert(allowed && ~original.UECSIPayloadRetired && ~original.CSIUCIDecodeOk && ...
    original.UECSIMeasurementInstallationSHA256==measurement.DLMeasurementInstallationSHA256);
same=sixgr.truth.DLMeasurementInstallation.install(state,1,bound);
assert(isequaln(sixgr.truth.UEQueuedCSIAdmission.reconcile(same),same));
state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
originalIndex=find(string(state.PendingCSITable.ReportIdentity)==string(original.ReportIdentity));
assert(isscalar(originalIndex));
trace=state.PUCCHGrantTraceTable; pending=owner.Pending;
assert(any(string(trace.PUCCHGrantId)=="PUCCH-CSI-"+string(original.ReportIdentity)) && ...
    ~sixgr.truth.UEQueuedCSIAdmission.waveformBound(state,original));
assert(any(sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueUEsRuntime(state,original.DueSlot)==1));
groups=1;

% Same cell/report epoch; only the UE's private acquisition changed.
before=state; random=rng;
state.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.ObservationStartSample=n;
state.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.AvailableAtSample=2*n;
state.UECommonCellConfigurationByUE{1}.AvailableSlot=3;
state.LastSuccessfulPBCHSlotByUE(:)=3;
state=sixgr.truth.DLMeasurementInstallation.install(state,1,bound);
state=sixgr.truth.UEQueuedCSIAdmission.reconcile(state);
retired=table2struct(state.PendingCSITable(originalIndex,:));
assert(retired.UECSIPayloadRetired && ~retired.Processed && ~retired.RightCensored && ...
    ~retired.CSIUCIDecodeOk && isnan(retired.DeliveredSlot));
assert(isequal(retired.CSIPart1BitsToken,original.CSIPart1BitsToken) && ...
    isequal(retired.CSIPart2BitsToken,original.CSIPart2BitsToken) && ...
    retired.UECSIMeasurementInstallationSHA256==original.UECSIMeasurementInstallationSHA256);
assert(isequaln(owner.Pending,pending) && isequaln(state.PUCCHGrantTraceTable,trace) && ...
    isequaln(state.LatestDLFeedback,before.LatestDLFeedback) && ...
    isequaln(state.PendingFeedbackTable,before.PendingFeedbackTable) && ...
    isequaln(state.CSIReportObligationTable,before.CSIReportObligationTable) && ...
    state.CfgMobility.phy.csi.reportConfigurationEpoch==before.CfgMobility.phy.csi.reportConfigurationEpoch && ...
    isequal(random,rng));
assert(isempty(sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueUEsRuntime(state,original.DueSlot)));
once=sixgr.truth.UEQueuedCSIAdmission.reconcile(state);
assert(isequaln(once,state) && numel(state.UECSIPayloadRetirements)==1);
audit=sixgr.truth.UEQueuedCSIAdmission.auditTable(state);
assert(height(audit)==1 && audit.OriginalUEReportSHA256== ...
    string(sixgr.util.sha256Hex(audit.OriginalUEReportJSON)));
saved=jsondecode(audit.OriginalUEReportJSON);
assert(string(saved.CSIPart1BitsToken)==string(original.CSIPart1BitsToken) && ...
    ~saved.UECSIPayloadRetired && ~saved.CSIUCIDecodeOk);
groups=groups+1;

% A reservation flag is not proof of encoded IQ. It cannot preserve an old
% payload or cause its old PUSCH-layout bits to be reserialized on PUCCH.
reserved=before;
reserved.PreconfiguredDLMeasurementInstallationByUE=state.PreconfiguredDLMeasurementInstallationByUE;
reserved.UECommonCellConfigurationByUE=state.UECommonCellConfigurationByUE;
reserved.LastSuccessfulPBCHSlotByUE=state.LastSuccessfulPBCHSlotByUE;
reserved.PendingCSITable.CSIUCITransport=string(reserved.PendingCSITable.CSIUCITransport);
reserved.PendingCSITable.CSIUCITransport(originalIndex)="pusch_bound";
reserved.PendingCSITable.CSIUCIMultiplexedOnPUSCH(originalIndex)=true;
reserved.PendingCSITable.CSIUCIPUSCHGrantContextId=string(reserved.PendingCSITable.CSIUCIPUSCHGrantContextId);
reserved.PendingCSITable.CSIUCIPUSCHGrantContextId(originalIndex)="declared_unencoded_reservation";
reserved=sixgr.truth.UEQueuedCSIAdmission.reconcile(reserved);
assert(reserved.PendingCSITable.UECSIPayloadRetired(originalIndex) && ...
    string(reserved.PendingCSITable.CSIPart1BitsToken(originalIndex,:))==string(original.CSIPart1BitsToken) && ...
    ~sixgr.truth.UEQueuedCSIAdmission.waveformBound(reserved,original));
% A separate HARQ reservation still blocks/owns its actual due resource.
mixed=state; h=trace(string(trace.PUCCHGrantId)=="PUCCH-CSI-"+string(original.ReportIdentity),:);
h.PUCCHGrantId=string(h.PUCCHGrantId); h.UCIType=string(h.UCIType);
h.PUCCHGrantId(:)="declared_independent_HARQ_reservation"; h.UCIType(:)="harq_ack"; h.HarqID(:)=0;
mixed.PUCCHGrantTraceTable.PUCCHGrantId=string(mixed.PUCCHGrantTraceTable.PUCCHGrantId);
mixed.PUCCHGrantTraceTable.UCIType=string(mixed.PUCCHGrantTraceTable.UCIType);
mixed.PUCCHGrantTraceTable=[mixed.PUCCHGrantTraceTable;h];
assert(any(sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueUEsRuntime(mixed,original.DueSlot)==1));
assert(isequaln(mixed.PendingFeedbackTable,state.PendingFeedbackTable) && isequaln(owner.Pending,pending));
groups=groups+1;

% Missing/corrupt bindings cannot be restored by editing a row Eligible
% flag. Only a fresh original measurement may stamp a new payload.
for field=["UECSIMeasurementInstallationSHA256","UECSIMeasurementConfigurationSHA256"]
    bad=original; bad=rmfield(bad,field);
    [allowed,~]=sixgr.truth.UEQueuedCSIAdmission.eligible(state,bad); assert(~allowed);
    bad=original; bad.(field)=0;
    reject(@()sixgr.truth.UEQueuedCSIAdmission.eligible(state,bad),'sixgr:truth:UECSIAdmissionBinding');
end
bad=original; bad.UECSIPayloadRetired=0;
reject(@()sixgr.truth.UEQueuedCSIAdmission.eligible(before,bad),'sixgr:truth:UECSIAdmissionBinding');
standalone=rmfield(before,'SharedWaveformStream');
assert(sixgr.truth.UEQueuedCSIAdmission.eligible(standalone,original) && ...
    isequaln(sixgr.truth.UEQueuedCSIAdmission.reconcile(standalone),standalone));
% Already received records are not retired by this producer-only reducer.
received=state; received.PendingCSITable.Processed(originalIndex)=true;
received.PendingCSITable.UECSIPayloadRetired(originalIndex)=false;
received.PendingCSITable.CSIUCITransport=string(received.PendingCSITable.CSIUCITransport);
received.PendingCSITable.CSIUCITransport(originalIndex)="pucch_decoded";
received.PendingCSITable.CSIUCIDecodeOk(originalIndex)=true;
assert(isequaln(sixgr.truth.UEQueuedCSIAdmission.reconcile(received),received));
groups=groups+1;

% The next eligible observation restores reporting. Do not move it into an
% old reference window just to make a same-occasion replacement pass.
[state,completed]=owner.advanceSlot(state,cfg); assert(isempty(completed));
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,4,40,-10);
fresh=declaredMeasurement(state,bound,2*n,3*n,3);
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,fresh);
state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',fresh,bound,fresh);
next=table2struct(state.PendingCSITable(end,:));
assert(sixgr.truth.UEQueuedCSIAdmission.eligible(state,next) && ...
    next.UECSIMeasurementInstallationSHA256~=original.UECSIMeasurementInstallationSHA256 && ...
    next.SourceSlot>original.SourceSlot && ~next.CSIUCIDecodeOk && ...
    isequaln(sixgr.truth.UEQueuedCSIAdmission.auditTable(state),audit));
path=fullfile(folder,'ue_csi_payload_retirements.csv');
sixgr.util.csvWriteTable(path,audit,'PreserveSchema',true,'RoundTripNumericText',true);
roundtrip=readtable(path,'TextType','string');
assert(roundtrip.OriginalUEReportJSON==audit.OriginalUEReportJSON && ...
    roundtrip.OriginalUEReportSHA256==audit.OriginalUEReportSHA256);
groups=groups+1;
evidence=struct('Scope',"declared_receiver_boundaries_real_shared_idle_clock_and_typed_enqueue", ...
    'IdlePhysicalSlots',3,'UCIWaveformExecutions',0,'GNBDecoderExecutions',0, ...
    'EncodedTransportReacquisitionQualified',false,'Groups',groups);
save(fullfile(folder,'admission_evidence.mat'),'evidence','original','retired','next','audit');
fprintf('UE_QUEUED_CSI_ADMISSION_PASS groups=%d idle_slots=3 UCI_RX=0 GNB_reconfiguration=0 folder=%s\n',groups,folder);
ok=true;
end

function row=declaredMeasurement(state,cfg,first,last,slot)
row=table(1,1,slot,first,last,state.SharedWaveformStream.SampleRateHz, ...
    double(state.SharedWaveformStream.Physical.ConfigurationEpoch),'VariableNames', ...
    {'UEIndex','ServingCell','Slot','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','MeasurementClockEpoch'});
for name=["Transmitted","Observed","Consumed","ResourceExtractionAvailable", ...
        "ChannelEstimateAvailable","CSIMeasurementAvailable"], row.(name)=true; end
row.CQI=10; row.RI=1; row.PMI=0; row.CRI=0; row.LI=0; row.SINR_dB=12;
for name=["PMI_I11","PMI_I12","PMI_I13","PMI_I2"], row.(name)=0; end
row.MeasurementSource="declared_received_boundary_for_UE_queue_policy_test";
row.ObservationDeliverySlot=double(state.CurrentSlot);
row=sixgr.truth.bindDeliveredReferenceClock(state,row);
row=sixgr.truth.DLMeasurementInstallation.stamp(state,row,cfg,1,"CSI-RS");
assert(row.DLMeasurementAuthorityEligible);
end

function reject(f,id)
try, f(); catch err
    assert(strcmp(err.identifier,id),'Expected %s; got %s: %s',id,err.identifier,err.message); return;
end
error('test:MissingError','Expected %s.',id);
end
