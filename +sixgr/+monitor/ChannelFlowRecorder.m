classdef ChannelFlowRecorder
    %CHANNELFLOWRECORDER Summarize real profile/trace evidence per channel.

    methods (Static)
        function summaryT = export(runDir, profileT, eventT)
            if nargin < 3
                eventT = table();
            end
            specs = sixgr.monitor.ChannelFlowRecorder.channelSpecs();
            rows = repmat(struct("channel", "", "profile_function_count", 0, ...
                "profile_call_count", 0, "trace_event_count", 0, "tx_called", false, ...
                "rx_called", false, "channel_model_called", false, ...
                "decode_or_detect_called", false, "metrics_emitted", false, ...
                "status", "", "notes", ""), 0, 1);
            for i = 1:numel(specs)
                spec = specs(i);
                flowT = sixgr.monitor.ChannelFlowRecorder.flowTable(spec, profileT, eventT);
                sixgr.util.csvWriteTable(fullfile(runDir, spec.FileName), flowT);
                tx = any(localContainsAny(flowT.function_name, ["_tx","tx.","tx","generate","modulate","preamble"]));
                rx = any(localContainsAny(flowT.function_name, ["_rx","rx.","rx","receiver","demod","estimate","detect"]));
                model = any(localContainsAny(flowT.function_name, ["channel","factory","propagat","interfer","noise"]));
                decode = any(localContainsAny(flowT.function_name, ["decode","detect","crc","recover","demod"]));
                metrics = any(localContainsAny(flowT.function_name, ["metric","kpi","export","trace"]));
                calls = 0;
                if istable(flowT) && height(flowT) > 0 && ismember("call_count", string(flowT.Properties.VariableNames))
                    calls = sum(double(flowT.call_count), "omitnan");
                end
                status = "not_observed_in_profile";
                notes = "No matching MATLAB profiler or monitor events were observed for this scenario.";
                if height(flowT) > 0
                    status = "observed";
                    notes = "Observed through MATLAB profiler and/or explicit monitor events.";
                end
                rows(end+1, 1) = struct("channel", spec.Name, ...
                    "profile_function_count", height(flowT), "profile_call_count", calls, ...
                    "trace_event_count", sixgr.monitor.ChannelFlowRecorder.traceCount(eventT, spec.Name), ...
                    "tx_called", tx, "rx_called", rx, "channel_model_called", model, ...
                    "decode_or_detect_called", decode, "metrics_emitted", metrics, ...
                    "status", status, "notes", notes); %#ok<AGROW>
            end
            summaryT = struct2table(rows);
            sixgr.util.csvWriteTable(fullfile(runDir, "channel_flow_summary.csv"), summaryT);
            sixgr.monitor.ChannelFlowRecorder.writeSkipped(runDir, eventT);
        end

        function flowT = flowTable(spec, profileT, eventT)
            rows = repmat(struct("channel", "", "function_name", "", "file_path", "", ...
                "call_count", NaN, "total_time_s", NaN, "self_time_s", NaN, ...
                "source", "", "event_type", "", "status", "", "notes", ""), 0, 1);
            if istable(profileT) && height(profileT) > 0
                hay = lower(string(profileT.function_name) + " " + string(profileT.file_path) + " " + string(profileT.inferred_channel_or_block));
                mask = localContainsAny(hay, spec.Tokens);
                for j = find(mask(:).')
                    rows(end+1, 1) = struct("channel", spec.Name, ...
                        "function_name", string(profileT.function_name(j)), ...
                        "file_path", string(profileT.file_path(j)), ...
                        "call_count", double(profileT.call_count(j)), ...
                        "total_time_s", double(profileT.total_time_s(j)), ...
                        "self_time_s", double(profileT.self_time_s(j)), ...
                        "source", "matlab_profiler", "event_type", "", ...
                        "status", "called", "notes", "function appeared in MATLAB profile"); %#ok<AGROW>
                end
            end
            if istable(eventT) && height(eventT) > 0
                eventChannel = localTableStringColumn(eventT, "channel");
                eventFunction = localTableStringColumn(eventT, "function_name");
                mask = strcmpi(eventChannel, spec.Name) | localContainsAny(lower(eventFunction), spec.Tokens);
                for j = find(mask(:).')
                    rows(end+1, 1) = struct("channel", spec.Name, ...
                        "function_name", localTableString(eventT, "function_name", j), ...
                        "file_path", localTableString(eventT, "file_path", j), ...
                        "call_count", 1, "total_time_s", localTableDouble(eventT, "elapsed_wall_s", j), ...
                        "self_time_s", NaN, "source", "run_monitor", ...
                        "event_type", localTableString(eventT, "event_type", j), ...
                        "status", localTableString(eventT, "status", j), ...
                        "notes", localTableString(eventT, "skip_reason", j) + localTableString(eventT, "bypass_reason", j)); %#ok<AGROW>
                end
            end
            flowT = struct2table(rows);
        end

        function n = traceCount(eventT, channel)
            n = 0;
            if istable(eventT) && height(eventT) > 0 && ismember("channel", string(eventT.Properties.VariableNames))
                n = sum(strcmpi(localTableStringColumn(eventT, "channel"), string(channel)));
            end
        end

        function writeSkipped(runDir, eventT)
            T = table('Size', [0 10], ...
                'VariableTypes', {'string','string','string','string','string','string','string','string','string','string'}, ...
                'VariableNames', {'event_time','function','channel','phase','condition_checked','branch_taken','skip_or_bypass_reason','config_key','expected_for_scenario','severity'});
            if istable(eventT) && height(eventT) > 0
                eventType = localTableStringColumn(eventT, "event_type");
                skipReason = localTableStringColumn(eventT, "skip_reason");
                bypassReason = localTableStringColumn(eventT, "bypass_reason");
                mask = ismember(eventType, ["SKIPPED","BYPASSED","FALLBACK_USED","WARNING"]) | ...
                    strlength(skipReason) > 0 | strlength(bypassReason) > 0;
                for i = find(mask(:).')
                    reason = skipReason(i);
                    if strlength(reason) == 0
                        reason = bypassReason(i);
                    end
                    T(end+1, :) = {localTableString(eventT, "timestamp_wall", i), localTableString(eventT, "function_name", i), ...
                        localTableString(eventT, "channel", i), localTableString(eventT, "phase", i), "", eventType(i), ...
                        reason, "", "unknown", "MEDIUM"}; %#ok<AGROW>
                end
            end
            sixgr.util.csvWriteTable(fullfile(runDir, "skipped_or_bypassed_activity.csv"), T);
        end

        function specs = channelSpecs()
            specs = [
                struct("Name","PDSCH", "FileName","channel_flow_pdsch.csv", "Tokens", ["pdsch"])
                struct("Name","PUSCH", "FileName","channel_flow_pusch.csv", "Tokens", ["pusch"])
                struct("Name","PDCCH", "FileName","channel_flow_pdcch.csv", "Tokens", ["pdcch","dci","coreset"])
                struct("Name","PUCCH", "FileName","channel_flow_pucch.csv", "Tokens", ["pucch","uci"])
                struct("Name","PRACH", "FileName","channel_flow_prach.csv", "Tokens", ["prach","random_access","fourstep","ra."])
                struct("Name","PBCH_SSB", "FileName","channel_flow_pbch_ssb.csv", "Tokens", ["pbch","ssb","pss","sss","sib1","broadcast"])
                struct("Name","SRS", "FileName","channel_flow_srs.csv", "Tokens", ["srs"])
                struct("Name","TRS", "FileName","channel_flow_trs.csv", "Tokens", ["trs"])
                struct("Name","CSI_RS", "FileName","channel_flow_csi_rs.csv", "Tokens", ["csi_rs","csirs","csi-rs"])
                struct("Name","BEAMFORMING", "FileName","channel_flow_beamforming.csv", "Tokens", ["beam","pmi","precod","mimo"])
                ];
        end
    end
end

function mask = localContainsAny(values, tokens)
values = lower(string(values));
tokens = lower(string(tokens));
mask = false(size(values));
for token = tokens(:).'
    mask = mask | contains(values, token);
end
end

function values = localTableStringColumn(T, name)
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    values = string(T.(char(name)));
else
    values = strings(height(T), 1);
end
values = values(:);
end

function value = localTableString(T, name, idx)
values = localTableStringColumn(T, name);
if idx >= 1 && idx <= numel(values)
    value = values(idx);
else
    value = "";
end
end

function value = localTableDouble(T, name, idx)
value = NaN;
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    raw = T.(char(name));
    if idx >= 1 && idx <= numel(raw)
        if isnumeric(raw) || islogical(raw)
            value = double(raw(idx));
        else
            value = str2double(string(raw(idx)));
        end
    end
end
end
