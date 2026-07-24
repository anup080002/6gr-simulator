function ok = testPUSCHDMRSEPREDifference()
%TESTPUSCHDMRSEPREDIFFERENCE Verify configurable PUSCH DM-RS EPRE scaling.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if ~localHaveRequired5G()
    warning("testPUSCHDMRSEPREDifference:Missing5G", ...
        "Skipping PUSCH DM-RS EPRE test because required 5G Toolbox APIs are unavailable.");
    ok = true;
    return;
end

rng(38214, "twister");
cfgDefault = localCfg();
[txDefault, infoDefault] = sixgr.phy.ul.PUSCH_Tx(cfgDefault, "CompactOutput", false);
[~, nominalDMRS] = sixgr.phy.refsig.dmrsPUSCH(txDefault.Carrier, txDefault.PUSCH);

assert(abs(double(txDefault.DMRSDataToDMRSEPREDifference_dB)) < 1e-12 && ...
        abs(double(txDefault.DMRSAmplitudeScale) - 1) < 1e-12 && ...
        ~logical(txDefault.DMRSEPREDifference.Applied), ...
    "Missing PUSCH DM-RS EPRE config must preserve the historical 0 dB default.");
assert(localMaxAbs(txDefault.DMRSSymbols - nominalDMRS) < 1e-12, ...
    "The default PUSCH DM-RS symbols must remain identical to the toolbox reference.");
assert(abs(double(infoDefault.DMRS.DMRSAmplitudeScale) - 1) < 1e-12, ...
    "PUSCH Tx info must disclose the default unit DM-RS scale.");

cfgBoost = cfgDefault;
cfgBoost.phy.pusch.dmrs.dataToDMRSEPREDifference_dB = -3;
expectedScale = sqrt(2);
expectedRealizedBoost_dB = 10 * log10(2);
[txBoost, infoBoost] = sixgr.phy.ul.PUSCH_Tx(cfgBoost, ...
    "Carrier", txDefault.Carrier, ...
    "PUSCH", txDefault.PUSCH, ...
    "TransportBlockBits", txDefault.TransportBlock, ...
    "TransportBlockSizeOverride", txDefault.TransportBlockSize, ...
    "TargetCodeRate", txDefault.TargetCodeRate, ...
    "RV", txDefault.RV, ...
    "CompactOutput", false);

assert(abs(double(txBoost.DMRSDataToDMRSEPREDifference_dB) + 3) < 1e-12 && ...
        abs(double(txBoost.DMRSConfiguredPowerBoost_dB) - 3) < 1e-12 && ...
        abs(double(txBoost.DMRSPowerBoost_dB) - expectedRealizedBoost_dB) < 1e-12 && ...
        abs(double(txBoost.DMRSAmplitudeScale) - expectedScale) < 1e-12 && ...
        logical(txBoost.DMRSEPREDifference.Applied) && ...
        logical(txBoost.DMRSEPREDifference.NormativeMinus3dBBetaApplied), ...
    "The normative -3 dB token must apply exact beta=sqrt(2) and disclose configured versus realized dB.");
assert(localMaxAbs(txBoost.DMRSSymbols - nominalDMRS .* expectedScale) < 1e-12, ...
    "PUSCH Tx must scale every logical-port DM-RS symbol by the configured amplitude.");
assert(localMaxAbs(txBoost.PUSCHPortSymbols - txDefault.PUSCHPortSymbols) < 1e-12, ...
    "PUSCH DM-RS EPRE scaling must not change PUSCH data symbols.");
assert(abs(double(infoBoost.DMRSEPREDifference.DMRSPowerScale) - expectedScale^2) < 1e-12, ...
    "PUSCH Tx info must disclose the realized DM-RS power scale.");
assert(string(infoBoost.DMRSEPREDifference.ScalePolicy) == "ts_38_104_minus3_db_beta_sqrt2", ...
    "The normative -3 dB scale policy must be explicit in PUSCH Tx provenance.");
localAssertMappedDMRS(txBoost);

[rxBoost, rxInfo] = sixgr.phy.ul.PUSCH_Rx(txBoost.Waveform, cfgBoost, ...
    "Carrier", txBoost.Carrier, ...
    "PUSCH", txBoost.PUSCH, ...
    "PUSCHIndices", txBoost.PUSCHIndices, ...
    "TransportBlockSize", txBoost.TransportBlockSize, ...
    "TargetCodeRate", txBoost.TargetCodeRate, ...
    "RV", txBoost.RV, ...
    "NoiseVar", 1e-9, ...
    "NoiseVarDomain", "grid", ...
    "CodingLayout", txBoost.CodingLayout, ...
    "CompactOutput", false, ...
    "SkipTimingEstimate", true);

