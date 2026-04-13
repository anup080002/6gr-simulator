function cfgOut = applyLinkAdaptationDecision(cfgIn, direction, decision)
%APPLYLINKADAPTATIONDECISION Apply an LLS closed-loop adaptation decision.

cfgOut = cfgIn;
direction = upper(string(direction));
if direction ~= "DL" && direction ~= "UL"
    error("sixgr:link:LinkAdaptation:BadDirection", ...
        "Direction must be 'DL' or 'UL'.");
end
if nargin < 3 || isempty(decision) || ~isstruct(decision) || ~logical(sixgr.util.structGet(decision, "Valid", false))
    return;
end

if direction == "DL"
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.modulation", char(string(decision.Modulation)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.codeRate", double(decision.TargetCodeRate));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.mcsIndex", double(decision.MCSIndex));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", double(decision.NumLayers));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", double(decision.NumLayers));
    if logical(sixgr.util.structGet(decision, "PMIUpdated", false))
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", double(decision.PMI));
    end
    if logical(sixgr.util.structGet(decision, "CRIUpdated", false))
        cfgOut = sixgr.util.structSet(cfgOut, "phy.beamManagement.selectedCRI", double(decision.CRI));
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csi.selectedCRI", double(decision.CRI));
    end
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.modulation", char(string(decision.Modulation)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.codeRate", double(decision.TargetCodeRate));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.mcsIndex", double(decision.MCSIndex));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.numLayers", double(decision.NumLayers));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nLayers", double(decision.NumLayers));
    if logical(sixgr.util.structGet(decision, "PMIUpdated", false))
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.PMI", double(decision.PMI));
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.TPMI", double(decision.PMI));
    end
end

cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.lastDecision", decision);
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.lastAppliedDirection", char(direction));
end
