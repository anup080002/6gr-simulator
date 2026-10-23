function ok=testCausalFeedbackReportMetrics()
% Numerical and production-export regression, not physical-link qualification.
setup6GRSimToolkit('Verbose',false);
[reports,measurements]=latencyFixture();
before=reports;
T=sixgr.report.collectCSIReportLatency(reports,measurements);
assert(isequaln(before,reports) && height(T)==2 && all(T.LatencyAvailable));
assert(isequal(T.MeasurementSourceSlot,[18;18]) && all(T.ConfiguredReferenceSlot==19));
assert(max(abs(T.MeasurementEndToDelivery_ms-[1.1;2.1]))<1e-12);
assert(max(abs(T.MeasurementCompletionDelay_ms+.0+ ...
    T.MeasurementAvailableToUCIObservationEnd_ms+T.UCICompletionDelay_ms- ...
    T.MeasurementEndToDelivery_ms))<1e-12);
assert(all(T.MeasurementAvailableToDelivery_ms < T.MeasurementEndToDelivery_ms));
% Captures may start before measurement availability due to RX pre-roll.
pre=reports(1,:); pre.ObservationStartSample=1000;
assert(sixgr.report.collectCSIReportLatency(pre,measurements).LatencyAvailable);
for field=["ReceiverClockEpoch","ObservationSampleRateHz"]
    bad=reports; bad.(field)(1)=bad.(field)(1)+1;
    reject(@()sixgr.report.collectCSIReportLatency(bad,measurements),'sixgr:report:CSILatencyClockMismatch');
end
bad=reports; bad.AvailableAtSample(1)=bad.ObservationEndSampleExclusive(1)-1;
reject(@()sixgr.report.collectCSIReportLatency(bad,measurements),'sixgr:report:CSILatencyNoncausalClock');
reject(@()sixgr.report.collectCSIReportLatency(reports,[measurements;measurements(1,:)]), ...
    'sixgr:report:CSILatencyAmbiguousObservation');
bad=reports; bad.CSIUCIDecodeOk(:)=false;
assert(~any(sixgr.report.collectCSIReportLatency(bad,measurements).LatencyAvailable));
bad=reports; bad.UEReferenceRecordJSON(:)="";
assert(~any(sixgr.report.collectCSIReportLatency(bad,measurements).LatencyAvailable));
legacy=removevars(reports,'ReceiverClockEpoch');
old=sixgr.report.collectCSIReportLatency(legacy,measurements);
assert(~any(old.LatencyAvailable) && all(isnan(old.MeasurementEndToDelivery_ms)));
% A same-slot sample clock alone cannot identify the chosen CSI estimate.
for field=["CSIReportConfigID","CSIMeasurementID","CSIMeasurementDigest"]
    bad=measurements; bad.(field)(1)="another_identity";
    missing=sixgr.report.collectCSIReportLatency(reports,bad);
    assert(~missing.LatencyAvailable(1) && missing.LatencyAvailable(2));
    multiple=sixgr.report.collectCSIReportLatency(reports,[measurements;bad(1,:)]);
    assert(all(multiple.LatencyAvailable));
end
bad=measurements; bad.CSIConfigurationEpoch(1)=999;
assert(~sixgr.report.collectCSIReportLatency(reports(1,:),bad).LatencyAvailable);
bad=measurements; bad.MeasurementClockEpoch(1)=999;
assert(all(sixgr.report.collectCSIReportLatency(reports,[measurements;bad(1,:)]).LatencyAvailable));
bad=reports; audit=jsondecode(bad.UEReferenceRecordJSON(1));
audit=rmfield(audit,'CSIMeasurementDigest'); bad.UEReferenceRecordJSON(1)=string(jsonencode(audit));
assert(~sixgr.report.collectCSIReportLatency(bad(1,:),measurements).LatencyAvailable);
% Decoded content errors must not change clock association or scheduler data.
wrong=reports; wrong.CQI(:)=1; wrong.RI(:)=1;
assert(isequal(sixgr.report.collectCSIReportLatency(wrong,measurements).MeasurementEndToDelivery_ms, ...
    T.MeasurementEndToDelivery_ms));

