function counted = linkTrialDecodeCoverage(T)
%LINKTRIALDECODECOVERAGE Eligibility for completed DL/UL TB-trial coverage.
% This is an evidence/publication contract, not an NR reception threshold.
% Failed CRC is a valid decoded trial. An executed waveform, finite allocation,
% partial reception or usable pilot measurement alone is not a TB decode.
% This helper does not change the raw population, lifecycle or decoder result.
% It does not claim statistical sufficiency or define HARQ BLER denominators.
assert(istable(T),'sixgr:util:LinkTrialCoverageTableRequired', ...
    'Decode coverage requires the original DL/UL trial table.');
n=height(T);
direction=upper(strtrim(string(localColumn(T,'Direction',""))));
status=upper(strtrim(string(localColumn(T,'Status',""))));
crc=double(localColumn(T,'CRCPass',NaN));
schAttempted=(direction=="DL" & localTrue(T,'DLSCHDecodeAttempted')) | ...
    (direction=="UL" & localTrue(T,'ULSCHDecodeAttempted'));
schAvailable=(direction=="DL" & localTrue(T,'DLSCHDecodeAvailable')) | ...
    (direction=="UL" & localTrue(T,'ULSCHDecodeAvailable'));
counted=localTrue(T,'FinalizedFlag') & localFalse(T,'PartialRowFlag') & ...
    localFalse(T,'Crash') & localFalse(T,'IsWarmupFrame') & ...
    localTrue(T,'DecodeAttempted') & localTrue(T,'DecodeUsable') & ...
    schAttempted & schAvailable & localTrue(T,'CRCApplicable') & ...
    isfinite(crc) & (crc==0 | crc==1) & (status=="PASS" | status=="FAIL");
counted=reshape(logical(counted),n,1);
end

function value=localTrue(T,name)
% NaN is not positive evidence (logical(NaN) would incorrectly be true).
raw=localColumn(T,name,false);
assert(islogical(raw) || isnumeric(raw), ...
    'sixgr:util:LinkTrialCoverageFlagType','%s must be a numeric/logical flag.',name);
value=isfinite(double(raw)) & double(raw)==1;
end

function value=localFalse(T,name)
% Unknown exclusion flags cannot qualify a standalone row.
raw=localColumn(T,name,NaN);
assert(islogical(raw) || isnumeric(raw), ...
    'sixgr:util:LinkTrialCoverageFlagType','%s must be a numeric/logical flag.',name);
value=isfinite(double(raw)) & double(raw)==0;
end

function value=localColumn(T,name,default)
n=height(T);
if ismember(string(name),string(T.Properties.VariableNames))
    value=T.(name);
    assert(size(value,2)==1 && size(value,1)==n, ...
        'sixgr:util:LinkTrialCoverageColumnShape','%s must have one value per trial.',name);
else
    value=repmat(default,n,1);
end
end
