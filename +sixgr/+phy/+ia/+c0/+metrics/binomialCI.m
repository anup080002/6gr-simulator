function result = binomialCI(errors,trials,confidence)
%BINOMIALCI Binomial interval for the C0 initial-access campaign.
%BINOMIALCI Exact count plus Wilson 95%-style confidence interval.
if trials == 0
    result = struct("Errors",0,"Trials",0,"Estimate",NaN, ...
        "CILow",NaN,"CIHigh",NaN,"ConfidenceLevel",double(confidence));
    return;
end
[~,~,low,high] = sixgr.stats.wilsonBinomialCI(errors,trials,confidence);
result = struct("Errors",double(errors),"Trials",double(trials), ...
    "Estimate",double(errors/trials),"CILow",double(low), ...
    "CIHigh",double(high),"ConfidenceLevel",double(confidence));
end
