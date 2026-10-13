function audit = restoreRALiteralEvidence(runFolder)
%RESTORERALITERALEVIDENCE Recover byte strings from sealed received evidence.
% Never invert rounded numbers or regenerate payloads from UE/config values.
% All other CSV cells, row counts and failed/no-observation states are kept.
root = string(runFolder);
audit = table('Size',[0 6],'VariableTypes',repmat({'string'},1,6), ...
    'VariableNames',{'TargetPath','SourcePath','SourceSHA256', ...
    'BeforeSHA256','AfterSHA256','BackupPath'});
manifestPath = fullfile(root,'raw','execution_manifest.json');
if ~isfile(manifestPath), return; end
manifest = jsondecode(fileread(manifestPath));
if ~isfield(manifest,'RawEvidenceIndexRelativePath') || ...
        strlength(string(manifest.RawEvidenceIndexRelativePath))==0
    % Older/failed runs may have no sealed raw tables. They cannot supply
    % recovery values; leave their existing evidence and failures untouched.
    return;
end
indexPath = fullfile(root,'raw','evidence','raw_evidence_index.csv');
assert(string(manifest.RawEvidenceIndexRelativePath)== ...
    "evidence/raw_evidence_index.csv",'sixgr:truth:RALiteralIndexPath', ...
    'Unexpected sealed evidence index path.');
assert(localHash(indexPath)==lower(string(manifest.RawEvidenceIndexSHA256)), ...
    'sixgr:truth:RALiteralHashMismatch','Sealed raw index hash differs.');
index = localTextTable(indexPath);
entry = index(index.TableName=="rawtrials_prach",:);
if isempty(entry), return; end
assert(height(entry)==1 && entry.RelativePath=="tables/rawtrials_prach.csv", ...
    'sixgr:truth:RALiteralSourceAmbiguous','Expected one sealed PRACH source.');
sourcePath = fullfile(root,'raw','evidence',entry.RelativePath);
sourceHash = localHash(sourcePath);
assert(sourceHash==lower(entry.SHA256), ...
    'sixgr:truth:RALiteralHashMismatch','Sealed PRACH source hash differs.');
source = localTextTable(sourcePath);
for field = ["RunID","ExecutionID","ConfigHash"]
    sourceField=field;
    if field=="ConfigHash", sourceField="ScenarioConfigHash"; end
    assert(all(source.(sourceField)==string(manifest.(field))) && ...
        entry.(field)==string(manifest.(field)), ...
        'sixgr:truth:RALiteralExecutionMismatch','Raw %s identity differs.',field);
end
assert(all(source.EvidenceScope=="in_path") && ...
    height(source)==str2double(entry.RowCount), ...
    'sixgr:truth:RALiteralSourceInvalid','Raw PRACH population differs.');
paths = ["air_interface/csv/prach_trials.csv","control/csv/prach_trials.csv", ...
    "control/csv/prach_table.csv","control/csv/msg3_pusch_trials.csv", ...
    "control/csv/msg4_contention_resolution.csv","control/csv/msg4_trials.csv", ...
    "control/csv/contention_monitoring_observations.csv", ...
    "control/csv/ue_contention_events.csv"];
