function [ok,result]=testPRACHPublicProvenance()
% Declared producer-shaped metadata through the real public adapter/CSV.
% No native PRACH, decoded SI, association or gNB monitoring is executed.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','prach_public_provenance', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite retained evidence.');
sixgr.util.ensureFolder(folder);
meta=struct('logical_run_id',"declared_public_wrapper",'run_id',17);
contract=sixgr.truth.llsOutputContract();
source=table([10;30;50],[1;1;1],[2;2;2], ...
    'VariableNames',{'Slot','CellId','UEId'});
source.RunId=repmat("declared_original_run",3,1);
source.RARunId=repmat("declared_ra_attempt_run",3,1);
source.RAAttemptId=[1;2;3];
source.RACellId=[1;1;1]; source.RAUEId=[2;2;2];
source.PreambleIndexTx=[7;11;15];
source.PreambleIndexDetected=[7;NaN;16]; % Preserve miss/different RAPID.
source.PreambleIndex=[7;NaN;16]; % Standalone detector's actual legacy meaning.
source.RequestedPreambleIndex=source.PreambleIndexTx;
source.DetectedPreambleIndex=source.PreambleIndexDetected;
source.RARNTI=[14;28;42]; source.PRACHFrequencyIndex=[0;1;2];
source.PRACHOccasionID=["f0_s9_l0_f0";"f1_s9_l0_f1";"f2_s9_l0_f2"];
source.PRACHOccasionFrame=[0;1;2]; source.PRACHOccasionSlot=[9;9;9];
source.PRACHOccasionSymbol=[0;0;0]; source.PRACHOccasionIndex=[0;1;2];
source.RASlotTimeBase=repmat("absolute_zero_based",3,1);
source.Msg1ScheduledSlot=[9;29;49];
source.AssociatedSSBIndex=[0;1;2];
source.AssociatedSSBSelectionSource=repmat("declared_metadata_fixture_not_received",3,1);
source.AssociatedSSBMeasurement_dB=[-80.5;-81.25;-82.75];
source.SSBToPRACHAssociationApplied=[true;false;true];
source.SIB1RACHBindingApplied=[true;true;false];
source.SIB1RACHBindingSource=repmat("declared_binding_fixture",3,1);
source.SIB1RACHPayloadHash=repmat(string(repmat('a',1,64)),3,1);
source.SIB1RACHTreeHash=repmat(string(repmat('b',1,64)),3,1);
source.RACHConfigHash=repmat(string(repmat('c',1,64)),3,1);
source.ObservationID=["declared_obs_a";"declared_obs_b";"declared_obs_c"];
source.ObservationStartSample=[100;200;300];
source.ObservationEndSampleExclusive=[150;250;350];
source.ObservationSampleRateHz=repmat(30.72e6,3,1);
source.ResultAvailableAtSample=[151;251;351];
source.PRACHTimingSampleRate_Hz=repmat(30.72e6,3,1);
source.PRACHRawTimingEstimate_samples=[0;1;2];
source.SweepPointIndex=[1;1;2]; source.ConfiguredSNR_dB=[30;30;20];
source.source_artifact_ref=repmat("declared/air_interface/csv/prach_trials.csv",3,1);
original=source;
out=project(source,contract,meta);
assert(isequaln(source,original)&&height(out)==3);
assert(isequal(out.RA_RNTI,source.RARNTI)&& ...
    isequal(out.FrequencyIndex,source.PRACHFrequencyIndex)&& ...
    isequaln(out.PreambleIndex,source.PreambleIndex)&& ...
    isequal(out.OccasionID,source.PRACHOccasionID)&& ...
    isequal(out.OccasionIndex,source.PRACHOccasionIndex));
retained=setdiff(string(source.Properties.VariableNames),["CellId","UEId"],'stable');
for field=retained
    assert(isequaln(out.(field),source.(field)),'Original field changed: %s.',field);
end
assert(contains(out.PRACHProjectionScope(1),"not_association")&& ...
    all(contains(out.SSBToPRACHAssociationAppliedScope,"not_validated_ro"))&& ...
    ~ismember("SSBToPRACHAssociationVerified",string(out.Properties.VariableNames)));

