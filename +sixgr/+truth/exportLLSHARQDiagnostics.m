function artifacts = exportLLSHARQDiagnostics(cfg, airInterfaceRunFolder, opt)
%EXPORTLLSHARQDIAGNOSTICS Emit measured HARQ runtime diagnostics for LLS.

artifacts = struct("PacketCSV", "", "SummaryCSV", "", "TimelineCSV", "", ...
    "PacketTable", table(), "SummaryTable", table(), "TimelineTable", table(), ...
    "PreviewOnly", false);

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.HARQCSVDir);

if ~logical(sixgr.util.structGet(cfg, "phy.harq.enable", false))
    return;
end

snrAnchor = double(sixgr.util.structGet(opt, "LinkSNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 30)));
snrGrid = localReduceSweepGrid(double(sixgr.util.structGet(opt, "LinkSNRGrid_dB", snrAnchor)), ...
    min(5, max(3, round(double(sixgr.util.structGet(opt, "LinkSweepMaxPoints", 4))))), snrAnchor);
numPackets = localResolveProbePacketCount(cfg, opt);
directions = localResolveProbeDirections(cfg, opt);
previewOnly = logical(sixgr.util.structGet(opt, "HARQLivePreview", false));
if previewOnly
    snrGrid = localReduceSweepGrid(snrGrid, 2, snrAnchor);
    if ~localHasProbePacketOverride(cfg, opt)
        numPackets = min(numPackets, 2);
    end
    artifacts.PreviewOnly = true;
end

packetParts = cell(0, 1);
summaryParts = cell(0, 1);
for direction = directions(:).'
    for i = 1:numel(snrGrid)
        [packetT, summaryT] = localRunDirectionProbe(cfg, direction, snrGrid(i), numPackets);
        if istable(packetT) && ~isempty(packetT)
            packetParts{end+1, 1} = packetT; %#ok<AGROW>
        end
        if istable(summaryT) && ~isempty(summaryT)
            summaryParts{end+1, 1} = summaryT; %#ok<AGROW>
        end
    end
end

if isempty(packetParts)
    return;
end

packetT = vertcat(packetParts{:});
summaryT = localConcatProbeTables(summaryParts);
invalidDirections = localInvalidProbeDirections(packetT, summaryT, airInterfaceRunFolder);
if ~isempty(invalidDirections)
    packetT = packetT(~ismember(string(packetT.Direction), invalidDirections), :);
    if ~isempty(summaryT)
        keepSummary = true(height(summaryT), 1);
        for i = 1:numel(invalidDirections)
            keepSummary = keepSummary & ~startsWith(string(summaryT.Entity), invalidDirections(i) + "@");
        end
        summaryT = summaryT(keepSummary, :);
    end
end
if isempty(packetT)
    packetT = localEmptyPacketTable();
end
if isempty(summaryT)
    summaryT = localEmptyProbeMetricTable();
end
timelineT = packetT;

packetPath = fullfile(layout.HARQCSVDir, "probe_harq_packets.csv");
timelinePath = fullfile(layout.HARQCSVDir, "harq_process_timeline.csv");
summaryPath = fullfile(layout.HARQCSVDir, "probe_harq_summary.csv");

sixgr.util.csvWriteTable(packetPath, packetT);
sixgr.util.csvWriteTable(timelinePath, timelineT);
sixgr.util.csvWriteTable(summaryPath, summaryT);

artifacts.PacketCSV = packetPath;
artifacts.TimelineCSV = timelinePath;
artifacts.SummaryCSV = summaryPath;
artifacts.PacketTable = packetT;
artifacts.TimelineTable = timelineT;
artifacts.SummaryTable = summaryT;
artifacts.PreviewOnly = logical(previewOnly);
end

function n = localResolveProbePacketCount(cfg, opt)
raw = sixgr.util.structGet(opt, "HARQProbePackets", []);
if isempty(raw)
    raw = sixgr.util.structGet(opt, "HARQProbePacketCount", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "phy.harq.probePackets", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "lls6g.harq.probe_packets", []);
end
if ~isempty(raw)
    rawNum = double(raw);
    rawNum = rawNum(:);
    if numel(rawNum) ~= 1 || ~(isfinite(rawNum) && rawNum >= 1)
        error("sixgr:truth:HARQProbePacketCountInvalid", ...
            "HARQ probe packet count must be a finite positive scalar.");
    end
    n = max(1, round(rawNum));
    return;
end
n = max(4, round(double(sixgr.util.structGet(opt, "LinkSweepFrames", ...
    max(4, ceil(double(sixgr.util.structGet(cfg, "run.numFrames", 8)) / 2))))));
end

function tf = localHasProbePacketOverride(cfg, opt)
tf = ~isempty(sixgr.util.structGet(opt, "HARQProbePackets", [])) || ...
    ~isempty(sixgr.util.structGet(opt, "HARQProbePacketCount", [])) || ...
    ~isempty(sixgr.util.structGet(cfg, "phy.harq.probePackets", [])) || ...
    ~isempty(sixgr.util.structGet(cfg, "lls6g.harq.probe_packets", []));
end

function directions = localResolveProbeDirections(cfg, opt)
raw = sixgr.util.structGet(opt, "HARQProbeDirections", []);
if isempty(raw)
    raw = sixgr.util.structGet(opt, "HARQProbeDirection", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "phy.harq.probeDirections", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "lls6g.harq.probe_directions", []);
end
if isempty(raw)
    linkDir = lower(strtrim(string(sixgr.util.structGet(cfg, "lls6g.simulation.link_direction", "both"))));
    switch linkDir
        case "dl"
            directions = "DL";
        case "ul"
            directions = "UL";
        otherwise
            directions = ["DL"; "UL"];
    end
    return;
end

tokens = upper(strtrim(string(raw)));
if isscalar(tokens)
    tokens = split(replace(tokens, [";", ","], " "), " ");
end
tokens = tokens(strlength(tokens) > 0);
tokens = unique(tokens(:), "stable");
if isempty(tokens) || any(~ismember(tokens, ["DL"; "UL"; "BOTH"]))
    error("sixgr:truth:HARQProbeDirectionInvalid", ...
        "HARQ probe directions must be DL, UL, or BOTH.");
end
if any(tokens == "BOTH")
    directions = ["DL"; "UL"];
else
    directions = tokens(:);
end
end

function [packetT, summaryT] = localRunDirectionProbe(cfg, direction, snr_dB, numPackets)
packetRows = repmat(localEmptyPacketRow(), 0, 1);
summaryT = localEmptyProbeMetricTable();

mode = localHARQProbeMode(cfg);
successStopCondition = localHARQSuccessStopCondition(mode);
slotDur_s = localSlotDuration(cfg);
feedbackSlots = max(1, round(double(sixgr.util.structGet(cfg, "phy.harq.feedbackTimingSlots", 4))));
seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1)) + 1000 * double(direction == "UL");
rnti = 1;
harq = sixgr.l2.mac.HARQEntity(cfg, "Direction", char(direction));
cfgDyn = cfg;
laState = [];
frameCounter = 1;
warmupCount = localWarmupFrameCount(cfg);

