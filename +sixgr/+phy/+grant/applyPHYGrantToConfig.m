function cfgOut = applyPHYGrantToConfig(cfgIn, phyGrant)
%APPLYPHYGRANTTOCONFIG Project frozen PHYGrant dimensions into runtime cfg.
% Keep this file ASCII-only.

cfgOut = cfgIn;
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)))
    return;
end

sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "apply_phygrant_to_config");

direction = upper(string(sixgr.util.structGet(phyGrant, "Direction", "DL")));
if direction == "UL"
    root = "phy.pusch";
else
    root = "phy.pdsch";
end

ant = phyGrant.AntennaArchitecture;
ra = phyGrant.ResourceAllocation;
cl = phyGrant.CodingLayout;
prec = phyGrant.PrecodingState;

numWaveformColumns = max(1, round(double(ant.NumWaveformColumns)));
numRxAntennas = max(1, round(double(ant.NumRxAntennas)));
numLogicalPorts = max(1, round(double(ant.NumLogicalPorts)));
numLayers = max(1, round(double(ant.NumLayers)));

cfgOut = sixgr.util.structSet(cfgOut, root + ".numLayers", numLayers);
cfgOut = sixgr.util.structSet(cfgOut, root + ".nLayers", numLayers);
cfgOut = sixgr.util.structSet(cfgOut, root + ".modulation", char(string(cl.Modulation)));
if isfinite(double(cl.TargetCodeRate)) && double(cl.TargetCodeRate) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".codeRate", double(cl.TargetCodeRate));
end
if isfinite(double(cl.MCSIndex))
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mcsIndex", double(cl.MCSIndex));
end
cfgOut = sixgr.util.structSet(cfgOut, root + ".prbSet", double(ra.PRBSet(:).'));
cfgOut = sixgr.util.structSet(cfgOut, root + ".nPRB", numel(double(ra.PRBSet(:))));
cfgOut = sixgr.util.structSet(cfgOut, root + ".symbolAllocation", double(ra.SymbolAllocation(:).'));
dmrsPortSet = double(sixgr.util.structGet(cl, "DMRSPortSet", []));
if ~isempty(dmrsPortSet)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".dmrs.portSet", ...
        double(dmrsPortSet(:).'));
    cfgOut = sixgr.util.structSet(cfgOut, root + ".dmrs.DMRSPortSet", ...
        double(dmrsPortSet(:).'));
end
ptrsEnabled = logical(sixgr.util.structGet(cl, "PTRSEnabled", ...
    sixgr.util.structGet(cfgOut, root + ".enablePTRS", false)));
ptrsPortSet = double(sixgr.util.structGet(cl, "PTRSPortSet", []));
cfgOut = sixgr.util.structSet(cfgOut, root + ".enablePTRS", ptrsEnabled);
if ptrsEnabled
    if isempty(ptrsPortSet)
        error("sixgr:phy:grant:MissingFrozenPTRSPortSet", ...
            "A frozen PT-RS-enabled %s PHYGrant requires PTRSPortSet.", ...
            char(direction));
    end
    cfgOut = sixgr.util.structSet(cfgOut, root + ".ptrs.portSet", ...
        double(ptrsPortSet(:).'));
end

cfgOut = sixgr.util.structSet(cfgOut, "phy.nTxAnt", numWaveformColumns);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nRxAnt", numRxAntennas);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nTxAnt", numWaveformColumns);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nRxAnt", numRxAntennas);

if direction == "DL"
    logicalMatrix = sixgr.util.structGet(prec, "MatrixLogicalPorts", prec.Matrix);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", double(logicalMatrix));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", double(logicalMatrix));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", double(logicalMatrix));
    frozenHybridMatrix = double(sixgr.util.structGet(prec, ...
        "HybridElementToPortMatrix", []));
    if logical(sixgr.util.structGet(prec, "HybridElementDomainApplied", false))
        if isempty(frozenHybridMatrix)
            error("sixgr:phy:grant:MissingFrozenHybridMatrix", ...
                "Element-domain PDSCH replay requires the exact frozen hybrid RF matrix.");
        end
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridElementToPortMatrix", frozenHybridMatrix);
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridElementToPortMatrixSHA256", ...
            char(string(sixgr.util.structGet(prec, ...
            "HybridElementToPortMatrixSHA256", ...
            sixgr.phy.mimo.MatrixContract.digest(frozenHybridMatrix)))));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridRFDesignPolicy", char(string(sixgr.util.structGet( ...
            prec, "HybridRFDesignPolicy", "fixed_configured_matrix"))));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridRFDesignStatus", char(string(sixgr.util.structGet( ...
            prec, "HybridRFDesignStatus", ""))));
    end
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.selectedPrecoderSHA256", ...
        char(string(sixgr.util.structGet(prec, "SelectedMatrixSHA256", ...
        sixgr.phy.mimo.MatrixContract.digest(double(prec.Matrix))))));
    % CSI-RS owns an independent logical-port resource configured by the
    % scenario. A PDSCH grant freezes data-layer and antenna-element
    % dimensions only; projecting its 64 element-domain waveform columns
    % into phy.csirs.nPorts corrupts the CSI-RS row contract.
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.NumAntennaPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.numPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "channel.ul.nTxAnt", numWaveformColumns);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.ul.nTxAnt", numWaveformColumns);
    cfgOut = sixgr.util.structSet(cfgOut, "channel.ul.nRxAnt", numRxAntennas);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.ul.nRxAnt", numRxAntennas);
end

cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.enabled", true);
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.contextId", char(string(phyGrant.GrantContextId)));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.direction", char(direction));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.spatialSignature", ...
    double(prec.Matrix));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.spatialSignatureSHA256", ...
    char(sixgr.phy.mimo.MatrixContract.digest(double(prec.Matrix))));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.spatialSignatureSource", ...
    "executed_frozen_phy_grant_precoding_matrix");
end
