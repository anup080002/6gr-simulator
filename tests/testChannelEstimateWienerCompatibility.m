function ok = testChannelEstimateWienerCompatibility()
%TESTCHANNELESTIMATEWIENERCOMPATIBILITY Guard nrChannelEstimate interpolation API.

setup6GRSimToolkit("Verbose", false);
assert(exist("nrChannelEstimate", "file") == 2 && exist("nrPDSCHDMRS", "file") == 2, ...
    'test:Missing5GToolbox','This receiver compatibility test requires the actual 5G Toolbox.');
installed=ver('5g');
assert(isscalar(installed),'test:Missing5GToolbox','Require the actual installed toolbox version.');
for versionText=["2.4","24.1","24.2"]
    [legacyOptions,legacy]=sixgr.phy.rx.channelEstimateWienerOptions(versionText);
    assert(isequal(legacyOptions,{'AveragingWindow',[0 0]}) && ...
        ~legacy.InterpolationOptionForwarded && legacy.InterpolationMode=="on" && ...
        legacy.FiveGToolboxVersion==versionText && ...
        legacy.Policy=="legacy_native_always_interpolating_API");
end
for versionText=["25.1","25.2","26.1"]
    [modernOptions,modern]=sixgr.phy.rx.channelEstimateWienerOptions(versionText);
    assert(isequal(modernOptions,{'Interpolation','on','AveragingWindow',[0 0]}) && ...
        modern.InterpolationOptionForwarded && modern.InterpolationMode=="on");
end
for invalid=["","R2024a","25","25.1x","-1.0"]
    caught=false;
    try
        sixgr.phy.rx.channelEstimateWienerOptions(invalid);
    catch ME
        caught=strcmp(ME.identifier,'sixgr:phy:channelEstimate:InvalidToolboxVersion');
    end
    assert(caught,'Reject malformed or inferred toolbox-version authority.');
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

% This documented default-on call is valid on R2024a and newer APIs.
[Href, nVarRef] = nrChannelEstimate(carrier,rxGrid,refInd,refSym,'AveragingWindow',[0 0]);
[actualOptions,actualCapability]=sixgr.phy.rx.channelEstimateWienerOptions(installed.Version);
[Hactual,nActual]=nrChannelEstimate(carrier,rxGrid,refInd,refSym,actualOptions{:});
assert(isequaln(Hactual,Href) && isequaln(nActual,nVarRef), ...
    'Version-selected public options must preserve native default-on arithmetic.');

assert(isequal(size(Hest), size(Href)) && ...
    isequal([size(Hest, 1), size(Hest, 2)], [size(rxGrid, 1), size(rxGrid, 2)]), ...
    "Wiener estimation must return the resource-selective nrChannelEstimate grid.");
assert(all(isfinite(real(Hest(:)))) && all(isfinite(imag(Hest(:)))), ...
    "Wiener estimation returned non-finite channel coefficients.");
assert(isequaln(Hest, Href) && isequaln(nVar, nVarRef), ...
    "The Wiener wrapper must match the documented native interpolation-on behavior.");
assert(strcmp(string(info.EngineUsed), "nrChannelEstimate"), ...
    "Wiener estimation must remain on the exact nrChannelEstimate engine.");
assert(strcmp(string(info.InterpolationMethod), "on"), ...
    "Wiener estimation must retain its applied interpolation-on policy.");
assert(isequaln(info.NativeInterpolationCompatibility,actualCapability), ...
    'Retain actual installed API capability and exact forwarded-option metadata.');
assert(~logical(info.ScalarFastPathUsed), ...
    "Wiener estimation on a fading profile must not use the scalar fast path.");
assert(any(abs(Hest(:)-Hest(1))>1e-9), ...
    'Resource-dependent pilot observations must not collapse to one full-grid scalar.');

fprintf("ChannelEstimateWienerCompatibility: executed MATLAB %s, 5G %s, option forwarded=%d; legacy option-contract checks are not legacy-runtime execution.\n", ...
    version("-release"),installed.Version,actualCapability.InterpolationOptionForwarded);
ok = true;
end