assert(logical(rxBoost.Ok) && ~logical(rxBoost.CRCError), ...
    "Matched boosted-DMRS PUSCH must decode in the no-noise identity channel.");
assert(all(int8(rxBoost.TransportBlock(:)) == int8(txBoost.TransportBlock(:))), ...
    "Matched boosted-DMRS PUSCH must recover the transmitted transport block.");
assert(localMaxAbs(rxBoost.DMRSSymbols - txBoost.DMRSSymbols) < 1e-12, ...
    "PUSCH Tx and Rx must use the same boosted DM-RS reference.");
assert(abs(double(rxBoost.DMRSAmplitudeScale) - expectedScale) < 1e-12 && ...
        abs(double(rxInfo.DMRS.DMRSAmplitudeScale) - expectedScale) < 1e-12, ...
    "PUSCH Rx outputs must disclose the configured DM-RS scale.");

pilotH = nrExtractResources(txBoost.DMRSIndices, rxBoost.ChannelEstimate);
pilotH = pilotH(isfinite(real(pilotH)) & isfinite(imag(pilotH)));
assert(~isempty(pilotH) && abs(median(abs(double(pilotH))) - 1) < 2e-2, ...
    "Matched boosted DM-RS references must preserve a unit identity-channel estimate.");

localAssertInvalidDifferenceRejected(cfgDefault);

fprintf("PUSCHDMRSEPREDifference: 0 dB default, -3 dB boost, grid mapping, and matched Rx estimation verified.\n");
ok = true;
end

function localAssertMappedDMRS(tx)
ind = tx.DMRSWaveformIndices;
sym = tx.DMRSWaveformSymbols;
assert(numel(ind) == numel(sym), ...
    "Single-port PUSCH test fixture must provide one mapped index per DM-RS symbol.");
mapped = tx.Grid(ind(:));
assert(localMaxAbs(mapped(:) - sym(:)) < 1e-12, ...
    "The waveform resource grid must contain the boosted DM-RS symbols.");
end

function localAssertInvalidDifferenceRejected(cfg)
cfg.phy.pusch.dmrs.dataToDMRSEPREDifference_dB = NaN;
thrown = false;
try
    sixgr.phy.ul.PUSCH_Tx(cfg, "CompactOutput", true);
catch ME
    thrown = strcmp(ME.identifier, "sixgr:phy:ul:PUSCHDMRSEPREDifferenceInvalid");
end
assert(thrown, "A non-finite PUSCH data-to-DMRS EPRE difference must fail loudly.");
end

function cfg = localCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictNoiseVarianceRequired = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 45;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.antenna.ue.numElements = 1;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.pusch.prbSet = 0:5;
cfg.phy.pusch.symbolAllocation = [0 14];
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.30;
cfg.phy.pusch.mcsIndex = 4;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numAntennaPorts = 1;
cfg.phy.pusch.numPorts = 1;
cfg.phy.pusch.transmissionScheme = "nonCodebook";
cfg.phy.pusch.transformPrecoding = false;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.pusch.equalizer = "MMSE";
cfg.phy.pusch.dmrs.typeAPosition = 2;
cfg.phy.pusch.dmrs.configurationType = 1;
cfg.phy.pusch.dmrs.additionalPosition = 1;
cfg.phy.pusch.dmrs.maxLength = 1;
cfg.phy.pusch.dmrs.numCDMGroupsWithoutData = 2;
cfg.phy.channelEstimation.method = "LS";
end

function value = localMaxAbs(x)
if isempty(x)
    value = 0;
else
    value = max(abs(double(x(:))));
end
end

function tf = localHaveRequired5G()
tf = exist("nrPUSCH", "file") == 2 && ...
    exist("nrPUSCHDMRS", "file") == 2 && ...
    exist("nrPUSCHDMRSIndices", "file") == 2 && ...
    exist("nrPUSCHDecode", "file") == 2 && ...
    exist("nrChannelEstimate", "file") == 2 && ...
    exist("nrRateRecoverLDPC", "file") == 2 && ...
    exist("nrLDPCDecode", "file") == 2;
end
