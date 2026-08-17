function ok = testFrozenGrantWaveformReplayAuthority()
%TESTFROZENGRANTWAVEFORMREPLAYAUTHORITY Replay exact per-grant precoders.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.frequency.bandwidth_hz = 20e6;
cfg.channel.bandwidth_Hz = 20e6;
cfg.phy.channelBandwidth_MHz = 20;
cfg.channel.subcarrierSpacing_kHz = 30;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.channel.awgnOnly = true;
cfg.channel.model = "AWGN";
cfg.channel.fading.enable = false;
cfg.scenario.bs.nTxAnt = 2;
cfg.scenario.ue.nRxAnt = 2;
cfg.antenna.bs.numElements = 2;
cfg.antenna.bs.numRFChains = 2;
cfg.antenna.ue.numElements = 2;
cfg.antenna.ue.numRFChains = 2;
cfg.rf.bs.numRFChains = 2;
cfg.rf.ue.numRFChains = 2;
cfg.channel.nTxAnt = 2;
cfg.channel.nRxAnt = 2;
cfg.phy.nTxAnt = 2;
cfg.phy.nRxAnt = 2;
cfg.phy.beamManagement.hybridBeamformingEnabled = true;
cfg.phy.pdsch.numLayers = 2;
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.numPorts = 2;
cfg.phy.pdsch.nPorts = 2;
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.3;
cfg.phy.pdsch.symbolAllocation = [2 10];
cfg.phy.pdsch.dmrs.portSet = [0 1];
cfg.phy.csirs.enable = false;
cfg.phy.ptrs.enable = false;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, "bs", ...
    "Signal", "PDSCH", "MinimumPorts", 2);
logicalMatrices = cat(3, eye(2) ./ sqrt(2), [1 1; 1 -1] ./ 2);
replay = cell(2, 1);
expectedDigest = strings(2, 1);

for index = 1:2
    logicalMatrix = logicalMatrices(:, :, index);
    physicalMatrix = double(arch.HybridElementToPortMatrix) * logicalMatrix;
    grant = struct( ...
        "Direction", "DL", "Frame", 0, "Slot", 0, ...
        "RNTI", 100 + index, "UEIndex", index, "ServingCell", 1, ...
        "PRBSet", 0:5, "SymbolAllocation", [2 10], ...
        "Modulation", "QPSK", "NumLayers", 2, "Layers", 2, ...
        "NumLogicalPorts", 2, "NumRFChains", 2, ...
        "TargetCodeRate", 0.3, "MCSIndex", 1, ...
        "PrecodingMatrixLogicalPorts", logicalMatrix, ...
        "PrecodingMatrix", physicalMatrix, ...
        "HybridElementToPortMatrix", double(arch.HybridElementToPortMatrix), ...
        "PrecoderNormalizationConvention", "unit_frobenius", ...
        "PrecoderSource", "focused_frozen_grant_regression");
    grant.PHYGrant = sixgr.phy.grant.freezePHYGrant(cfg, "DL", grant, ...
        "SNR_dB", 45, "Frame", 0, "Slot", 0);
    expectedDigest(index) = string( ...
        grant.PHYGrant.PrecodingState.SelectedMatrixSHA256);
    replay{index} = sixgr.system.waveform.replayGrant( ...
        cfg, "DL", grant, [], 45, "StrictMode", true, ...
        "CompactPHYIO", true, "FastAWGNPath", false);
end

requestedDigest = string(cellfun(@(x)x.RequestedPrecoderSHA256, replay, ...
    "UniformOutput", false));
appliedDigest = string(cellfun(@(x)x.AppliedPrecoderSHA256, replay, ...
    "UniformOutput", false));
assert(all(requestedDigest == expectedDigest), ...
    "Every replay must request the exact physical precoder frozen into its grant.");
assert(all(appliedDigest == expectedDigest), ...
    "Every waveform must apply the exact frozen physical precoder.");
assert(expectedDigest(1) ~= expectedDigest(2), ...
    "The regression grants must carry distinct physical precoder identities.");
assert(strlength(string(replay{1}.FrozenGrantContextId)) > 0 && ...
    strlength(string(replay{2}.FrozenGrantContextId)) > 0, ...
    "Every replay must disclose its frozen configuration-authority context identity.");
assert(all(cellfun(@(x)logical(x.WaveformReplayExecuted), replay)), ...
    "Both frozen grants must execute through the waveform chain.");

ok = true;
end
