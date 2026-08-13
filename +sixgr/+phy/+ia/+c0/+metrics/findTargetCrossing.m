function result = findTargetCrossing(points,metric,target)
%FINDTARGETCROSSING Use only adjacent, statistically qualified MC points.
snr = double(points.SNRDB);
value = double(points.(char(metric)));
[errors,trials,qualified,ciLow,ciHigh] = localQualification(points,string(metric));
valid = isfinite(snr)&isfinite(value)&logical(qualified);
snr = snr(valid); value = value(valid);
errors = errors(valid); trials = trials(valid);
ciLow = ciLow(valid); ciHigh = ciHigh(valid);
[snr,order] = sort(snr); value = value(order);
errors = errors(order); trials = trials(order);
ciLow = ciLow(order); ciHigh = ciHigh(order);
result = struct("Metric",string(metric),"Target",double(target), ...
    "Bracketed",false,"LowerSNRDB",NaN,"UpperSNRDB",NaN, ...
    "LowerValue",NaN,"UpperValue",NaN, ...
    "LowerErrors",NaN,"LowerTrials",NaN, ...
    "UpperErrors",NaN,"UpperTrials",NaN, ...
    "CrossingSNRDB",NaN,"CrossingCILowDB",NaN, ...
    "CrossingCIHighDB",NaN,"Interpolation","not_available", ...
    "Status","BLOCKED_UNBRACKETED_OR_INSUFFICIENT_STATISTICS");
for k = 1:numel(snr)-1
    if (value(k)-target)*(value(k+1)-target) > 0
        continue;
    end
    if value(k)<=0 || value(k+1)<=0
        result.Status = "BLOCKED_ZERO_RAW_ENDPOINT_REQUIRES_CONFIDENCE_ENVELOPE";
        continue;
    end
    result.Bracketed = true;
    result.LowerSNRDB = snr(k); result.UpperSNRDB = snr(k+1);
    result.LowerValue = value(k); result.UpperValue = value(k+1);
    result.LowerErrors = errors(k); result.LowerTrials = trials(k);
    result.UpperErrors = errors(k+1); result.UpperTrials = trials(k+1);
    x = [log10(value(k)) log10(value(k+1))];
    result.CrossingSNRDB = interp1( ...
        x,[snr(k) snr(k+1)],log10(target),"linear");
    envelope=[localEnvelope(snr(k:k+1),ciLow(k:k+1),target) ...
        localEnvelope(snr(k:k+1),ciHigh(k:k+1),target)];
    envelope=envelope(isfinite(envelope));
    if numel(envelope)==2
        result.CrossingCILowDB=min(envelope);
        result.CrossingCIHighDB=max(envelope);
    end
    result.Interpolation = "linear_in_log10_probability";
    result.Status = "QUALIFIED_SIMULATED_BRACKET";
    return;
end
end

function [errors,trials,qualified,ciLow,ciHigh] = localQualification(points,metric)
n=height(points); errors=nan(n,1); trials=nan(n,1); qualified=false(n,1);
ciLow=nan(n,1); ciHigh=nan(n,1);
if metric=="JointSSMDR"
    names=["JointSSErrors" "Trials" "JointSSStoppingQualified" ...
        "JointSSCILow" "JointSSCIHigh"];
elseif any(metric==["PBCHBLER" "PBCHComponentBLER"])
    names=["PBCHComponentErrors" "PBCHComponentTrials" ...
        "PBCHComponentStoppingQualified" "PBCHComponentCILow" ...
        "PBCHComponentCIHigh"];
else
    return;
end
if all(ismember(names,string(points.Properties.VariableNames)))
    errors=double(points.(names(1)));
    trials=double(points.(names(2)));
    qualified=logical(points.(names(3)));
    ciLow=double(points.(names(4)));
    ciHigh=double(points.(names(5)));
end
end

function crossing=localEnvelope(snr,probability,target)
crossing=NaN;
if all(isfinite(probability))&&all(probability>0)&& ...
        (probability(1)-target)*(probability(2)-target)<=0
    crossing=interp1(log10(probability),snr,log10(target),"linear");
end
end