singleShotSuccess = false(numPackets, 1);
finalSuccess = false(numPackets, 1);
retxCount = NaN(numPackets, 1);
rttMs = NaN(numPackets, 1);
stopCondition = strings(numPackets, 1);

for warmIdx = 1:warmupCount
    [cfgDyn, laState] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, direction, frameCounter, "Phase", "before");
    cfgWarm = cfgDyn;
    cfgWarm.run.seed = seedBase + 5000 + warmIdx;
    [~, rxWarm, diagWarm] = localRunAttempt(cfgWarm, direction, snr_dB, [], 0, []);
    warmMetrics = localExtractLinkAdaptationMetrics(cfgWarm, rxWarm, diagWarm);
    [cfgDyn, laState] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, direction, frameCounter, "Phase", "after", "Metrics", warmMetrics);
    frameCounter = frameCounter + 1;
end

for pkt = 1:numPackets
    slotBase = (pkt - 1) * (feedbackSlots + 1);
    [cfgDyn, laState] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, direction, frameCounter, "Phase", "before");
    cfgPkt = cfgDyn;
    cfgPkt.run.seed = seedBase + pkt - 1;

    [tx, rx, diag] = localRunAttempt(cfgPkt, direction, snr_dB, [], 0, []);
    observeMetrics = localExtractLinkAdaptationMetrics(cfgPkt, rx, diag);
    txp = harq.allocate(rnti, slotBase, ceil(double(tx.TransportBlockSize) / 8), "NewData", true);
    txGrant = localHARQGrantFromExecutedTx(tx, direction, slotBase, txp.HARQ, struct());
    harq.onTx(rnti, txp.HARQ.HarqID, uint8(tx.TransportBlock(:)), txGrant, slotBase);

    packetRows(end+1, 1) = localMakePacketRow(direction, snr_dB, pkt, 1, slotBase, txp.HARQ, diag, feedbackSlots, slotDur_s, "pending", tx.TransportBlockSize, mode); %#ok<AGROW>
    harq.onFeedback(rnti, txp.HARQ.HarqID, diag.CombinedDecodeOK);

    singleShotSuccess(pkt) = diag.CurrentDecodeOK;
    finalSuccess(pkt) = diag.CombinedDecodeOK;
    retxCount(pkt) = 0;
    rttMs(pkt) = feedbackSlots * slotDur_s * 1e3;
    stopCondition(pkt) = successStopCondition;

    attempt = 1;
    while ~diag.CombinedDecodeOK
        retx = harq.peekRetx(rnti);
        if isempty(retx)
            stopCondition(pkt) = "max_retx_drop";
            packetRows(end).StopCondition = stopCondition(pkt);
            break;
        end
        attempt = attempt + 1;
        cfgPkt.run.seed = seedBase + pkt - 1 + 37 * attempt;
        [tx, rx, diag] = localRunAttempt(cfgPkt, direction, snr_dB, int8(retx.TB(:)), retx.HARQ.RV, diag.HARQSoftBuffer);
        txSlot = slotBase + attempt - 1;
        txGrant = localHARQGrantFromExecutedTx(tx, direction, txSlot, ...
            retx.HARQ, sixgr.util.structGet(retx, "TBContext", struct()));
        harq.onTx(rnti, retx.HARQ.HarqID, uint8(tx.TransportBlock(:)), txGrant, txSlot);
        packetRows(end+1, 1) = localMakePacketRow(direction, snr_dB, pkt, attempt, slotBase + attempt - 1, retx.HARQ, diag, feedbackSlots * attempt, slotDur_s, "pending", tx.TransportBlockSize, mode); %#ok<AGROW>
        harq.onFeedback(rnti, retx.HARQ.HarqID, diag.CombinedDecodeOK);
        finalSuccess(pkt) = diag.CombinedDecodeOK;
        retxCount(pkt) = attempt - 1;
        rttMs(pkt) = feedbackSlots * attempt * slotDur_s * 1e3;
        if diag.CombinedDecodeOK
            stopCondition(pkt) = successStopCondition;
            packetRows(end).RecoveryAfterRetx = logical(~singleShotSuccess(pkt));
        end
    end

    if stopCondition(pkt) == ""
        stopCondition(pkt) = successStopCondition;
    end
    packetRows(end).StopCondition = stopCondition(pkt);
    [cfgDyn, laState] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, direction, frameCounter, "Phase", "after", "Metrics", observeMetrics);
    frameCounter = frameCounter + 1;
end

packetT = struct2table(packetRows);
successStopMask = ismember(stopCondition, ["ack","crc_pass"]);
llrGainRows = double(packetT.LLRCombiningGain_dB);
llrGainRows = llrGainRows(isfinite(llrGainRows) & logical(packetT.HARQCombiningApplied));
meanLLRGain_dB = NaN;
if ~isempty(llrGainRows)
    meanLLRGain_dB = mean(llrGainRows, "omitnan");
end
llrGainObserved = isfinite(meanLLRGain_dB);
llrGainAvailability = localRetxClaimAvailability(mode, llrGainObserved);
llrGainText = localRetxClaimText(mode, llrGainObserved);
entity = direction + "@SNR=" + string(snr_dB) + "dB";
retxObserved = isfinite(retxCount) & retxCount > 0;
retxClaimAvailability = localRetxClaimAvailability(mode, retxObserved);
recoveryRate = NaN;
if any(retxObserved)
    recoveryRate = mean(finalSuccess & ~singleShotSuccess, "omitnan");
