function ok=testSharedPUCCHFalseAlarmExports()
% Export-only fixtures: no waveform, independence or conformance claim.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','validation','shared_pucch_false_alarm_exports', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
layout=sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
manifest=struct('CodeVersion',"test",'CodeDetail',"declared_export_fixture_no_PHY_execution", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
T=fixture();
% The same capture can be exported twice or evaluated under another
% hypothesis ID; neither creates another noise realization.
duplicate=T(1,:); duplicate.PresenceObservationID="another_hypothesis_same_capture";
duplicate.PresenceReceiverContextDigest="another_hypothesis_context";
duplicate.UEIndex=2; duplicate.RNTI=8;
duplicate.PresenceUEIndex=2; duplicate.PresenceRNTI=8;
input=[T;T(1,:);duplicate];
before=input;
contract=sixgr.truth.llsOutputContract();
meta=struct('logical_run_id',"declared_export_fixture",'run_id',17);
public=sixgr.truth.buildLLSPublicOutputTables(struct('pucch_table',input),contract,meta);
P=public.pucch_uci_table;
assert(isequaln(input,before),'Public export must not mutate runtime evidence.');
fields=string(input.Properties.VariableNames);
fields=fields(startsWith(fields,"Presence") | ismember(fields, ...
    ["SignalPresent","TrialType","FalseAlarmFlag","FalseAcceptanceFlag", ...
    "DetectionMetricSource","DetectionMetricValid","DetectionThreshold","DetectionThresholdSource"]));
for name=fields
    assert(isequaln(P.(name),input.(name)),'Public table lost %s.',name);
end
assert(isnan(P.SignalPresent(14)) && isnan(P.FalseAlarmFlag(14)));
assert(P.FalseAlarmFlag(1)==1 && P.FalseAcceptanceFlag(1)==0, ...
    'Physical detection must not become receiver acceptance or CSI delivery.');

out=publish(input);
F=falseAlarmRows(out);
rates=F(F.Statistic=="rate",:);
assert(height(rates)==12,'Format, detector policy, point, payload, epoch, RF and seed strata must stay separate.');
assert(sum(F.ValueNumeric(F.Statistic=="sample_count"))==14, ...
    'Unknown decisions, unknown presence, H1, incomplete receipts and duplicates cannot enlarge the decision denominator.');
assert(sum(F.ValueNumeric(F.Statistic=="capture_count"))==15, ...
    'One known-absent capture with an unknown decision is retained separately from the decision denominator.');
base=find(contains(rates.Entity,"/no_signal_before_receiver_noise_and_RF/") & rates.ValueNumeric==.5);
assert(isscalar(base));
entity=rates.Entity(base);
assert(F.ValueNumeric(F.Entity==entity & F.Statistic=="sample_count")==2);
assert(F.ValueNumeric(F.Entity==entity & F.Statistic=="capture_count")==3);
assert(F.ValueNumeric(F.Entity==entity & F.Statistic=="physical_receiver_acceptance_rate")==0);
background=rates(contains(rates.Entity,"/target_absent_with_background/"),:);
assert(height(background)==1 && background.ValueNumeric==.5);
assert(nnz(contains(rates.Entity,"/target_absent_receiver_background_unknown/"))==1);
assert(all(contains(F.Notes,"not established independent")) && ...
    all(contains(F.Notes,"not statistically qualified")) && ...
    all(contains(F.Notes,"no semantic acceptance or delivered false CSI is inferred")));
assert(isnan(compactRate(out.TechnicalReport)), ...
    'The compact control report must not pool different H0/population strata.');
saved=sixgr.util.csvReadTable(out.DetailCSV,'TextType','string');
saved=saved(saved.MetricKey=="false_alarm_probability" & startsWith(saved.Entity,"PUCCH/"),:);
assert(height(saved)==height(F));

% A single explicit no-signal cohort has a descriptive rate; duplicate rows
% and its undecidable capture still do not become independent trials.
out=publish([T([1 2 16],:);T(1,:)]);
assert(compactRate(out.TechnicalReport)==.5);
F=falseAlarmRows(out);
assert(F.ValueNumeric(F.Statistic=="rate")==.5 && ...
    F.ValueNumeric(F.Statistic=="sample_count")==2);

% Historical flags / receive-only intentions cannot manufacture H0, and a
% label cannot override explicit unknown presence.
legacy=table([0;0;0],[NaN;NaN;NaN],["";"no_signal";"false_alarm"], ...
    'VariableNames',{'FalseAlarmFlag','SignalPresent','TrialType'});
legacy.DTXFlag=false(3,1); legacy.PUCCHTransmissionPrepared=zeros(3,1);
public=sixgr.truth.buildLLSPublicOutputTables(struct('pucch_table',legacy),contract,meta);
assert(all(isnan(public.pucch_uci_table.SignalPresent)) && ...
    all(isnan(public.pucch_uci_table.PresenceRXStartSample)) && ...
    all(isnan(public.pucch_uci_table.DetectionMetricValid)));
out=publish(legacy);
assert(isempty(falseAlarmRows(out)) && isnan(compactRate(out.TechnicalReport)));

% Conflicting scoring and executed receiver decisions fail loudly.
bad=T(1,:); bad.FalseAlarmFlag=0;
rejected=false;
try
    publish(bad);
catch ME
    rejected=strcmp(ME.identifier,'sixgr:truth:ConflictingFalseAlarmEvidence');
    if ~rejected, rethrow(ME); end
end
assert(rejected,'Conflicting false-detection evidence must not be averaged.');
fprintf('SHARED_PUCCH_FALSE_ALARM_EXPORTS_PASS export_fixture_only cohorts=12 evidence=%s\n',root);
ok=true;

    function result=publish(rows)
        sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'pucch_trials.csv'), ...
            rows,'PreserveSchema',true,'RoundTripNumericText',true);
        result=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false), ...
            manifest,struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
    end
