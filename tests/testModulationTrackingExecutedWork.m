function ok = testModulationTrackingExecutedWork()
% Executed equalizer work is not a frequency/time-grid size proxy.
% Component measurement contract, not a decoder FLOP/conformance claim.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg = sixgr.config.defaultConfig();
reference = repmat([1+1i -1+1i; -1-1i 1-1i]/sqrt(2),6,1);
nRE = size(reference,1);
channel = repmat(reshape(eye(2),1,2,2),nRE,1,1);
[equalized,~,executed] = sixgr.phy.rx.equalizeMMSE(reference,channel,.01);
names = ["EqualizerSolveCount","EqualizerUniqueSolveCount", ...
    "EqualizerCovarianceFactorizationCount"];
expected = [executed.SolveCount,executed.UniqueSolveCount, ...
    executed.CovarianceFactorizationCount];
for direction = ["DL","UL"]
    tx = struct('LayerSymbolDomain','layer');
    if direction == "DL"
        tx.PDSCH = struct('Modulation','QPSK');
        tx.PDSCHLayerSymbolsForEvidence = reference;
    else
        tx.PUSCH = struct('Modulation','QPSK');
        tx.PUSCHLayerSymbolsForEvidence = reference;
    end
    rx = struct('LayerEqualizedSymbolsForEvidence',equalized, ...
        'EqualizedSymbolDomain','layer');
    for index = 1:numel(names)
        rx.(names(index)) = expected(index);
    end
    % Padding the diagnostic channel grid cannot change work already done
    % by the actual extracted-RE equalizer above.
    for subcarriers = [12 24]
        rx.ChannelEstimate = repmat(reshape(eye(2),1,1,2,2),subcarriers,14,1,1);
        measured = sixgr.link.deriveModulationTrackingMetrics(tx,rx,cfg,direction);
        assert(isnan(measured.DetectorComplexityUnits), ...
            'test:UnmeasuredDetectorOperations', ...
            'Grid dimensions must not be exported as measured detector operations.');
        for index = 1:numel(names)
            assert(isfield(measured,names(index)) && ...
                measured.(names(index)) == expected(index), ...
                'test:ExecutedEqualizerWorkMissing', ...
                'Retain actual receiver counter %s without a shape-derived replacement.',names(index));
        end
    end
    rx = rmfield(rx,cellstr(names));
    measured = sixgr.link.deriveModulationTrackingMetrics(tx,rx,cfg,direction);
    for index = 1:numel(names)
        assert(isfield(measured,names(index)) && isnan(measured.(names(index))), ...
            'test:UnknownEqualizerWorkFabricated', ...
            'Absent executed counter %s must not become a zero or inferred count.',names(index));
    end
end
ok = true;
fprintf('MODULATION_TRACKING_EXECUTED_WORK_PASS: DL/UL use executed equalizer counters, not grid-size operations.\n');
end
