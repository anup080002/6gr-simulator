function [sinr_dB,source,role,status]=selectReceiverDataSINR(row)
%SELECTRECEIVERDATASINR Select actual post-equalization data evidence.
% Reference-pilot SINR is a different measurement plane, not a cap on data
% SINR. Preserve provenance so the CQI resolver can enforce its own guards.
% This selector does not calibrate CQI, estimate SINR, or average layers.
assert((isstruct(row) && isscalar(row)) || (istable(row) && height(row)==1), ...
    'sixgr:link:ScalarReceiverRowRequired','Supply exactly one receiver evidence row.');
sinr_dB=NaN; source=""; role=""; status="";
% Canonical post-equalization evidence has priority over legacy aliases.
fields=[
    "PostEqSINR_dB", "PostEqSINRSource", "PostEqSINRValueRole", "PostEqSINRValueStatus"
    "MeasuredTrialSINR_dB", "MeasuredTrialSINRSource", "MeasuredTrialSINRValueRole", "MeasuredTrialSINRValueStatus"
    "MeasuredSINR_dB", "MeasuredTrialSINRSource", "MeasuredTrialSINRValueRole", "MeasuredTrialSINRValueStatus"];
blocked=["proxy","fallback","configured","sweep","oracle","true_channel","true-channel", ...
    "diagnostic","not_scheduling","not_for_scheduling","unavailable","failed","rejected", ...
    "receiver_hest","reference_signal_measurement","pilot_sinr","reference_signal_quality", ...
    "not_post_equalization","not_applicable","estimated", ...
    "conservative_min","predicted","prediction"];
for k=1:size(fields,1)
    value=localField(row,fields(k,1),NaN);
    if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value))
        continue;
    end
    candidateSource=localText(localField(row,fields(k,2),""));
    candidateRole=localText(localField(row,fields(k,3),""));
    candidateStatus=localText(localField(row,fields(k,4),""));
    if any(ismissing([candidateSource candidateRole candidateStatus])) || ...
            any(strlength(strtrim([candidateSource candidateRole candidateStatus]))==0) || ...
            any(lower(strtrim([candidateSource candidateRole candidateStatus]))=="nan")
        continue;
    end
    provenance=lower(strjoin([candidateSource candidateRole]," "));
    token=lower(strjoin([candidateSource candidateRole candidateStatus]," "));
    statusToken=lower(strtrim(candidateStatus));
    validStatus=any(statusToken==["ok","pass","measured"]) || startsWith(statusToken,"ok_");
    if ~validStatus || ~contains(provenance,"post_equalization") || any(contains(token,blocked))
        continue;
    end
    sinr_dB=double(value);
    source=candidateSource; role=candidateRole; status=candidateStatus;
    return;
end
end

function value=localField(row,name,defaultValue)
value=defaultValue;
if (isstruct(row) && isfield(row,name)) || ...
        (istable(row) && ismember(name,string(row.Properties.VariableNames)))
    value=row.(name);
    if iscell(value) && isscalar(value), value=value{1}; end
end
end

function value=localText(raw)
value="";
if (isstring(raw) && isscalar(raw)) || (ischar(raw) && isrow(raw))
    value=string(raw);
end
end