trials=adaptationFixture();
A=sixgr.report.collectAdaptationApplicationEvidence(trials,"DL");
assert(height(A)==4 && isequal(A.ApplicationObserved,[true;false;false;false]) && ...
    isequal(A.RightCensored,[false;false;true;false]));
assert(A.FirstAppliedSlot(1)==3 && isnan(A.FirstAppliedSlot(2)) && ...
    isnan(A.FirstAppliedSlot(4)), ...
    'A different point or same-row older decision must not complete this decision.');
assert(contains(A.ApplicationStatus(2),"not_proven_scheduler_loss"));
bad=trials; bad.LinkAdaptationAppliedFeedbackSourceSlot(2)=2;
reject(@()sixgr.report.collectAdaptationApplicationEvidence(bad,"DL"), ...
    'sixgr:report:AdaptationAppliedBeforeDue');
bad=trials; bad.LinkAdaptationScheduled(1)=2;
reject(@()sixgr.report.collectAdaptationApplicationEvidence(bad,"DL"), ...
    'sixgr:report:InvalidAdaptationFlag');
reject(@()sixgr.report.collectAdaptationApplicationEvidence([trials;trials(1,:)],"DL"), ...
    'sixgr:report:AdaptationAmbiguousDecision');
bad=trials; bad.LinkAdaptationScheduledFeedbackSourceSlot(1)=0;
reject(@()sixgr.report.collectAdaptationApplicationEvidence(bad,"DL"), ...
    'sixgr:report:AdaptationNoncausalDecision');
bad=trials; bad.LinkAdaptationScheduledApplySlot(1)=bad.Slot(1);
reject(@()sixgr.report.collectAdaptationApplicationEvidence(bad,"DL"), ...
    'sixgr:report:AdaptationNoncausalDecision');
assert(isempty(sixgr.report.collectAdaptationApplicationEvidence( ...
    removevars(trials,'LinkAdaptationScheduledApplySlot'),"DL")));

root=fullfile(pwd,'results','validation','causal_feedback_metrics', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
layout=sixgr.report.resultLayout(root); sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'received_csi_reports.csv'),reports,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'csi_rs_trials.csv'),measurements,'PreserveSchema',true);
trials.AirInterfaceTTI_ms=repmat(.5,height(trials),1); % wrong old latency surrogate
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'),trials,'PreserveSchema',true);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
manifest=struct('CodeVersion',"test",'CodeDetail',"numerical_clock_and_decision_fixtures", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
out=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false), ...
    manifest,struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
rows=out.CategoryRows;
L=rows(rows.MetricKey=="report_latency" & rows.Statistic=="MeasurementEndToDelivery_ms",:);
assert(height(L)==2 && all(L.CountsTowardCoverage) && ...
    max(abs(sort(L.ValueNumeric)-[1.1;2.1]))<1e-12);
assert(all(contains(L.MetricName,"conditional engineering")));
assert(~any(ismember(rows.Statistic,["application_step_ms","DL_radio_tti", ...
    "UL_radio_tti","scheduled_not_applied_rate"])));
rates=rows(rows.MetricKey=="scheduler_application_loss" & rows.Statistic=="application_observed_fraction",:);
assert(height(rates)==2 && isequal(sort(rates.ValueNumeric),[0;.5]), ...
    'Denominator must be eligible scheduled decisions in each point, not all data rows.');
assert(all(contains(rates.MetricName,"not scheduler-loss")));
readback=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'csi_report_latency_observations.csv'),'TextType','string');
assert(height(readback)==2 && all(readback.LatencyAvailable==1));
% No retained receiver completion: a finite configured TTI is not latency.
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'received_csi_reports.csv'),reports([],:),'PreserveSchema',true);
unjoined=trials; unjoined.LinkAdaptationScheduledFeedbackSourceSlot(:)=NaN;
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'),unjoined,'PreserveSchema',true);
out=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false), ...
    manifest,struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
