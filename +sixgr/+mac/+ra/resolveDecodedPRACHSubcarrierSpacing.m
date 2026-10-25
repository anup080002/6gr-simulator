function [scs,source]=resolveDecodedPRACHSubcarrierSpacing(rach)
%RESOLVEDECODEDPRACHSUBCARRIERSPACING Received semantic PRACH numerology.
% TS38.331 V18.8.0 RACH-ConfigCommon Cond L139 requires msg1 SCS for
% short L139. Long L839 uses the index-derived format and TS38.211
% Table6.3.3.1-1: formats0/1/2=1.25kHz, format3=5kHz.
% preambleFormat is the retained decoder-derived table result, NOT a wire
% IE. This boundary does not independently authenticate that derivation.
% A semantic long-SCS value may have been materialized by the decoder; its
% presence here must not be reported as wire presence of msg1-SCS.
assert(isstruct(rach) && isscalar(rach) && isfield(rach,'preambleFormat'), ...
    'sixgr:mac:ra:MissingDecodedPRACHFormatAnchor','Require the original derived PRACH format.');
f=rach.preambleFormat;
assert((isstring(f)&&isscalar(f)&&~ismissing(f)) || (ischar(f)&&isrow(f)), ...
    'sixgr:mac:ra:InvalidDecodedPRACHSpacing','PRACH format must be original scalar text.');
f=string(f); long=any(f==["0","1","2","3"]);
assert(long || any(f==["A1","A2","A3","B1","B2","B3","B4","C0","C2","A1/B1","A2/B2","A3/B3"]), ...
    'sixgr:mac:ra:InvalidDecodedPRACHSpacing','Unsupported original PRACH format.');
present=isfield(rach,'msg1SubcarrierSpacing_kHz');
if present
    scs=rach.msg1SubcarrierSpacing_kHz;
    assert(isnumeric(scs) && ~islogical(scs) && isreal(scs) && isscalar(scs) && isfinite(scs), ...
        'sixgr:mac:ra:InvalidDecodedPRACHSpacing','PRACH SCS must be an original finite numeric scalar.');
    scs=double(scs);
end
if long
    expected=1.25; if f=="3", expected=5; end
    assert(~present || scs==expected,'sixgr:mac:ra:InvalidDecodedPRACHSpacing', ...
        'Long PRACH semantic SCS disagrees with its index-derived format.');
    scs=expected;
    source="decoded_index_derived_long_format_spacing";
else
    assert(present,'sixgr:mac:ra:MissingDecodedPRACHSpacing', ...
        'Short PRACH requires msg1-SubcarrierSpacing; the UL BWP SCS is not a substitute.');
    assert(any(scs==[15 30 60 120]),'sixgr:mac:ra:InvalidDecodedPRACHSpacing', ...
        'Unsupported short PRACH SCS; carrier/range legality is validated by the native resolver.');
    source="decoded_short_msg1_subcarrier_spacing";
end
end
