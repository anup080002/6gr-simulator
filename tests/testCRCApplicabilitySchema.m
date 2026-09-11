function ok=testCRCApplicabilitySchema()
% Keep unavailable CRC values alongside their explicit applicability;
% never turn detection, no decode, or missing data into a CRC pass/fail.
T=table(NaN,false,true,NaN,'VariableNames', ...
    {'CRCPass','CRCApplicable','DetectionSuccess','UnrelatedBlank'});
kept=sixgr.util.pruneStructurallyBlankTableColumns(T);
assert(ismember('CRCPass',kept.Properties.VariableNames) && ...
    isnan(kept.CRCPass) && ~kept.CRCApplicable && kept.DetectionSuccess);
assert(~ismember('UnrelatedBlank',kept.Properties.VariableNames));
% A missing result on an applicable CRC must also remain visible to audits.
T.CRCApplicable=true;
kept=sixgr.util.pruneStructurallyBlankTableColumns(T);
assert(ismember('CRCPass',kept.Properties.VariableNames) && isnan(kept.CRCPass));
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
path=fullfile(folder,'crc_applicability.csv');
sixgr.util.csvWriteTable(path,T);
persisted=readtable(path,'VariableNamingRule','preserve');
assert(ismember('CRCPass',persisted.Properties.VariableNames) && ...
    isnan(persisted.CRCPass) && persisted.CRCApplicable);
ok=true;
end
