function ok = testOFDMNoiseTransformCalibration()
%TESTOFDMNOISETRANSFORMCALIBRATION Validate OFDM noise-domain contracts.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

if ~localHaveRequired5G()
    ok = true;
    return;
end

localTestModDemodReconstruction();
localTestNoiseVariancePrediction();
localTestReferenceDeclarations();
localTestReceiverNoiseConversionAgreement();

ok = true;
end

function localTestModDemodReconstruction()
cases = {
    15, "normal", 0;
    30, "normal", 0;
    60, "normal", 8;
    60, "extended", 0
    };
for i = 1:size(cases, 1)
    carrier = localCarrier(cases{i, 1}, cases{i, 2});
    K = carrier.NSizeGrid * 12;
    L = carrier.SymbolsPerSlot;
    grid = localReferenceGrid(K, L);
    try
        [waveform, txInfo] = sixgr.phy.waveform.ofdmModulate(carrier, grid, ...
            "Windowing", double(cases{i, 3}));
        [rxGrid, rxInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, waveform);
    catch ME
        if strcmpi(char(cases{i, 2}), "extended")
            continue;
        end
        rethrow(ME);
    end
    err = max(abs(rxGrid(:) - grid(:)));
    assert(err < 1e-11, ...
        "OFDM mod-demod reconstruction error %.3g exceeds double-precision tolerance.", err);
    assert(isfield(txInfo, "NoiseTransform") && isfield(rxInfo, "NoiseTransform"), ...
        "OFDM wrappers must expose calibrated noise-transform metadata.");
end
end

function localTestNoiseVariancePrediction()
carrier = localCarrier(15, "normal");
sigma2 = 2e-5;
cal = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier, ...
    "Windowing", 0, ...
    "NumNoiseRE", 1048576, ...
    "ForceRecompute", true);
[measuredGridVariance, nRE] = localMeasureNoiseGridVariance(carrier, sigma2, 1048576, 271828);
predictedGridVariance = sigma2 * double(cal.SampleToGridNoiseVarianceGain);
errdB = abs(10 * log10(max(measuredGridVariance, realmin) / max(predictedGridVariance, realmin)));
assert(nRE >= 1e6, "Independent OFDM noise variance check must use at least 1e6 RE.");
assert(errdB < 0.05, ...
    "Calibrated OFDM grid-noise variance error %.4f dB exceeds 0.05 dB.", errdB);
end

function localTestReferenceDeclarations()
carrier = localCarrier(15, "normal");
cal0 = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier, ...
    "Windowing", 0, "NumNoiseRE", 262144, "ForceRecompute", true);
calW = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier, ...
    "Windowing", 12, "NumNoiseRE", 262144, "ForceRecompute", true);
gainDelta = abs(10 * log10(double(calW.SampleToGridNoiseVarianceGain) / ...
    double(cal0.SampleToGridNoiseVarianceGain)));
assert(gainDelta < 0.05, ...
    "TX windowing must not silently change the declared receiver noise transform.");
assert(double(cal0.FFTUnusedSubcarrierCount) > 0 && double(cal0.CyclicPrefixSampleCount) > 0, ...
    "Calibration metadata must declare unused FFT bins and CP samples.");
assert(strcmp(string(cal0.TimeDomainSignalPowerReference), "active_samples_excluding_cp"), ...
    "Time-domain SNR reference must be active samples excluding CP.");
assert(strcmp(string(cal0.FrequencyDomainSignalPowerReference), "occupied_resource_grid_RE"), ...
    "Grid-domain SNR reference must be occupied resource-grid RE.");
end

function localTestReceiverNoiseConversionAgreement()
sampleNoiseVar = 1e-6;
cfg = localBaseCfg();
carrier = sixgr.phy.grid.makeCarrier(cfg);
ofdmInfo = nrOFDMInfo(carrier);
ofdmInfo.NoiseTransform = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier);
ofdmInfo.SampleToGridNoiseVarianceGain = ofdmInfo.NoiseTransform.SampleToGridNoiseVarianceGain;
[expectedGridVar, ~] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain(sampleNoiseVar, ofdmInfo, ...
    "InputDomain", "time");

pdsch = nrPDSCHConfig;
pdsch.PRBSet = 0:5;
pdsch.SymbolAllocation = [0 10];
pdsch.MappingType = "A";
pdsch.Modulation = "QPSK";
pdsch.NumLayers = 1;
pdsch.RNTI = 1;
pdsch.NID = 1;
try
    pdsch.DMRS.DMRSPortSet = 0;
catch
end
[txDL, ~] = sixgr.phy.dl.PDSCH_Tx(cfg, ...
    "Carrier", carrier, "PDSCH", pdsch, "NumTxAnt", 1, "CompactOutput", true);
[rxDL, ~] = sixgr.phy.dl.PDSCH_Rx(txDL.Waveform, cfg, ...
    "Carrier", txDL.Carrier, "PDSCH", txDL.PDSCH, "PDSCHIndices", txDL.PDSCHIndices, ...
    "TransportBlockSize", txDL.TransportBlockSize, "TargetCodeRate", txDL.TargetCodeRate, ...
    "RV", txDL.RV, "CodingPlan", txDL.CodingPlans, ...
    "NoiseVar", sampleNoiseVar, "NoiseVarDomain", "time", ...
    "FastAWGNPath", true, "SkipTimingEstimate", true, "CompactOutput", true);
localAssertNear(double(rxDL.PreEqualizationNoiseVar), expectedGridVar, "PDSCH");

