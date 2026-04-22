function metrics = PDSCHMetrics(trialT)
%PDSCHMetrics Aggregate scenario-level truthful PDSCH KPIs.

metrics = struct();
metrics.SummaryBySNR = localAggregate(trialT, "snr_db");
metrics.SummaryByBand = localAggregate(trialT, "band");
metrics.SummaryByFDRAType = localAggregate(trialT, "fdra_type");
metrics.SummaryByTDRAMode = localAggregate(trialT, "tdra_mode");
metrics.SummaryByDMRSSetting = localAggregate(trialT, "dmrs_config_summary");
metrics.SummaryByPTRSSetting = localAggregate(trialT, "ptrs_enabled");
metrics.SummaryByRank = localAggregate(trialT, "rank");
metrics.SummaryByRepetition = localAggregate(trialT, "repetition_mode");
metrics.ComplexitySummary = localComplexitySummary(trialT);
end

function out = localAggregate(T, groupVar)
if isempty(T) || height(T) == 0 || ~ismember(groupVar, T.Properties.VariableNames)
    out = table();
    return;
end
groupVals = T.(groupVar);
if ischar(groupVals)
    groupVals = cellstr(groupVals);
elseif iscell(groupVals)
    groupVals = cellfun(@char, groupVals, 'UniformOutput', false);
end
[G, keys] = findgroups(groupVals);
meanBLER = splitapply(@localMean, double(T.bler_flag), G);
meanDet = splitapply(@localMean, double(T.crc_pass), G);
meanThroughput = splitapply(@localMean, double(T.throughput_bps), G);
meanSE = splitapply(@localMean, double(T.spectral_efficiency), G);
meanOps = splitapply(@localMean, double(T.complexity_proxy_ops), G);
if iscell(keys)
    out = table(string(keys), 'VariableNames', {char(groupVar)});
else
    out = table(keys, 'VariableNames', {char(groupVar)});
end
out.mean_BLER = meanBLER;
out.mean_DetectionProbability = meanDet;
out.mean_Throughput_bps = meanThroughput;
out.mean_SE = meanSE;
out.mean_ComplexityOps = meanOps;
end

function value = localMean(x)
value = mean(double(x), "omitnan");
end

function out = localComplexitySummary(T)
if isempty(T) || height(T) == 0
    out = table();
    return;
end
out = table(mean(double(T.complexity_proxy_ops), "omitnan"), ...
    mean(double(T.tb_size_bits), "omitnan"), ...
    mean(double(T.num_rb .* T.num_symbols), "omitnan"), ...
    "VariableNames", {"AverageComplexityOps","AverageTBSize_bits","AverageScheduledRBxSymbols"});
end
