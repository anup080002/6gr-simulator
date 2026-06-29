classdef ComplexityCounter
    %COMPLEXITYCOUNTER Export transparent operation estimates from evidence.

    methods (Static)
        function [summaryT, byFunctionT, byChannelT] = export(runDir, profileT)
            byFunctionT = sixgr.monitor.ComplexityCounter.byFunction(profileT);
            byChannelT = sixgr.monitor.ComplexityCounter.byChannel(byFunctionT);
            summaryT = sixgr.monitor.ComplexityCounter.summary(byFunctionT);
            sixgr.util.csvWriteTable(fullfile(runDir, "complexity_by_function.csv"), byFunctionT);
            sixgr.util.csvWriteTable(fullfile(runDir, "complexity_by_channel.csv"), byChannelT);
            sixgr.util.csvWriteTable(fullfile(runDir, "complexity_summary.csv"), summaryT);
        end

        function T = byFunction(profileT)
            rows = repmat(struct("function_name", "", "channel", "", "phase", "", ...
                "operation_type", "", "count", NaN, "size_parameters_json", "", ...
                "estimated_ops", NaN, "elapsed_time_s", NaN, "ops_per_second", NaN, ...
                "notes", ""), 0, 1);
            if istable(profileT) && height(profileT) > 0
                for i = 1:height(profileT)
                    name = string(profileT.function_name(i));
                    calls = double(profileT.call_count(i));
                    elapsed = double(profileT.total_time_s(i));
                    [op, opsPerCall, notes] = sixgr.monitor.ComplexityCounter.estimateOperation(name);
                    estimated = opsPerCall * max(calls, 0);
                    rate = estimated / max(elapsed, eps);
                    rows(end+1, 1) = struct("function_name", name, ...
                        "channel", string(profileT.inferred_channel_or_block(i)), ...
                        "phase", sixgr.monitor.ComplexityCounter.inferPhase(name), ...
                        "operation_type", op, "count", calls, ...
                        "size_parameters_json", "{}", "estimated_ops", estimated, ...
                        "elapsed_time_s", elapsed, "ops_per_second", rate, ...
                        "notes", notes); %#ok<AGROW>
                end
            end
            required = ["OFDM_FFT","CHANNEL_CONVOLUTION","MIMO_EQUALIZATION","LDPC_DECODING", ...
                "PDCCH_BLIND_DECODE","PRACH_CORRELATION","BEAM_SWEEP","INTERFERENCE_COMBINE","HARQ_COMBINE"];
            existing = string({rows.operation_type});
            for op = required
                if ~any(existing == op)
                    rows(end+1, 1) = struct("function_name", "not_observed", "channel", "", ...
                        "phase", "", "operation_type", op, "count", 0, ...
                        "size_parameters_json", "{}", "estimated_ops", 0, ...
                        "elapsed_time_s", 0, "ops_per_second", NaN, ...
                        "notes", "operation_not_observed_in_this_profiled_run"); %#ok<AGROW>
                end
            end
            T = struct2table(rows);
        end

        function T = byChannel(byFunctionT)
            if ~(istable(byFunctionT) && height(byFunctionT) > 0)
                T = table();
                return;
            end
            channels = unique(string(byFunctionT.channel));
            rows = repmat(struct("channel", "", "function_count", 0, "call_count", 0, ...
                "estimated_ops", 0, "elapsed_time_s", 0, "ops_per_second", NaN), 0, 1);
            for ch = channels(:).'
                mask = string(byFunctionT.channel) == ch;
                elapsed = sum(double(byFunctionT.elapsed_time_s(mask)), "omitnan");
                ops = sum(double(byFunctionT.estimated_ops(mask)), "omitnan");
                rows(end+1, 1) = struct("channel", ch, "function_count", sum(mask), ...
                    "call_count", sum(double(byFunctionT.count(mask)), "omitnan"), ...
                    "estimated_ops", ops, "elapsed_time_s", elapsed, ...
                    "ops_per_second", ops / max(elapsed, eps)); %#ok<AGROW>
            end
            T = struct2table(rows);
        end

        function T = summary(byFunctionT)
            if ~(istable(byFunctionT) && height(byFunctionT) > 0)
                T = table("empty_profile", 0, 0, 0, NaN, ...
                    'VariableNames', {'Status','FunctionRows','ObservedOperationRows','EstimatedOps','ElapsedTime_s','OpsPerSecond'});
                return;
            end
            observed = string(byFunctionT.function_name) ~= "not_observed";
            ops = sum(double(byFunctionT.estimated_ops(observed)), "omitnan");
            elapsed = sum(double(byFunctionT.elapsed_time_s(observed)), "omitnan");
            T = table("profile_based_complexity_estimate", height(byFunctionT), sum(observed), ...
                ops, elapsed, ops / max(elapsed, eps), ...
                'VariableNames', {'Status','FunctionRows','ObservedOperationRows','EstimatedOps','ElapsedTime_s','OpsPerSecond'});
        end

        function [op, ops, notes] = estimateOperation(functionName)
            n = lower(string(functionName));
            op = "GENERAL";
            ops = 1;
            notes = "profile_call_count_based_estimate";
            if contains(n, "ofdmmod") || contains(n, "ofdmdemod") || contains(n, "fft") || contains(n, "ifft")
                op = "OFDM_FFT";
                nfft = 4096;
                ops = nfft * log2(nfft);
                notes = "O(Nfft log2 Nfft) per profiled call with default audit Nfft=4096";
            elseif contains(n, "channel") && (contains(n, "factory") || contains(n, "step") || contains(n, "apply"))
                op = "CHANNEL_CONVOLUTION";
                ops = 1e6;
                notes = "O(Nsamples Ntaps Ntx Nrx) profile placeholder until trace dimensions are available";
            elseif contains(n, "equaliz") || contains(n, "mimodetect") || contains(n, "posteqsinr")
                op = "MIMO_EQUALIZATION";
                ops = 273 * 12 * (4 * 2^2 + 2^3);
                notes = "O(Nre(Nrx Nlayers^2 + Nlayers^3)) default audit estimate";
            elseif contains(n, "ldpc") || contains(n, "raterecover") || contains(n, "ratematch")
                op = "LDPC_DECODING";
                ops = 8448 * 8 * 6;
                notes = "O(iterations coded_bits degree) default audit estimate";
            elseif contains(n, "pdcch")
                op = "PDCCH_BLIND_DECODE";
                ops = 44 * 1e4;
                notes = "O(Ncandidates decode_cost) default audit estimate";
            elseif contains(n, "prach")
                op = "PRACH_CORRELATION";
                ops = 64 * 4096 * log2(4096);
                notes = "O(Ncandidates Nfft log2 Nfft) default audit estimate";
            elseif contains(n, "beam") || contains(n, "pmi")
                op = "BEAM_SWEEP";
                ops = 64 * 273 * 12;
                notes = "O(Nbeams measurement_cost) default audit estimate";
            elseif contains(n, "interfer")
                op = "INTERFERENCE_COMBINE";
                ops = 2 * 1e5;
                notes = "O(Ninterferers waveform_samples rx_antennas) default audit estimate";
            elseif contains(n, "harq") || contains(n, "combinesoft")
                op = "HARQ_COMBINE";
                ops = 8448;
                notes = "O(observed mother-code LLR positions) default audit estimate";
            end
        end

        function phase = inferPhase(functionName)
            n = lower(string(functionName));
            if contains(n, "_tx") || contains(n, "tx")
                phase = "TX";
            elseif contains(n, "_rx") || contains(n, "rx")
                phase = "RX";
            elseif contains(n, "decode") || contains(n, "ldpc")
                phase = "DECODING";
            elseif contains(n, "sched")
                phase = "SCHEDULER";
            else
                phase = "GENERAL";
            end
        end
    end
end
