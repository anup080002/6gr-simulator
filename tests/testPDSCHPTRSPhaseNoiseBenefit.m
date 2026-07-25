function ok = testPDSCHPTRSPhaseNoiseBenefit()
%TESTPDSCHPTRSPHASENOISEBENEFIT Exercise production PT-RS CPE correction.
%
% A deterministic oscillator phase-noise realization is scaled to four
% severities and applied as symbol-wise CPE.  PT-RS references and indices
% come from the production reference-signal path.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
carrier = nrCarrierConfig;
carrier.NSizeGrid = 24;
carrier.SubcarrierSpacing = 30;
carrier.NCellID = 73;
carrier.NSlot = 5;
pdsch = nrPDSCHConfig;
pdsch.PRBSet = 0:23;
pdsch.SymbolAllocation = [0 14];
pdsch.MappingType = "A";
pdsch.NumLayers = 1;
pdsch.Modulation = "64QAM";
pdsch.RNTI = 144;
pdsch.NID = 73;
pdsch.DMRS.DMRSConfigurationType = 1;
pdsch.DMRS.DMRSLength = 1;
pdsch.DMRS.DMRSAdditionalPosition = 1;
pdsch.DMRS.DMRSTypeAPosition = 2;
pdsch.DMRS.DMRSPortSet = 0;
pdsch.EnablePTRS = true;
pdsch.PTRS.TimeDensity = 1;
pdsch.PTRS.FrequencyDensity = 2;
pdsch.PTRS.REOffset = "00";
pdsch.PTRS.PTRSPortSet = 0;

[ptrsInd, ptrsSym] = sixgr.phy.refsig.ptrsPDSCH( ...
    carrier, pdsch, "IndexBase", "1based");
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPDSCH( ...
    carrier, pdsch, "IndexBase", "1based");
assert(~isempty(ptrsInd) && ~isempty(ptrsSym), ...
    "Production PT-RS reference path returned no resources.");

K = carrier.NSizeGrid * 12;
L = carrier.SymbolsPerSlot;
rng(907, "twister");
bitsI = 2 * randi([0 1], K, L) - 1;
bitsQ = 2 * randi([0 1], K, L) - 1;
txGrid = complex(bitsI, bitsQ) / sqrt(2);
txGrid(ptrsInd) = ptrsSym;
txGrid(dmrsInd) = dmrsSym;
dataMask = true(K, L);
dataMask(ptrsInd) = false;
dataMask(dmrsInd) = false;
[~, ptrsSymbols] = ind2sub([K L], double(ptrsInd(:)));
observedSymbols = unique(ptrsSymbols(:)).';
symbolMask = false(1, L);
symbolMask(observedSymbols) = true;
measureMask = dataMask & repmat(symbolMask, K, 1);
assert(any(measureMask, "all"), ...
    "PT-RS phase-noise test has no data RE on corrected symbols.");

rng(991, "twister");
unitTrajectory = cumsum(randn(1, L));
severity = [0 0.02 0.08 0.18];
evmBefore = zeros(size(severity));
evmAfter = zeros(size(severity));
cpeBefore = zeros(size(severity));
cpeAfter = zeros(size(severity));
for i = 1:numel(severity)
    phase = severity(i) .* unitTrajectory;
    impaired = txGrid .* exp(1j * phase);
    [corrected, estimated, info] = ...
        sixgr.phy.rx.correctCPEFromPTRS( ...
        impaired, ptrsInd, ptrsSym, carrier);
    assert(info.Enabled && ...
        info.NumSymbolsCorrected == numel(observedSymbols), ...
        "Production PT-RS correction was not applied at severity %.3g.", ...
        severity(i));

    evmBefore(i) = localEVM(impaired(measureMask), ...
        txGrid(measureMask));
    evmAfter(i) = localEVM(corrected(measureMask), ...
        txGrid(measureMask));
    cpeBefore(i) = localMeanCPE(impaired, txGrid, ...
        measureMask, observedSymbols);
    cpeAfter(i) = localMeanCPE(corrected, txGrid, ...
        measureMask, observedSymbols);
    assert(all(isfinite(estimated(observedSymbols))), ...
        "PT-RS CPE estimates are nonfinite at severity %.3g.", severity(i));
    assert(evmAfter(i) <= evmBefore(i) + 1e-10 && ...
        cpeAfter(i) <= cpeBefore(i) + 1e-10, ...
        "PT-RS worsened EVM or CPE at severity %.3g.", severity(i));
end
assert(all(evmAfter(2:end) < evmBefore(2:end) - 1e-6) && ...
    all(cpeAfter(2:end) < cpeBefore(2:end) - 1e-6), ...
    "PT-RS must improve both EVM and CPE at every nonzero severity.");
assert(all(evmAfter < 1e-8) && all(cpeAfter < 1e-8), ...
    "Exact common-phase PT-RS correction left excess residual error.");
ok = true;
end

function value = localEVM(observed, reference)
value = 100 * sqrt(mean(abs(observed(:) - reference(:)).^2) / ...
    mean(abs(reference(:)).^2));
end

function value = localMeanCPE(observed, reference, mask, symbols)
values = zeros(numel(symbols), 1);
for i = 1:numel(symbols)
    l = symbols(i);
    active = mask(:, l);
    values(i) = abs(angle(sum(observed(active, l) .* ...
        conj(reference(active, l)))));
end
value = mean(values);
end
