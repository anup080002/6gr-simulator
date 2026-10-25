function ok=testControlDetectionPopulationReporting()
% Declared producer-shaped observations through real CSV/final reporting.
% No detector, waveform, independence or statistical qualification claim.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','control_detection_populations', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite retained evidence.');
layout=sixgr.report.resultLayout(folder); sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
s=scfg.toStruct(); s.output.artifact_contract_engine.enabled=false;
scfg=sixgr.lls6g.config.ScenarioConfig(s);
cfg=sixgr.lls6g.buildInternalConfig(scfg,folder);
n=257;
base=table((1:n).',ones(n,1),repmat("FAIL",n,1),false(n,1), ...
    'VariableNames',{'Slot','UEID','Status','Crash'});
base.RunID=repmat("declared_fixture_not_PHY",n,1);
base.SweepPointIndex=ones(n,1); base.ConfiguredSNR_dB=zeros(n,1);
base.ObservationStartSample=(0:n-1).'*100;
base.ObservationEndSampleExclusive=base.ObservationStartSample+100;
base.ObservationSampleRateHz=repmat(1000,n,1);
base.ReceiverID=repmat("declared_receiver",n,1);
base.ReceiverObservationSHA256=repmat(string(repmat('a',1,64)),n,1);
base.SignalPresent=nan(n,1); base.DetectionAttempted=nan(n,1);
u=base; u.DetectionMetricValid=nan(n,1); u.DetectionOutcome=strings(n,1);
u.DTXFlag=nan(n,1); u.CRCPass=nan(n,1);
u.PresenceScoringStatus=repmat("observed_executed_component_presence",n,1);
u.DetectionMetricSource=repmat("declared_original_receiver_presence_decision",n,1);
u.ReceiverPUCCHFormat=repmat(2,n,1); u.ReceiverPUCCHResourceId=repmat("resource2",n,1);
u.SignalPresent(1:9)=[1;1;0;1;1;NaN;1;1;1];
u.DetectionAttempted(1:9)=[1;1;1;0;1;1;1;1;1];
u.DetectionMetricValid(1:9)=[1;1;1;0;0;1;1;2;1];
u.DetectionOutcome(1:9)=["detected";"dtx";"detected";"unavailable";"unavailable"; ...
    "detected";"detected";"dtx";"detected"];
u.DTXFlag(1:9)=[0;1;0;NaN;NaN;0;0;1;0];
u.CRCPass(1)=0; % Detected but UCI CRC failed: not a presence miss.
u.Status(3)="PASS"; % Quiet false acceptance: not an H1 miss population.
u.Status([4 7])="CRASH"; u.Crash([4 7])=true;
% Row7 completed a detector before a later crash; retain its original outcome.
u.PresenceScoringStatus(9)="unavailable_original_presence_not_retained";
u.SignalPresent(257)=NaN; u.DetectionAttempted(257)=1;
u.DetectionMetricValid(257)=1; u.DetectionOutcome(257)="dtx";
p=base;
for name=["DetectionUsable","DetectionSuccess","DCICrcPass","PDCCHPayloadMatch", ...
        "PDCCHExpectedDCIBitCount","PDCCHDCIBitsCompared","PDCCHDCIBitErrors", ...
        "PDCCHErrFlag","PDCCHCandidatesAvailable","PDCCHCandidatesAttempted","BlindDecodeCount"]
    p.(name)=nan(n,1);
end
for k=1:8
    p.SignalPresent(k)=1; p.DetectionAttempted(k)=1; p.DetectionUsable(k)=1;
    p.DetectionSuccess(k)=1; p.DCICrcPass(k)=1; p.PDCCHPayloadMatch(k)=1;
    p.PDCCHExpectedDCIBitCount(k)=41; p.PDCCHDCIBitsCompared(k)=41;
    p.PDCCHDCIBitErrors(k)=0; p.PDCCHErrFlag(k)=0;
    p.PDCCHCandidatesAvailable(k)=2; p.PDCCHCandidatesAttempted(k)=2; p.BlindDecodeCount(k)=4;
end
p.DCICrcPass(1)=0; p.PDCCHErrFlag(1)=17; p.DetectionSuccess(1)=0;
p.PDCCHPayloadMatch(1)=0; p.PDCCHDCIBitErrors(1)=2;
p.DetectionSuccess(2)=0; % CRC passed, contextual command acceptance failed.
p.SignalPresent(4)=0; p.DetectionAttempted(5)=0;
p.Status(5)="CRASH"; p.Crash(5)=true;
p.SignalPresent(6)=NaN; p.PDCCHCandidatesAttempted(7)=1;
p.PDCCHDCIBitsCompared(8)=NaN; % Configured expected length alone proves no TX.
p.SignalPresent(257)=1; p.DetectionAttempted(257)=2;
paths=[string(fullfile(layout.AirInterfaceCSVDir,'pdcch_trials.csv')), ...
    string(fullfile(layout.AirInterfaceCSVDir,'pucch_trials.csv'))];