assert(~any(out.CategoryRows.CountsTowardCoverage(out.CategoryRows.MetricKey=="report_latency")));
assert(~any(out.CategoryRows.CountsTowardCoverage(out.CategoryRows.MetricKey=="scheduler_application_loss")));
censored=trials(5,:);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'),censored,'PreserveSchema',true);
out=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false), ...
    manifest,struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
assert(~any(out.CategoryRows.CountsTowardCoverage(out.CategoryRows.MetricKey=="scheduler_application_loss")));
fprintf('CAUSAL_FEEDBACK_REPORT_METRICS_PASS clock_pairs=2 decision_pairs=4 full_export=3 evidence=%s\n',root);
ok=true;
end

function [reports,measurements]=latencyFixture()
ue=struct('Direction',"DL",'UEIndex',1,'RNTI',7,'ServingCell',1, ...
    'SourceSlot',18,'MeasurementAvailableSlot',19,'DueSlot',24,'CSIReferenceSlot',19, ...
    'SourceSignal',"CSI-RS",'ReportIdentity',"report24",'CSIReportConfigID',"report0", ...
    'CSIConfigurationEpoch',2,'MeasurementAvailableAtSample',1300,'MeasurementClockEpoch',3, ...
    'CSIMeasurementID',"fixture_CSI18",'CSIMeasurementDigest',"fixture_digest_CSI18", ...
    'MeasurementClockDomain',"shared_receiver_sample_clock/v1");
r=ue; r.SourceSlot=19;
r.SourceSlotAuthority="configured_CSI_reference_resource_not_UE_measurement_slot";
r.UEReferenceRecordJSON=string(jsonencode(ue)); r.CSIUCIDecodeOk=true;
r.DeliveryStatus="delivered_to_runtime_scheduler"; r.DeliveredSlot=25;
r.CSIUCIChannel="PUCCH"; r.ObservationID="rx24";
r.AvailableAtSample=2300; r.ReceiverClockEpoch=3;
r.ReceiverClockDomain="shared_receiver_sample_clock/v1";
r.ObservationStartSample=2000; r.ObservationEndSampleExclusive=2200; r.ObservationSampleRateHz=1e6;
r.SweepPointIndex=1; r.CQI=10; r.RI=2;
reports=struct2table(r); r.SweepPointIndex=2; r.AvailableAtSample=3300;
reports=[reports;struct2table(r)];
measurements=table([18;18],[1;1],[7;7],[1;2],[1000;1000],[1200;1200], ...
    [1300;1300],[1e6;1e6],[3;3],repmat("shared_receiver_sample_clock/v1",2,1), ...
    'VariableNames',{'Slot','UEIndex','RNTI','SweepPointIndex','ObservationStartSample', ...
    'ObservationEndSampleExclusive','ResultAvailableAtSample','ObservationSampleRateHz', ...
    'MeasurementClockEpoch','MeasurementClockDomain'});
measurements.CSIReportConfigID=repmat("report0",2,1);
measurements.CSIConfigurationEpoch=repmat(2,2,1);
measurements.CSIMeasurementID=repmat(ue.CSIMeasurementID,2,1);
measurements.CSIMeasurementDigest=repmat(ue.CSIMeasurementDigest,2,1);
end

function T=adaptationFixture()
% Decision at 1 applies at 3. Decision at 2 does not apply by the retained
% horizon. Decision at 5 is censored. Point 2 cannot consume point-1 feedback.
T=table([1;2;3;4;5;1;5],[1;1;0;0;1;1;0],[0;1;1;1;1;0;0], ...
    [1;2;NaN;NaN;5;1;NaN],[3;4;NaN;NaN;7;3;NaN], ...
    [NaN;0;1;1;1;NaN;NaN],[1;1;1;1;1;2;2],ones(7,1), ...
    'VariableNames',{'Slot','LinkAdaptationScheduled','LinkAdaptationApplied', ...
    'LinkAdaptationScheduledFeedbackSourceSlot','LinkAdaptationScheduledApplySlot', ...
    'LinkAdaptationAppliedFeedbackSourceSlot','SweepPointIndex','UEIndex'});
end

function reject(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s; got %s',id,ex.identifier); return; end
error('test:ExpectedRejection','Expected %s',id);
end
