function [text,evidence]=formatLiveSINRStatistic(trials,varName,label)
% Summarize only finite, accepted-status receiver observations in live logs.
% This formatter does not validate an RF implementation or modify raw rows.
arguments
    trials
    varName (1,1) string
    label (1,1) string
end
text=string(sprintf('%s pending',label));
evidence=struct('Rows',0,'AcceptedCount',0,'ExcludedCount',0, ...
    'NoiseFloorBoundCount',0,'MissingStatusCount',0,'Median_dB',NaN);
if ~istable(trials) || isempty(trials) || ~ismember(varName,string(trials.Properties.VariableNames))
    return;
end
assert(endsWith(varName,'_dB'),'sixgr:truth:InvalidSINRProgressMetric', ...
    'A SINR metric must identify its matching *_dB and *ValueStatus columns.');
n=height(trials); evidence.Rows=n;
values=trials.(varName);
assert(isnumeric(values) && isreal(values) && isequal(size(values),[n 1]), ...
    'sixgr:truth:InvalidSINRProgressMetric','SINR progress requires one numeric value per row.');
statusName=regexprep(varName,'_dB$','ValueStatus');
statuses=strings(n,1);
if ismember(statusName,string(trials.Properties.VariableNames))
    statuses=strtrim(string(trials.(statusName)));
    assert(isequal(size(statuses),[n 1]),'sixgr:truth:InvalidSINRProgressMetric', ...
        'SINR status must identify each receiver observation.');
end
missingStatus=ismissing(statuses) | strlength(statuses)==0;
statuses(missingStatus)="";
accepted=isfinite(values) & sixgr.util.isAcceptableSINRStatus(statuses);
% Honor explicit rejection/availability flags when the receiver emitted them.
% Missing optional flags do not invent success; accepted status is mandatory.
flags=strings(0,1);
switch varName
    case "ReceiverHestSINR_dB", flags="ReceiverHestSINRApplicable";
    case "PostEqSINR_dB", flags=["PostEqSINRAvailable","PostEqSINRReceiverDerived"];
    case "MeasuredTrialSINR_dB", flags="MeasurementUsable";
end
for flag=reshape(flags,1,[])
    if ~ismember(flag,string(trials.Properties.VariableNames)), continue; end
    value=trials.(flag);
    assert((islogical(value) || isnumeric(value)) && isreal(value) && isequal(size(value),[n 1]), ...
        'sixgr:truth:InvalidSINRProgressFlag','Receiver availability must be one numeric/logical flag per row.');
    accepted=accepted & isfinite(value) & value==1;
end
evidence.AcceptedCount=nnz(accepted);
evidence.ExcludedCount=n-evidence.AcceptedCount;
evidence.NoiseFloorBoundCount=nnz(isfinite(values) & upper(statuses)=="LOWER_BOUND_NOISE_FLOOR");
evidence.MissingStatusCount=nnz(missingStatus);
if any(accepted)
    evidence.Median_dB=median(double(values(accepted)));
    text=string(sprintf('median accepted %s %.3f dB',label,evidence.Median_dB));
else
    text=label+" unavailable";
end
text=text+string(sprintf(' (accepted=%d, excluded=%d, noise-floor bounds=%d, missing status=%d)', ...
    evidence.AcceptedCount,evidence.ExcludedCount,evidence.NoiseFloorBoundCount,evidence.MissingStatusCount));
end
