function ok = testReceiverEVMReferenceNormalization()
% Reporting must not use TX payload knowledge to repair receiver symbols.
setup6GRSimToolkit('Verbose', false, 'RunToolboxChecks', false);
ref = nrSymbolModulate(int8(reshape(dec2bin(0:15, 4).'-'0', [], 1)), '16QAM');
for duplex = ["TDD", "FDD"]
    for direction = ["DL", "UL"]
        for scale = [1e-10, 1, 10]
            reference = scale * ref;
            for gain = [1, 1.2, exp(1i*pi/6), 0]
                measured = gain * reference;
                [metrics, samples] = localMeasure(reference, measured, duplex, direction);
                evm = comm.EVM('Normalization', 'Average reference signal power', ...
                    'ReferenceSignalSource', 'Input port');
                expected = evm(reference, measured) / 100;
                assert(abs(metrics.EVM_rms - expected) < 1e-12, ...
                    'Actual receiver EVM must equal independent comm.EVM, including gain/phase errors.');
                assert(abs(metrics.EVM_rms - abs(gain-1)) < 1e-12);
                assert(isequal(complex(samples.EqualizedReal, samples.EqualizedImag), measured), ...
                    'Reporter must preserve the actual receiver symbols without payload fitting.');
                assert(isequal(samples.EqualizedReal, samples.RawEqualizedReal) && ...
                    isequal(samples.EqualizedImag, samples.RawEqualizedImag));
                assert(all(samples.Normalization == metrics.EVMComputationDomain));
                assert(all(samples.EqualizationSource == "receiver_output_without_payload_gain_or_phase_fit"));
                assert(all(samples.ObservationSymbolCount == numel(reference)));
                assert(max(abs(samples.SymbolEVM_rms - abs(measured-reference) / ...
                    sqrt(mean(abs(reference).^2)))) < 1e-12);
            end
        end
        % A quarter-turn QPSK error is not corrected by a payload phase fit.
        qpsk = nrSymbolModulate(int8([0;0;0;1;1;0;1;1]), 'QPSK');
        metrics = localMeasure(qpsk, 1i*qpsk, duplex, direction, 'QPSK');
        assert(metrics.SymbolErrors == numel(qpsk) && metrics.SymbolErrorRate == 1);
        assert(abs(metrics.EVM_rms-sqrt(2)) < 1e-12);

        % The preview must use the full observation's reference power, not
        % the first 512 symbols or each individual QAM radius.
        reference = [repmat(ref(1), 512, 1); ref];
        measured = reference + 0.07 + 0.03i;
        [metrics, samples] = localMeasure(reference, measured, duplex, direction);
        expected = abs(0.07+0.03i) / sqrt(mean(abs(reference).^2));
        assert(abs(metrics.EVM_rms-expected) < 1e-12);
        assert(height(samples) == 512 && all(samples.CaptureScope == "paired_sample_preview"));
        assert(all(samples.ObservationSymbolCount == numel(reference)));
        assert(max(abs(samples.SymbolEVM_rms-expected)) < 1e-12);

        for invalid = [NaN, Inf]
            broken = ref;
            broken(end) = invalid;
            localAssertNonfinite(@() localMeasure(ref, broken, duplex, direction));
            localAssertNonfinite(@() localMeasure(broken, ref, duplex, direction));
        end
    end
end
ok = true;
fprintf('ReceiverEVMReferenceNormalization PASS: DL/UL, TDD/FDD, gain/phase/zero/tiny power, invalid samples.\n');
end

function [metrics, samples] = localMeasure(ref, measured, duplex, direction, modulation)
if nargin < 5, modulation = '16QAM'; end
cfg = struct('duplexMode', duplex);
tx = struct('LayerSymbolDomain', 'layer');
if direction == "DL"
    tx.PDSCH = struct('Modulation', modulation);
    tx.PDSCHLayerSymbolsForEvidence = ref;
else
    tx.PUSCH = struct('Modulation', modulation);
    tx.PUSCHLayerSymbolsForEvidence = ref;
end
rx = struct('LayerEqualizedSymbolsForEvidence', measured, 'EqualizedSymbolDomain', 'layer');
[metrics, samples] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, direction);
end

function localAssertNonfinite(action)
try
    action();
catch ME
    assert(strcmp(ME.identifier, 'sixgr:link:NonfiniteSymbolEvidence'), ...
        'Invalid samples must fail at the evidence boundary, not be silently omitted.');
    return;
end
error('testReceiverEVMReferenceNormalization:MissingError', 'Nonfinite samples were accepted.');
end
