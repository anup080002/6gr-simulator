function ok = testSRSOutOfRangeFeedback(runFolder)
% CQI zero is an observed outage, not permission to bootstrap a new TB.
% Optional retained rows replay measurements only; no new PHY is claimed.
setup6GRSimToolkit('Verbose',false);
if nargin > 0
    scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(runFolder, ...
        'meta','scenario_config_resolved.yaml'));
    rows = sixgr.util.csvReadTable(fullfile(runFolder,'air_interface','csv','srs_trials.csv'));
else
    scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
        'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
    rows = table();
end
cfg = sixgr.lls6g.buildInternalConfig(scfg,tempname);
positiveRow=table();
if isempty(rows)
    positive = sixgr.link.runSRSChannelEstimation(cfg,'SNR_dB',20,'SlotIndex',25);
    assert(positive.CQI>0 && isfinite(positive.MCSIndex));
    positive.Slot=25; positive.ServingCell=1;
    positiveRow=struct2table(positive,'AsArray',true);
    out = sixgr.link.runSRSChannelEstimation(cfg,'SNR_dB',-10,'SlotIndex',30);
    assert(out.ConfiguredSNR_dB==-10 && out.AppliedAWGNSNR_dB==-10);
    assert(out.CQI==0 && isnan(out.MCSIndex) && ...
        string(out.CQIValueStatus)=="measured_cqi_zero_out_of_range", ...
        'Actual low-SNR SRS must preserve out-of-range CQI without a fallback MCS.');
    assert(abs(out.CQISelectionSINR_dB + out.CQIAppliedSINRMargin_dB - ...
        out.PredictedPUSCHMinimumLayerSINR_dB)<1e-10);
    out.Slot = 30; out.ServingCell = 1;
    rows = struct2table(out,'AsArray',true);
    fprintf('SRS_OUTAGE_PRODUCER_PASS appliedSNR=%g selectionSINR=%g margin=%g CQI=%g\n', ...
        out.AppliedAWGNSNR_dB,out.CQISelectionSINR_dB,out.CQIAppliedSINRMargin_dB,out.CQI);
end
multi = struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state.CurrentServingIdx(:)=1;
state.CurrentFrame=1;
state.ULQueueBits(:)=1e6;
if ~isempty(positiveRow)
    state.CurrentSlot=25; state.CurrentCanonicalSlot=25;
    state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,positiveRow);
    assert(state.LatestULFeedback(1).Valid && state.LatestULFeedback(1).CQI>0);
end
for k=1:height(rows)
    row=rows(k,:);
    slot=double(row.Slot);
    if ismember('ObservationDeliverySlot',row.Properties.VariableNames)
        delivered=double(row.ObservationDeliverySlot);
        % CSV decimal rounding must not alter the integer sample clock.
        exactCompletion=row.ObservationEndSampleExclusive/row.ObservationSampleRateHz;
        exactDelivery=(delivered-1)*state.SlotDuration_s;
        assert(abs(row.ObservationCompletionTime_s-exactCompletion)<16*eps(exactCompletion) && ...
            abs(row.ObservationDeliveryTime_s-exactDelivery)<16*eps(exactDelivery));
        row.ObservationCompletionTime_s=exactCompletion;
        row.ObservationDeliveryTime_s=exactDelivery;
    else
        delivered=slot;
    end
    state.CurrentSlot=delivered;
    state.CurrentCanonicalSlot=delivered;
    beforeHARQ=state.ULHarq.Stats;
    beforeLA=struct();
    if iscell(state.ULLinkAdaptationState) && ...
            numel(state.ULLinkAdaptationState)>=1 && ...
            isstruct(state.ULLinkAdaptationState{1})
        beforeLA=state.ULLinkAdaptationState{1};
    end
    beforeOLLAUpdates=double(sixgr.util.structGet(beforeLA,'OLLAUpdateCount',0));
    beforeOLLAMargin=double(sixgr.util.structGet(beforeLA,'DeltaMCS',0));
    beforeCQIObservations=double(sixgr.util.structGet(beforeLA,'CQIObservationCount',0));
    state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,row);
    fb=sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(state,1,'UL');
    assert(fb.Valid && fb.CQI==0 && isnan(fb.MCSIndex), ...
        'SRS row %d lost measured CQI zero or retained a stale MCS.',k);
    assert(fb.SourceSlot==slot && fb.DeliveredSlot==delivered && ...
        fb.SchedulerCQIRawCQI==0 && isfinite(fb.SchedulerAdjustedSINR_dB));
    afterLA=state.ULLinkAdaptationState{1};
    assert(isequaln(beforeHARQ,state.ULHarq.Stats) && ...
        double(afterLA.OLLAUpdateCount)==beforeOLLAUpdates && ...
        double(afterLA.DeltaMCS)==beforeOLLAMargin && ...
        double(afterLA.CQIObservationCount)==beforeCQIObservations+1 && ...
        logical(afterLA.LastCQIOutOfRange), ...
        ['An SRS outage must update only the receiver-owned ILLA observation ' ...
         'state; HARQ and ACK/NACK-owned OLLA state must remain unchanged.']);
    [state,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime( ...
        state,cfg,1,'UL',1);
    assert(ue.FeedbackValid && ue.CQI==0 && ue.CausalFeedbackUsable, ...
        'The production scheduler boundary reopened bootstrap on CQI zero.');
    plan=state.ULSchedulers{1}.buildNewDataGrantPlan(ue,0:23,[2 12],4000);
    assert(~plan.Valid && plan.TBSBits==0 && ...
        string(plan.GrantBlocker)=="blocked_measured_cqi_zero_out_of_range", ...
        'Measured SRS CQI zero must reach the existing new-data outage gate.');
    retx=struct('IsRetransmission',true,'RV',2,'NDI',0,'NumLayers',1, ...
        'TBSBits',1024,'MCSIndex',4,'Modulation','QPSK','TargetCodeRate',0.3);
    retained=sixgr.truth.CoupledTruthRuntime.realignGrantAMCFromMeasuredFeedbackRuntime( ...
        retx,fb,state.ULSchedulers{1},cfg,'UL');
    assert(isequaln(retained,retx),'Outage feedback changed an in-flight HARQ grant.');
    fprintf('SRS_OUTAGE_ROW_PASS row=%d source=%g delivered=%g CQI=%g blocker=%s\n', ...
        k,slot,delivered,fb.CQI,string(plan.GrantBlocker));
end
fprintf('SRS_OUT_OF_RANGE_FEEDBACK_PASS rows=%d\n',height(rows));
ok=true;
end
