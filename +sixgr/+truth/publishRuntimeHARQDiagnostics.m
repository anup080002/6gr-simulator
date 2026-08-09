function artifacts = publishRuntimeHARQDiagnostics(cfg, airInterfaceRunFolder, runtimeArtifacts)
%PUBLISHRUNTIMEHARQDIAGNOSTICS Publish HARQ views from the actual slot run.
% This adapter performs no PHY replay and creates no fallback rows. Every
% packet row is a deterministic projection of the canonical runtime HARQ
% timeline; unavailable metrics remain explicitly unavailable.

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.HARQCSVDir);
timeline = sixgr.util.structGet(runtimeArtifacts, "TimelineTable", table());
if ~(istable(timeline) && height(timeline) > 0)
    error("sixgr:truth:RuntimeHARQTimelineMissing", ...
        "Runtime HARQ publication requires a nonempty canonical timeline table.");
end

packetT = localBuildPacketTable(cfg, timeline);
summaryT = localBuildMetricTable(packetT);
packetPath = fullfile(layout.HARQCSVDir, "probe_harq_packets.csv");
timelinePath = fullfile(layout.HARQCSVDir, "harq_process_timeline.csv");
summaryPath = fullfile(layout.HARQCSVDir, "probe_harq_summary.csv");
sixgr.util.csvWriteTable(packetPath, packetT);
sixgr.util.csvWriteTable(timelinePath, packetT);
sixgr.util.csvWriteTable(summaryPath, summaryT);

artifacts = struct( ...
    "PacketCSV", packetPath, ...
    "SummaryCSV", summaryPath, ...
    "TimelineCSV", timelinePath, ...
    "PacketTable", packetT, ...
    "SummaryTable", summaryT, ...
    "TimelineTable", packetT, ...
    "PreviewOnly", false, ...
    "Source", "canonical_slot_runtime_harq_timeline", ...
    "ExecutionBackend", "runtime_observation_schema_adapter", ...
    "ApproximationMode", "none");
end

function T = localBuildPacketTable(cfg, source)
rows = repmat(localPacketRow(), 0, 1);
directions = upper(localTextColumn(source, "Direction", ""));
ue = localNumberColumn(source, "UEIndex", NaN);
harqId = localNumberColumn(source, "HarqID", NaN);
ndiEpoch = localNumberColumn(source, "NDIEpoch", NaN);
configuredSNR = localNumberColumn(source, "ConfiguredSNR_dB", NaN);
sweepPoint = localNumberColumn(source, "SweepPointIndex", NaN);
tbId = localTextColumn(source, "TBId", "");
slot = localNumberColumn(source, "Slot", NaN);
% TBId is the canonical transport-block identity and remains unchanged over
% retransmissions.  HARQ process and NDI epoch are intentionally reusable,
% particularly after an independent SNR-point reset, so they cannot by
% themselves identify a packet across a sweep.  Preserve a deterministic
% legacy fallback for older timelines that do not yet expose TBId.
keys = directions + "|tb=" + tbId;
missingTBId = strlength(strtrim(tbId)) == 0;
fallbackSweepToken = "sweep=" + string(sweepPoint);
missingSweepPoint = ~isfinite(sweepPoint);
fallbackSweepToken(missingSweepPoint) = ...
    "configured_snr=" + string(compose("%.17g", configuredSNR(missingSweepPoint)));
keys(missingTBId) = directions(missingTBId) + "|" + ...
    fallbackSweepToken(missingTBId) + "|ue=" + string(ue(missingTBId)) + ...
    "|harq=" + string(harqId(missingTBId)) + ...
    "|epoch=" + string(ndiEpoch(missingTBId));
