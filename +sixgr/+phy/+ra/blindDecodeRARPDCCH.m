function [rx, info] = blindDecodeRARPDCCH(rxWaveform, cfg, raCfg, sched, varargin)
%BLINDDECODERARPDCCH Blind-decode RA-RNTI PDCCH candidates for MSG2.
p = inputParser;
p.addParameter("RNTIAttempted", sched.RNTI, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
cfgRx = cfg;
cfgRx.phy.carrier.NCellID = double(raCfg.NCellID);
cfgRx.phy.carrier.NSizeGrid = double(raCfg.NSizeGrid);
cfgRx.phy.carrier.SubcarrierSpacing = double(raCfg.CarrierSCSkHz);
cfgRx.phy.pdcch.rnti = double(p.Results.RNTIAttempted);
cfgRx.phy.pdcch.KBits = double(raCfg.DCIPayloadBits);
cfgRx.phy.pdcch.dciPayloadBits = double(raCfg.DCIPayloadBits);
cfgRx.phy.pdcch.blindSearch = true;
cfgRx.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfgRx.phy.pdcch.aggregationLevel = 4;
cfgRx.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgRx);
cfgRx = sixgr.phy.ra.localizeRAPDCCHConfig(cfgRx, carrier);
[rx, info] = sixgr.phy.dl.PDCCH_Rx(rxWaveform, cfgRx, ...
    "Carrier", carrier, ...
    "PDCCH", sixgr.util.structGet(sched, "PDCCH", []), ...
    "K", double(raCfg.DCIPayloadBits));
end