end
summaryT = [summaryT; ... %#ok<AGROW>
    localProbeMetricRow("rtt_distribution", entity, "mean_ms", "available", mean(rttMs, "omitnan"), "", "ms", mode, ...
        localHARQModeNote(mode, "Measured packet RTT from HARQ feedback timing and actual attempt count.", retxObserved)); ...
    localProbeMetricRow("rtt_distribution", entity, "p95_ms", "available", localPercentile(rttMs, 95), "", "ms", mode, ...
        localHARQModeNote(mode, "Measured packet RTT from HARQ feedback timing and actual attempt count.", retxObserved)); ...
    localProbeMetricRow("retransmission_count_distribution", entity, "mean_retx", "available", mean(retxCount, "omitnan"), "", "count", mode, ...
        localHARQModeNote(mode, "Average HARQ retransmissions per packet from real waveform decode outcomes.", retxObserved)); ...
    localProbeMetricRow("retransmission_count_distribution", entity, "retx_packet_rate", "available", mean(retxObserved, "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "Fraction of packets that required at least one HARQ retransmission.", retxObserved)); ...
    localProbeMetricRow("retransmission_count_distribution", entity, "retx_packets_observed", "available", sum(retxObserved), "", "count", mode, ...
        localHARQModeNote(mode, "Count of packets that required at least one HARQ retransmission.", retxObserved)); ...
    localProbeMetricRow("combining_gain", entity, "recovered_after_retx_rate", retxClaimAvailability, recoveryRate, ...
        localRetxClaimText(mode, retxObserved), "fraction", mode, ...
        localHARQRetxClaimNote(mode, "Fraction of packets only recovered after HARQ combining.", retxObserved)); ...
    localProbeMetricRow("combining_gain", entity, "mean_llr_gain_dB", llrGainAvailability, meanLLRGain_dB, ...
        llrGainText, "dB", mode, ...
        localHARQRetxClaimNote(mode, "Mean HARQ LLR combining gain from canonical position-aware soft buffers.", llrGainObserved)); ...
    localProbeMetricRow("ack_nack_dtx_distribution", entity, "first_attempt_ack_rate", "available", mean(singleShotSuccess, "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "First-attempt ACK rate before any HARQ retransmission opportunity.", retxObserved)); ...
    localProbeMetricRow("ack_nack_dtx_distribution", entity, "first_attempt_nack_rate", "available", mean(~singleShotSuccess, "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "First-attempt NACK rate before any HARQ retransmission opportunity.", retxObserved)); ...
    localProbeMetricRow("ack_nack_dtx_distribution", entity, "final_ack_rate", "available", mean(finalSuccess, "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "Final ACK rate after the HARQ process completes.", retxObserved)); ...
    localProbeMetricRow("ack_nack_dtx_distribution", entity, "final_nack_rate", "available", mean(~finalSuccess, "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "Final drop/NACK rate after the HARQ process completes.", retxObserved)); ...
    localProbeMetricRow("ack_nack_dtx_distribution", entity, "dtx_rate", "available", 0, "", "fraction", mode, ...
        localHARQModeNote(mode, "DTX is not modeled in the current LLS HARQ probe.", retxObserved)); ...
    localProbeMetricRow("feedback_overhead", entity, "total_bits", "available", height(packetT), "", "bits", mode, ...
        localHARQModeNote(mode, "One ACK/NACK feedback bit per HARQ attempt.", retxObserved)); ...
    localProbeMetricRow("stop_condition_distribution", entity, "ack_rate", "available", mean(successStopMask, "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "Packets that terminated after successful CRC/ACK.", retxObserved)); ...
    localProbeMetricRow("stop_condition_distribution", entity, "drop_rate", "available", mean(stopCondition == "max_retx_drop", "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "Packets that exhausted retransmissions.", retxObserved)); ...
    localProbeMetricRow("latency_percentile", entity, "p95_ms", "available", localPercentile(rttMs, 95), "", "ms", mode, ...
        localHARQModeNote(mode, "HARQ RTT percentile.", retxObserved)); ...
    localProbeMetricRow("reliability_percentile", entity, "success_rate", "available", mean(finalSuccess, "omitnan"), "", "fraction", mode, ...
        localHARQModeNote(mode, "Packet success rate after the HARQ process.", retxObserved)); ...
    localProbeMetricRow("control_miss_induced_harq_penalties", entity, "penalty_rate", "available", 0, "", "fraction", mode, ...
        localHARQModeNote(mode, "PDCCH-miss induced HARQ penalties are disabled in the current LLS HARQ probe.", retxObserved)); ...
    localProbeMetricRow("parity_cb_packet_level_coding_benefits", entity, "gain_fraction", "available", 0, "", "fraction", mode, ...
        localHARQModeNote(mode, "Parity-CB and packet-level coding enhancements are disabled in the current LLS HARQ probe.", retxObserved)); ...
    localProbeMetricRow("harq_gain_per_retransmission", entity, "recovered_after_retx_rate", retxClaimAvailability, recoveryRate, ...
        localRetxClaimText(mode, retxObserved), "fraction", mode, ...
        localHARQRetxClaimNote(mode, "Recovered packets attributable to HARQ retransmissions.", retxObserved))];
end

function grant = localHARQGrantFromExecutedTx(tx, direction, slot, harqState, tbContext)
% The executed PHY transmitter owns the immutable coding/TBS authority.
% Never rebuild a HARQ layout from nominal scenario fields in diagnostics.
layout = sixgr.util.structGet(tx, "CodingLayout", struct());
if ~(isstruct(layout) && ~isempty(fieldnames(layout)))
    layouts = sixgr.util.structGet(tx, "CodingLayouts", {});
    if iscell(layouts) && ~isempty(layouts) && isstruct(layouts{1})
        layout = layouts{1};
    end
end
if ~(isstruct(layout) && ~isempty(fieldnames(layout)))
    error("sixgr:truth:HARQDiagnosticMissingCodingLayout", ...
        "Executed %s HARQ probe did not expose its coding layout.", ...
        char(upper(string(direction))));
end

direction = upper(string(direction));
if direction == "DL"
    channelCfg = sixgr.util.structGet(tx, "PDSCH", struct());
else
    channelCfg = sixgr.util.structGet(tx, "PUSCH", struct());
end
grant = struct( ...
    "Direction", char(direction), ...
    "Slot", double(slot), ...
    "TBSBits", double(tx.TransportBlockSize), ...
    "TransportBlockSize", double(tx.TransportBlockSize), ...
    "Modulation", sixgr.util.structGet(layout, "Modulation", ...
        sixgr.util.structGet(channelCfg, "Modulation", "")), ...
    "NumLayers", double(sixgr.util.structGet(layout, "NumLayers", ...
        sixgr.util.structGet(channelCfg, "NumLayers", 1))), ...
    "TargetCodeRate", double(sixgr.util.structGet(layout, "TargetCodeRate", ...
        sixgr.util.structGet(tx, "TargetCodeRate", NaN))), ...
    "CodingLayout", layout, ...
    "HARQ", harqState);
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    grant.HARQTBContext = tbContext;
end
end

function [tx, rx, diag] = localRunAttempt(cfg, direction, snr_dB, tbBits, rv, combinedPrev)
if nargin < 6
    combinedPrev = [];
end
cfgAttempt = localSanitizeHARQProbeConfig(cfg, direction);
if upper(string(direction)) == "DL"
    cfgAttempt = localConfigureDLHARQCalibrationOwnership(cfgAttempt);
end
if isempty(tbBits)
    tbBitsArg = {};
else
    tbBitsArg = {"TransportBlockBits", tbBits};
end

switch upper(string(direction))
    case "UL"
        [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfgAttempt, tbBitsArg{:}, "RV", rv);
        chState = localInitChannelState(cfgAttempt, tx, txInfo, direction);
        rxWave = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState);
        [rx, ~] = sixgr.phy.ul.PUSCH_Rx(rxWave, cfgAttempt, "Carrier", tx.Carrier, "PUSCH", tx.PUSCH, ...
            "PUSCHIndices", tx.PUSCHIndices, "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, "RV", tx.RV, ...
            "SkipTimingEstimate", logical(sixgr.util.structGet(chState, "UseFading", false)));
        recLLR = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
        decIt = mean(double(sixgr.util.structGet(rx, "ActiveIterations", NaN)), "omitnan");
    otherwise
        [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfgAttempt, ...
            tbBitsArg{:}, "RV", rv, ...
            "ExecutionProfile", "phy_calibration");
        chState = localInitChannelState(cfgAttempt, tx, txInfo, direction);
        rxWave = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState);
        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgAttempt, "Carrier", tx.Carrier, "PDSCH", tx.PDSCH, ...
            "PDSCHIndices", tx.PDSCHIndices, "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, "RV", tx.RV, ...
            "CodingPlan", tx.CodingPlans, ...
            "HARQSoftBufferLLR", combinedPrev, ...
            "HARQSoftBufferLayout", sixgr.util.structGet( ...
                combinedPrev,"CodingPlans",struct()), ...
            "ExecutionProfile", "phy_calibration", ...
            "SkipTimingEstimate", logical(sixgr.util.structGet(chState, "UseFading", false)));
        recLLR = sixgr.util.structGet(rx, "RecLLR", []);
        decIt = NaN;
end

if isempty(tbBits)
    tbBits = int8(tx.TransportBlock(:));
else
    tbBits = int8(tbBits(:));
end
diag = sixgr.link.evaluateHARQDecode(tx, rx, cfgAttempt, []);
if upper(string(direction)) == "DL"
    % The canonical receiver already performed position-aware combining.
    % Preserve that cumulative soft buffer and outcome; do not combine the
    % same prior a second time in the diagnostic wrapper.
    diag.CombinedLLR = sixgr.util.structGet(rx, "RecLLR", []);
    diag.HARQSoftBuffer = sixgr.util.structGet( ...
        rx, "HARQSoftBuffer", struct());
    if isstruct(diag.HARQSoftBuffer) && isscalar(diag.HARQSoftBuffer)
        diag.HARQSoftBuffer.CodingPlans = tx.CodingPlans;
    end
    diag.SoftBuffer = diag.HARQSoftBuffer;
    diag.HARQSoftCombiningInfo = sixgr.util.structGet( ...
        rx, "HARQSoftCombiningInfoPerCodeword", {});
    diag.HARQSoftCombiningReason = char(string(sixgr.util.structGet( ...
        rx, "HARQSoftCombiningReason", "")));
    diag.HARQSoftCombiningApplied = logical(sixgr.util.structGet( ...
        rx, "HARQSoftCombiningApplied", false));
    diag.HARQSoftCombiningPositionAware = logical(sixgr.util.structGet( ...
        rx, "HARQSoftCombiningPositionAware", false));
    diag.HARQSoftCombiningOverlapPositionCount = double( ...
        sixgr.util.structGet(rx, ...
        "HARQSoftCombiningOverlapPositionCount", NaN));
    diag.CombinedDecodeOK = logical(sixgr.util.structGet(rx, "Ok", false));
end
rxBits = int8(sixgr.util.structGet(rx, "TransportBlock", int8([])));
[bitErr, bitsCompared] = localBitErrors(tbBits, rxBits);
diag.BitErrors = double(bitErr);
diag.BitsCompared = double(bitsCompared);
diag.CurrentDecodeOK = logical(sixgr.util.structGet(rx, "Ok", false)) && bitErr == 0 && numel(rxBits(:)) == numel(tbBits(:));
fallbackMetrics = localExtractLinkAdaptationMetrics(cfgAttempt, rx, struct("MeasuredSINR_dB", NaN));
measuredSINR = localExtractSINR(rx);
if ~isfinite(measuredSINR)
    measuredSINR = double(sixgr.util.structGet(fallbackMetrics, "SINR_dB", NaN));
end
diag.MeasuredSINR_dB = measuredSINR;
if ~isfield(diag, "Notes")
    diag.Notes = "";
end
end

function cfgOut = localConfigureDLHARQCalibrationOwnership(cfgOut)
nLayers = max(1, round(double(sixgr.util.structGet( ...
    cfgOut, "phy.pdsch.numLayers", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.nLayers", 1)))));
numCodewords = 1 + double(nLayers > 4);
cfgOut.run.pdschExecutionProfile = "phy_calibration";
cfgOut.phy.pdsch.executionProfile = "phy_calibration";
cfgOut.phy.pdsch.mcsTable = repmat( ...
    "calibration_explicit", 1, numCodewords);
cfgOut.phy.pdsch.mcsIndex = 0:(numCodewords - 1);
modulation = upper(strtrim(string(sixgr.util.structGet( ...
    cfgOut, "phy.pdsch.modulation", ""))));
if any(modulation(:).' == "1024QAM")
    % A 1024QAM diagnostic must carry explicit capability and deployment
    % eligibility from its caller; this probe never auto-enables the gates.
    return;
end
cfgOut.phy.pdsch.mcsContext = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "not_applicable_non1024_harq_probe", ...
    "OperatingBand", "not_applicable_non1024_harq_probe", ...
    "DeploymentClass", "lls_harq_calibration_probe");
end

function row = localMakePacketRow(direction, snr_dB, packetID, attempt, slotIdx, harqInfo, diag, rttSlots, slotDur_s, stopCondition, tbSizeBits, mode)
row = localEmptyPacketRow();
row.Direction = string(direction);
row.SNR_dB = double(snr_dB);
row.PacketID = double(packetID);
row.Attempt = double(attempt);
row.Frame = double(packetID);
row.Slot = double(slotIdx);
row.HARQProcess = double(sixgr.util.structGet(harqInfo, "HarqID", NaN));
row.RV = double(sixgr.util.structGet(harqInfo, "RV", NaN));
row.IsRetransmission = logical(sixgr.util.structGet(harqInfo, "IsRetransmission", attempt > 1));
row.CurrentDecodeOK = logical(diag.CurrentDecodeOK);
row.CombinedDecodeOK = logical(diag.CombinedDecodeOK);
row.ACK = logical(diag.CombinedDecodeOK);
row.NACK = ~logical(diag.CombinedDecodeOK);
row.DTX = false;
row.StopCondition = string(stopCondition);
row.RTT_slots = double(rttSlots);
row.RTT_ms = double(rttSlots * slotDur_s * 1e3);
row.FeedbackBits = 1;
row.RetransmissionCount = double(max(attempt - 1, 0));
row.RecoveryAfterRetx = false;
row.TBSize_bits = double(tbSizeBits);
row.BitErrors = double(diag.BitErrors);
row.BitsCompared = double(diag.BitsCompared);
row.DecoderIterations = double(diag.DecoderIterations);
row.CombinedDecoderIterations = double(diag.CombinedDecoderIterations);
row.MeasuredSINR_dB = double(diag.MeasuredSINR_dB);
row.HARQCombiningApplied = logical(sixgr.util.structGet(diag, "HARQSoftCombiningApplied", false));
row.HARQSoftCombiningPositionAware = logical(sixgr.util.structGet(diag, "HARQSoftCombiningPositionAware", false));
row.HARQSoftCombiningOverlapPositionCount = double(sixgr.util.structGet(diag, "HARQSoftCombiningOverlapPositionCount", NaN));
row.LLRCombiningGain_dB = double(sixgr.util.structGet(diag, "LLRCombiningGain_dB", NaN));
row.ProbeMode = string(mode);
row.Notes = string(diag.Notes);
end

function row = localEmptyPacketRow()
row = struct( ...
    "Direction", "", "SNR_dB", NaN, "PacketID", NaN, "Attempt", NaN, ...
    "Frame", NaN, "Slot", NaN, "HARQProcess", NaN, "RV", NaN, ...
    "IsRetransmission", false, "CurrentDecodeOK", false, "CombinedDecodeOK", false, ...
    "ACK", false, "NACK", false, "DTX", false, "StopCondition", "", ...
    "RTT_slots", NaN, "RTT_ms", NaN, "FeedbackBits", NaN, ...
    "RetransmissionCount", NaN, "RecoveryAfterRetx", false, "TBSize_bits", NaN, ...
    "BitErrors", NaN, "BitsCompared", NaN, "DecoderIterations", NaN, ...
    "CombinedDecoderIterations", NaN, "MeasuredSINR_dB", NaN, ...
    "HARQCombiningApplied", false, "HARQSoftCombiningPositionAware", false, ...
    "HARQSoftCombiningOverlapPositionCount", NaN, "LLRCombiningGain_dB", NaN, ...
    "ProbeMode", "", "Notes", "");
end

function T = localEmptyPacketTable()
T = struct2table(repmat(localEmptyPacketRow(), 0, 1));
end

function sinr_dB = localExtractSINR(rx)
sinr_dB = NaN;
try
    csi = sixgr.util.structGet(rx, "CSI", []);
    if isstruct(csi)
        x = sixgr.util.structGet(csi, "SINRPerRE", []);
        x = double(x(:));
        x = x(isfinite(x) & x > 0);
        if ~isempty(x)
            sinr_dB = 10 * log10(mean(x, "omitnan"));
            return;
        end
    end
catch
end
end

function cfgOut = localSanitizeHARQProbeConfig(cfg, direction)
cfgOut = cfg;
direction = upper(string(direction));
if direction == "UL"
    nLayers = max(1, round(double(sixgr.util.structGet(cfgOut, ...
        "phy.pusch.numLayers", sixgr.util.structGet(cfgOut, ...
        "phy.pusch.nLayers", 1)))));
    [dmrsPortSet, dmrsPortSource] = ...
        sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
        cfgOut, "UL", nLayers, struct());
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pusch.dmrs.portSet", dmrsPortSet);
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pusch.dmrs.DMRSPortSet", dmrsPortSet);
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pusch.dmrs.portSetSource", char(dmrsPortSource));
    return;
end

nLayers = max(1, round(double(sixgr.util.structGet(cfgOut, "phy.pdsch.numLayers", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.nLayers", 1)))));
[dmrsPortSet, dmrsPortSource] = ...
    sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
    cfgOut, "DL", nLayers, struct());
cfgOut = sixgr.util.structSet(cfgOut, ...
    "phy.pdsch.dmrs.portSet", dmrsPortSet);
cfgOut = sixgr.util.structSet(cfgOut, ...
    "phy.pdsch.dmrs.DMRSPortSet", dmrsPortSet);
cfgOut = sixgr.util.structSet(cfgOut, ...
    "phy.pdsch.dmrs.portSetSource", char(dmrsPortSource));
cfgOut = sixgr.util.structSet(cfgOut, ...
    "pdsch6gr.DMRSPortSet", dmrsPortSet);
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
clearMatrix = false;
staleMatrix = false;
for i = 1:numel(paths)
    W = sixgr.util.structGet(cfgOut, paths(i), []);
    if isempty(W)
        continue;
    end
    W = localSqueezeSingletonPage(W);
    if ~ismatrix(W)
        continue;
    end
    if localMatrixMatchesPDSCHLayers(W, nLayers)
        return;
    end
    staleMatrix = true;
    if size(W, 1) > localMaxNRLogicalPDSCHPorts() || size(W, 2) > localMaxNRLogicalPDSCHPorts()
        clearMatrix = true;
    end
end

if ~staleMatrix
    return;
end

if localHasFiniteDLPMI(cfgOut)
    [Wprobe, pmiMeta] = localMaterializeHARQProbePMIPrecoder(cfgOut, nLayers);
    cfgOut = localInstallHARQProbePDSCHPrecoder(cfgOut, Wprobe, nLayers, ...
        "harq_probe_rank_localized_pmi_codebook", pmiMeta);
    return;
end

if ~clearMatrix
    return;
end

cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nLayers);
for i = 1:numel(paths)
    cfgOut = sixgr.util.structSet(cfgOut, paths(i), []);
end
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.source", "harq_probe_rank_localized_identity");
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.normalizePrecodingMatrix", true);
end

function [Wprobe, meta] = localMaterializeHARQProbePMIPrecoder(cfg, nLayers)
pmi = localFiniteDLPMI(cfg);
if ~isfinite(pmi)
    error("sixgr:truth:HARQProbePMIUnavailable", ...
        "Rank-local HARQ probe precoding requires a finite configured PMI/TPMI.");
end

numPorts = double(sixgr.util.structGet(cfg, "phy.pdsch.numPorts", ...
    sixgr.util.structGet(cfg, "phy.pdsch.nPorts", nLayers)));
if ~(isscalar(numPorts) && isfinite(numPorts) && numPorts >= nLayers)
    error("sixgr:truth:HARQProbePrecodingPortCountInvalid", ...
        "HARQ probe PDSCH port count must be a finite scalar not smaller than the active layer count.");
end
numPorts = round(numPorts);

mode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.csi.pmiCodebookMode", ""))));
if strlength(mode) == 0
    codebookType = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.csi.codebookType", "type1"))));
    switch codebookType
        case "type1"
            mode = "type1_su_mimo";
        case "type2"
            mode = "type2_mu_mimo";
        case "etype2"
            mode = "etype2_candidate";
        otherwise
            error("sixgr:truth:HARQProbeCodebookModeUnavailable", ...
                "HARQ probe cannot materialize PMI=%d for unsupported codebook type '%s'.", ...
                round(pmi), char(codebookType));
    end
end
if mode == "noncodebook"
    error("sixgr:truth:HARQProbeNonCodebookPMIUnsupported", ...
        "A scalar PMI cannot materialize a rank-local non-codebook HARQ probe precoder.");
end

[candidates, info] = sixgr.phy.dl.pmiCodebookCandidates( ...
    cfg, nLayers, numPorts, "Mode", mode);
pmiIndex = round(pmi);
if isempty(candidates) || pmiIndex < 0 || pmiIndex >= numel(candidates)
    error("sixgr:truth:HARQProbePMIOutOfRange", ...
        "HARQ probe PMI=%d is out of range for mode '%s', %d port(s), and %d layer(s).", ...
        pmiIndex, char(mode), numPorts, nLayers);
end

selected = candidates(pmiIndex + 1);
Wprobe = selected.W;
if size(Wprobe, 1) ~= numPorts || size(Wprobe, 2) ~= nLayers
    error("sixgr:truth:HARQProbePMIMatrixDimensionMismatch", ...
        "PMI codebook produced a %dx%d matrix for %d port(s) and %d layer(s).", ...
        size(Wprobe, 1), size(Wprobe, 2), numPorts, nLayers);
end
meta = struct( ...
    "PMI", double(pmiIndex), ...
    "PMIType", char(string(sixgr.util.structGet(selected, "PMIType", ""))), ...
    "CodebookMode", char(string(sixgr.util.structGet(selected, "CodebookMode", ...
        sixgr.util.structGet(info, "Mode", mode)))));
end

function cfgOut = localInstallHARQProbePDSCHPrecoder(cfgOut, Wprobe, nLayers, source, meta)
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", size(Wprobe, 1));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", size(Wprobe, 1));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", Wprobe);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", []);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", []);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.source", char(source));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.pmi", double(meta.PMI));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.pmiType", char(meta.PMIType));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.codebookMode", char(meta.CodebookMode));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.selectedPrecoderSHA256", ...
    char(sixgr.phy.mimo.MatrixContract.digest(Wprobe)));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.PrecoderSource", char(source));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.normalizePrecodingMatrix", ...
    ~logical(sixgr.util.structGet(cfgOut, "mimo.strict", ...
    sixgr.util.structGet(cfgOut, "phy.mimo.strict", false))));
end

function tf = localMatrixMatchesPDSCHLayers(W, nLayers)
tf = false;
if isempty(W) || ~ismatrix(W)
    return;
end
sz = size(W);
tf = (sz(2) == nLayers && sz(1) >= nLayers) || ...
    (sz(1) == nLayers && sz(2) >= nLayers);
end

function W = localSqueezeSingletonPage(W)
sz = size(W);
if numel(sz) > 2 && all(sz(3:end) == 1)
    W = reshape(W, sz(1), sz(2));
end
end

function tf = localHasFiniteDLPMI(cfg)
tf = isfinite(localFiniteDLPMI(cfg));
end

function pmi = localFiniteDLPMI(cfg)
pmi = NaN;
paths = ["phy.pdsch.tpmi", "phy.pdsch.TPMI", "phy.pdsch.pmi", "phy.pdsch.PMI"];
for i = 1:numel(paths)
    value = sixgr.util.structGet(cfg, paths(i), []);
    if isnumeric(value) && isscalar(value) && isfinite(double(value))
        pmi = double(value);
        return;
    end
end
end

function n = localMaxNRLogicalPDSCHPorts()
n = 32;
end

function [be, bt] = localBitErrors(txBits, rxBits)
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
L = min(numel(txBits), numel(rxBits));
if L <= 0
    be = numel(txBits);
    bt = max(numel(txBits), 1);
    return;
end
be = sum(txBits(1:L) ~= rxBits(1:L));
bt = max(numel(txBits), L);
end

function state = localInitChannelState(cfg, tx, txInfo, direction)
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0);

if nargin < 4
    direction = "";
end

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF"
    return;
end

cfgCh = cfg;
dopp = double(sixgr.util.structGet(cfgCh, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfgCh, "channel.dopplerHz", ...
    sixgr.util.structGet(cfgCh, "channel.fading.maxDoppler_Hz", 0))));
cfgCh.channel.doppler_Hz = max(0, dopp);

if startsWith(modelRaw, "TDL")
    cfgCh.channel.model = "TDL";
    if modelRaw ~= "TDL"
        cfgCh.channel.tdlProfile = char(modelRaw);
    end
elseif startsWith(modelRaw, "CDL")
    cfgCh.channel.model = "CDL";
    if modelRaw ~= "CDL"
        cfgCh.channel.cdlProfile = char(modelRaw);
    end
else
    cfgCh.channel.model = char(modelRaw);
end

fs = localResolveSampleRate(tx, txInfo);
numTx = max(1, size(tx.Waveform, 2));
numRx = localResolveProbeNumRxAnt(cfg, direction, numTx);

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", sixgr.util.structGet(cfg, "run.seed", 1));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
    [padSamples, trimSamples] = localResolveChannelDelaySamples(ch.Object, fs);
    state.ChannelPadSamples = padSamples;
    state.ChannelTrimSamples = trimSamples;
end
end

function numRx = localResolveProbeNumRxAnt(cfg, direction, fallback)
if nargin < 3
    fallback = 1;
end
if upper(string(direction)) == "UL"
    candidates = [ ...
        sixgr.util.structGet(cfg, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.nRxAnt", NaN)];
else
    candidates = [ ...
        sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.nRxAnt", NaN), ...
        fallback];
end
candidates = double(candidates(:));
candidates = candidates(isfinite(candidates) & candidates >= 1);
if isempty(candidates)
    numRx = max(1, round(double(fallback)));
else
    numRx = max(1, round(candidates(1)));
end
end

function y = localApplyChannelAndAwgn(x, snr_dB, state)
y = x;
if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
    try
        reset(state.Obj);
    catch
    end
    xIn = x;
    padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
    trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
    if padSamples > 0
        xIn = [x; zeros(padSamples, size(x, 2), 'like', x)];
    end
    try
        yRaw = state.Obj(xIn);
    catch
        [yRaw, ~] = state.Obj(xIn);
    end
    if trimSamples > 0 && size(yRaw, 1) >= (trimSamples + size(x, 1))
        y = yRaw(1+trimSamples:trimSamples+size(x, 1), :);
    else
        y = yRaw;
        if size(y, 1) > size(x, 1)
            y = y(1:size(x, 1), :);
        elseif size(y, 1) < size(x, 1)
            y(end+1:size(x, 1), :) = cast(0, 'like', y); %#ok<AGROW>
        end
    end
end
y = localAddAwgn(y, snr_dB);
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(fs) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            fs = [];
        end
    end
end
if isempty(fs) || ~isfinite(double(fs)) || double(fs) <= 0
    fs = 30.72e6;
else
    fs = double(fs);
end
end

function [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, fs)
padSamples = 0;
trimSamples = 0;
if isempty(chObj) || ~(isfinite(fs) && fs > 0)
    return;
end
filterDelay = 0;
pathDelays = [];
try
    chInfo = info(chObj);
    filterDelay = double(sixgr.util.structGet(chInfo, "ChannelFilterDelay", 0));
    pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
catch
end
if isempty(pathDelays)
    try
        pathDelays = double(chObj.PathDelays);
    catch
        pathDelays = [];
    end
end
if isempty(pathDelays)
    maxPathDelay = 0;
else
    maxPathDelay = ceil(max(double(pathDelays(:))) * double(fs));
end
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function y = localAddAwgn(x, snr_dB)
snrLin = 10.^(double(snr_dB) / 10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar / 2) * (randn(size(x)) + 1i * randn(size(x)));
y = x + n;
end

function T = localEmptyProbeMetricTable()
T = table('Size', [0 9], ...
    'VariableTypes', {'string','string','string','string','double','string','string','string','string'}, ...
    'VariableNames', {'MetricKey','Entity','Statistic','Availability','Value','TextValue','Unit','Mode','Notes'});
end

function T = localProbeMetricRow(metricKey, entity, statistic, availability, value, textValue, unit, mode, notes)
T = table(string(metricKey), string(entity), string(statistic), string(availability), double(value), string(textValue), string(unit), string(mode), string(notes), ...
    'VariableNames', {'MetricKey','Entity','Statistic','Availability','Value','TextValue','Unit','Mode','Notes'});
end

function T = localConcatProbeTables(parts)
parts = parts(~cellfun(@isempty, parts));
if isempty(parts)
    T = localEmptyProbeMetricTable();
else
    T = vertcat(parts{:});
end
end

function invalidDirections = localInvalidProbeDirections(packetT, summaryT, airInterfaceRunFolder)
invalidDirections = strings(0, 1);
if ~(istable(packetT) && ~isempty(packetT))
    return;
end
for direction = ["DL"; "UL"].'
    trialT = localReadPrimaryTrialTable(airInterfaceRunFolder, direction);
    if ~(istable(trialT) && ~isempty(trialT))
        continue;
    end
    successRate = localMeanLogicalColumn(trialT, "CRCPass");
    if ~(isfinite(successRate) && successRate > 0.5)
        continue;
    end
    pktDir = packetT(string(packetT.Direction) == direction, :);
    if isempty(pktDir)
        continue;
    end
    probeReliability = localProbeReliability(summaryT, direction);
    probeHasSINR = any(isfinite(double(pktDir.MeasuredSINR_dB)));
    if (~isfinite(probeReliability) || probeReliability <= 0) && ~probeHasSINR
        invalidDirections(end+1, 1) = direction; %#ok<AGROW>
    end
end
end

function T = localReadPrimaryTrialTable(airInterfaceRunFolder, direction)
if upper(string(direction)) == "UL"
    path = fullfile(airInterfaceRunFolder, "csv", "ul_pusch_trials.csv");
else
    path = fullfile(airInterfaceRunFolder, "csv", "dl_pdsch_trials.csv");
end
T = table();
if exist(path, "file") ~= 2
    return;
end
try
    T = sixgr.util.csvReadTable(path);
catch
    T = table();
end
end

function value = localMeanLogicalColumn(T, varName)
value = NaN;
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
x = x(isfinite(x));
if isempty(x)
    return;
end
value = mean(x, "omitnan");
end

function value = localProbeReliability(summaryT, direction)
value = NaN;
if ~(istable(summaryT) && ~isempty(summaryT))
    return;
end
mask = string(summaryT.MetricKey) == "reliability_percentile" & ...
    string(summaryT.Statistic) == "success_rate" & ...
    startsWith(string(summaryT.Entity), string(direction) + "@");
if ~any(mask)
    return;
end
x = double(summaryT.Value(mask));
x = x(isfinite(x));
if isempty(x)
    return;
end
value = mean(x, "omitnan");
end

function p = localPercentile(x, pct)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    p = NaN;
else
    p = prctile(x, pct);
end
end

function count = localWarmupFrameCount(cfg)
mode = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
if mode == "" || ismember(mode, ["disabled","none","off","false","fixed"])
    count = 0;
else
    count = 6;
end
end

function mode = localHARQProbeMode(cfg)
mode = lower(string(sixgr.util.structGet(cfg, "phy.harq.validationMode", ...
    sixgr.util.structGet(cfg, "lls6g.harq.validation_mode", "observation"))));
if ~ismember(mode, ["observation","exercise","closed_loop"])
    mode = "observation";
end
end

function stopToken = localHARQSuccessStopCondition(mode)
if string(mode) == "closed_loop"
    stopToken = "crc_pass";
else
    stopToken = "ack";
end
end

function tf = localHARQClaimsRetx(mode)
tf = ismember(string(mode), ["exercise","closed_loop"]);
end

function availability = localRetxClaimAvailability(mode, retxObserved)
if localHARQClaimsRetx(mode) && any(retxObserved)
    availability = "available";
else
    availability = "not_exercised";
end
end

function txt = localRetxClaimText(mode, retxObserved)
if localHARQClaimsRetx(mode) && any(retxObserved)
    txt = "";
elseif any(retxObserved)
    txt = "not_exercised_observation_mode";
else
    txt = "not_exercised_no_retransmissions_observed";
end
end

function note = localHARQModeNote(mode, baseNote, retxObserved)
note = "HARQ " + string(mode) + " mode. " + string(baseNote);
if ~any(retxObserved)
    note = note + " No retransmissions were observed from real waveform decode outcomes at this SNR.";
end
end

function note = localHARQRetxClaimNote(mode, baseNote, retxObserved)
note = "HARQ " + string(mode) + " mode. " + string(baseNote);
if ~localHARQClaimsRetx(mode)
    note = note + " Observation mode does not claim retransmission-effectiveness gain as covered evidence, so this metric remains not exercised.";
end
if ~any(retxObserved)
    note = note + " No retransmissions were observed from real waveform decode outcomes at this SNR, so this retransmission-effectiveness metric remains not exercised.";
end
end

function metrics = localExtractLinkAdaptationMetrics(cfg, rx, diag)
metrics = struct( ...
    "CQI", NaN, ...
    "RI", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "SINR_dB", double(sixgr.util.structGet(diag, "MeasuredSINR_dB", NaN)), ...
    "PMIType", "", ...
    "PMICodebookMode", "", ...
    "CSIReportMode", "", ...
    "CSIPayloadBitLength", NaN, ...
    "CSIPayloadHex", "");

csi = sixgr.util.structGet(rx, "CSI", []);
if ~isstruct(csi)
    hEst = sixgr.util.structGet(rx, "ChannelEstimate", []);
    nVar = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
    if ~isempty(hEst)
        try
            csiArgs = localBuildCSIFeedbackArgs(rx);
            csi = sixgr.phy.dl.CSI_Feedback(hEst, nVar, cfg, csiArgs{:});
        catch
            csi = struct();
        end
    else
        csi = struct();
    end
end

if isstruct(csi) && ~isempty(fieldnames(csi))
    metrics.CQI = double(sixgr.util.structGet(csi, "CQI", NaN));
    metrics.RI = double(sixgr.util.structGet(csi, "RI", NaN));
    metrics.PMI = double(sixgr.util.structGet(csi, "PMI", NaN));
    metrics.CRI = double(sixgr.util.structGet(csi, "CRI", NaN));
    metrics.PMIType = char(string(sixgr.util.structGet(csi, "PMIType", "")));
    metrics.PMICodebookMode = char(string(sixgr.util.structGet(csi, "PMICodebookMode", "")));
    metrics.CSIReportMode = char(string(sixgr.util.structGet(csi, "ChannelStateInformationMode", "")));
    metrics.CSIPayloadBitLength = double(sixgr.util.structGet(csi, "CSIPayloadBitLength", NaN));
    metrics.CSIPayloadHex = char(string(sixgr.util.structGet(csi, "CSIPayloadHex", "")));
    if ~isfinite(metrics.SINR_dB)
        metrics.SINR_dB = double(sixgr.util.structGet(csi, "SINR_dB", NaN));
    end
end
end

function args = localBuildCSIFeedbackArgs(rx)
args = {};
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
rxGrid = sixgr.util.structGet(rx, "RxGrid", []);
refInd = sixgr.util.structGet(rx, "DMRSIndices", []);
refSym = sixgr.util.structGet(rx, "DMRSSymbols", []);
if isempty(rxGrid) || isempty(refInd) || isempty(refSym)
    return;
end
args = {"ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym};
end

function g = localReduceSweepGrid(gridIn, maxPts, anchorSNR)
g = unique(double(gridIn(:)), "sorted");
if isempty(g)
    g = double(anchorSNR);
    return;
end
maxPts = max(3, round(double(maxPts)));
if numel(g) <= maxPts
    return;
end
anchorIdx = find(g <= anchorSNR, 1, "last");
if isempty(anchorIdx)
    anchorIdx = 1;
end
keep = unique([1; anchorIdx; numel(g)]);
if numel(keep) < maxPts
    need = maxPts - numel(keep);
    rem = setdiff((1:numel(g)).', keep(:), "stable");
    if ~isempty(rem)
        pickIdx = round(linspace(1, numel(rem), min(need, numel(rem))));
        keep = unique([keep(:); rem(pickIdx(:))], "stable");
    end
end
g = g(sort(keep));
end

function slotDur_s = localSlotDuration(cfg)
slotDur_s = sixgr.time.slotDurationSec(cfg);
end
