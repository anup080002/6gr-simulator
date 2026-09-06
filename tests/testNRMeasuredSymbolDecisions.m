function ok = testNRMeasuredSymbolDecisions()
% NR hard decisions must not learn their alphabet/bit labels from TX data.
setup6GRSimToolkit('Verbose', false, 'RunToolboxChecks', false);
for duplex = ["TDD", "FDD"]
    for direction = ["DL", "UL"]
        for modulation = ["BPSK", "QPSK", "16QAM", "64QAM", "256QAM", "1024QAM", "pi/2-BPSK"]
            if modulation == "pi/2-BPSK" && direction == "DL", continue; end
            qm = localQm(modulation);
            % Deliberately sparse payload: most legal constellation points
            % never occur in TX. RX errors may land on any legal point.
            bits = zeros(37*qm, 1, 'int8');
            bits(qm+1:2*qm) = 1;
            badBits = bits;
            badBits(3*qm+(1:qm)) = 1;
            badBits(7*qm+1) = 1;
            ref = nrSymbolModulate(bits, modulation);
            received = nrSymbolModulate(badBits, modulation);
            [metrics, samples] = localMeasure(ref, received, modulation, duplex, direction);
            assert(metrics.SymbolErrors == 2 && metrics.SymbolsCompared == 37);
            assert(metrics.SymbolDecisionBitErrors == qm+1);
            assert(metrics.SymbolDecisionBitsCompared == numel(bits));
            assert(abs(metrics.SymbolDecisionBitErrorRate-(qm+1)/numel(bits)) < 1e-12);
            assert(metrics.SymbolDecisionStatus == "measured_nr_hard_decision");
            assert(all(samples.SymbolDecisionStatus == metrics.SymbolDecisionStatus));
            % Reorder the payload and errors: diagnostics must not depend on
            % the order in which constellation points first appeared.
            if modulation ~= "pi/2-BPSK"
                reversed = localMeasure(flipud(ref), flipud(received), modulation, duplex, direction);
                assert(reversed.SymbolErrors == 2 && reversed.SymbolDecisionBitErrors == qm+1);
            end
        end
        ref = nrSymbolModulate(int8([0;0;0;1;1;0;1;1]), 'QPSK');
        metrics = localMeasure(10*ref, 11*ref, 'QPSK', duplex, direction);
        assert(abs(metrics.EVM_rms-0.1) < 1e-12);
        assert(isnan(metrics.SymbolErrorRate) && isnan(metrics.SymbolDecisionBitErrorRate));
        assert(metrics.SymbolDecisionStatus == "unavailable_reference_not_nr_normalized");
        % A study constellation is not silently assigned a guessed NR map.
        metrics = localMeasure(ref, ref, '4096QAM', duplex, direction);
        assert(metrics.EVM_rms == 0 && isnan(metrics.SymbolErrorRate));
        assert(metrics.SymbolDecisionStatus == "unavailable_unsupported_nr_constellation");
    end
end
ok = true;
fprintf('NRMeasuredSymbolDecisions PASS: sparse alphabet, NR bit labels, payload order, explicit unavailable mapping.\n');
end

function [metrics, samples] = localMeasure(ref, received, modulation, duplex, direction)
cfg = struct('duplexMode', duplex);
tx = struct('LayerSymbolDomain', 'layer');
if direction == "DL"
    tx.PDSCH = struct('Modulation', modulation);
    tx.PDSCHLayerSymbolsForEvidence = ref;
else
    tx.PUSCH = struct('Modulation', modulation);
    tx.PUSCHLayerSymbolsForEvidence = ref;
end
rx = struct('LayerEqualizedSymbolsForEvidence', received, 'EqualizedSymbolDomain', 'layer');
[metrics, samples] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, direction);
end

function qm = localQm(modulation)
switch modulation
    case {"BPSK", "pi/2-BPSK"}, qm = 1;
    case "QPSK", qm = 2;
    case "16QAM", qm = 4;
    case "64QAM", qm = 6;
    case "256QAM", qm = 8;
    case "1024QAM", qm = 10;
end
end
