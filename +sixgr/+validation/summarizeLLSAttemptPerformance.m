function out = summarizeLLSAttemptPerformance(trials)
%SUMMARIZELLSATTEMPTPERFORMANCE Statistics of retained PHY attempts only.
% These are not run-time, unique-TB or application-packet delivery rates.
% Unknown outcomes are not failures, and offered traffic is not goodput.
arguments
    trials table
end
out = struct('ExecutedTrialCount',height(trials), ...
    'RawBLER',NaN,'CRCTrialCount',0,'FailedCRCTrialCount',0, ...
    'BLERPopulation',"observed_CRC_attempts_including_retransmissions", ...
    'InitialBLER',NaN,'InitialCRCTrialCount',0,'InitialFailedCRCTrialCount',0, ...
    'RawBER',NaN,'ComparedBits',0,'ComparedBitErrors',0,'BitComparisonTrialCount',0, ...
    'ThroughputMbps',NaN,'ThroughputTrialCount',0, ...
    'ThroughputAggregation',"arithmetic_mean_of_observed_trial_rates_not_run_time_rate", ...
    'GoodputMbps',NaN,'GoodputTrialCount',0, ...
    'GoodputAggregation',"arithmetic_mean_of_observed_trial_goodput_not_application_goodput", ...
    'GoodputStatus',"unavailable_no_observed_trial_goodput", ...
    'HARQRetxRate',NaN,'HARQRetxObservedTrialCount',0,'HARQRetxTrialCount',0, ...
    'HARQRetxPopulation',"observed_executed_trial_retransmission_flags", ...
    'PacketLossRate',NaN, ...
    'PacketLossRateStatus',"unavailable_final_packet_delivery_not_established_by_PHY_attempts", ...
    'LatencyMeanMs',NaN,'LatencyTrialCount',0, ...
    'LatencySource',"observed_Latency_ms_not_decoder_compute_time");

crc = localNumeric(trials,"CRCPass");
localBooleanEvidence(crc,"CRCPass");
known = isfinite(crc);
out.CRCTrialCount = nnz(known);
out.FailedCRCTrialCount = nnz(crc==0);
if out.CRCTrialCount>0
    out.RawBLER = out.FailedCRCTrialCount/out.CRCTrialCount;
end

retx = nan(height(trials),1);
for name = ["IsRetransmission","HARQIsRetransmission","RetxFlag"]
    candidate = localNumeric(trials,name);
    localBooleanEvidence(candidate,name);
    overlap = isfinite(retx) & isfinite(candidate);
    assert(all(retx(overlap)==candidate(overlap)), ...
        'sixgr:validation:ConflictingRetransmissionEvidence', ...
        'Executed trial retransmission aliases must agree.');
    fill = ~isfinite(retx) & isfinite(candidate);
    retx(fill) = candidate(fill);
end
out.HARQRetxObservedTrialCount = nnz(isfinite(retx));
out.HARQRetxTrialCount = nnz(retx==1);
if out.HARQRetxObservedTrialCount>0
    out.HARQRetxRate = out.HARQRetxTrialCount/out.HARQRetxObservedTrialCount;
end
initial = known & retx==0;
out.InitialCRCTrialCount = nnz(initial);
out.InitialFailedCRCTrialCount = nnz(initial & crc==0);
if out.InitialCRCTrialCount>0
    out.InitialBLER = out.InitialFailedCRCTrialCount/out.InitialCRCTrialCount;
end

errors = localNumeric(trials,"BitErrors");
bits = localNumeric(trials,"BitsCompared");
localNonnegativeCount(errors,"BitErrors");
localNonnegativeCount(bits,"BitsCompared");
paired = isfinite(errors) & isfinite(bits);
assert(all(errors(paired)<=bits(paired)), ...
    'sixgr:validation:InvalidBitComparison','Bit errors cannot exceed compared bits.');
paired = paired & bits>0;
out.BitComparisonTrialCount = nnz(paired);
out.ComparedBits = sum(bits(paired));
out.ComparedBitErrors = sum(errors(paired));
if out.ComparedBits>0
    out.RawBER = out.ComparedBitErrors/out.ComparedBits;
end

[out.ThroughputMbps,out.ThroughputTrialCount] = localMeanObserved(trials,"Throughput_Mbps");
[out.GoodputMbps,out.GoodputTrialCount] = localMeanObserved(trials,"Goodput_Mbps");
if out.GoodputTrialCount>0
    out.GoodputStatus = "observed_trial_goodput_population";
    if out.GoodputTrialCount<height(trials)
        out.GoodputStatus = "partial_observed_trial_goodput_population";
    end
end
[out.LatencyMeanMs,out.LatencyTrialCount] = localMeanObserved(trials,"Latency_ms");
end

function values = localNumeric(T,name)
values = nan(height(T),1);
if ~ismember(name,string(T.Properties.VariableNames)), return; end
values = sixgr.truth.numericMeasurementColumn(T.(name),name);
assert(isnumeric(values) && isreal(values) && iscolumn(values) && numel(values)==height(T), ...
    'sixgr:validation:InvalidTrialEvidenceShape','Each trial needs one scalar %s value.',name);
values = double(values);
end

function localBooleanEvidence(values,name)
assert(all(isnan(values) | values==0 | values==1), ...
    'sixgr:validation:InvalidBooleanTrialEvidence', ...
    '%s must be observed 0/1 or explicitly unavailable.',name);
end

function localNonnegativeCount(values,name)
assert(all(isnan(values) | (isfinite(values) & values>=0 & values==fix(values))), ...
    'sixgr:validation:InvalidBitComparison','%s must be a nonnegative integer or unavailable.',name);
end

function [value,count] = localMeanObserved(T,name)
values = localNumeric(T,name);
assert(all(isnan(values) | (isfinite(values) & values>=0)), ...
    'sixgr:validation:InvalidTrialRateOrLatency','%s must be nonnegative, finite or unavailable.',name);
known = isfinite(values);
count = nnz(known);
value = NaN;
if count>0, value = mean(values(known)); end
end
