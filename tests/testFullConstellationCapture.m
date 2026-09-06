function ok = testFullConstellationCapture()
% Full evidence cannot be downgraded to preview or inferred from port grids.
setup6GRSimToolkit('Verbose', false);
repo = fileparts(fileparts(mfilename('fullpath')));
for scenario = ["lls_causal_access_to_data_wiring_tdd.yaml", "lls_causal_access_to_data_wiring.yaml"]
    scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(repo, 'simulator', 'configs', 'scenarios', scenario));
    cfg = sixgr.lls6g.buildInternalConfig(scfg, tempname);
    assert(cfg.outputs.constellationCaptureScope == "full_allocation");
end
carrier = nrCarrierConfig('NSizeGrid', 6);
indices = (1:600).' + (0:4)*(12*carrier.NSizeGrid*carrier.SymbolsPerSlot);
order = sixgr.phy.resource.buildSymbolOrderingMap(carrier, indices, 'layer');
reference = reshape(repmat(nrSymbolModulate(int8([0;0;0;1;1;0;1;1]), 'QPSK'), 750, 1), 600, 5);
tx = struct('PDSCH', struct('Modulation', 'QPSK'), ...
    'PDSCHLayerSymbolsForEvidence', reference, 'LayerSymbolDomain', 'layer', ...
    'LayerSymbolOrder', order, 'QAMSymbolCount', numel(reference), ...
    'CodewordLayerMapping', struct('CodewordIndexByLayer', [0 0 1 1 1]));
rx = struct('LayerEqualizedSymbolsForEvidence', reference*1.1, ...
    'EqualizedSymbolDomain', 'layer', 'LayerSymbolOrder', order);
cfg = struct('outputs', struct('constellationCaptureScope', 'full_allocation'));
[metrics, samples] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, 'DL');
assert(height(samples) == 3000 && all(samples.CapturedSymbolCount == 3000));
assert(all(samples.ObservationSymbolCount == 3000));
assert(all(samples.CaptureScope == "full_allocation_paired_symbols"));
assert(abs(metrics.EVM_rms - 0.1) < 1e-12);
assert(isequal(samples.LayerIndex, order.LayerIndex(:)));
assert(isequal(samples.OFDMSymbolIndex, order.OFDMSymbolIndex(:)));
assert(isequal(samples.CodewordIndex, repelem([0;0;1;1;1], 600)));
mixedTx = tx;
mixedTx.PDSCH.Modulation = ["QPSK", "16QAM"];
qam16 = nrSymbolModulate(int8(reshape(dec2bin(0:15, 4).'-'0', [], 1)), '16QAM');
qamStream = repmat(qam16, 113, 1);
mixedTx.PDSCHLayerSymbolsForEvidence(:, 3:5) = reshape(qamStream(1:1800), 600, 3);
mixedRx = rx;
mixedRx.LayerEqualizedSymbolsForEvidence = mixedTx.PDSCHLayerSymbolsForEvidence * 1.1;
[mixedMetrics, mixedSamples] = sixgr.link.deriveModulationTrackingMetrics(mixedTx, mixedRx, cfg, 'DL');
assert(all(mixedSamples.Modulation(mixedSamples.CodewordIndex == 0) == "QPSK"));
assert(all(mixedSamples.Modulation(mixedSamples.CodewordIndex == 1) == "16QAM"));
assert(isnan(mixedMetrics.ModulationOrderQm), 'A mixed codeword allocation has no single Qm.');
assert(abs(mixedMetrics.EVM_rms - 0.1) < 1e-12);
previewCfg = cfg;
previewCfg.outputs.constellationCaptureScope = 'preview';
[~, preview] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, previewCfg, 'DL');
assert(height(preview) == 512 && all(preview.ObservationSymbolCount == 3000));
assert(all(preview.CaptureScope == "paired_sample_preview"));
badTx = tx;
badTx.QAMSymbolCount = 3001;
localReject(@() sixgr.link.deriveModulationTrackingMetrics(badTx, rx, cfg, 'DL'), ...
    'sixgr:link:IncompleteConstellationAllocation');
badTx = tx;
badTx.LayerSymbolOrder = rmfield(order, 'OFDMSymbolIndex');
localReject(@() sixgr.link.deriveModulationTrackingMetrics(badTx, rx, cfg, 'DL'), ...
    'sixgr:link:IncompleteConstellationOrdering');
badTx = tx;
badTx = rmfield(badTx, 'CodewordLayerMapping');
localReject(@() sixgr.link.deriveModulationTrackingMetrics(badTx, rx, cfg, 'DL'), ...
    'sixgr:link:MissingConstellationCodewordMapping');
cfg.outputs.constellationCaptureScope = 'silently_truncate';
localReject(@() sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, 'DL'), ...
    'sixgr:link:InvalidConstellationCaptureScope');
ok = true;
fprintf('FullConstellationCapture PASS: YAML authority, 3000 paired symbols, codewords, fail-closed coverage.\n');
end

function localReject(action, identifier)
try
    action();
catch ME
    assert(strcmp(ME.identifier, identifier), 'Unexpected error: %s', ME.message);
    return;
end
error('testFullConstellationCapture:MissingError', 'Expected rejection %s.', identifier);
end