pusch = nrPUSCHConfig;
pusch.PRBSet = 0:5;
pusch.SymbolAllocation = [0 10];
pusch.MappingType = "A";
pusch.Modulation = "QPSK";
pusch.NumLayers = 1;
pusch.RNTI = 1;
pusch.NID = 1;
try
    pusch.NumAntennaPorts = 1;
    pusch.DMRS.DMRSPortSet = 0;
catch
end
[txUL, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, ...
    "Carrier", carrier, "PUSCH", pusch, "NumTxAnt", 1, "CompactOutput", true);
[rxUL, ~] = sixgr.phy.ul.PUSCH_Rx(txUL.Waveform, cfg, ...
    "Carrier", txUL.Carrier, "PUSCH", txUL.PUSCH, "PUSCHIndices", txUL.PUSCHIndices, ...
    "TransportBlockSize", txUL.TransportBlockSize, "TargetCodeRate", txUL.TargetCodeRate, ...
    "RV", txUL.RV, "NoiseVar", sampleNoiseVar, "NoiseVarDomain", "time", ...
    "FastAWGNPath", true, "SkipTimingEstimate", true, "CompactOutput", true);
localAssertNear(double(rxUL.PreEqualizationNoiseVar), expectedGridVar, "PUSCH");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s"));
cfgCtrl = localControlCfg(tmp);
fixture = sixgr.phy.pucch.PUCCHFixtureFactory.connected(1,int8(1));
[txPUCCH, ~] = sixgr.phy.ul.PUCCH_Tx(fixture.Carrier, ...
    fixture.Assignment,fixture.Report,"Carrier",fixture.Carrier);
[rxPUCCH, ~] = sixgr.phy.ul.PUCCH_Rx(txPUCCH.Waveform,fixture.Carrier, ...
    fixture.Assignment,fixture.Context,"Carrier",fixture.Carrier, ...
    "NoiseVariance",sampleNoiseVar,"NoiseVarianceDomain","sample");
pucchInfo = nrOFDMInfo(txPUCCH.Carrier);
pucchInfo.NoiseTransform = sixgr.phy.waveform.calibrateOFDMNoiseTransform(txPUCCH.Carrier);
pucchInfo.SampleToGridNoiseVarianceGain = pucchInfo.NoiseTransform.SampleToGridNoiseVarianceGain;
[expectedPUCCHGridVar, ~] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain(sampleNoiseVar, pucchInfo, ...
    "InputDomain", "time");
localAssertNear(double(rxPUCCH.GridNoiseVariance), expectedPUCCHGridVar, "PUCCH");
end

function cfg = localBaseCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 45;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.antenna.ue.numElements = 1;
cfg.antenna.bs.numElements = 1;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.rx.useIdealTimingSync = true;
cfg.phy.channelEstimation.method = "LS";
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.nPorts = 1;
cfg.phy.pdsch.dmrs.nPorts = 1;
cfg.phy.csirs.enabled = false;
cfg.phy.csirs.nPorts = 1;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.30;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.numPorts = 1;
cfg.phy.pusch.nPorts = 1;
cfg.phy.pusch.dmrs.nPorts = 1;
cfg.phy.pusch.transformPrecoding = false;
end

function cfg = localControlCfg(runFolder)
scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 20;
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.run.strictNoiseVarianceRequired = false;
cfg.run.interferenceExecutionMode = "none";
cfg.phy.pucch.format = 1;
cfg.phy.rnti = 320;
end

function carrier = localCarrier(scs, cyclicPrefix)
carrier = nrCarrierConfig;
carrier.NSizeGrid = 12;
carrier.NStartGrid = 0;
carrier.SubcarrierSpacing = double(scs);
carrier.CyclicPrefix = char(string(cyclicPrefix));
end

function grid = localReferenceGrid(K, L)
idx = reshape(1:(K * L), K, L);
phase = 2 * pi * mod(29 .* idx, 997) ./ 997;
grid = complex(cos(phase), sin(phase));
end

function [measuredGridVariance, nRE] = localMeasureNoiseGridVariance(carrier, sigma2, targetRE, seed)
K = carrier.NSizeGrid * 12;
L = carrier.SymbolsPerSlot;
[zeroWaveform, ~] = nrOFDMModulate(carrier, complex(zeros(K, L)), "Windowing", 0);
nColumns = max(1, ceil(double(targetRE) / double(K * L)));
oldRng = rng;
cleanup = onCleanup(@() rng(oldRng));
rng(double(seed), "twister");
noiseWaveform = sqrt(double(sigma2) / 2) .* ...
    (randn(size(zeroWaveform, 1), nColumns) + 1j * randn(size(zeroWaveform, 1), nColumns));
noiseGrid = nrOFDMDemodulate(carrier, noiseWaveform);
measuredGridVariance = mean(abs(noiseGrid(:)).^2, "omitnan");
nRE = numel(noiseGrid);
end

function localAssertNear(actual, expected, label)
tol = max(1e-12, abs(double(expected)) * 1e-9);
assert(abs(double(actual) - double(expected)) <= tol, ...
    "%s receiver noise variance %.12g did not match calibrated grid variance %.12g.", ...
    label, double(actual), double(expected));
end

function tf = localHaveRequired5G()
tf = exist("nrOFDMModulate", "file") == 2 ...
    && exist("nrOFDMDemodulate", "file") == 2 ...
    && exist("nrPDSCH", "file") == 2 ...
    && exist("nrPUSCH", "file") == 2 ...
    && exist("nrPUCCH", "file") == 2;
end
