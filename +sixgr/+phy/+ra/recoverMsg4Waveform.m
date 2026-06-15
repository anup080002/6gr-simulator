function [pdcchRx, pdschRx, msg4] = recoverMsg4Waveform(rxWaveform, cfg, raCfg, sched, tx)
%RECOVERMSG4WAVEFORM Decode temp-C-RNTI PDCCH and Msg4 DL-SCH.
cfgRx = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg);
cfgRx.phy.pdcch.rnti = double(raCfg.TempCRNTI);
cfgRx.phy.pdcch.KBits = double(raCfg.DCIPayloadBits);
cfgRx.phy.pdcch.dciPayloadBits = double(raCfg.DCIPayloadBits);
cfgRx.phy.pdcch.blindSearch = true;
cfgRx.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfgRx.phy.pdcch.aggregationLevel = 4;
cfgRx.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
cfgRx = sixgr.phy.ra.localizeRAPDCCHConfig(cfgRx, tx.Carrier);
[pdcchRx, pdcchInfo] = sixgr.phy.dl.PDCCH_Rx(rxWaveform, cfgRx, ...
    "Carrier", tx.Carrier, "PDCCH", sixgr.util.structGet(sched, "PDCCH", []), ...
    "K", double(raCfg.DCIPayloadBits));
pdcchRx.Info = pdcchInfo;
if ~logical(pdcchRx.Ok)
    pdschRx = struct("Ok", false, "CRCError", true);
    msg4 = struct();
    return;
end
[pdschRx, info] = sixgr.phy.dl.PDSCH_Rx(rxWaveform, cfgRx, ...
    "Carrier", tx.Carrier, "PDSCH", sched.PDSCH, ...
    "TransportBlockSize", double(tx.TransportBlockSize), ...
    "TargetCodeRate", double(sched.TargetCodeRate), "RV", double(sched.RV), ...
    "SkipTimingEstimate", true);
pdschRx.Info = info;
if logical(pdschRx.Ok)
    payloadBits = int8(pdschRx.TransportBlock(1:double(tx.Msg4BitLength)));
    msg4 = sixgr.mac.ra.parseMsg4ContentionResolution(payloadBits);
else
    msg4 = struct();
end
end
