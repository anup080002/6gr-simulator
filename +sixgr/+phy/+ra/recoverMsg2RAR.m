function [rx, rar] = recoverMsg2RAR(rxWaveform, cfg, raCfg, sched, tx)
%RECOVERMSG2RAR Decode RAR PDSCH after RA-RNTI PDCCH has been recovered.
cfgRx = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg);
cfgRx = sixgr.phy.ra.localizeRAPDSCHConfig(cfgRx, sched.PDSCH);
[pdschRx, info] = sixgr.phy.dl.PDSCH_Rx(rxWaveform, cfgRx, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", sched.PDSCH, ...
    "TransportBlockSize", double(tx.TransportBlockSize), ...
    "TargetCodeRate", double(sched.TargetCodeRate), ...
    "RV", double(sched.RV), ...
    "SkipTimingEstimate", false);
rx = pdschRx;
rx.Info = info;
if logical(pdschRx.Ok)
    payloadBits = int8(pdschRx.TransportBlock(1:double(tx.RARBitLength)));
    rar = sixgr.mac.ra.decodeMACRAR(payloadBits);
else
    rar = struct();
end
end