uniqueKeys = unique(keys, "stable");
slotDuration_s = sixgr.time.slotDurationSec(cfg);
packetId = 0;
for keyNumber = 1:numel(uniqueKeys)
    indices = find(keys == uniqueKeys(keyNumber));
    [~, order] = sort(slot(indices));
    indices = indices(order);
    packetId = packetId + 1;
    for attempt = 1:numel(indices)
        sourceIndex = indices(attempt);
        tr = source(sourceIndex, :);
        row = localPacketRow();
        row.Direction = directions(sourceIndex);
        row.SweepPointIndex = localNumber(tr, "SweepPointIndex", NaN);
        row.ConfiguredSNR_dB = localNumber(tr, "ConfiguredSNR_dB", NaN);
        measuredSINR_dB = localNumber(tr, "MeasuredSINR_dB", NaN);
        if isfinite(measuredSINR_dB)
            row.SNR_dB = measuredSINR_dB;
            row.SNRSource = "runtime_receiver_measured_sinr";
            row.SNRValueRole = "measured_receiver_observation";
        elseif isfinite(row.ConfiguredSNR_dB)
            row.SNR_dB = row.ConfiguredSNR_dB;
            row.SNRSource = "runtime_configured_operating_point";
            row.SNRValueRole = "configured_operating_point";
        end
        row.PacketID = double(packetId);
        row.UEIndex = localNumber(tr, "UEIndex", NaN);
        row.RNTI = localNumber(tr, "RNTI", NaN);
        row.NDIEpoch = localNumber(tr, "NDIEpoch", NaN);
        row.TBId = localText(tr, "TBId", "");
        row.HARQContextHash = localText(tr, "HARQContextHash", "");
        row.Attempt = double(attempt);
        row.Frame = localNumber(tr, "Frame", NaN);
        row.Slot = localNumber(tr, "Slot", NaN);
        row.HARQProcess = localNumber(tr, "HarqID", NaN);
        row.RV = localNumber(tr, "RV", NaN);
        row.IsRetransmission = logical(localBool(tr, "IsRetransmission", attempt > 1));
        row.CurrentDecodeOK = logical(localBool(tr, "CurrentDecodeOK", false));
        row.CombinedDecodeOK = logical(localBool(tr, "CombinedDecodeOK", false));
        row.ACK = row.CombinedDecodeOK;
        row.NACK = ~row.CombinedDecodeOK;
        row.DTX = false;
        if row.CombinedDecodeOK
            row.StopCondition = "crc_pass";
        elseif attempt == numel(indices)
            row.StopCondition = "observed_nack_at_run_end";
        else
            row.StopCondition = "nack_retransmission_pending";
        end
        dueSlot = localNumber(tr, "FeedbackDueSlot", NaN);
        if isfinite(dueSlot) && isfinite(row.Slot)
            row.RTT_slots = max(0, dueSlot - row.Slot);
            row.RTT_ms = row.RTT_slots * slotDuration_s * 1e3;
        end
        row.FeedbackBits = 1;
        row.RetransmissionCount = double(attempt - 1);
        row.RecoveryAfterRetx = row.CombinedDecodeOK && ...
            ~row.CurrentDecodeOK && attempt > 1;
        row.TBSize_bits = localNumber(tr, "CurrentTBSBits", ...
            localNumber(tr, "OriginalTBSBits", NaN));
        row.MeasuredSINR_dB = localNumber(tr, "MeasuredSINR_dB", NaN);
        row.HARQCombiningApplied = logical(localBool(tr, ...
            "HARQCombiningApplied", false));
        row.LLRCombiningGain_dB = localNumber(tr, "LLRCombiningGain_dB", NaN);
        row.ProbeMode = "canonical_slot_runtime_truth";
        row.Source = "canonical_slot_runtime_harq_timeline";
        row.ExecutionBackend = "runtime_observation_schema_adapter";
        row.ApproximationMode = "none";
        row.Notes = "Derived only from harq/csv/live_harq_observation_timeline.csv; no replay PHY was launched.";
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildMetricTable(packetT)
parts = cell(0, 1);
for direction = unique(string(packetT.Direction), "stable").'
    P = packetT(string(packetT.Direction) == direction, :);
    entity = direction + "@canonical_slot_runtime";
    rtt = double(P.RTT_ms);
    rtt = rtt(isfinite(rtt));
    packetIds = unique(double(P.PacketID), "stable");
    firstAck = false(numel(packetIds), 1);
    finalAck = false(numel(packetIds), 1);
    retxCount = zeros(numel(packetIds), 1);
    for index = 1:numel(packetIds)
        Q = P(double(P.PacketID) == packetIds(index), :);
        firstAck(index) = logical(Q.CombinedDecodeOK(1));
        finalAck(index) = logical(Q.CombinedDecodeOK(end));
        retxCount(index) = max(double(Q.RetransmissionCount));
    end
    retxObserved = retxCount > 0;
    gain = double(P.LLRCombiningGain_dB);
    gain = gain(isfinite(gain) & logical(P.HARQCombiningApplied));
    parts{end+1, 1} = [ ... %#ok<AGROW>
        localMetric("rtt_distribution", entity, "mean_ms", localAvailability(rtt), localMean(rtt), "ms", "Observed feedback-due minus transmission-slot interval."); ...
        localMetric("rtt_distribution", entity, "p95_ms", localAvailability(rtt), localPercentile(rtt, 95), "ms", "Observed feedback timing percentile."); ...
        localMetric("retransmission_count_distribution", entity, "mean_retx", "available", mean(retxCount), "count", "Observed retransmission count per runtime HARQ packet identity."); ...
        localMetric("retransmission_count_distribution", entity, "retx_packet_rate", "available", mean(retxObserved), "fraction", "Observed packets with at least one retransmission."); ...
        localMetric("retransmission_count_distribution", entity, "retx_packets_observed", "available", sum(retxObserved), "count", "Observed retransmitted packet identities."); ...
        localMetric("combining_gain", entity, "mean_llr_gain_dB", localAvailability(gain), localMean(gain), "dB", "Receiver-reported position-aware LLR combining gain."); ...
        localMetric("ack_nack_dtx_distribution", entity, "first_attempt_ack_rate", "available", mean(firstAck), "fraction", "Observed first-attempt combined decode result."); ...
        localMetric("ack_nack_dtx_distribution", entity, "first_attempt_nack_rate", "available", mean(~firstAck), "fraction", "Observed first-attempt NACK rate."); ...
        localMetric("ack_nack_dtx_distribution", entity, "final_ack_rate", "available", mean(finalAck), "fraction", "Last observed decode result for each runtime packet identity."); ...
        localMetric("ack_nack_dtx_distribution", entity, "final_nack_rate", "available", mean(~finalAck), "fraction", "Last observed NACK at run completion; not relabeled as a terminal drop."); ...
        localMetric("ack_nack_dtx_distribution", entity, "dtx_rate", "not_available", NaN, "fraction", "Runtime timeline does not expose a DTX observation."); ...
        localMetric("feedback_overhead", entity, "total_bits", "available", sum(double(P.FeedbackBits)), "bits", "One observed ACK/NACK feedback bit per runtime attempt."); ...
        localMetric("stop_condition_distribution", entity, "ack_rate", "available", mean(finalAck), "fraction", "Observed packet identities ending with CRC pass."); ...
        localMetric("stop_condition_distribution", entity, "drop_rate", "not_available", NaN, "fraction", "Run-end NACK is not sufficient evidence of max-retransmission drop."); ...
        localMetric("latency_percentile", entity, "p95_ms", localAvailability(rtt), localPercentile(rtt, 95), "ms", "Observed HARQ feedback timing percentile."); ...
        localMetric("reliability_percentile", entity, "success_rate", "available", mean(finalAck), "fraction", "Observed final decode success rate."); ...
        localMetric("control_miss_induced_harq_penalties", entity, "penalty_rate", "not_available", NaN, "fraction", "No control-miss attribution is present in the runtime HARQ timeline."); ...
        localMetric("parity_cb_packet_level_coding_benefits", entity, "gain_fraction", "not_available", NaN, "fraction", "No independent parity-CB benefit attribution is present."); ...
        localMetric("harq_gain_per_retransmission", entity, "recovered_after_retx_rate", localAvailability(retxObserved(retxObserved)), localRecoveryRate(P, packetIds, retxObserved), "fraction", "Observed packets recovered only after one or more retransmissions.")];
