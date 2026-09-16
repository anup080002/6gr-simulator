function ok=testSharedPeriodicCSIProducer()
% Actual periodic PUCCH IQ/CDL/RF/thermal noise. CSI and access timing are
% declared receiver-boundary fixtures, not CSI-RS RF or 12 dB qualification.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmpi(which('sixgr.truth.CoupledTruthRuntime'), ...
    fullfile(root,'+sixgr','+truth','CoupledTruthRuntime.m')));
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,12);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
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
[~,fixtureLink]=sixgr.link.applyWaveformImpairments(complex(zeros(1,1)),ul,fs,'ApplyRFChain',false);
pl=double(fixtureLink.AppliedLargeScaleLoss_dB);
ssb=table(0,pl,"SSB-0","analytic_component_pathloss_selector_fixture",1,-pl,0, ...
    'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB','PathlossReferenceRS', ...
    'MeasuredReferenceSignalPathlossSource','ServingCell','SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,ssb,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','analytic_component_selector_fixture');
row=table(1,1,1,true,true,true,true,true,true,10,1,0,0,0,18.5, ...
    "declared_received_CSI_periodic_transport_fixture", ...
    'VariableNames',{'Slot','UEIndex','ServingCell','Transmitted','Observed','Consumed', ...
    'ResourceExtractionAvailable','ChannelEstimateAvailable','CSIMeasurementAvailable', ...
    'CQI','RI','PMI','CRI','LI','SINR_dB','MeasurementSource'});
row.ObservationDeliverySlot=2;
row.ObservationStartSample=0;
row.ObservationEndSampleExclusive=sixgr.phy.frame.slotStartSample(carrier,1,fs);
row.ResultAvailableAtSample=row.ObservationEndSampleExclusive;
row.ObservationSampleRateHz=fs; row.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
row.MeasurementClockDomain="shared_receiver_sample_clock/v1";
row.DeliverySlotStartSample=row.ResultAvailableAtSample;
row.DeliverySlotEndSampleExclusive=sixgr.phy.frame.slotStartSample(carrier,2,fs);
% Retained future boundary fixture: it must not become usable before the
% real owner reaches its declared completion. No PDSCH is run or queued.
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,row);
queuedReport=table();
for slot=1:10
    [state,~,blocked]=sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
        state,cfg,'DL',1,1,slot,10,12,repmat(struct(),0,1),true);
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
report=state.PendingCSITable;
assert(height(report)==1 && report.DueSlot==9 && report.SourceSlot==1 && report.CSIReferenceSlot==4);
assert(report.Processed && report.CSIUCIDecodeOk && report.CSIUCITransport=="pucch_decoded");
assert(report.CQI==10 && report.RI==1 && report.PMI==0 && report.DeliveredSlot==10);
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
    audit.SourceSlot==row.Slot && audit.DueSlot==report.DueSlot, ...
    'UE-only timing must survive publication in the bound audit record.');
assert(isnan(report.MeasurementAvailableAtSample) && isnan(report.MeasurementAvailableSlot) && ...
    isnan(report.MeasurementClockEpoch) && strlength(report.MeasurementClockDomain)==0 && ...
    isnan(report.SINR_dB) && report.SourceSignal=="received_CSI_UCI", ...
    'Decoded CSI fields must not masquerade as a reported UE measurement clock or raw SINR.');
assert(height(state.ControlTrials.PUCCH)==1 && state.ControlTrials.PUCCH.Slot==9 && ...
    state.ControlTrials.PUCCH.PUCCHDecodeOk);
assert(isempty(state.PendingFeedbackTable) && height(state.PUCCHGrantTraceTable)==1 && ...
    state.PUCCHGrantTraceTable.GrantExecutedFlag && isnan(state.PUCCHGrantTraceTable.HarqID));
assert(state.LatestDLFeedback.Valid && state.LatestDLFeedback.SchedulerCQIRawCQI==10);
logsRoot=fullfile(root,'logs'); if ~isfolder(logsRoot), mkdir(logsRoot); end
folder=tempname(logsRoot); mkdir(folder);
writetable(report,fullfile(folder,'periodic_CSI_received_report.csv'));
writetable(state.ControlTrials.PUCCH,fullfile(folder,'actual_PUCCH_trial.csv'));
writetable(state.CSIReportObligationTable,fullfile(folder,'configured_CSI_obligations.csv'));
captures=state.TestPeriodicCSICaptures;
save(fullfile(folder,'shared_periodic_CSI.mat'),'cfg','row','queuedReport','report','audit','captures','fs');
fprintf('SHARED_PERIODIC_CSI_PRODUCER_PASS actual_PUCCH_slot=9 delivered=10 CSI_reference=4 PDSCH_executions=0 CSI_RF_executions=0 folder=%s\n',folder);
ok=true;
end
function state=receive(state,items)
for item=items
    if item.Kind=="PUCCHTX"
        state=sixgr.truth.commitSharedPUCCHTransmission(state,item);
        continue;
    end
    if item.Kind=="PreparePUCCH"
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
    elseif item.Kind=="PUCCH"
        captures=struct('ReceiverID',{},'Samples',{},'StartSample',{},'EndSampleExclusive',{});
        for i=1:numel(item.Planes)
            plane=item.Planes(i); obs=plane.Observation;
            captures(i)=struct('ReceiverID',plane.ReceiverID,'Samples',obs.readComplete(), ...
                'StartSample',obs.StartSample,'EndSampleExclusive',obs.EndSampleExclusive);
        end
        state.TestPeriodicCSICaptures=captures;
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(state,item);
    else
        error('test:UnexpectedPeriodicCSIEvent','Unexpected %s.',item.Kind);
    end
end
end
