function ok = testChannelEstimateWienerCompatibility()
%TESTCHANNELESTIMATEWIENERCOMPATIBILITY Guard nrChannelEstimate interpolation API.

setup6GRSimToolkit("Verbose", false);
if exist("nrChannelEstimate", "file") ~= 2 || exist("nrPDSCHDMRS", "file") ~= 2
    ok = true;
    return;
end

carrier = nrCarrierConfig;
carrier.NCellID = 17;
carrier.SubcarrierSpacing = 30;
carrier.NSizeGrid = 12;

pdsch = nrPDSCHConfig;
pdsch.PRBSet = 0:(carrier.NSizeGrid - 1);
pdsch.SymbolAllocation = [0 14];
pdsch.MappingType = "A";
pdsch.NumLayers = 1;

refInd = nrPDSCHDMRSIndices(carrier, pdsch);
refSym = nrPDSCHDMRS(carrier, pdsch);
rxGrid = nrResourceGrid(carrier, 1);
[k, l] = ind2sub([size(rxGrid, 1), size(rxGrid, 2)], refInd);
hPilot = (0.9 + 5e-4 .* double(k)) .* exp(1i .* 0.025 .* double(l));
rxGrid(refInd) = refSym .* cast(hPilot, "like", refSym);

[Hest, nVar, info] = sixgr.phy.rx.channelEstimate( ...
    carrier, rxGrid, refInd, refSym, ...
    "Method", "wiener", ...
    "ChannelModel", "TDL-C", ...
    "ExpectedTxPorts", 1, ...
    "ContextLabel", "testChannelEstimateWienerCompatibility");

[Href, nVarRef] = nrChannelEstimate( ...
    carrier, rxGrid, refInd, refSym, ...
    "Interpolation", "on", ...
    "AveragingWindow", [0 0]);

assert(isequal(size(Hest), size(Href)) && ...
    isequal([size(Hest, 1), size(Hest, 2)], [size(rxGrid, 1), size(rxGrid, 2)]), ...
    "Wiener estimation must return the resource-selective nrChannelEstimate grid.");
assert(all(isfinite(real(Hest(:)))) && all(isfinite(imag(Hest(:)))), ...
    "Wiener estimation returned non-finite channel coefficients.");
assert(isequaln(Hest, Href) && isequaln(nVar, nVarRef), ...
    "The Wiener wrapper must match nrChannelEstimate with Interpolation='on'.");
assert(strcmp(string(info.EngineUsed), "nrChannelEstimate"), ...
    "Wiener estimation must remain on the exact nrChannelEstimate engine.");
assert(strcmp(string(info.InterpolationMethod), "on"), ...
    "Wiener estimation must record the release-compatible Interpolation='on' policy.");
assert(~logical(info.ScalarFastPathUsed), ...
    "Wiener estimation on a fading profile must not use the scalar fast path.");

fprintf("ChannelEstimateWienerCompatibility: MATLAB %s accepted Interpolation='on'.\n", ...
    version("-release"));
ok = true;
end
