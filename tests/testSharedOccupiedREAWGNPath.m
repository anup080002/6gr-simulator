function ok = testSharedOccupiedREAWGNPath()
%TESTSHAREDOCCUPIEDREAWGNPATH Prove noise calibration is shared production PHY.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if ~localHaveRequired5G()
    ok = true;
    return;
end

localCheckCarrier("normal", 30, 24, 84101);
localCheckCarrier("extended", 60, 24, 84102);
localAssertNoProductionDependencyOnConformanceNoise();
ok = true;
end

function localCheckCarrier(cyclicPrefix, scs_kHz, nSizeGrid, seed)
carrier = nrCarrierConfig;
carrier.NCellID = 41;
carrier.NSizeGrid = nSizeGrid;
carrier.NStartGrid = 0;
carrier.SubcarrierSpacing = scs_kHz;
carrier.CyclicPrefix = cyclicPrefix;

K = 12 * carrier.NSizeGrid;
L = carrier.SymbolsPerSlot;
nRx = max(4, ceil(3e5 / (K * L)));
grid = localUnitEnergyQPSK(K, L, nRx);
txWaveform = nrOFDMModulate(carrier, grid, "Windowing", 0);

rng(8731, "twister");
stateBefore = rng;
[sharedWaveform, shared] = sixgr.phy.waveform.addOccupiedREAWGN( ...
    txWaveform, carrier, 7.25, "Seed", seed);
stateAfter = rng;
assert(isequal(stateBefore, stateAfter), ...
    "Seeded shared noise injection changed the caller RNG state.");
assert(shared.CallerGlobalRNGStatePreserved && ...
    ~shared.CallerGlobalRNGConsumed, ...
    "Seeded shared noise provenance does not match its RNG behavior.");

[adapterWaveform, adapter] = sixgr.conformance.addReferenceNoise( ...
    txWaveform, carrier, 7.25, "Seed", seed);
assert(isequal(sharedWaveform, adapterWaveform), ...
    "The legacy FRC adapter does not delegate exactly to shared PHY noise.");
assert(string(adapter.Source) == ...
    "sixgr.phy.waveform.addOccupiedREAWGN", ...
    "The compatibility adapter obscured the shared numerical source.");
assert(adapter.FRCCompatibilityAdapterUsed, ...
    "The compatibility adapter was not disclosed in provenance.");

noiseGrid = nrOFDMDemodulate(carrier, sharedWaveform - txWaveform);
measuredVariance = mean(abs(noiseGrid(:)).^2);
expectedVariance = 10^(-7.25 / 10);
error_dB = 10 * log10(measuredVariance / expectedVariance);
assert(abs(error_dB) <= 0.1, ...
    "Shared occupied-RE noise missed its variance by %.4f dB.", error_dB);
assert(string(shared.ConfiguredCyclicPrefix) == string(cyclicPrefix), ...
    "Shared noise provenance lost the configured cyclic prefix.");
assert(shared.ConfiguredSubcarrierSpacing_kHz == scs_kHz, ...
    "Shared noise provenance lost the configured subcarrier spacing.");
assert(~shared.ProxyUsed && ~shared.FallbackUsed && ...
    string(shared.ApproximationMode) == "none", ...
    "Shared production noise was mislabeled as proxy/fallback evidence.");
end

function localAssertNoProductionDependencyOnConformanceNoise()
repoRoot = fileparts(fileparts(mfilename("fullpath")));
sourceRoot = fullfile(repoRoot, "+sixgr");
files = dir(fullfile(sourceRoot, "**", "*.m"));
for i = 1:numel(files)
    path = fullfile(files(i).folder, files(i).name);
    normalized = replace(string(path), "\", "/");
    if endsWith(normalized, "/+conformance/addReferenceNoise.m")
        continue;
    end
    source = string(fileread(path));
    assert(~contains(source, "sixgr.conformance.addReferenceNoise"), ...
        "Production source still depends on conformance-only noise: %s", path);
end
end

function grid = localUnitEnergyQPSK(K, L, nColumns)
index = reshape(0:(K * L * nColumns - 1), K, L, nColumns);
inPhase = 1 - 2 * mod(index, 2);
quadrature = 1 - 2 * mod(floor(index / 2), 2);
grid = complex(inPhase, quadrature) / sqrt(2);
end

function tf = localHaveRequired5G()
tf = exist("nrCarrierConfig", "class") == 8 && ...
    exist("nrOFDMModulate", "file") == 2 && ...
    exist("nrOFDMDemodulate", "file") == 2;
end
