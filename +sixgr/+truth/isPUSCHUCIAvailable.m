function tf=isPUSCHUCIAvailable(cfg)
% Existing coordinator capability/config predicate, shared without policy
% changes. An enabled mode cannot supply missing native multiplex/codec APIs.
tf=exist("nrULSCHMultiplex","file")==2 && exist("nrULSCHDemultiplex","file")==2 && ...
    exist("nrUCIEncode","file")==2 && exist("nrUCIDecode","file")==2;
if ~tf, return; end
mode=lower(strtrim(string(sixgr.util.structGet(cfg,"phy.pusch.uciMultiplexingMode", ...
    sixgr.util.structGet(cfg,"pusch.uci_multiplexing_mode", ...
    sixgr.util.structGet(cfg,"mac.scheduler.uciMultiplexingMode","harq_ack_on_pusch_when_pucch_collides"))))));
if any(mode==["disabled","off","none","pucch_only"]), tf=false; end
end
