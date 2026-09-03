function ok = testMultiPortChannelEstimatePilotDiagnostics()
%TESTMULTIPORTCHANNELESTIMATEPILOTDIAGNOSTICS Reconstruct CDM pilots jointly.

setup6GRSimToolkit("Verbose", false);

carrier = nrCarrierConfig;
carrier.NCellID = 41;
carrier.NSizeGrid = 6;
carrier.SubcarrierSpacing = 30;
carrier.CyclicPrefix = "normal";
carrier.NSlot = 0;

pdsch = nrPDSCHConfig;
pdsch.PRBSet = 0:5;
pdsch.SymbolAllocation = [0 14];
pdsch.MappingType = "A";
pdsch.Modulation = "QPSK";
pdsch.NumLayers = 2;
pdsch.DMRS.DMRSConfigurationType = 1;
pdsch.DMRS.DMRSTypeAPosition = 2;
pdsch.DMRS.DMRSAdditionalPosition = 1;
pdsch.DMRS.DMRSLength = 1;
pdsch.DMRS.NumCDMGroupsWithoutData = 2;
pdsch.DMRS.DMRSPortSet = [0 1];

refInd = nrPDSCHDMRSIndices(carrier, pdsch);
refSym = nrPDSCHDMRS(carrier, pdsch);
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
R = 2;
P = 2;
H = [0.82 + 0.11i, 0.24 - 0.08i; ...
     -0.17 + 0.05i, 0.71 + 0.19i];
trueGrid = repmat(reshape(H, [1 1 R P]), K, L, 1, 1);
rxFlat = complex(zeros(K * L, R));
indices = double(refInd(:));
symbols = double(refSym(:));
physical = mod(indices - 1, K * L) + 1;
ports = floor((indices - 1) ./ (K * L)) + 1;
for ii = 1:numel(indices)
    rxFlat(physical(ii), :) = rxFlat(physical(ii), :) + ...
        H(:, ports(ii)).' .* symbols(ii);
end
rxGrid = reshape(rxFlat, K, L, R);

[~, nVar, info] = sixgr.phy.rx.channelEstimate( ...
    carrier, rxGrid, refInd, refSym, ...
    "CDMLengths", [2 1], "ExpectedTxPorts", P, ...
    "TrueChannel", trueGrid, "OracleTestMode", true, ...
    "EffectiveChannelConvention", "rx_by_tx_resource_grid", ...
    "ContextLabel", "multiport_cdm_diagnostic_test");

assert(isfinite(double(nVar)) && nVar >= 0, ...
    "The practical estimator must return a finite disturbance variance.");
assert(double(info.PilotReferencePortCount) == P, ...
    "Pilot diagnostics must retain both CDM reference ports.");
assert(isfinite(double(info.PilotResidualNMSE_dB)) && ...
    double(info.PilotResidualNMSE_dB) < -100, ...
    "Joint multi-port pilot reconstruction must be near exact without noise.");
assert(isfinite(double(info.OracleNMSE_dB)) && ...
    double(info.OracleNMSE_dB) < -100, ...
    sprintf("The focused oracle NMSE is %.6g dB; expected below -100 dB.", ...
        double(info.OracleNMSE_dB)));

ok = true;
end