% Exercise original source serialization, actual generic reader, adapter,
% public writer and reader. No original source bytes may be rewritten.
sourcePath=fullfile(folder,'declared_original_prach.csv');
sixgr.util.csvWriteTable(sourcePath,source,'PreserveSchema',true,'RoundTripNumericText',true);
sourceSHA=sixgr.util.sha256File(sourcePath);
imported=sixgr.util.csvReadTable(sourcePath,'TextType','string');
published=project(imported,contract,meta);
publicPath=fullfile(folder,'prach_detection_table.csv');
sixgr.util.csvWriteTable(publicPath,published,'PreserveSchema',true,'RoundTripNumericText',true);
readback=sixgr.util.csvReadTable(publicPath,'TextType','string');
for field=["RARNTI","RA_RNTI","FrequencyIndex","PreambleIndex", ...
        "PreambleIndexDetected","AssociatedSSBIndex","ObservationStartSample", ...
        "ObservationEndSampleExclusive","ResultAvailableAtSample","RAAttemptId"]
    assert(isequaln(double(readback.(field)),double(published.(field))));
end
for field=["OccasionID","PRACHOccasionID","RARunId","SIB1RACHPayloadHash", ...
        "SIB1RACHTreeHash","RACHConfigHash","RASlotTimeBase","ObservationID", ...
        "SSBToPRACHAssociationAppliedScope","PRACHProjectionIndexScope"]
    assert(isequal(string(readback.(field)),string(published.(field))));
end
assert(string(sourceSHA)==string(sixgr.util.sha256File(sourcePath)));

% Missing original fields are unavailable, not reconstructed from metadata.
legacy=table(10,'VariableNames',{'Slot'});
missing=project(legacy,contract,meta);
assert(isnan(missing.RA_RNTI)&&isnan(missing.FrequencyIndex)&& ...
    isnan(missing.PreambleIndex)&&isnan(missing.OccasionIndex)&&missing.OccasionID=="");
for field=["AssociatedSSBIndex","SIB1RACHPayloadHash","RACHConfigHash", ...
        "SSBToPRACHAssociationApplied","SSBToPRACHAssociationAppliedScope","ObservationID"]
    assert(~ismember(field,string(missing.Properties.VariableNames)));
end
legacy.prach_occasion_id=4;
legacy.RA_RNTI=12; legacy.FrequencyIndex=0; legacy.preamble_id=3;
old=project(legacy,contract,meta);
assert(old.OccasionIndex==4&&old.OccasionID==""&&old.RA_RNTI==12&&old.PreambleIndex==3);
empty=project(table(),contract,meta); assert(isempty(empty));

% Unknown numeric aliases do not hide a populated original producer field.
same=source; same.RA_RNTI=source.RARNTI; same.RA_RNTI(2)=NaN;
same.FrequencyIndex=source.PRACHFrequencyIndex; same.OccasionID=source.PRACHOccasionID;
joined=project(same,contract,meta); assert(isequal(joined.RA_RNTI,source.RARNTI));
bad=same; bad.RA_RNTI(3)=99;
reject(@()project(bad,contract,meta),'sixgr:report:PRACHProvenanceConflict');
bad=same; bad.OccasionID(3)="other_original_occasion";
reject(@()project(bad,contract,meta),'sixgr:report:PRACHProvenanceConflict');
bad=same; bad.preamble_id=source.PreambleIndex; bad.preamble_id(3)=99;
reject(@()project(bad,contract,meta),'sixgr:report:PRACHProvenanceConflict');
bad=source; bad.RARNTI=string(source.RARNTI);
reject(@()project(bad,contract,meta),'sixgr:report:PRACHProvenanceType');
bad=source; bad.PRACHOccasionID=[1;2;3];
reject(@()project(bad,contract,meta),'sixgr:report:PRACHProvenanceType');
bad=source; bad.PRACHFrequencyIndex=[0;1;1.5];
reject(@()project(bad,contract,meta),'sixgr:report:PRACHProvenanceValue');
bad=source; bad.RARNTI=[source.RARNTI,source.RARNTI];
reject(@()project(bad,contract,meta),'sixgr:report:PRACHProvenanceType');
late=source(ones(257,1),:); late.FrequencyIndex=late.PRACHFrequencyIndex;
late.FrequencyIndex(257)=9;
reject(@()project(late,contract,meta),'sixgr:report:PRACHProvenanceConflict');
result=struct('Scope',"declared_publication_metadata_not_physical_access", ...
    'SourcePath',string(sourcePath),'SourceSHA256',string(sourceSHA), ...
    'PublicPath',string(publicPath),'OriginalRows',height(source));
ok=true;
fprintf('PASS testPRACHPublicProvenance (declared metadata/CSV only; no PHY or association qualification)\n');
end

function out=project(source,contract,meta)
tables=sixgr.truth.buildLLSPublicOutputTables(struct('prach_table',source),contract,meta);
out=tables.prach_detection_table;
end

function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s.',id,cause.identifier);
    return;
end
error('sixgr:test:MissingPRACHProjectionGuard','Expected %s.',id);
end
