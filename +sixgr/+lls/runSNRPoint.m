function [summaryRow, trialTable, diagnostic] = runSNRPoint(llsCfg, configHash, snrIndex)
%RUNSNRPOINT Run adaptive Monte-Carlo trials at one configured SNR.

snrDb = double(llsCfg.simulation.snrDb(snrIndex));
phyCfg = sixgr.lls.buildPHYConfig(llsCfg, snrDb);
maxTB = double(llsCfg.simulation.maxTransportBlocks);
rows = cell(maxTB, 1);
errors = 0;
diagnostic = struct();
pointClock = tic;
trialIndex = 0;
parallelEnabled = logical(llsCfg.execution.parallelEnabled);
batchSize = double(llsCfg.execution.batchTransportBlocks);
if parallelEnabled
    localEnsurePool(double(llsCfg.execution.maximumWorkers));
end
decision = sixgr.lls.stats.evaluateSamplingPlan(llsCfg, errors, trialIndex);
while trialIndex < maxTB && ~decision.Stop
    batchStart = trialIndex + 1;
    if parallelEnabled
        requested = min(batchSize,maxTB-trialIndex);
    else
        requested = 1;
    end
    batchRows = cell(requested,1);
    batchDiagnostics = cell(requested,1);
    if parallelEnabled
        parfor localIndex = 1:requested
            globalIndex = batchStart + localIndex - 1;
            [batchRows{localIndex},batchDiagnostics{localIndex}] = ...
                sixgr.lls.runTransportBlock(llsCfg,phyCfg,configHash, ...
                snrIndex,globalIndex,"CaptureDiagnostic",globalIndex == 1);
        end
    else
        [batchRows{1},batchDiagnostics{1}] = sixgr.lls.runTransportBlock( ...
            llsCfg,phyCfg,configHash,snrIndex,batchStart, ...
            "CaptureDiagnostic",batchStart == 1);
    end
    priorErrors = errors;
    batchErrors = cellfun(@(r) double(r.CRCError),batchRows);
    keep = requested;
    for localIndex = 1:requested
        globalIndex = batchStart + localIndex - 1;
        cumulativeErrors = priorErrors + sum(batchErrors(1:localIndex));
        localDecision = sixgr.lls.stats.evaluateSamplingPlan( ...
            llsCfg, cumulativeErrors, globalIndex);
        if localDecision.Stop
            keep = localIndex;
            break;
        end
    end
    for localIndex = 1:keep
        globalIndex = batchStart + localIndex - 1;
        rows{globalIndex,1} = batchRows{localIndex};
    end
    if batchStart == 1
        diagnostic = batchDiagnostics{1};
    end
    trialIndex = batchStart + keep - 1;
    errors = priorErrors + sum(batchErrors(1:keep));
    decision = sixgr.lls.stats.evaluateSamplingPlan(llsCfg, errors, trialIndex);
end
trialTable = struct2table(vertcat(rows{1:trialIndex}));
numTB = height(trialTable);
numBits = sum(trialTable.TransportBlockSizeBits);
bitErrors = sum(trialTable.BitErrors);
bler = errors / numTB;
ber = bitErrors / numBits;
[lowerCI, upperCI] = sixgr.lls.stats.wilsonInterval(errors, numTB, ...
    double(llsCfg.simulation.confidenceLevel));
slotDurationSeconds = 1e-3 / (double(llsCfg.carrier.subcarrierSpacingKHz)/15);
successfulBits = sum(trialTable.TransportBlockSizeBits(~trialTable.CRCError));
simulatedDurationSeconds = numTB * slotDurationSeconds;
throughputBps = successfulBits / simulatedDurationSeconds;
if errors == 0
    blerDisplay = "< " + compose("%.6g", upperCI) + " (" + ...
        compose("%.3g", 100*double(llsCfg.simulation.confidenceLevel)) + ...
        "% Wilson upper bound)";
else
    blerDisplay = compose("%.6g", bler);
end

summaryRow = struct( ...
    "ScenarioId", string(llsCfg.scenario.id), ...
    "ConfigSHA256", configHash, ...
    "SNRIndex", double(snrIndex), ...
    "SNRdB", snrDb, ...
    "NumTB", double(numTB), ...
    "NumBlockErrors", double(errors), ...
    "BLER", double(bler), ...
    "BLERDisplay", string(blerDisplay), ...
    "BLERLowerCI", double(lowerCI), ...
    "BLERUpperCI", double(upperCI), ...
    "ConfidenceLevel", double(llsCfg.simulation.confidenceLevel), ...
    "NumBits", double(numBits), ...
    "NumBitErrors", double(bitErrors), ...
    "BER", double(ber), ...
    "SuccessfulInformationBits", double(successfulBits), ...
    "SimulatedDurationSeconds", double(simulatedDurationSeconds), ...
    "ThroughputBps", double(throughputBps), ...
    "MeanMeasuredSNRdB", mean(trialTable.MeasuredSNRdB), ...
    "MeasuredSNRStdDevdB", std(trialTable.MeasuredSNRdB), ...
    "StoppingReason", string(decision.StoppingReason), ...
    "SamplingPlan", string(decision.SamplingPlan), ...
    "ConfidenceIntervalMethod", string(decision.ConfidenceIntervalMethod), ...
    "StatisticalPointQualified", logical(decision.StatisticallyQualified), ...
    "RuntimeSeconds", toc(pointClock), ...
    "ExecutionBackend", "waveform_truth", ...
    "ApproximationMode", "none");
summaryRow.StatisticalClass = string(llsCfg.simulation.statisticalClass);
end

function pool = localEnsurePool(maximumWorkers)
pool = gcp("nocreate");
if isempty(pool)
    pool = parpool("Processes",maximumWorkers);
elseif pool.NumWorkers > maximumWorkers
    % A pool is process-global MATLAB state, not campaign authority.  A
    % previous run may legitimately have created a larger pool; retaining
    % it would violate this run's YAML worker ceiling and aborting would make
    % results depend on ambient session history.  Recreate an exact,
    % process-based pool owned by the current execution policy.
    delete(pool);
    pool = parpool("Processes",maximumWorkers);
end
end
