function out = resolveTDDCommonRuntime(originalIE, activeSCSKHz, cyclicPrefix, frequencyRange)
%RESOLVETDDCOMMONRUNTIME Validate an original TDD IE; derive a separate map.
% TS 38.331 V18.8.0 section 6.3.2, TDD-UL-DL-ConfigCommon/Pattern,
% pp1153-1154; TS 38.213 V18.8.0 section 11.1.
% Input uses the decoded MATLAB tree's underscore spelling of ASN.1 names.
% This is not a decoder or proof of received/installed authority. Callers
% retain their original payload/clock/cell binding and validate every other
% configured BWP's SCS separately. No scenario/dedicated-TDD fallback exists.
% Empty numeric [] or an empty scalar struct represents absent optional IE.
% Unknown extensions fail closed rather than being silently discarded.
out=struct('Present',false,'OriginalIE',originalIE, ...
    'EffectiveConfig',struct(),'SlotFormatState',[], ...
    'Reference',"TS38.331_V18.8.0_6.3.2_TDD_UL_DL_ConfigCommon_and_TS38.213_V18.8.0_11.1");
if (isnumeric(originalIE) && isreal(originalIE) && isequal(size(originalIE),[0 0])) || ...
        (isstruct(originalIE) && isscalar(originalIE) && isempty(fieldnames(originalIE)))
    return;
end
localFields(originalIE,["referenceSubcarrierSpacing","pattern1"],"pattern2","TDD-UL-DL-ConfigCommon");
range=localToken(frequencyRange,["FR1","FR2-1","FR2-2"],"frequencyRange");
cp=localToken(cyclicPrefix,["normal","extended"],"cyclicPrefix");
tokens=["kHz15","kHz30","kHz60","kHz120","kHz240","kHz480","kHz960"];
values=[15 30 60 120 240 480 960];
ref=values(tokens==localToken(originalIE.referenceSubcarrierSpacing,tokens,"referenceSubcarrierSpacing"));
switch range
    case "FR1", allowed=[15 30 60];
    case "FR2-1", allowed=[60 120];
    case "FR2-2", allowed=[120 480 960];
end
assert(ismember(ref,allowed),'sixgr:rrc:asn1:TDDReferenceSCSFrequencyRange', ...
    'The original reference SCS is not applicable to the explicitly supplied frequency range.');
assert(isnumeric(activeSCSKHz) && isreal(activeSCSKHz) && isscalar(activeSCSKHz) && ...
    isfinite(activeSCSKHz) && ismember(activeSCSKHz,values), ...
    'sixgr:rrc:asn1:InvalidTDDActiveSCS','Active BWP SCS must be an original numeric NR SCS in kHz.');
p1=localPattern(originalIE.pattern1,"pattern1",cp);
p2=struct();
if isfield(originalIE,'pattern2')
    p2=localPattern(originalIE.pattern2,"pattern2",cp);
end
effective=struct('ReferenceSubcarrierSpacingKHz',ref,'Pattern1',p1,'Pattern2',p2);
state=sixgr.phy.frame.SlotFormatResolver.resolve( ...
    'ReferenceSubcarrierSpacingKHz',ref,'ActiveSubcarrierSpacingKHz',double(activeSCSKHz), ...
    'CyclicPrefix',cp,'Pattern1',p1,'Pattern2',p2);
out.Present=true;
out.EffectiveConfig=effective;
out.SlotFormatState=state;
end

function effective=localPattern(original,label,cp)
counts=["nrofDownlinkSlots","nrofDownlinkSymbols","nrofUplinkSlots","nrofUplinkSymbols"];
localFields(original,["dl_UL_TransmissionPeriodicity",counts], ...
    "dl_UL_TransmissionPeriodicity_v1530",label);
tokens=["ms0p5","ms0p625","ms1","ms1p25","ms2","ms2p5","ms5","ms10"];
values=[0.5 0.625 1 1.25 2 2.5 5 10];
period=values(tokens==localToken(original.dl_UL_TransmissionPeriodicity,tokens,label+".dl_UL_TransmissionPeriodicity"));
if isfield(original,'dl_UL_TransmissionPeriodicity_v1530')
    extension=localToken(original.dl_UL_TransmissionPeriodicity_v1530,["ms3","ms4"], ...
        label+".dl_UL_TransmissionPeriodicity_v1530");
    if extension=="ms3", period=3; else, period=4; end
end
limits=[320 13 320 13];
% The wire range remains 0..13; an extended-CP runtime slot has 12
% symbols, so 12/13 partial symbols cannot be applied as partial slots.
if cp=="extended", limits([2 4])=11; end
canonical=["NumDownlinkSlots","NumDownlinkSymbols","NumUplinkSlots","NumUplinkSymbols"];
effective=struct('PeriodicityMilliseconds',period);
for k=1:numel(counts)
    value=original.(counts(k));
    assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && ...
        value>=0 && value<=limits(k) && value==fix(value), ...
        'sixgr:rrc:asn1:InvalidTDDPatternCount', ...
        '%s.%s must be an original numeric integer in [0,%d].',label,counts(k),limits(k));
    effective.(canonical(k))=double(value);
end
end

function token=localToken(raw,allowed,label)
assert((ischar(raw) && isrow(raw) && ~isempty(raw)) || ...
    (isstring(raw) && isscalar(raw) && ~ismissing(raw)), ...
    'sixgr:rrc:asn1:InvalidTDDEnum','%s must be an original scalar enum token.',label);
token=string(raw);
assert(any(token==allowed),'sixgr:rrc:asn1:InvalidTDDEnum', ...
    '%s has an unsupported or malformed enum token.',label);
end

function localFields(value,required,optional,label)
assert(isstruct(value) && isscalar(value) && all(isfield(value,required)), ...
    'sixgr:rrc:asn1:InvalidTDDCommonIE','%s requires its original mandatory fields.',label);
assert(all(ismember(string(fieldnames(value)),[required optional])), ...
    'sixgr:rrc:asn1:UnsupportedTDDCommonField', ...
    '%s contains an unsupported field; do not silently discard extensions or aliases.',label);
end
