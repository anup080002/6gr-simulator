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
feedbackT = sixgr.util.structGet(runtimeArtifacts,"FeedbackObservationTable",table());
packetT = sixgr.truth.bindRuntimeHARQFeedbackEvidence(packetT,feedbackT);
summaryT = localBuildMetricTable(packetT);
packetPath = fullfile(layout.HARQCSVDir, "probe_harq_packets.csv");
timelinePath = fullfile(layout.HARQCSVDir, "harq_process_timeline.csv");
summaryPath = fullfile(layout.HARQCSVDir, "probe_harq_summary.csv");
sixgr.util.csvWriteTable(packetPath, packetT,"PreserveSchema",true);
sixgr.util.csvWriteTable(timelinePath, packetT,"PreserveSchema",true);
sixgr.util.csvWriteTable(summaryPath, summaryT);

artifacts = struct( ...
    "PacketCSV", packetPath, ...
    "SummaryCSV", summaryPath, ...
    "TimelineCSV", timelinePath, ...
    "PacketTable", packetT, ...
    "SummaryTable", summaryT, ...
    "TimelineTable", packetT, ...
    "FeedbackObservationTable", feedbackT, ...
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
% TBId remains unchanged over retransmissions within a point. Independent
% point resets can reuse TBId as well as HARQ process and NDI epoch: every
% packet key must therefore retain sweep scope, even when TBId is present.
missingTBId = strlength(strtrim(tbId)) == 0;
fallbackSweepToken = "sweep=" + string(sweepPoint);
missingSweepPoint = ~isfinite(sweepPoint);
fallbackSweepToken(missingSweepPoint) = ...
    "configured_snr=" + string(compose("%.17g", configuredSNR(missingSweepPoint)));
keys = directions + "|" + fallbackSweepToken + "|tb=" + tbId;
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
    observedRetxCount = 0;
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
        row.PHYGrantContextId = localText(tr,"PHYGrantContextId","");
        row.HARQContextHash = localText(tr, "HARQContextHash", "");
        row.Attempt = double(attempt);
        row.Frame = localNumber(tr, "Frame", NaN);
        row.Slot = localNumber(tr, "Slot", NaN);
        row.HARQProcess = localNumber(tr, "HarqID", NaN);
        row.RV = localNumber(tr, "RV", NaN);
        row.IsRetransmission = logical(localBool(tr, "IsRetransmission", attempt > 1));
        observedRetxCount = observedRetxCount + double(row.IsRetransmission);
        row.CurrentDecodeOK = logical(localBool(tr, "CurrentDecodeOK", false));
        row.CombinedDecodeOK = logical(localBool(tr, "CombinedDecodeOK", false));
        if row.CombinedDecodeOK
            row.StopCondition = "crc_pass";
        elseif attempt == numel(indices)
            row.StopCondition = "last_observed_crc_failure_at_run_end";
        else
            row.StopCondition = "crc_failure_before_observed_retransmission";
        end
        dueSlot = localNumber(tr, "FeedbackDueSlot", NaN);
        if isfinite(dueSlot) && isfinite(row.Slot)
            row.ScheduledFeedbackOffset_slots = dueSlot - row.Slot;
            row.ScheduledFeedbackOffset_ms = row.ScheduledFeedbackOffset_slots * slotDuration_s * 1e3;
        end
        row.RTTSlotDuration_ms=slotDuration_s*1e3;
        for name=["DataTransmitSymbolStartSample","DataTransmitSymbolEndSampleExclusive","DataTransmitSampleRateHz"]
            row.(name)=localNumber(tr,name,NaN);
        end
        row.DataTransmitTimingSource=localText(tr,"DataTransmitTimingSource","");
        row.RetransmissionCount = observedRetxCount;
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
        row.Notes = "Data CRC and packet identity come from canonical slot-runtime HARQ state; feedback outcomes require exact independently received UCI identity joins. No replay PHY was launched.";
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
    firstAck = NaN(numel(packetIds), 1);
    finalAck = false(numel(packetIds), 1);
    retxCount = zeros(numel(packetIds), 1);
    for index = 1:numel(packetIds)
        Q = P(double(P.PacketID) == packetIds(index), :);
        % A trace may begin at a retransmission. Its first *observed* row
        % is not evidence of the original transmission's CRC result.
        if ~logical(Q.IsRetransmission(1))
            firstAck(index) = double(Q.CombinedDecodeOK(1));
        end
        finalAck(index) = logical(Q.CombinedDecodeOK(end));
        retxCount(index) = max(double(Q.RetransmissionCount));
    end
    firstAck = firstAck(isfinite(firstAck));
    retxObserved = retxCount > 0;
    gain = double(P.LLRCombiningGain_dB);
    gain = gain(isfinite(gain) & logical(P.HARQCombiningApplied));
    feedback = P(logical(P.FeedbackObservationAvailable),:);
    parts{end+1, 1} = [ ... %#ok<AGROW>
        localMetric("rtt_distribution", entity, "mean_ms", localAvailability(rtt), localMean(rtt), "ms", "Executed data-symbol TX start to independently received usable ACK/NACK result availability; excludes DTX/unobserved feedback."); ...
        localMetric("rtt_distribution", entity, "p95_ms", localAvailability(rtt), localPercentile(rtt, 95), "ms", "Sample-clock feedback completion latency percentile, not configured K1 or packet service latency."); ...
        localMetric("retransmission_count_distribution", entity, "mean_retx", "available", mean(retxCount), "count", "Observed retransmission count per runtime HARQ packet identity."); ...
        localMetric("retransmission_count_distribution", entity, "retx_packet_rate", "available", mean(retxObserved), "fraction", "Observed packets with at least one retransmission."); ...
        localMetric("retransmission_count_distribution", entity, "retx_packets_observed", "available", sum(retxObserved), "count", "Observed retransmitted packet identities."); ...
        localMetric("combining_gain", entity, "mean_llr_gain_dB", localAvailability(gain), localMean(gain), "dB", "Receiver-reported position-aware LLR combining gain."); ...
        localMetric("receiver_crc_distribution", entity, "first_attempt_crc_pass_rate", localAvailability(firstAck), localMean(firstAck), "fraction", "Original-transmission receiver CRC pass rate; excludes left-censored attempts; not received feedback."); ...
        localMetric("receiver_crc_distribution", entity, "first_attempt_crc_fail_rate", localAvailability(firstAck), localMean(1-firstAck), "fraction", "Original-transmission receiver CRC failure rate; not received feedback."); ...
        localMetric("receiver_crc_distribution", entity, "last_observed_crc_pass_rate", "available", mean(finalAck), "fraction", "Last observed decode result per packet identity; not terminal residual BLER."); ...
        localMetric("receiver_crc_distribution", entity, "last_observed_crc_fail_rate", "available", mean(~finalAck), "fraction", "Last observed CRC failure; does not prove terminal drop."); ...
        localMetric("ack_nack_dtx_distribution", entity, "received_ack_rate", localAvailability(feedback.ACK), localMean(feedback.ACK), "fraction", "ACK logical-bit dispositions divided by associated received HARQ bit dispositions, including DTX; not independent occasion probability."); ...
        localMetric("ack_nack_dtx_distribution", entity, "received_nack_rate", localAvailability(feedback.NACK), localMean(feedback.NACK), "fraction", "NACK logical-bit dispositions divided by associated received HARQ bit dispositions, including DTX."); ...
        localMetric("ack_nack_dtx_distribution", entity, "dtx_rate", localAvailability(feedback.DTX), localMean(feedback.DTX), "fraction", "DTX logical-bit dispositions divided by associated received HARQ bit dispositions; not transmitter silence probability."); ...
        localMetric("ack_nack_dtx_distribution", entity, "associated_bit_dispositions", "available", height(feedback), "count", "Exact sweep/grant/source-slot/UE/RNTI/process joins; receiver-only obligations remain in the separate observation table."); ...
        localMetric("feedback_overhead", entity, "total_bits", "not_available", NaN, "bits", "Coded air-interface feedback overhead is not inferred as one bit per data attempt."); ...
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
    "RNTI", NaN, "NDIEpoch", NaN, "TBId", "", "PHYGrantContextId", "", ...
    "HARQContextHash", "", "Attempt", NaN, ...
    "Frame", NaN, "Slot", NaN, "HARQProcess", NaN, "RV", NaN, ...
    "IsRetransmission", false, "CurrentDecodeOK", false, "CombinedDecodeOK", false, ...
    "ACK", NaN, "NACK", NaN, "DTX", NaN, "StopCondition", "", ...
    "RTT_slots", NaN, "RTT_ms", NaN, "FeedbackBits", NaN, ...
    "RTTSlotDuration_ms",NaN,"ScheduledFeedbackOffset_slots",NaN,"ScheduledFeedbackOffset_ms",NaN, ...
    "DataTransmitSymbolStartSample",NaN,"DataTransmitSymbolEndSampleExclusive",NaN, ...
    "DataTransmitSampleRateHz",NaN,"DataTransmitTimingSource","", ...
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
    raw = T.(name);
    values = strings(height(T), 1);
    if ischar(raw) && height(T) == 1
        values(1) = string(raw);
        return;
    end
    if ~iscell(raw)
        converted = string(raw);
        if numel(converted) ~= height(T)
            error("sixgr:truth:InvalidRuntimeHARQTextColumn", ...
                "Runtime HARQ column %s has %d values for %d rows.", ...
                char(name), numel(converted), height(T));
        end
        values = converted(:);
        return;
    end
    if numel(raw) ~= height(T)
        error("sixgr:truth:InvalidRuntimeHARQTextColumn", ...
            "Runtime HARQ cell column %s has %d values for %d rows.", ...
            char(name), numel(raw), height(T));
    end
    for rowIndex = 1:height(T)
        values(rowIndex) = localScalarText(raw{rowIndex}, name, rowIndex, fallback);
    end
else
    values = repmat(string(fallback), height(T), 1);
end
end

function value = localScalarText(raw, name, rowIndex, fallback)
% Legacy runtime tables may contain one extra scalar-cell wrapper around
% empty character values.  Unwrap scalar cells without accepting arrays,
% structs, or other ambiguous values as transport-block identities.
while iscell(raw) && isscalar(raw)
    raw = raw{1};
end
if isempty(raw)
    value = string(fallback);
elseif ischar(raw)
    value = string(raw);
elseif isstring(raw) && isscalar(raw)
    value = raw;
elseif (isnumeric(raw) || islogical(raw)) && isscalar(raw)
    value = string(raw);
else
    error("sixgr:truth:InvalidRuntimeHARQTextValue", ...
        "Runtime HARQ column %s row %d is not a scalar text value (class %s).", ...
        char(name), rowIndex, class(raw));
end
if ismissing(value)
    value = string(fallback);
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
    column = localTextColumn(row, name, fallback);
    if isscalar(column) && ~ismissing(column), value = column; return; end
end
value = string(fallback);
end
