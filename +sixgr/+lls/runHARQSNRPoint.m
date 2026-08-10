function [summaryRow,trialTable,diagnostic] = runHARQSNRPoint(llsCfg,configHash,snrIndex)
%RUNHARQSNRPOINT Execute a packet-level waveform HARQ campaign.
% Each attempt traverses the actual Tx/channel/Rx chain. Retransmissions
% reuse the original transport block, select a YAML-owned RV, and feed the
% prior position-aware mother-code soft buffer to the production decoder.

snrDb = double(llsCfg.simulation.snrDb(snrIndex));
phyCfg = sixgr.lls.buildPHYConfig(llsCfg,snrDb);
minPackets = double(llsCfg.simulation.minTransportBlocks);
minErrors = double(llsCfg.simulation.minBlockErrors);
maxPackets = double(llsCfg.simulation.maxTransportBlocks);
rvSequence = double(llsCfg.harq.rvSequence(:).');
maxTransmissions = double(llsCfg.harq.maxTransmissions);
stoppingMetric = lower(string(llsCfg.harq.stoppingMetric));

rows = cell(maxPackets*maxTransmissions,1);
rowCount = 0;
packetIndex = 0;
firstErrors = 0;
residualErrors = 0;
successfulBits = 0;
totalBits = 0;
diagnostic = struct();
pointClock = tic;
while packetIndex < maxPackets && ...
        ~(packetIndex >= minPackets && localStoppingErrors( ...
        stoppingMetric,firstErrors,residualErrors) >= minErrors)
    packetIndex = packetIndex + 1;
    transportBlock = [];
    priorSoftBuffer = [];
    priorLayout = struct();
    packetRows = zeros(maxTransmissions,1);
    firstCRCError = false;
    finalCRCError = true;
    packetTBS = NaN;
    for attemptIndex = 1:maxTransmissions
        rowCount = rowCount + 1;
        packetRows(attemptIndex) = rowCount;
        [row,attemptDiagnostic] = sixgr.lls.runTransportBlock( ...
            llsCfg,phyCfg,configHash,snrIndex,rowCount, ...
            "PacketIndex",packetIndex,"AttemptIndex",attemptIndex, ...
            "TransportBlockBits",transportBlock, ...
            "RV",rvSequence(attemptIndex), ...
            "HARQSoftBuffer",priorSoftBuffer, ...
            "HARQSoftBufferLayout",priorLayout);
        rows{rowCount} = row;
        if rowCount == 1
            diagnostic = attemptDiagnostic;
        end
        if attemptIndex == 1
            firstCRCError = logical(row.CRCError);
            packetTBS = double(row.TransportBlockSizeBits);
            transportBlock = attemptDiagnostic.Tx.TransportBlock;
        end
        finalCRCError = logical(row.CRCError);
        if ~finalCRCError
            packetRows = packetRows(1:attemptIndex);
            break;
        end
        priorSoftBuffer = sixgr.util.structGet( ...
            attemptDiagnostic.Rx,"HARQSoftBuffer",struct());
        priorLayout = localCurrentLayout(attemptDiagnostic);
    end
    firstErrors = firstErrors + double(firstCRCError);
    residualErrors = residualErrors + double(finalCRCError);
    totalBits = totalBits + packetTBS;
    if ~finalCRCError
        successfulBits = successfulBits + packetTBS;
    end
    for index = packetRows(:).'
        rows{index}.FirstTransmissionCRCError = firstCRCError;
        rows{index}.FinalPacketCRCError = finalCRCError;
        rows{index}.PacketTransmissions = numel(packetRows);
    end
end

trialTable = struct2table(vertcat(rows{1:rowCount}));
numPackets = packetIndex;
numTransmissions = height(trialTable);
firstBLER = firstErrors/numPackets;
residualBLER = residualErrors/numPackets;
[firstLower,firstUpper] = sixgr.lls.stats.wilsonInterval( ...
    firstErrors,numPackets,double(llsCfg.simulation.confidenceLevel));
[residualLower,residualUpper] = sixgr.lls.stats.wilsonInterval( ...
    residualErrors,numPackets,double(llsCfg.simulation.confidenceLevel));
slotDurationSeconds = 1e-3/(double(llsCfg.carrier.subcarrierSpacingKHz)/15);
simulatedDurationSeconds = numTransmissions*slotDurationSeconds;
summaryRow = struct( ...
    "ScenarioId",string(llsCfg.scenario.id), ...
    "ConfigSHA256",configHash, ...
    "SNRIndex",double(snrIndex), ...
    "SNRdB",snrDb, ...
    "NumTB",double(numPackets), ...
    "NumBlockErrors",double(firstErrors), ...
    "BLER",double(firstBLER), ...
    "BLERDisplay",localBoundDisplay(firstErrors,firstBLER,firstUpper,llsCfg), ...
    "BLERLowerCI",double(firstLower), ...
    "BLERUpperCI",double(firstUpper), ...
    "ConfidenceLevel",double(llsCfg.simulation.confidenceLevel), ...
    "NumBits",double(totalBits), ...
    "NumBitErrors",double(sum(trialTable.BitErrors(trialTable.AttemptIndex == 1))), ...
    "BER",double(sum(trialTable.BitErrors(trialTable.AttemptIndex == 1))/totalBits), ...
    "SuccessfulInformationBits",double(successfulBits), ...
    "SimulatedDurationSeconds",double(simulatedDurationSeconds), ...
    "ThroughputBps",double(successfulBits/simulatedDurationSeconds), ...
    "MeanMeasuredSNRdB",mean(trialTable.MeasuredSNRdB), ...
    "MeasuredSNRStdDevdB",std(trialTable.MeasuredSNRdB), ...
    "StoppingReason",localStoppingReason(numPackets,firstErrors,residualErrors, ...
        minPackets,minErrors,maxPackets,stoppingMetric), ...
    "RuntimeSeconds",toc(pointClock), ...
    "ExecutionBackend","waveform_truth", ...
    "ApproximationMode","none", ...
    "StatisticalClass",string(llsCfg.simulation.statisticalClass), ...
    "StudyType","harq_throughput", ...
    "NumTransmissions",double(numTransmissions), ...
    "FirstTransmissionBLER",double(firstBLER), ...
    "FirstTransmissionBLERLowerCI",double(firstLower), ...
    "FirstTransmissionBLERUpperCI",double(firstUpper), ...
    "PostHARQResidualBLER",double(residualBLER), ...
    "PostHARQResidualBLERLowerCI",double(residualLower), ...
    "PostHARQResidualBLERUpperCI",double(residualUpper), ...
    "AverageTransmissions",double(numTransmissions/numPackets), ...
    "MaxTransmissions",double(maxTransmissions), ...
    "RVSequence",string(mat2str(rvSequence)));
end

function value = localStoppingErrors(metric,firstErrors,residualErrors)
if metric == "post_harq_residual_bler"
    value = residualErrors;
else
    value = firstErrors;
end
end

function reason = localStoppingReason(n,firstErrors,residualErrors,minN,minE,maxN,metric)
if n >= minN && localStoppingErrors(metric,firstErrors,residualErrors) >= minE
    reason = "minimum_packets_and_" + metric + "_errors_reached";
elseif n >= maxN
    reason = "maximum_packets_reached";
else
    reason = "invalid_unexpected_termination";
end
end

function text = localBoundDisplay(errors,bler,upper,cfg)
if errors == 0
    text = "< " + compose("%.6g",upper) + " (" + ...
        compose("%.3g",100*double(cfg.simulation.confidenceLevel)) + ...
        "% Wilson upper bound)";
else
    text = compose("%.6g",bler);
end
end

function layout = localCurrentLayout(diagnostic)
if isfield(diagnostic.Tx,"PUSCH") && isfield(diagnostic.Tx,"CodingLayout")
    layout = diagnostic.Tx.CodingLayout;
elseif isfield(diagnostic.Tx,"CodingLayouts")
    layout = diagnostic.Tx.CodingLayouts;
elseif isfield(diagnostic.Tx,"CodingLayout")
    layout = diagnostic.Tx.CodingLayout;
else
    layout = struct();
end
end