sixgr.util.csvWriteTable(paths(1),p,'PreserveSchema',true,'RoundTripNumericText',true);
sixgr.util.csvWriteTable(paths(2),u,'PreserveSchema',true,'RoundTripNumericText',true);
sha=[string(sixgr.util.sha256File(paths(1))),string(sixgr.util.sha256File(paths(2)))];
manifest=struct('CodeVersion',"test",'CodeDetail',"declared_metadata_no_PHY", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
out=sixgr.truth.exportLLSReportingBundle(folder,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
for candidate={out.CategoryRows,sixgr.util.csvReadTable(out.DetailCSV,'TextType','string')}
    rows=candidate{1};
    check(rows,"miss_detection_probability","PUCCH",[1 2 7],[0 1 0],sha(2));
    check(rows,"pdcch_missed_expected_dci_command","PDCCH",[1 2 3],[1 1 0],sha(1));
    pure=rows(rows.MetricKey=="miss_detection_probability" & rows.Entity=="PDCCH_signal_presence",:);
    assert(height(pure)==1 && isnan(pure.ValueNumeric) && ~pure.CountsTowardCoverage);
    assert(~any(rows.MetricKey=="miss_detection_probability" & ismember(rows.Entity,["PDCCH","PUCCH"])), ...
        'Generic Status failure rates must not survive as control missed detection.');
end
% Copied contradictory original DTX alias must fail, not be silently dropped.
badFolder=fullfile(folder,'contradictory_original_outcome'); badLayout=sixgr.report.resultLayout(badFolder);
sixgr.util.ensureFolder(badLayout.AirInterfaceCSVDir);
bad=u; bad.DTXFlag(1)=1;
sixgr.util.csvWriteTable(fullfile(badLayout.AirInterfaceCSVDir,'pucch_trials.csv'),bad,'PreserveSchema',true);
caught=false;
try
    sixgr.truth.exportLLSReportingBundle(badFolder,scfg,cfg,struct('Ok',false),manifest, ...
        struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
catch exception
    caught=string(exception.identifier)=="sixgr:report:ConflictingControlDetectionEvidence";
    if ~caught, rethrow(exception); end
end
assert(caught && sha(1)==string(sixgr.util.sha256File(paths(1))) && ...
    sha(2)==string(sixgr.util.sha256File(paths(2))),'Original evidence changed or contradiction accepted.');
% Invalid original presence is a global input error, including for the
% existing false-alarm consumer. It is not a positive unknown-presence row.
badFolder=fullfile(folder,'invalid_presence_row257'); badLayout=sixgr.report.resultLayout(badFolder);
sixgr.util.ensureFolder(badLayout.AirInterfaceCSVDir);
bad=u; bad.SignalPresent(257)=2;
sixgr.util.csvWriteTable(fullfile(badLayout.AirInterfaceCSVDir,'pucch_trials.csv'),bad,'PreserveSchema',true);
caught=false;
try
    sixgr.truth.exportLLSReportingBundle(badFolder,scfg,cfg,struct('Ok',false),manifest, ...
        struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
catch exception
    caught=string(exception.identifier)=="sixgr:truth:InvalidFalseAlarmPresence";
    if ~caught, rethrow(exception); end
end
assert(caught,'Malformed original presence must fail the existing global guard.');
assert(sha(1)==string(sixgr.util.sha256File(paths(1))) && ...
    sha(2)==string(sixgr.util.sha256File(paths(2))),'Negative checks changed original evidence.');
fprintf('CONTROL_DETECTION_POPULATION_REPORTING_PASS declared_metadata_only=1 PHY=0\n');
ok=true;
end

function check(rows,key,signal,indices,values,digest)
r=rows(rows.MetricKey==key & startsWith(rows.Entity,signal+"@source_row="),:);
assert(height(r)==numel(indices) && all(r.Statistic=="observation") && all(r.Availability=="observed"));
for k=1:numel(indices)
    selected=r(r.Entity==signal+"@source_row="+indices(k),:);
    assert(height(selected)==1 && selected.ValueNumeric==values(k));
    q=jsondecode(selected.PopulationJSON);
    assert(q.SourceRowIndex==indices(k) && q.SourceRowCount==257 && ...
        string(q.SourceSHA256)==digest && ~q.StatisticallyQualified && ~q.StandardizedAccuracyQualified);
    assert(string(sixgr.util.sha256Hex(char(selected.PopulationJSON)))==selected.PopulationID);
    original=jsondecode(q.OriginalOperandsJSON);
    assert(isfield(original,'SignalPresent') && isfield(original,'DetectionAttempted') && ...
        isfield(original,'ObservationStartSample') && isfield(original,'Status'));
end
end
