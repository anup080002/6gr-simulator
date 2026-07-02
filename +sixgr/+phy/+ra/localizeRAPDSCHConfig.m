function cfgOut = localizeRAPDSCHConfig(cfg, pdsch)
%LOCALIZERAPDSCHCONFIG Isolate RA Msg2/Msg4 PDSCH from data-grant precoding.
cfgOut = cfg;
nLayers = max(1, round(double(pdsch.NumLayers)));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", []);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", []);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", []);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.mode", "ra_control_identity");
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.source", "ra_msg2_msg4_schedule");
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.normalizePrecodingMatrix", true);
end
