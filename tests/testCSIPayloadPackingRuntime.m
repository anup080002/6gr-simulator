function ok = testCSIPayloadPackingRuntime()
%TESTCSIPAYLOADPACKINGRUNTIME Verify runtime CSI payload packing for supported modes.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.nTxAnt = 4;
cfg.phy.nRxAnt = 2;
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPayloadMode", "compressed");
cfg = sixgr.util.structSet(cfg, "phy.csi.crcAttached", true);
cfg = sixgr.util.structSet(cfg, "phy.csirs.numResources", 4);
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.trpCount", 4);

Hwb = [1.05 + 0.05j, 0.35 - 0.10j, 0.20 + 0.03j, 0.05; ...
       0.18 + 0.04j, 0.95 + 0.02j, 0.12 - 0.08j, 0.30 + 0.05j];
Hest = repmat(reshape(Hwb, 1, 1, size(Hwb, 1), size(Hwb, 2)), [24, 14, 1, 1]);

cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", "type2_mu_mimo");
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", "type2");
[csi2, info2] = sixgr.phy.dl.CSI_Feedback(Hest, 0.02, cfg, "MaxRank", 2);
assert(csi2.CSIPayloadBitLength > 0, "Type-2 runtime CSI payload must not be empty.");
assert(strlength(string(csi2.CSIPayloadHex)) > 0, "Type-2 runtime CSI payload must export hex.");
names2 = string({info2.Payload.FieldLayout.Name});
assert(any(names2 == "PMI_START_BEAM"), "Type-2 payload must include PMI_START_BEAM.");
assert(any(names2 == "PMI_STRIDE_INDEX"), "Type-2 payload must include PMI_STRIDE_INDEX.");
assert(any(names2 == "CSI_CRC"), "CRC-attached payload must export CSI_CRC.");

cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", "etype2_candidate");
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", "etype2");
[csi3, info3] = sixgr.phy.dl.CSI_Feedback(Hest, 0.02, cfg, "MaxRank", 2);
assert(csi3.CSIPayloadBitLength >= csi2.CSIPayloadBitLength, ...
    "eType2 payload should not be smaller than type-2 for the same rank.");
names3 = string({info3.Payload.FieldLayout.Name});
assert(any(names3 == "PMI_PHASE_INDEX"), "eType2 payload must include PMI_PHASE_INDEX.");
assert(~strcmpi(string(csi2.CSIPayloadHex), string(csi3.CSIPayloadHex)), ...
    "Type-2 and eType2 runtime payloads should not collapse to the same packed bits.");

ok = true;
end