planned = cell(size(paths));
% Validate every replacement before touching any target.
for k=1:numel(paths)
    path=fullfile(root,paths(k));
    if ~isfile(path), continue; end
    T=localTextTable(path); before=T;
    if isempty(T), continue; end
    names=string(T.Properties.VariableNames);
    isPRACH=ismember("RARunId",names);
    if isPRACH
        targetKeys=["RARunId","RAUEId","RAAttemptId"];
        fields=names(endsWith(names,"Hex") | endsWith(names,"ContentionIdentity"));
        fields=intersect(fields,string(source.Properties.VariableNames),'stable');
        mapping=[fields(:),fields(:)];
    elseif contains(paths(k),"msg3")
        targetKeys=["RunId","UEId","AttemptId"];
        mapping=["PayloadHex","Msg3PayloadHex"; ...
            "TransmittedPayloadHex","Msg3TransmittedPayloadHex"; ...
            "ContentionIdentity","Msg3ContentionIdentity"];
    elseif contains(paths(k),"msg4")
        targetKeys=["RunId","UEId","AttemptId"];
        mapping=["PayloadHex","Msg4PayloadHex"; ...
            "TransmittedPayloadHex","Msg4TransmittedPayloadHex"; ...
            "ExpectedContentionIdentity","Msg3ContentionIdentity"; ...
            "DecodedContentionIdentity","Msg4ContentionIdentity"];
    else
        targetKeys=["RunId","UEId","AttemptId"];
        mapping=["ReceivedIdentity","Msg4ContentionIdentity"];
    end
    assert(all(ismember(targetKeys,names)), ...
        'sixgr:truth:RALiteralMissingKey','RA table lacks an exact attempt key: %s',path);
    for row=1:height(T)
        matched=true(height(source),1);
        sourceKeys=["RARunId","RAUEId","RAAttemptId"];
        for key=1:3
            matched=matched & source.(sourceKeys(key))==T.(targetKeys(key))(row);
        end
        assert(nnz(matched)==1,'sixgr:truth:RALiteralSourceAmbiguous', ...
            'RA row must match exactly one sealed received attempt: %s row %d.',path,row);
        S=source(matched,:);
        if ismember("ConfigHash",names)
            assert(T.ConfigHash(row)==S.ScenarioConfigHash, ...
                'sixgr:truth:RALiteralExecutionMismatch','Target configuration differs.');
        end
        if ismember("ScheduledSlot",names)
            slotField="Msg4ScheduledSlot";
            if contains(paths(k),"msg3"), slotField="Msg3ScheduledSlot"; end
            assert(T.ScheduledSlot(row)==S.(slotField), ...
                'sixgr:truth:RALiteralSlotMismatch','RA scheduled slot differs.');
        end
        for field=1:size(mapping,1)
            target=mapping(field,1); original=mapping(field,2);
            if ~ismember(target,names), continue; end
            value=T.(target)(row);
            % Do not invent identity observations for no-DCI/failed decodes.
            if target=="ReceivedIdentity"
                if ismissing(value) || any(lower(value)==["","nan","<missing>"]), continue; end
                assert(T.IdentityMatches(row)=="1" && T.DCICrcPass(row)=="1", ...
                    'sixgr:truth:RALiteralObservationUnproven', ...
                    'Cannot reconstruct an unmatched/failed received identity.');
                crcField="TBCrcPass";
                if ismember("PDSCHCrcPass",names), crcField="PDSCHCrcPass"; end
                assert(ismember(crcField,names) && T.(crcField)(row)=="1", ...
                    'sixgr:truth:RALiteralObservationUnproven', ...
                    'Received contention identity requires its recorded TB CRC pass.');
                if ismember("AbsoluteSlot",names)
                    assert(T.AbsoluteSlot(row)==S.Msg4ScheduledSlot, ...
                        'sixgr:truth:RALiteralSlotMismatch','Received Msg4 slot differs.');
                end
            end
            exact=S.(original);
            missingExact=ismissing(exact) || any(lower(exact)==["","nan","<missing>"]);
            missingValue=ismissing(value) || any(lower(value)==["","nan","<missing>"]);
            if missingExact && missingValue, continue; end
            assert(~ismissing(exact) && ~isempty(regexp(char(exact), ...
                '^[0-9A-Fa-f]+$','once')), ...
                'sixgr:truth:RALiteralSourceInvalid','Source literal %s is not hex.',original);
            T.(target)(row)=exact;
        end
    end
    if ~isequaln(before,T), planned{k}=T; end
end
for k=1:numel(paths)
    if isempty(planned{k}), continue; end
    path=fullfile(root,paths(k)); beforeHash=localHash(path);
    [~,stem]=fileparts(path);
    backup=fullfile(root,'reports','recovery_sources',beforeHash+"_"+stem+".csv.original");
    if ~isfolder(fileparts(backup)), mkdir(fileparts(backup)); end
    if ~isfile(backup), copyfile(path,backup); end
    assert(localHash(backup)==beforeHash,'sixgr:truth:RALiteralBackupMismatch', ...
        'Cannot replace a target without preserving its original bytes.');
    sixgr.util.csvWriteTable(path,planned{k},'PreserveSchema',true);
    audit(end+1,:)={paths(k),"raw/evidence/tables/rawtrials_prach.csv", ...
        sourceHash,beforeHash,localHash(path),backup}; %#ok<AGROW>
end
if ~isempty(audit)
    sixgr.util.csvWriteTable(fullfile(root,'reports','csv', ...
        'ra_literal_evidence_recovery.csv'),audit,'PreserveSchema',true);
end
end

function T=localTextTable(path)
opts=detectImportOptions(path,'Delimiter',',','VariableNamingRule','preserve');
opts.VariableNamesLine=1; opts.DataLines=[2 Inf];
opts=setvartype(opts,opts.VariableNames,'string');
opts=setvaropts(opts,opts.VariableNames,'WhitespaceRule','preserve', ...
    'TreatAsMissing',{},'EmptyFieldRule','missing');
T=readtable(path,opts);
end

function value=localHash(path)
fid=fopen(path,'rb');
assert(fid>=0,'sixgr:truth:RALiteralSourceMissing','Missing file %s.',path);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=lower(sixgr.util.sha256Hex(fread(fid,Inf,'*uint8')));
end
