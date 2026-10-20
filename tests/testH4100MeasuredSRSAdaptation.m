function ok=testH4100MeasuredSRSAdaptation()
% Two actual sounding occasions on one H4 shared CDL/RF clock, followed by
% replay through the production SRS->ILLA consumer. No authored RI/CQI/TPMI.
% Access/TAG remain declared component inputs. This does NOT execute PUSCH,
% qualify full coordinator delivery or substitute for the server scenario.
scenario='simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml';
source=sixgr.lls6g.config.loadScenarioConfig(scenario);
paths=[string(mfilename('fullpath'))+".m"; ...
    string(which('testH4100SharedSRSScoring')); ...
    string(which('sixgr.truth.CoupledTruthRuntime')); ...
    string(which('sixgr.link.runSRSChannelEstimation')); ...
    string(which('sixgr.phy.ul.SRS_Rx')); ...
    string(which('sixgr.truth.CoupledWaveformStream')); ...
    string(which('sixgr.truth.SharedWaveformPhysicalRuntime')); ...
    string(which('sixgr.rf.runtime.RFImpairmentStream')); source.SourceFiles];
hashes=strings(size(paths));
for n=1:numel(paths), hashes(n)=string(sixgr.util.sha256File(paths(n))); end
[passed,receptions,folder]=testH4100SharedSRSScoring(scenario,2);
assert(passed && numel(receptions)==2);
saved=load(fullfile(folder,'configuration.mat'),'cfg'); cfg=saved.cfg;
latest=sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRowRuntime();
state=struct('CfgMobility',cfg,'NumUsers',1,'DLSchedulers',{{}}, ...
    'ULSchedulers',{{}},'DLLinkAdaptationState',{{struct()}}, ...
    'ULLinkAdaptationState',{{struct()}},'SlotDuration_s',sixgr.time.slotDurationSec(cfg), ...
    'LatestDLFeedback',latest,'LatestULFeedback',latest,'PendingCSITable',table());
assert(cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2);
rows=table(); feedback=cell(2,1);
for n=1:2
    actual=receptions{n}; row=actual.Output;
    assert(row.SRSRuntimeEvidenceUsable && row.DetectionSuccess && row.ChannelEstimateAvailable);
    % The helper consumes completed captures at the end of a radio slot.
    % Replay delivery at the first subsequent canonical slot boundary;
    % never label capture time or an earlier source slot as knowledge time.
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    samplesPerSlot=actual.SampleRateHz*state.SlotDuration_s;
    delivered=ceil(actual.ReceiverConsumedAtSample/samplesPerSlot)+1;
    first=sixgr.phy.frame.slotStartSample(carrier,delivered-1,actual.SampleRateHz);
    assert(first>=actual.ObservationEndSampleExclusive && first>=actual.ReceiverConsumedAtSample);
    state.CurrentSlot=delivered;
    row.Slot=actual.SourceSlot; row.ServingCell=1;
    row.ObservationStartSample=actual.ObservationStartSample;
    row.ObservationEndSampleExclusive=actual.ObservationEndSampleExclusive;
    row.ObservationSampleRateHz=actual.SampleRateHz;
    row.ObservationCompletionTime_s=actual.ObservationEndSampleExclusive/actual.SampleRateHz;
    row.ObservationCoverageSource="complete_contiguous_received_sample_buffer";
    row.ObservationDeliverySlot=delivered;
    row.ObservationDeliveryTime_s=(delivered-1)*state.SlotDuration_s;
    row.ObservationDeliverySource="canonical_slot_start_after_complete_received_window";
    original=row;
    state=sixgr.truth.CoupledTruthRuntime.updateLatestULFeedbackFromSRSTrialRuntime( ...
        state,1,row,actual.SourceSlot);
    assert(isequaln(row,original),'Do not alter measured receiver evidence.');
    feedback{n}=state.LatestULFeedback;
    la=state.ULLinkAdaptationState{1};
    measured=table(actual.SourceSlot,delivered,row.RIEstimate,row.TPMIEstimate, ...
        row.CQI,row.PredictedPUSCHMinimumLayerSINR_dB,la.SchedulerAcceptedRank, ...
        feedback{n}.Valid,feedback{n}.MCSIndex,feedback{n}.CQI,la.OLLAUpdateCount, ...
        false,false,'VariableNames',{'SRSSourceSlot','ReplayDeliverySlot', ...
        'MeasuredRI','MeasuredTPMI','MeasuredCQI','PredictedPUSCHMinimumLayerSINR_dB', ...
        'AcceptedRank','FeedbackValid','ScheduledMCSReference','SchedulerCQI', ...
        'OLLAUpdateCount','ScenarioAccepted','StatisticallyQualified'});
    measured.Scope="actual_shared_SRS_to_production_adaptation_API_replay_no_data_execution";
    rows=[rows;measured]; %#ok<AGROW>
    sixgr.util.csvWriteTable(fullfile(folder,'measured_srs_adaptation.csv'),rows,'PreserveSchema',true);
    save(fullfile(folder,'adaptation_replay.mat'),'feedback','rows','paths','hashes','-v7.3');
    fprintf('H4_MEASURED_SRS_ADAPTATION source=%g delivered=%g RI=%g TPMI=%g accepted=%g valid=%d MCS=%g\n', ...
        actual.SourceSlot,delivered,row.RIEstimate,row.TPMIEstimate, ...
        la.SchedulerAcceptedRank,feedback{n}.Valid,feedback{n}.MCSIndex);
    assert(la.OLLAUpdateCount==0,'SRS is not a HARQ ACK/NACK event.');
    if n==1 && row.RIEstimate>cfg.phy.pusch.numLayers
        assert(~feedback{n}.Valid && la.SchedulerAcceptedRank==cfg.phy.pusch.numLayers, ...
            'One higher-rank observation cannot bypass two-report confirmation.');
    end
end
assert(rows.MeasuredRI(1)==rows.MeasuredRI(2), ...
    'test:H4SRSRankNotStable','Retain the measured rank change; do not manufacture confirmation.');
assert(feedback{2}.Valid && feedback{2}.RI==rows.MeasuredRI(2) && ...
    feedback{2}.PMI==rows.MeasuredTPMI(2) && isfinite(feedback{2}.MCSIndex) && ...
    feedback{2}.SourceSlot==rows.SRSSourceSlot(2) && ...
    feedback{2}.DeliveredSlot==rows.ReplayDeliverySlot(2), ...
    'test:H4MeasuredSRSNotConsumed','Real sounding did not establish a complete causal UL adaptation decision.');
for n=1:numel(paths)
    assert(hashes(n)==string(sixgr.util.sha256File(paths(n))), ...
        'test:H4SRSSourceChanged','Do not mix changing sources inside a physical check.');
end
fprintf('H4_MEASURED_SRS_ADAPTATION_PASS folder=%s PUSCH_executed=0 scenario_accepted=0\n',folder);
ok=true;
end