end

function F=falseAlarmRows(out)
F=out.CategoryRows;
F=F(F.MetricKey=="false_alarm_probability" & startsWith(F.Entity,"PUCCH/"),:);
end

function value=compactRate(path)
report=fileread(path);
token=regexp(report,'\| PUCCH \| [^|]+ \| ([^|]+) \|','tokens','once');
assert(~isempty(token),'Control report must retain its PUCCH row.');
value=str2double(strtrim(token{1}));
end

function T=fixture()
r=struct('Slot',1,'UEIndex',1,'RNTI',7,'ServingCell',1,'SweepPointIndex',1, ...
    'Seed',1,'RFProfile',"fixture_RF_A",'SignalPresent',0, ...
    'TrialType',"no_signal_before_receiver_noise_and_RF", ...
    'FalseAlarmFlag',1,'FalseAcceptanceFlag',0,'DetectionOutcome',"detected", ...
    'DetectionMetric',.7,'DetectionMetricValid',true,'DetectionThreshold',.2, ...
    'DetectionThresholdSource',"fixture_detector_A",'DetectionMetricSource',"fixture_metric_A", ...
    'PUCCHFormat',1,'PUCCHResourceId',"resource0",'ReceiverExpectedBitCount',2, ...
    'ReceiverExpectedHARQBitCount',2,'ReceiverExpectedSRBitCount',0, ...
    'ReceiverExpectedCSIPart1BitCount',0,'ReceiverExpectedCSIPart2BitCount',0, ...
    'CRCApplicable',false,'PresenceScoringStatus',"observed_executed_component_presence", ...
    'PresenceScoringSource',"declared_export_fixture_not_physical_evidence", ...
    'PresenceObservationID',"capture1",'PresenceConfigurationEpoch',1, ...
    'PresenceReceiverSchemaDigest',"fixture_schema",'PresenceReceiverResourceDigest',"fixture_resource", ...
    'PresenceEvidenceJSON',"declared_export_fixture_no_execution_receipt", ...
    'PresenceEvidenceSHA256',"declared_export_fixture_no_physical_evidence_hash", ...
    'PresenceNonzeroCountUnit',"complex_sample_by_physical_chain", ...
    'PresenceUEIndex',1,'PresenceRNTI',7,'PresenceServingCell',1, ...
    'PresencePhysicalOccasionID',"fixture_occasion", ...
    'PresenceReceiverAssignmentDigest',"assignment1",'PresenceReceiverContextDigest',"context1", ...
    'PresenceTXStartSample',0,'PresenceTXEndSampleExclusive',100, ...
    'PresenceRXStartSample',0,'PresenceRXEndSampleExclusive',100,'PresenceSampleRateHz',1000, ...
    'PresenceTargetNonzeroInputSamples',0,'PresenceReceiverBackground',"all_link_contributions_exactly_zero", ...
    'PresenceObservationCount',1,'PresenceIndependentTrialsEstablished',false, ...
    'PresenceScoringUsedByReceiver',false,'ExecutionBackend',"declared_export_fixture",'ApproximationMode',"none");
rows=repmat(r,20,1);
for k=1:numel(rows)
    rows(k).Slot=k;
    rows(k).PresenceObservationID="capture"+k;
    rows(k).PresenceReceiverAssignmentDigest="assignment"+k;
    rows(k).PresenceReceiverContextDigest="context"+k;
    rows(k).PresenceTXStartSample=(k-1)*100;
    rows(k).PresenceTXEndSampleExclusive=k*100;
    rows(k).PresenceRXStartSample=(k-1)*100;
    rows(k).PresenceRXEndSampleExclusive=k*100;
end
for k=[2 4 5], rows(k).FalseAlarmFlag=0; rows(k).DetectionOutcome="dtx"; end
for k=[3 4]
    rows(k).TrialType="target_absent_with_background";
    rows(k).PresenceReceiverBackground="nonzero_link_contribution_in_capture";
end
rows(5).PUCCHFormat=3;
rows(6).DetectionThreshold=.3;
rows(7).DetectionThresholdSource="fixture_detector_B";
rows(7).FalseAcceptanceFlag=1;
rows(8).DetectionMetricSource="fixture_metric_B";
rows(9).SweepPointIndex=2;
rows(10).ReceiverExpectedBitCount=3; rows(10).ReceiverExpectedHARQBitCount=3;
rows(11).PresenceConfigurationEpoch=2;
rows(12).RFProfile="fixture_RF_B";
rows(13).Seed=2;
rows(14).SignalPresent=NaN; rows(14).FalseAlarmFlag=NaN;
rows(14).FalseAcceptanceFlag=NaN; rows(14).TrialType="unknown_signal_presence";
rows(15).SignalPresent=1; rows(15).FalseAlarmFlag=NaN;
rows(15).FalseAcceptanceFlag=NaN; rows(15).TrialType="signal_present";
rows(16).DetectionOutcome="unavailable"; rows(16).FalseAlarmFlag=NaN;
rows(16).FalseAcceptanceFlag=NaN;
% A nonzero elsewhere in a clipped covering interval does not prove a
% nonzero background within this capture, even if a legacy label says so.
rows(17).TrialType="target_absent_with_background";
rows(17).PresenceReceiverBackground="nonzero_covering_interval_exact_capture_location_unknown";
rows(18).PresenceScoringStatus="unavailable_legacy_execution_receipts";
rows(19).PresenceRXStartSample=NaN;
rows(20).PresenceServingCell=NaN; rows(20).ServingCell=NaN;
T=struct2table(rows);
end