end
if isempty(parts)
    T = localEmptyMetricTable();
else
    T = vertcat(parts{:});
end
end

function value = localRecoveryRate(P, packetIds, retxObserved)
value = NaN;
if ~any(retxObserved)
    return;
end
recovered = false(numel(packetIds), 1);
for index = 1:numel(packetIds)
    Q = P(double(P.PacketID) == packetIds(index), :);
    recovered(index) = ~logical(Q.CombinedDecodeOK(1)) && logical(Q.CombinedDecodeOK(end));
end
value = mean(recovered(retxObserved));
end

function T = localMetric(key, entity, statistic, availability, value, unit, notes)
T = table(string(key), string(entity), string(statistic), string(availability), ...
    double(value), "", string(unit), "canonical_slot_runtime_truth", string(notes), ...
    'VariableNames', {'MetricKey','Entity','Statistic','Availability','Value','TextValue','Unit','Mode','Notes'});
end

function T = localEmptyMetricTable()
T = table('Size', [0 9], ...
    'VariableTypes', {'string','string','string','string','double','string','string','string','string'}, ...
    'VariableNames', {'MetricKey','Entity','Statistic','Availability','Value','TextValue','Unit','Mode','Notes'});
end

function token = localAvailability(values)
if isempty(values)
    token = "not_available";
