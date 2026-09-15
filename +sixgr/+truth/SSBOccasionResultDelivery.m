classdef SSBOccasionResultDelivery
% Periodic serving-SSB measurements, independent of full-burst beam selection.
methods(Static)
    function state=complete(state,item)
        c=item.Context; p=c.Prepared;
        cellState=string(state.CellAcquisitionState(item.UE));
        assert(any(cellState==["acquired","not_required"]), ...
            'sixgr:truth:ServingSSBTrackingBeforeAcquisition','Periodic tracking requires acquired serving-cell state.');
        [~,pre,~,~,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
        h=c.SSBOccasionHorizon;
        fs=post.SampleRateHz;
        assert(c.TrackingOnly && post.StartSample==c.BroadcastStartSample && ...
            post.EndSampleExclusive==c.BroadcastStartSample+h.ObservationEndSampleExclusive && ...
            state.SharedWaveformStream.Events.NextSampleIndex==post.EndSampleExclusive, ...
            'sixgr:truth:SSBOccasionClockMismatch','Decode each SSB at its actual completed observation boundary.');
        r=sixgr.phy.broadcast.recoverSIB1FromWaveform(post,p.ReceiverConfig, ...
            'RecoveryScope','SSB_MIB','CandidateSSBIndex',h.SSBIndex, ...
            'PhysicalMeasurementObservation',pre);
        r=sixgr.link.normalizeReceivedSSBPowerReference(r,p.Config);
        carrier=sixgr.phy.grid.makeCarrier(p.ReceiverConfig);
        valid=r.NCellID==carrier.NCellID && r.SSBMIBComplete && r.BCHCrcPass && r.MIBDecoded && ...
            r.SSBIndex==h.SSBIndex && (isfinite(r.SS_RSRP_dBm) || ...
            isfinite(sixgr.util.structGet(r,'SS_RSRP_dB_re_UnitOccupiedRE_Es',NaN)));
        samplesPerSlot=fs*state.SlotDuration_s;
        assert(samplesPerSlot==fix(samplesPerSlot),'sixgr:truth:SSBOccasionSlotClock','Slot boundary must be on the sample clock.');
        producer=floor((c.BroadcastStartSample+h.SSBStartSample)/samplesPerSlot)+1;
        row=table(double(item.UE),double(c.ServingCell),double(c.Slot),double(h.SSBIndex), ...
            double(producer),double(post.StartSample),double(post.EndSampleExclusive),double(fs), ...
            logical(r.BCHCrcPass),string(r.Status),string(r.FailureReason),double(r.SS_RSRP_dBm), ...
            double(r.SS_SINR_dB),double(r.TimingOffset),double(r.FrequencyOffsetHz), ...
            string(sixgr.util.structGet(r,'SSBWindowRSSIPerReceiveAntenna_dBm','')), ...
            string(sixgr.util.structGet(r,'SSBWindowPowerMeasurementJSON','')), ...
            'VariableNames',{'UEId','ServingCell','BurstSlot','ReferenceSignalId','ProducerSlot', ...
            'ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz', ...
            'CRCPass','Status','FailureReason','SS_RSRP_dBm','SS_SINR_dB', ...
            'EstimatedTimingOffset_samples','EstimatedCFO_Hz', ...
            'SSBWindowRSSIPerReceiveAntenna_dBm','SSBWindowPowerMeasurementJSON'});
        row.MeasurementSource="actual_shared_ssb_occasion_pre_rx_rf_measurement";
        row.MeasurementValid=logical(valid);
        row.MeasuredSSBIndex=double(r.SSBIndex);
        row.MeasuredNCellID=double(r.NCellID);
        row.ExpectedNCellID=double(carrier.NCellID);
        row.PowerReferencePlane="actual_pre_rx_rf_antenna_connector";
        if isfield(r,'PowerReferencePlane'), row.PowerReferencePlane=string(r.PowerReferencePlane); end
        row.SS_RSRP_dB_re_UnitOccupiedRE_Es=double(sixgr.util.structGet(r,'SS_RSRP_dB_re_UnitOccupiedRE_Es',NaN));
        row.SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es= ...
            string(sixgr.util.structGet(r,'SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es',""));
        powerEvidence=sixgr.link.ssbPowerReferenceEvidence(r);
        for field=string(fieldnames(powerEvidence)).'
            row.(field)=powerEvidence.(field);
        end
        row.MeasurementClockEpoch=state.SharedWaveformStream.Physical.ConfigurationEpoch;
        row.ResultCompletedAtSample=state.SharedWaveformStream.Events.NextSampleIndex;
        row.RecoveryScope=string(r.RecoveryScope);
        row.SIB1ReceptionAttempted=logical(r.SIB1ReceptionAttempted);
        pending=sixgr.util.structGet(state,'PendingSSBOccasionMeasurements',table());
        if isempty(pending), pending=row; else, pending=[pending;row]; end
        state.PendingSSBOccasionMeasurements=pending;
    end

    function state=deliver(state)
        T=sixgr.util.structGet(state,'PendingSSBOccasionMeasurements',table());
        if isempty(T), return; end
        now=(state.CurrentSlot-1)*state.SlotDuration_s;
        due=T.ObservationEndSampleExclusive./T.ObservationSampleRateHz<=now;
        ready=T(due,:);
        [~,order]=sort(ready.ObservationEndSampleExclusive./ready.ObservationSampleRateHz);
        for k=reshape(order,1,[])
            row=ready(k,:); ue=row.UEId;
            assert(row.ServingCell==state.CurrentServingIdx(ue), ...
                'sixgr:truth:SSBOccasionServingCellChanged','Cannot deliver an SSB measurement to another serving cell.');
            old=sixgr.util.structGet(state,'DeliveredSSBOccasionMeasurements',table());
            if ~isempty(old)
                assert(~any(old.UEId==ue & old.BurstSlot==row.BurstSlot & ...
                    old.ReferenceSignalId==row.ReferenceSignalId), ...
                    'sixgr:truth:DuplicateSSBOccasion','A received SSB occasion may update the filter only once.');
            end
            row.AvailableSlot=double(state.CurrentSlot);
            row=sixgr.truth.bindSharedReferenceDeliveryClock(row,state);
            state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
                state,'SSB','UE',ue,row,'ProducerSlot',row.ProducerSlot, ...
                'AvailableSlot',state.CurrentSlot,'Valid',row.MeasurementValid,'Direction','DL', ...
                'SourceSignal','SSB','MeasurementSource',row.MeasurementSource);
            % Preserve actual sample-clock/RSSI evidence in the already exported
            % canonical measurement ledger, including failures and missing data.
            ledger=state.ReferenceSignalMeasurementTable;
            powerFields=sixgr.link.ssbPowerReferenceEvidence();
            for field=string(fieldnames(powerFields)).'
                if ~ismember(field,string(ledger.Properties.VariableNames))
                    ledger.(field)=repmat(powerFields.(field),height(ledger),1);
                end
                ledger.(field)(end)=row.(field);
            end
            for field=["ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz","BurstSlot","MeasuredNCellID","ExpectedNCellID"]
                if ~ismember(field,string(ledger.Properties.VariableNames)), ledger.(field)=nan(height(ledger),1); end
                ledger.(field)(end)=row.(field);
            end
            for field=["SSBWindowRSSIPerReceiveAntenna_dBm","SSBWindowPowerMeasurementJSON", ...
                    "SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"]
                if ~ismember(field,string(ledger.Properties.VariableNames)), ledger.(field)=strings(height(ledger),1); end
                ledger.(field)(end)=row.(field);
            end
            if ~ismember("SSBOccasionBCHCRCPass",string(ledger.Properties.VariableNames))
                ledger.SSBOccasionBCHCRCPass=nan(height(ledger),1);
            end
            ledger.SSBOccasionBCHCRCPass(end)=double(row.CRCPass);
            for field=["Status","FailureReason","RecoveryScope"]
                target="SSBOccasion"+field;
                if ~ismember(target,string(ledger.Properties.VariableNames)), ledger.(target)=strings(height(ledger),1); end
                ledger.(target)(end)=row.(field);
            end
            state.ReferenceSignalMeasurementTable=ledger;
            if isempty(old), old=row; else, old=[old;row]; end
            state.DeliveredSSBOccasionMeasurements=old;
        end
        state.PendingSSBOccasionMeasurements=T(~due,:);
    end

    function assertDelivered(state,ue,trial)
        T=sixgr.util.structGet(state,'DeliveredSSBOccasionMeasurements',table());
        assert(~isempty(T),'sixgr:truth:MissingSSBOccasionDelivery','Full tracking burst has no per-occasion delivery evidence.');
        assert(height(unique(trial(:,{'Slot','SSBIndex'}),'rows'))==height(trial), ...
            'sixgr:truth:DuplicateSSBOccasion', ...
            'Full-burst rows must bind distinct observed occasions, not reuse a decoded hypothesis.');
        for k=1:height(trial)
            hit=T.UEId==ue & T.BurstSlot==trial.Slot(k) & T.ReferenceSignalId==trial.SSBIndex(k);
            assert(nnz(hit)==1 && T.AvailableSlot(hit)<=state.CurrentSlot, ...
                'sixgr:truth:MissingSSBOccasionDelivery','Each tracking candidate requires exactly one prior occasion delivery.');
        end
    end

    function state=censorAtSweepBoundary(state)
        pending=sixgr.util.structGet(state,'PendingSSBOccasionMeasurements',table());
        if ~isempty(pending)
            history=sixgr.util.structGet(state,'CensoredSSBOccasionMeasurements',{});
            history{end+1}=struct('Reason',"independent_sweep_boundary_before_delivery",'Measurements',pending);
            state.CensoredSSBOccasionMeasurements=history;
        end
        state.PendingSSBOccasionMeasurements=pending([],:);
    end
end
end
