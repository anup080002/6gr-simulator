function ok = testAntennaPortArchitectureContracts()
%TESTANTENNAPORTARCHITECTURECONTRACTS Keep elements, ports, RF chains and power separate.

setup6GRSimToolkit("Verbose", false);

cfgDL = sixgr.config.defaultConfig();
cfgDL.phy.bsArray = [8 8 1];
cfgDL.phy.nTxAnt = 64;
cfgDL.channel.nTxAnt = 64;
cfgDL.scenario.bs.nTxAnt = 64;
cfgDL.phy.pdsch.numPorts = 2;
cfgDL.phy.pdsch.nPorts = 2;
cfgDL.phy.pdsch.precoding.matrix = eye(2);
pdsch = nrPDSCHConfig;
pdsch.NumLayers = 2;
pdsch.Modulation = "QPSK";
pdsch.PRBSet = 0:5;
pdsch.SymbolAllocation = [0 14];
pdsch.DMRS.DMRSPortSet = 0:1;
precDL = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfgDL, "FixedReferenceMode", true);
assert(precDL.NumElements == 64 && precDL.NumPorts == 2 && precDL.NumRFChains == 2, ...
    "DL precoding must keep 64 physical elements separate from 2 logical PDSCH ports/RF chains.");
assert(isequal(size(precDL.PortToElementMatrix), [64 2]) && isequal(size(precDL.MatrixPorts), [2 2]), ...
    "DL element-port and port-layer matrices have incorrect dimensions.");
assert(abs(precDL.PrecoderTraceWWH - 2) < 1e-12 && precDL.TotalPowerPreservingTrace, ...
    "DL precoder must satisfy trace(W*W'')=NumLayers for the identity 2-port contract.");

cfgUL = sixgr.config.defaultConfig();
cfgUL.phy.ueArray = [2 2 1];
cfgUL.scenario.ue.nTxAnt = 4;
cfgUL.antenna.ue.numElements = 4;
cfgUL.phy.pusch.NumAntennaPorts = 2;
cfgUL.phy.pusch.numAntennaPorts = 2;
cfgUL.phy.pusch.numPorts = 2;
pusch = nrPUSCHConfig;
pusch.NumLayers = 1;
pusch.NumAntennaPorts = 2;
pusch.TransmissionScheme = "codebook";
pusch.TPMI = 0;
precUL = sixgr.phy.ul.resolvePUSCHPrecoding(pusch, cfgUL, "FixedReferenceMode", true);
assert(precUL.NumElements == 4 && precUL.NumPorts == 2 && precUL.NumRFChains == 2, ...
    "UL precoding must keep 4 UE elements separate from 2 PUSCH ports/RF chains.");
assert(isequal(size(precUL.PortToElementMatrix), [4 2]) && isequal(size(precUL.MatrixPorts), [2 1]), ...
    "UL element-port and port-layer matrices have incorrect dimensions.");
assert(abs(precUL.PrecoderRawTraceWWH - 0.5) < 1e-12, ...
    "UL raw Toolbox codebook trace must be exposed without relabeling it as total-power preserving.");
assert(abs(precUL.PrecoderNormalizedTraceWWH - 1) < 1e-12 && precUL.TotalPowerPreservingNormalizedTrace, ...
    "UL normalized power contract must satisfy trace((alpha*W)*(alpha*W'))=NumLayers.");

assert(abs(localBeamGainDb([1 1], [1; 1] ./ sqrt(2)) - 10*log10(2)) < 0.05, ...
    "Known 2x2 coherent beam gain must be 3.01 dB within 0.05 dB.");
assert(abs(localBeamGainDb(ones(1, 4), ones(4, 1) ./ 2) - 10*log10(4)) < 0.05, ...
    "Known 4x4 coherent beam gain must be 6.02 dB within 0.05 dB.");

for nPorts = [2 4]
    for rankVal = 1:nPorts
        W = localDFT(nPorts, nPorts);
        W = W(:, 1:rankVal);
        S = reshape(complex(1:(64 * rankVal), -(1:(64 * rankVal))), 64, rankVal);
        X = S * W';
        assert(abs(sum(abs(X(:)).^2) - sum(abs(S(:)).^2)) < 1e-12 * max(1, sum(abs(S(:)).^2)), ...
            "Total radiated power must be invariant for orthonormal rank/precoder combinations.");
    end
