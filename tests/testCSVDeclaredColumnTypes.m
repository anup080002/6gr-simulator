function ok=testCSVDeclaredColumnTypes()
% Explicit receiver schema, exact bit strings and malformed-cell rejection.
root=tempname;
mkdir(root);
cleanup=onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
path=fullfile(root,'declared.csv');
T=table("1","76777","00000101","001234", ...
    'VariableNames',{'CRCPass','DataDecodeAvailableAtSample', ...
    'UCIDecodedBitVector','AssignmentDigest'});
types=struct('CRCPass','double','DataDecodeAvailableAtSample','double', ...
    'UCIDecodedBitVector','string','AssignmentDigest','string');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
R=sixgr.util.csvReadTable(path,'TextType','string','ColumnTypes',types);
assert(R.CRCPass==1 && R.DataDecodeAvailableAtSample==76777);
assert(R.UCIDecodedBitVector=="00000101" && R.AssignmentDigest=="001234");
try
    sixgr.util.csvReadTable(path,'ColumnTypes',struct('MissingColumn','double'));
    error('test:ExpectedMissingColumn','Missing schema column was accepted.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:util:csvReadTable:MissingDeclaredColumn'));
end
T.CRCPass="not_a_number";
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
rejected=false;
try
    sixgr.util.csvReadTable(path,'ColumnTypes',types);
catch ME
    rejected=~isempty(ME.identifier);
end
assert(rejected,'Malformed numeric evidence must not silently become missing.');
ok=true;
fprintf('CSV_DECLARED_COLUMN_TYPES_PASS\n');
end
