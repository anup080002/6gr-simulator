classdef ComplexityAnalyzer
    %COMPLEXITYANALYZER Lightweight operation/memory estimates for PHY stages.
    %
    % The estimates are intentionally transparent engineering estimates for
    % runtime profiling. They are not promoted to PHY truth metrics.

    methods (Static)
        function [flops, bytes, note] = estimate(functionName, meta)
            if nargin < 2 || ~isstruct(meta)
                meta = struct();
            end
            name = lower(string(functionName));
            nRE = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NRE","NumRE","ResourceElements"], NaN);
            nSub = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NSubcarriers","Subcarriers"], NaN);
            nSym = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NSymbols","Symbols"], NaN);
            nRx = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NRx","NumRxAnt","ReceiveAntennas"], 1);
            nTx = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NTx","NumTxAnt","TransmitAntennas","NumPorts"], 1);
            nLayers = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NLayers","Layers"], min(nRx, nTx));
            nSamples = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NSamples","Samples"], NaN);
            fftSize = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["FFTSize","NFFT"], NaN);
            nFrames = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NumFrames","Frames","Slots"], 1);
            modOrder = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["ModulationOrder","Qm"], NaN);
            tbBits = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["TBSBits","TransportBlockSize"], NaN);
            iterations = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["Iterations","MaxIterations"], 8);

            flops = NaN;
            bytes = NaN;
            note = "estimate_unavailable";

            if contains(name, "applywaveformimpairments")
                if isfinite(nSamples)
                    flops = 12 * nSamples;
                    bytes = 2 * nSamples * 16;
                    note = "sample_domain_gain_phase_cfo_timing_estimate";
                end
                return;
            end

            if contains(name, "mimodetect")
                if ~isfinite(nRE)
                    nRE = max(1, nSub) * max(1, nSym);
                end
                if isfinite(nRE)
                    flops = nRE * (8 * nRx * nTx * max(nLayers, 1) + 20 * max(nLayers, 1)^3);
                    bytes = nRE * max(nRx + nRx * nTx + nLayers, 1) * 16;
                    note = "linear_mimo_equalizer_matrix_estimate";
                end
                return;
            end

            if contains(name, "computeposteqsinr")
                if ~isfinite(nRE)
                    nRE = max(1, nSub) * max(1, nSym);
                end
                if isfinite(nRE)
                    flops = nRE * max(nRx * nTx * 10, 1);
                    bytes = nRE * max(nRx * nTx, 1) * 16;
                    note = "post_equalization_sinr_estimate";
                end
                return;
            end

            if contains(name, "pdsch_rx") || contains(name, "pusch_rx")
                if ~isfinite(nRE)
                    nRE = max(1, nSub) * max(1, nSym);
                end
                if isfinite(nRE)
                    if ~isfinite(modOrder)
                        modOrder = 6;
                    end
                    if ~isfinite(tbBits)
                        tbBits = nRE * max(modOrder, 1) * max(nLayers, 1);
                    end
                    ceEq = nRE * max(nRx * nTx, 1) * 20;
                    demod = nRE * max(modOrder, 1) * max(nLayers, 1) * 6;
                    decoder = tbBits * max(iterations, 1) * 8;
                    flops = ceEq + demod + decoder;
                    bytes = (nRE * max(nRx + nRx * nTx + nLayers, 1) * 16) + tbBits / 8;
                    note = "ofdm_channel_estimation_equalization_demod_ldpc_estimate";
                end
                return;
            end

            if contains(name, "run_dl_pdsch") || contains(name, "rundlpdsch")
                if isfinite(nFrames)
                    flops = nFrames * 1e6;
                    bytes = nFrames * 1e5;
                    note = "outer_dl_trial_loop_estimate";
                end
                return;
            end

            if contains(name, "run_ul_pusch") || contains(name, "runulpusch")
                if isfinite(nFrames)
                    flops = nFrames * 1e6;
                    bytes = nFrames * 1e5;
                    note = "outer_ul_trial_loop_estimate";
                end
                return;
            end

            if contains(name, "prach")
                candidates = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["CandidatePreambles","NumCandidates"], 64);
                if ~isfinite(nSamples)
                    nSamples = max(1, nSub) * max(1, nSym);
                end
                if isfinite(nSamples)
                    flops = candidates * nSamples * 8;
                    bytes = candidates * nSamples * 16;
                    note = "prach_correlation_search_estimate";
                end
                return;
            end

            if contains(name, "scheduler")
                nUE = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NumUE","UEs"], NaN);
                nPRB = sixgr.perf.ComplexityAnalyzer.scalar(meta, ["NumPRB","PRBs"], NaN);
                if isfinite(nUE) && isfinite(nPRB)
                    flops = nUE * max(nPRB, 1) * 12;
                    bytes = nUE * 256;
                    note = "pf_scheduler_metric_scan_estimate";
                end
                return;
            end
        end

        function value = scalar(meta, names, defaultValue)
            value = defaultValue;
            if nargin < 3
                defaultValue = NaN;
            end
            names = string(names);
            for i = 1:numel(names)
                raw = sixgr.util.structGet(meta, names(i), []);
                if isempty(raw)
                    continue;
                end
                if isnumeric(raw) || islogical(raw)
                    raw = double(raw);
                    raw = raw(:);
                    raw = raw(isfinite(raw));
                    if ~isempty(raw)
                        value = double(raw(1));
                        return;
                    end
                end
            end
        end
    end
end