end

cfgBad = sixgr.config.defaultConfig();
cfgBad.channel.model = "TDL";
cfgBad.channel.tdlProfile = "TDL-C";
badRuntime = struct("Size", [8 8], "NPol", 1, "Nant", 64, "NumPorts", 64);
badMeta = struct("NumRows", 8, "NumCols", 8, "NumPolarizations", 1, "NumElements", 64, "NumPorts", 64);
localAssertThrows(@() sixgr.channel.ChannelFactory.create(cfgBad, ...
    "Model", "TDL-C", "NumTxAnt", 2, "NumRxAnt", 1, ...
    "TransmitAntennaRuntime", badRuntime, "TransmitAntennaMeta", badMeta), ...
    "ChannelFactory:RuntimeAntennaPortMismatch");

if exist("nrCDLChannel", "class") == 8
    cfgCDL = cfgDL;
    cfgCDL.channel.model = "CDL";
    cfgCDL.channel.cdlProfile = "CDL-D";
    cfgCDL.phy.ueArray = [2 1 1];
    cfgCDL.phy.pusch.NumAntennaPorts = 2;
    cfgCDL.phy.pusch.numPorts = 2;
    bsRuntime = sixgr.rf.AntennaArrayFactory.build(cfgCDL, "bs");
    ueRuntime = sixgr.rf.AntennaArrayFactory.build(cfgCDL, "ue");
    bsMeta = localRuntimeMeta(bsRuntime);
    ueMeta = localRuntimeMeta(ueRuntime);
    ch = sixgr.channel.ChannelFactory.create(cfgCDL, ...
        "Model", "CDL-D", "SampleRate", 30.72e6, "NumTxAnt", 2, "NumRxAnt", 2, ...
        "TransmitAntennaRuntime", bsRuntime, "ReceiveAntennaRuntime", ueRuntime, ...
        "TransmitAntennaMeta", bsMeta, "ReceiveAntennaMeta", ueMeta);
    assert(ch.Meta.TransmitAntennaNumElements == 64 && ch.Meta.TransmitAntennaNumPorts == 2, ...
        "CDL channel metadata must preserve BS elements while consuming 2 logical ports.");
    assert(prod(double(ch.Object.TransmitAntennaArray.Size(1:3))) == 2, ...
        "CDL channel object must consume the projected logical port-domain array, not 64 waveform columns.");
    assert(strcmpi(string(ch.Meta.GeometryAdapterType), "port_domain_channel_array_from_element_to_port_mapping"), ...
        "CDL metadata must disclose logical port projection from element geometry.");
end

ok = true;
end

function gainDb = localBeamGainDb(H, w)
y = H * w;
gainDb = 10 * log10(real(y' * y));
end

function W = localDFT(nRows, nCols)
n = (0:nRows-1).';
k = 0:nCols-1;
W = exp(-1j * 2 * pi * (n * k) / nRows) ./ sqrt(nRows);
end

function meta = localRuntimeMeta(arr)
spacing = double(sixgr.util.structGet(arr, "ElementSpacing_m", [NaN NaN]));
lambda = double(sixgr.util.structGet(arr, "Lambda_m", NaN));
spacingLambda = [NaN NaN];
if isfinite(lambda) && lambda > 0 && numel(spacing) >= 2
    spacingLambda = spacing(1:2) ./ lambda;
end
meta = struct( ...
    "NumRows", double(arr.Size(1)), ...
    "NumCols", double(arr.Size(2)), ...
    "NumPolarizations", double(arr.NPol), ...
    "NumElements", double(arr.NumElements), ...
    "NumPorts", double(arr.NumPorts), ...
    "NumRFChains", double(arr.NumRFChains), ...
    "SpacingH_lambda", double(spacingLambda(1)), ...
    "SpacingV_lambda", double(spacingLambda(2)), ...
    "Azimuth_deg", 0, ...
    "Heading_deg", 0, ...
    "Tilt_deg", 0);
end

function localAssertThrows(fh, expectedId)
try
    fh();
catch ME
    assert(strcmp(ME.identifier, expectedId), ...
        "Expected %s, got %s: %s", expectedId, ME.identifier, ME.message);
    return;
end
error("ExpectedException:notThrown", "Expected %s to be thrown.", expectedId);
end