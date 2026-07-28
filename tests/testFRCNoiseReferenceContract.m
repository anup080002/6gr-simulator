function ok = testFRCNoiseReferenceContract()
%TESTFRCNOISEREFERENCECONTRACT Validate the FRC occupied-RE Es/N0 contract.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

if ~localHaveRequired5G()
    ok = true;
    return;
end

localCheckCarrier(12, 30, 72001);
localCheckCarrier(273, 30, 72002);
localCheckOccupancyIndependence();
localCheckScaledOccupiedREEnergy();

ok = true;
end

function localCheckScaledOccupiedREEnergy()
carrier = nrCarrierConfig;
carrier.NSizeGrid = 24;
carrier.NStartGrid = 0;
carrier.SubcarrierSpacing = 30;
carrier.CyclicPrefix = "normal";

K = 12 * carrier.NSizeGrid;
L = carrier.SymbolsPerSlot;
signalEnergy = 10^(23 / 10);
referenceGrid = sqrt(signalEnergy) .* localUnitEnergyQPSK(K, L, 8);
txWaveform = nrOFDMModulate(carrier, referenceGrid, "Windowing", 0);
requestedEsN0_dB = 0;
[rxWaveform, info] = sixgr.conformance.addReferenceNoise( ...
    txWaveform, carrier, requestedEsN0_dB, "Seed", 74001, ...
    "SignalEnergyPerOccupiedRE", signalEnergy);
rxGrid = nrOFDMDemodulate(carrier, rxWaveform);
noiseGrid = rxGrid - referenceGrid;
measuredEsN0_dB = 10 * log10( ...
    mean(abs(referenceGrid(:)).^2) / mean(abs(noiseGrid(:)).^2));

assert(abs(measuredEsN0_dB - requestedEsN0_dB) <= 0.1, ...
    ["Physical power scaling changed the requested occupied-RE Es/N0: " ...
    "requested %.3f dB, measured %.3f dB."], ...
    requestedEsN0_dB, measuredEsN0_dB);
localAssertNear(info.SignalEnergyPerOccupiedRE, signalEnergy, ...
    "scaled occupied-RE signal energy");
localAssertNear(info.GridNoiseVariance, signalEnergy, ...
    "scaled grid-domain noise variance");
end

function localCheckCarrier(nSizeGrid, scs_kHz, seed)
carrier = nrCarrierConfig;
carrier.NSizeGrid = nSizeGrid;
carrier.NStartGrid = 0;
carrier.SubcarrierSpacing = scs_kHz;
carrier.CyclicPrefix = "normal";

K = 12 * nSizeGrid;
L = carrier.SymbolsPerSlot;
targetNoiseRE = 6e5;
nRx = max(3, ceil(targetNoiseRE / (K * L)));
referenceGrid = localUnitEnergyQPSK(K, L, nRx);
txWaveform = nrOFDMModulate(carrier, referenceGrid, "Windowing", 0);

requestedEsN0_dB = 11.25;
[rxWaveform, info] = sixgr.conformance.addReferenceNoise( ...
    txWaveform, carrier, requestedEsN0_dB, "Seed", seed);
rxGrid = nrOFDMDemodulate(carrier, rxWaveform);
noiseGrid = rxGrid - referenceGrid;

measuredSignalEnergy = mean(abs(referenceGrid(:)).^2);
measuredNoiseVariance = mean(abs(noiseGrid(:)).^2);
measuredEsN0_dB = 10 * log10(measuredSignalEnergy / measuredNoiseVariance);
error_dB = measuredEsN0_dB - requestedEsN0_dB;

assert(abs(error_dB) <= 0.1, ...
    ["FRC occupied-RE Es/N0 contract missed for NSizeGrid=%d: " ...
    "requested %.3f dB, measured %.3f dB, delta %.3f dB."], ...
    nSizeGrid, requestedEsN0_dB, measuredEsN0_dB, error_dB);
