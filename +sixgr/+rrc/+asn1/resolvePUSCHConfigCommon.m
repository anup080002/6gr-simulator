function [timing,common]=resolvePUSCHConfigCommon(common,scsKHz)
% Validate base received/configured IE without filling its absent wire fields.
% TS 38.331 V18.8.0 PUSCH-ConfigCommon pp983-984 and TDRA pp990-991.
% Timing defaults below apply to an existing allocation row, never an absent
% list. They are not a decoded grant or a physical scheduling decision.
err='sixgr:rrc:asn1:UnsupportedSIB1IE';
allowed=["groupHoppingEnabledTransformPrecoding","pusch_TimeDomainAllocationList", ...
    "msg3_DeltaPreamble","p0_NominalWithGrant"];
assert(isstruct(common)&&isscalar(common)&&all(ismember(string(fieldnames(common)),allowed)), ...
    err,'Unsupported PUSCH-ConfigCommon fields.');
if isfield(common,'groupHoppingEnabledTransformPrecoding')
    v=common.groupHoppingEnabledTransformPrecoding;
    assert((ischar(v)&&isrow(v)||isstring(v)&&isscalar(v)) && string(v)=="enabled", ...
        err,'groupHoppingEnabledTransformPrecoding must be enabled or absent.');
    common.groupHoppingEnabledTransformPrecoding=string(v);
end
if isfield(common,'msg3_DeltaPreamble')
    localInteger(common.msg3_DeltaPreamble,-1,6,err);
    common.msg3_DeltaPreamble=double(common.msg3_DeltaPreamble);
end
if isfield(common,'p0_NominalWithGrant')
    localInteger(common.p0_NominalWithGrant,-202,24,err);
    assert(mod(common.p0_NominalWithGrant,2)==0,err,'p0-NominalWithGrant permits only even dBm values.');
    common.p0_NominalWithGrant=double(common.p0_NominalWithGrant);
end
timing=struct('Available',false,'K2Slots',zeros(1,0),'K2Present',false(1,0), ...
    'K2Source',strings(1,0),'MappingType',strings(1,0),'StartSymbolAndLength',zeros(1,0), ...
    'Source',"PUSCH_ConfigCommon_original_row_operands", ...
    'StandardsReference',"TS38.331_V18.8.0_PUSCH_TimeDomainResourceAllocation");
if ~isfield(common,'pusch_TimeDomainAllocationList'), return; end
rows=common.pusch_TimeDomainAllocationList;
assert((isstruct(rows)||iscell(rows))&&isvector(rows)&&numel(rows)>=1&&numel(rows)<=16, ...
    err,'pusch-TimeDomainAllocationList requires 1..16 original allocation rows.');
assert(isnumeric(scsKHz)&&isreal(scsKHz)&&isscalar(scsKHz)&&ismember(scsKHz,[15 30 60 120]), ...
    err,'Base PUSCH common timing supports explicit 15/30/60/120-kHz BWP SCS.');
for k=1:numel(rows)
    if iscell(rows), r=rows{k}; else, r=rows(k); end
    assert(isstruct(r)&&isscalar(r)&&all(isfield(r,{'mappingType','startSymbolAndLength'})) && ...
        all(ismember(string(fieldnames(r)),["k2","mappingType","startSymbolAndLength"])), ...
        err,'Unsupported or incomplete PUSCH time-domain allocation row.');
    v=r.mappingType;
    assert((ischar(v)&&isrow(v)||isstring(v)&&isscalar(v))&&any(string(v)==["typeA","typeB"]), ...
        err,'PUSCH mappingType requires typeA/typeB.');
    localInteger(r.startSymbolAndLength,0,127,err);
    present=isfield(r,'k2');
    if present
        localInteger(r.k2,0,32,err); k2=double(r.k2); source="original_k2_field";
    else
        k2=1+(scsKHz==60)+2*(scsKHz==120); source="standard_default_absent_k2_field";
    end
    timing.K2Slots(k)=k2; timing.K2Present(k)=present; timing.K2Source(k)=source;
    timing.MappingType(k)=string(r.mappingType);
    timing.StartSymbolAndLength(k)=double(r.startSymbolAndLength);
    r.mappingType=string(r.mappingType); r.startSymbolAndLength=double(r.startSymbolAndLength);
    if present, r.k2=double(r.k2); end
    if iscell(rows), rows{k}=r; else, rows(k)=r; end
end
common.pusch_TimeDomainAllocationList=rows;
timing.Available=true;
end

function localInteger(v,lo,hi,err)
assert(isnumeric(v)&&~islogical(v)&&isreal(v)&&isscalar(v)&&isfinite(v)&& ...
    v==fix(v)&&v>=lo&&v<=hi,err,'Common PUSCH integer operand is outside its ASN.1 domain.');
end
