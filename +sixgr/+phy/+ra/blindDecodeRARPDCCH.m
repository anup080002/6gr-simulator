function [rx, info] = blindDecodeRARPDCCH(rxWaveform, cfg, raCfg, sched, varargin)
%BLINDDECODERARPDCCH Blind-decode RA-RNTI PDCCH candidates for MSG2.
p = inputParser;
p.addParameter("RNTIAttempted", sched.RNTI, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
cfgRx = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg, raCfg.Msg2Slot);
cfgRx.phy.pdcch.rnti = double(p.Results.RNTIAttempted);
cfgRx.phy.pdcch.KBits = double(raCfg.DCIPayloadBits);
cfgRx.phy.pdcch.dciPayloadBits = double(raCfg.DCIPayloadBits);
cfgRx.phy.pdcch.blindSearch = logical(sixgr.util.structGet(cfg, ...
    "phy.pdcch.blindSearch", false));
sixgr.config.assertRuntimeFeatureUse(cfgRx, "pdcch_blind_search", ...
    cfgRx.phy.pdcch.blindSearch, "blindDecodeRARPDCCH");
cfgRx.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfgRx.phy.pdcch.aggregationLevel = 4;
cfgRx.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgRx);
cfgRx = sixgr.phy.ra.localizeRAPDCCHConfig(cfgRx, carrier);
[rx, info] = sixgr.phy.dl.PDCCH_Rx(rxWaveform, cfgRx, ...
    "Carrier", carrier, ...
    "PDCCH", sixgr.util.structGet(sched, "PDCCH", []), ...
    "K", double(raCfg.DCIPayloadBits), ...
    "ExpectedDCIBits", int8(sched.DCIBits(:)));
end