assert(info.NumRxColumns == nRx, ...
    "FRC reference noise provenance must preserve arbitrary receive-column count.");
assert(info.NumTimeSamples == size(txWaveform, 1), ...
    "FRC reference noise provenance must report the waveform sample count.");
assert(info.SeedApplied && info.Seed == seed, ...
    "FRC reference noise provenance must report the deterministic seed.");
assert(~info.WaveformPowerUsed && ~info.CyclicPrefixPowerUsed && ...
    ~info.UnusedFFTBinPowerUsed, ...
    "FRC reference noise must not derive Es/N0 from whole-waveform power.");

expectedGridVariance = 10.^(-requestedEsN0_dB / 10);
expectedSampleVariance = expectedGridVariance / ...
    double(info.SampleToGridNoiseVarianceGain);
localAssertNear(info.GridNoiseVariance, expectedGridVariance, ...
    "grid-domain noise variance");
localAssertNear(info.SampleNoiseVariance, expectedSampleVariance, ...
    "sample-domain noise variance");
end

function localCheckOccupancyIndependence()
carrier = nrCarrierConfig;
carrier.NSizeGrid = 12;
carrier.NStartGrid = 0;
carrier.SubcarrierSpacing = 30;
carrier.CyclicPrefix = "normal";

K = 12 * carrier.NSizeGrid;
L = carrier.SymbolsPerSlot;
nRx = 5;
fullGrid = localUnitEnergyQPSK(K, L, nRx);
sparseGrid = complex(zeros(size(fullGrid)));
mask = false(K, L);
mask(1:4:end, 2:3:end) = true;
for column = 1:nRx
    page = fullGrid(:, :, column);
    sparsePage = sparseGrid(:, :, column);
    sparsePage(mask) = page(mask);
    sparseGrid(:, :, column) = sparsePage;
end

fullWaveform = nrOFDMModulate(carrier, fullGrid, "Windowing", 0);
sparseWaveform = nrOFDMModulate(carrier, sparseGrid, "Windowing", 0);
seed = 73001;
[fullNoisy, fullInfo] = sixgr.conformance.addReferenceNoise( ...
    fullWaveform, carrier, 8.5, "Seed", seed);
[sparseNoisy, sparseInfo] = sixgr.conformance.addReferenceNoise( ...
    sparseWaveform, carrier, 8.5, "Seed", seed);

fullNoise = fullNoisy - fullWaveform;
sparseNoise = sparseNoisy - sparseWaveform;
noiseDelta = max(abs(fullNoise(:) - sparseNoise(:)));
assert(noiseDelta < 1e-12, ...
    ["FRC reference noise changed with grid occupancy despite identical " ...
    "carrier, shape, SNR, and seed (max delta %.3g)."], noiseDelta);
localAssertNear(fullInfo.GridNoiseVariance, sparseInfo.GridNoiseVariance, ...
    "occupancy-independent grid noise variance");
localAssertNear(fullInfo.SampleNoiseVariance, sparseInfo.SampleNoiseVariance, ...
    "occupancy-independent sample noise variance");
end

function grid = localUnitEnergyQPSK(K, L, nColumns)
index = reshape(0:(K * L * nColumns - 1), K, L, nColumns);
inPhase = 1 - 2 * mod(index, 2);
quadrature = 1 - 2 * mod(floor(index / 2), 2);
grid = complex(inPhase, quadrature) / sqrt(2);
end

function localAssertNear(actual, expected, label)
tolerance = max(1e-14, 32 * eps(max(abs(double(expected)), 1)));
assert(abs(double(actual) - double(expected)) <= tolerance, ...
    "FRC %s %.15g does not match expected %.15g.", ...
    label, double(actual), double(expected));
end

function tf = localHaveRequired5G()
tf = exist("nrCarrierConfig", "class") == 8 ...
    && exist("nrOFDMModulate", "file") == 2 ...
    && exist("nrOFDMDemodulate", "file") == 2;
end