else
    token = "available";
end
end

function value = localMean(values)
if isempty(values), value = NaN; else, value = mean(values, "omitnan"); end
end

function value = localPercentile(values, percentile)
if isempty(values), value = NaN; else, value = prctile(values, percentile); end
end

function row = localPacketRow()
row = struct( ...
    "Direction", "", "SNR_dB", NaN, "ConfiguredSNR_dB", NaN, ...
    "SNRSource", "", "SNRValueRole", "", ...
    "SweepPointIndex", NaN, "PacketID", NaN, "UEIndex", NaN, ...
    "RNTI", NaN, "NDIEpoch", NaN, "TBId", "", ...
    "HARQContextHash", "", "Attempt", NaN, ...
    "Frame", NaN, "Slot", NaN, "HARQProcess", NaN, "RV", NaN, ...
    "IsRetransmission", false, "CurrentDecodeOK", false, "CombinedDecodeOK", false, ...
    "ACK", false, "NACK", false, "DTX", false, "StopCondition", "", ...
    "RTT_slots", NaN, "RTT_ms", NaN, "FeedbackBits", NaN, ...
    "RetransmissionCount", NaN, "RecoveryAfterRetx", false, "TBSize_bits", NaN, ...
    "BitErrors", NaN, "BitsCompared", NaN, "DecoderIterations", NaN, ...
    "CombinedDecoderIterations", NaN, "MeasuredSINR_dB", NaN, ...
    "HARQCombiningApplied", false, "HARQSoftCombiningPositionAware", false, ...
    "HARQSoftCombiningOverlapPositionCount", NaN, "LLRCombiningGain_dB", NaN, ...
    "ProbeMode", "", "Source", "", "ExecutionBackend", "", ...
    "ApproximationMode", "", "Notes", "");
end

function values = localNumberColumn(T, name, fallback)
if ismember(name, string(T.Properties.VariableNames))
    values = double(T.(name));
else
    values = repmat(double(fallback), height(T), 1);
end
end

function values = localTextColumn(T, name, fallback)
if ismember(name, string(T.Properties.VariableNames))
    values = string(T.(name));
else
    values = repmat(string(fallback), height(T), 1);
end
end

function value = localNumber(row, name, fallback)
if ismember(name, string(row.Properties.VariableNames))
    raw = double(row.(name));
    if isscalar(raw) && isfinite(raw), value = raw; return; end
end
value = double(fallback);
end

function value = localBool(row, name, fallback)
if ismember(name, string(row.Properties.VariableNames))
    raw = row.(name);
    if ~isempty(raw), value = logical(raw(1)); return; end
end
value = logical(fallback);
end

function value = localText(row, name, fallback)
if ismember(name, string(row.Properties.VariableNames))
    raw = string(row.(name));
    if isscalar(raw) && ~ismissing(raw), value = raw; return; end
end
value = string(fallback);
end
