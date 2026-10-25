function ok=testPUCCHPowerAdmissionExport()
% Declared audit-row serialization test, not a waveform/DTX/CRC campaign.
setup6GRSimToolkit('Verbose',false);
old=getenv('SIXGR_PERSISTENCE_ENABLED');
cleanup=onCleanup(@()setenv('SIXGR_PERSISTENCE_ENABLED',old)); %#ok<NASGU>
setenv('SIXGR_PERSISTENCE_ENABLED','1');
root=fullfile(pwd,'results','validation','pucch_power_admission_export', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(root),'Never replace prior evidence.');
reuseScope=sixgr.util.CSVWriteReuse.scope(root); %#ok<NASGU> same explicit scope as live publication
layout=sixgr.report.resultLayout(root);
primaryPath=fullfile(layout.AirInterfaceCSVDir,'pucch_trials.csv');
primary=table("original_receiver_fixture",false,0, ...
    'VariableNames',{'ObservationID','DTXFlag','CRCPass'});
sixgr.util.csvWriteTable(primaryPath,primary,'PreserveSchema',true);
primarySHA=sixgr.util.sha256File(primaryPath);
row=localRow(); T=repmat(row,257,1);
T.ObservationID="declared_observation_"+string((1:height(T))');
T.PhysicalOccasionID="declared_occasion_"+string((1:height(T))');
T.DecisionSample=(0:height(T)-1)'*30720;
T.DecisionSlot=(1:height(T))'; T.PUCCHResourceSlot=T.DecisionSlot;
% Configured maximum age is a threshold, not an integer calendar period.
T.MaximumPowerReferenceAgeSlots(1)=0.5; T.MaximumPowerReferenceAgeSlots(2)=Inf;
T.PowerReferenceStatus(end)="stale";
T.PowerReferenceMeasurementID(end)="original_reference_001";
T.PowerReferenceProducerSlot(end)=1; T.PowerReferenceAvailableSlot(end)=2;
T.MeasuredPathloss_dB(end)=113.2718281828459;
T.SelectedGNBTransport(end)="PUSCH"; % Not permission to invent a PUCCH receiver.
T.PathlossReferenceLifetime=repmat("configured_age_limit",height(T),1);
T.ReferenceLifecycleStatus=repmat("not_enabled_configured_age_limit",height(T),1);
T.PowerReferenceStatus(256)="reference_lifecycle_unavailable";
T.PathlossReferenceLifetime(256)="retained_filtered_reference";
T.ReferenceLifecycleStatus(256)="no_observation_for_current_reference_power_generation";
T.OriginalFixtureNote=repmat("quoted ""field"", no RX claim"+newline+"second line",height(T),1);
state=struct('SharedPUCCHPowerAdmissionTable',T,'ControlTrials',struct('PUCCH',primary));
original=state;
path=sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(state,root);
assert(path==string(fullfile(layout.ControlCSVDir,'pucch_power_admission.csv')));
assert(isequaln(original,state),'Serialization cannot mutate runtime value state.');
types=struct();
for name=string(T.Properties.VariableNames)
    if isstring(T.(name)), types.(name)='string'; end
end
saved=sixgr.util.csvReadTable(path,'ColumnTypes',types);
assert(isequal(saved.Properties.VariableNames,T.Properties.VariableNames)&&height(saved)==height(T));
for name=string(T.Properties.VariableNames)
    if isstring(T.(name))
        % Missing CSV text denotes the original unavailable empty token.
        actual=string(saved.(name)); actual(ismissing(actual))="";
        assert(isequal(actual,T.(name)),'Original scalar text/JSON must survive the real writer.');
    elseif islogical(T.(name))
        assert(isequal(logical(saved.(name)),T.(name)));
    else
        assert(isequaln(saved.(name),T.(name)),'Round-trip numeric export must preserve original operands.');
    end
end
assert(sixgr.util.sha256File(primaryPath)==primarySHA);
assert(~isfile(fullfile(layout.AirInterfaceCSVDir,'pucch_power_admission.csv')));
auditSHA=sixgr.util.sha256File(path);
% The production cache is explicitly scoped, never a global timestamp cache.
% Verify its own counters plus original file bytes/mtime; no timestamp mutation.
file=java.io.File(char(path));
mtime=file.lastModified();
cacheBefore=sixgr.util.CSVWriteReuse.statistics();
assert(sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(state,root)==path);
cacheAfter=sixgr.util.CSVWriteReuse.statistics();
assert(cacheAfter.ReusedWrites==cacheBefore.ReusedWrites+1&& ...
    cacheAfter.PublishedWrites==cacheBefore.PublishedWrites);
assert(file.lastModified()==mtime&&sixgr.util.sha256File(path)==auditSHA);
for mutation=["late_admitted","late_prepared","late_false_required","late_missing_id", ...
        "late_wrong_scope","late_duplicate_observation","late_bad_epoch","late_bad_json", ...
        "late_unjoined_report","numeric_flag","missing_column","receiver_result", ...
        "unknown_status","missing_lifecycle","wrong_lifecycle_mode","available_lifecycle","unknown_lifecycle"]
    bad=state;
    switch mutation
        case "late_admitted", bad.SharedPUCCHPowerAdmissionTable.PreparationAdmitted(end)=true;
        case "late_prepared", bad.SharedPUCCHPowerAdmissionTable.UETransmissionPrepared(end)=true;
        case "late_false_required", bad.SharedPUCCHPowerAdmissionTable.MeasuredPowerReferenceRequired(end)=false;
        case "late_missing_id", bad.SharedPUCCHPowerAdmissionTable.ObservationID(end)="";
        case "late_wrong_scope", bad.SharedPUCCHPowerAdmissionTable.EvidenceClass(end)="received_PUCCH";
        case "late_duplicate_observation"
            bad.SharedPUCCHPowerAdmissionTable.ObservationID(end)=T.ObservationID(1);
        case "late_bad_epoch", bad.SharedPUCCHPowerAdmissionTable.ClockEpoch(end)=NaN;
        case "late_bad_json", bad.SharedPUCCHPowerAdmissionTable.PUCCHGrantIDsJSON(end)="[1]";
        case "late_unjoined_report", bad.SharedPUCCHPowerAdmissionTable.CSIReportIdentitiesJSON(end)='["other_report"]';
        case "numeric_flag"
            bad.SharedPUCCHPowerAdmissionTable.PreparationAdmitted=double(T.PreparationAdmitted);
        case "missing_column", bad.SharedPUCCHPowerAdmissionTable.ObservationID=[];
        case "receiver_result", bad.SharedPUCCHPowerAdmissionTable.DTXFlag=true(height(T),1);
        case "unknown_status", bad.SharedPUCCHPowerAdmissionTable.PowerReferenceStatus(end)="arbitrary_failure";
        case "missing_lifecycle", bad.SharedPUCCHPowerAdmissionTable.ReferenceLifecycleStatus=[];
        case "wrong_lifecycle_mode", bad.SharedPUCCHPowerAdmissionTable.PathlossReferenceLifetime(256)="configured_age_limit";
        case "available_lifecycle", bad.SharedPUCCHPowerAdmissionTable.ReferenceLifecycleStatus(256)="retained_filtered_reference_available";
        case "unknown_lifecycle", bad.SharedPUCCHPowerAdmissionTable.ReferenceLifecycleStatus(256)="arbitrary_failure";
    end
    localMustFail(@()sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(bad,root));
    assert(sixgr.util.sha256File(path)==auditSHA&&sixgr.util.sha256File(primaryPath)==primarySHA, ...
        'Rejected audit must not overwrite original valid or primary output.');
end
emptyRoot=fullfile(root,'empty');
assert(sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(struct(),emptyRoot)=="");
assert(sixgr.truth.exportPUCCHPowerAdmissionDiagnostics( ...
    struct('SharedPUCCHPowerAdmissionTable',T([],:)),emptyRoot)=="");
assert(~isfolder(emptyRoot),'No observation means no fabricated diagnostic artifact.');
bad=struct('SharedPUCCHPowerAdmissionTable',struct());
localMustFail(@()sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(bad,emptyRoot));
setenv('SIXGR_PERSISTENCE_ENABLED','0');
assert(sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(state,emptyRoot)==""&&~isfolder(emptyRoot));
% Production source-wiring check complements the actual helper export above;
% it does not claim this test executed a full live/final/failure scenario.
source=fileread(which('sixgr.truth.CoupledTruthRuntime'));
assert(count(string(source),'sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(state,runFolder)')==1);
bundle=fileread(which('sixgr.truth.runWaveformLinkBundle'));
assert(contains(bundle,'state = sixgr.truth.CoupledTruthRuntime.writeTables(state, runFolder);'));
fprintf('PUCCH_ADMISSION_EXPORT_PASS rows=257 malformed_cases=18 retained_lifecycle_roundtrip=1 primary_unchanged=1 scope=declared_audit_serialization\n');
ok=true;
end

function T=localRow()
r=struct('UEIndex',1,'ServingCell',1,'DecisionSlot',1,'PUCCHResourceSlot',1, ...
    'MeasuredPowerReferenceRequired',true,'PreparationAdmitted',false, ...
    'PowerReferenceStatus',"no_measurements", ...
    'Action',"defer_PUCCH_unavailable_measured_power_reference", ...
    'PowerReferenceRS',"SSB-0",'PowerReferenceSignalID',0,'MaximumPowerReferenceAgeSlots',8, ...
    'PowerReferenceMeasurementID',"",'PowerReferenceProducerSlot',NaN, ...
    'PowerReferenceAvailableSlot',NaN,'MeasuredPathloss_dB',NaN, ...
    'Source',"original_PUCCH_reference_preparation_admission", ...
    'EvidenceClass',"preparation_admission_not_PHY_execution",'RNTI',101, ...
    'ComponentCarrier',0,'ActiveULBWP',0,'PhysicalOccasionID',"declared_occasion", ...
    'ObservationID',"declared_observation",'DecisionSample',0,'ClockEpoch',1,'SampleRateHz',30720000, ...
    'PUCCHGrantIDsJSON',string('["grant_harq","PUCCH-CSI-report_001"]'), ...
    'CSIReportIdentitiesJSON',string('["report_001"]'),'SelectedGNBTransport',"PUCCH", ...
    'UETransmissionPrepared',false,'UEProducerDisposition',"closed_untransmitted_missing_measured_power_reference");
T=struct2table(r,'AsArray',true);
end

function localMustFail(f)
try, f(); catch ME
    assert(startsWith(string(ME.identifier),'sixgr:truth:PUCCHAdmissionExport'), ...
        'Unexpected rejection identifier: %s',ME.identifier);
    return;
end
error('sixgr:test:PUCCHAdmissionExportAccepted','Malformed admission evidence was accepted.');
end
