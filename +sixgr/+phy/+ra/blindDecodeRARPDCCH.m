function [rx, info] = blindDecodeRARPDCCH(rxWaveform, cfg, raCfg, sched, varargin)
%BLINDDECODERARPDCCH Blind-decode RA-RNTI PDCCH candidates for MSG2.
p = inputParser;
p.addParameter("RNTIAttempted", raCfg.RARNTI, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
cfgRx = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg, raCfg.Msg2Slot);
cfgRx.phy.pdcch.rnti = double(p.Results.RNTIAttempted);
context = sixgr.phy.pdcch.RARDCIContext.create(raCfg.RARDCIReference,double(p.Results.RNTIAttempted));
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
cfgRx.phy.pdcch.KBits = schema.RawBits;
cfgRx.phy.pdcch.dciPayloadBits = schema.RawBits;
cfgRx.phy.pdcch.blindSearch = logical(sixgr.util.structGet(cfg, ...
    "phy.pdcch.blindSearch", false));
sixgr.config.assertRuntimeFeatureUse(cfgRx, "pdcch_blind_search", ...
    cfgRx.phy.pdcch.blindSearch, "blindDecodeRARPDCCH");
cfgRx.phy.pdcch.allowBlindCandidateTimingEstimate = false;
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgRx);
[commonPDCCH,commonEvidence] = sixgr.phy.ra.buildRARCommonPDCCH(cfgRx,raCfg,carrier);
[rx, info] = sixgr.phy.dl.PDCCH_Rx(rxWaveform, cfgRx, ...
    "Carrier", carrier, "PDCCH",commonPDCCH,"RNTI",double(p.Results.RNTIAttempted), ...
    "PDCCHScramblingRNTI",0, "K", schema.RawBits);
info.DCIContextDigest = context.Digest;
info.DCIContextSource = context.Data.FrequencyReferenceSource;
info.CommonControlEvidence=commonEvidence;
info.SelectedCandidateIndex=NaN;
if logical(rx.Ok), info.SelectedCandidateIndex=double(rx.CandidateIndex); end
% sched remains an API compatibility argument, not receiver input authority.
end
