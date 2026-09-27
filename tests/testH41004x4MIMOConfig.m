function ok = testH41004x4MIMOConfig()
%TESTH41004X4MIMOCONFIG Lock the H4 64-TXRU / four-chain UE contract.

setup6GRSimToolkit("Verbose", false);

scenarioFiles = [ ...
    "h4_100_a0_fixed_mcs.yaml"
    "h4_100_tdla30_fixed_mcs.yaml"
    "h4_100_cdlc100_fixed_mcs.yaml"
    "h4_100_tdla30_connected_adaptive.yaml"
    "h4_100_cdlc100_connected_adaptive.yaml"];

for scenarioOrdinal = 1:numel(scenarioFiles)
    scenarioPath = fullfile("simulator", "configs", "scenarios", ...
        scenarioFiles(scenarioOrdinal));
    scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
    cfg = sixgr.lls6g.buildInternalConfig(scfg, ...
        fullfile(tempdir, "h4_100_4x4_config", string(scenarioOrdinal)));

    assert(isequal(double(cfg.phy.bsArray), [4 4 2 2 1]), ...
        "The two-panel gNB must resolve to 4x4 spatial positions, H/V and two panels.");
    assert(isequal(double(cfg.phy.ueArray), [1 2 2 1 1]), ...
        "The four-chain UE must resolve to two spatial positions with H/V polarization.");
    assert(double(cfg.phy.nTxAnt) == 64 && double(cfg.phy.nRxAnt) == 4, ...
        "The installed downlink channel must be 64-by-4 element-domain MIMO.");
    assert(double(cfg.phy.pdsch.numAntennaPorts) == 8 && ...
        double(cfg.phy.pdsch.maxRankDefault) == 4, ...
        "The gNB must expose eight logical DL ports with rank capped at four.");
    assert(double(cfg.phy.pusch.numAntennaPorts) == 4 && ...
        double(cfg.phy.pusch.maxRankDefault) == 4, ...
        "The UE must expose four logical UL ports with rank capped at four.");
    assert(double(cfg.phy.srs.nPorts) == 4, ...
        "Four-chain UL rank adaptation requires four independently mapped SRS ports.");

    precoders = cfg.phy.csirs.precoderMatrices;
    assert(isequal(size(precoders), [64 8 8]), ...
        "The CSI-RS codebook must contain eight 64-by-8 physical beam states.");
    panelIndices = double(cfg.phy.csirs.precoderPanelIndices);
    assert(all(panelIndices(:,1:4) == 0, "all") && ...
        all(panelIndices(:,5:8) == 1, "all"), ...
        "CSI-RS logical ports must retain explicit two-panel ownership.");
    for resourceOrdinal = 1:size(precoders, 3)
        W = precoders(:,:,resourceOrdinal);
        assert(norm(W' * W - eye(8), "fro") < 1e-10, ...
            "Each eight-port CSI-RS physical precoder must be orthonormal.");
    end
end

ok = true;
end
