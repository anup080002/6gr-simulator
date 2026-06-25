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

cfgOut = sixgr.util.structSet(cfgOut, "phy.nTxAnt", numWaveformColumns);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nRxAnt", numRxAntennas);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nTxAnt", numWaveformColumns);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nRxAnt", numRxAntennas);

if direction == "DL"
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", double(prec.Matrix));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", double(prec.Matrix));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", double(prec.Matrix));
    if logical(sixgr.util.structGet(cfgOut, "phy.csirs.enable", false))
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.nPorts", numWaveformColumns);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.numPorts", numWaveformColumns);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.rowNumber", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.symbolLocations", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.subcarrierLocations", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.density", "");
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.cdmType", "");
    end
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
end
