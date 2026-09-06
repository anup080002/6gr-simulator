function [tx, pusch] = generateRRCSetupCompleteWaveform( ...
        cfg, raCfg, grant, message)
%GENERATERRCSETUPCOMPLETEWAVEFORM Carry UL-DCCH/SRB1 on PUSCH/UL-SCH.
%
% This stage deliberately reuses the production PUSCH and UL-SCH chain.
% Its allocation is resolved from the explicit setup-complete PUSCH
% configuration, not inferred from aggregate served bits.

cfgTx = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg, raCfg.SetupCompleteSlot);
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgTx);
setupGrant = localSetupGrant(raCfg, grant);
pusch = sixgr.phy.ra.localPUSCHConfigFromGrant(raCfg, setupGrant);
probe = sixgr.phy.ul.PUSCH_Tx(cfgTx, ...
    "Carrier", carrier, "PUSCH", pusch, ...
    "TargetCodeRate", double(setupGrant.TargetCodeRate), ...
    "RV", double(setupGrant.RV), "CompactOutput", true, ...
    "ExecutionProfile", "ra_setup_complete");
tbBits = localPadBits(message.PayloadBits, probe.TransportBlockSize);
[puschTx, info] = sixgr.phy.ul.PUSCH_Tx(cfgTx, ...
    "Carrier", carrier, "PUSCH", pusch, ...
    "TransportBlockBits", tbBits, ...
    "TargetCodeRate", double(setupGrant.TargetCodeRate), ...
    "RV", double(setupGrant.RV), ...
    "ExecutionProfile", "ra_setup_complete");
tx = puschTx;
tx.RRCSetupComplete = message;
tx.RRCSetupCompleteBitLength = double(numel(message.PayloadBits));
tx.TransportBlockBits = tbBits;
tx.Info = info;
tx.Grant = setupGrant;
tx.ScheduledSlot = double(raCfg.SetupCompleteSlot);
end

function grant = localSetupGrant(raCfg, decodedRARGrant)
grant = decodedRARGrant;
s = raCfg.SetupCompletePUSCH;
grant.PRBStart = double(s.PRBStart);
grant.NumPRB = double(s.NumPRB);
grant.SymbolStart = double(s.SymbolStart);
grant.NumSymbols = double(s.NumSymbols);
% This configured SRB1 allocation is distinct from the RAR's Msg3 TDRA.
% Do not inherit a Msg3 mapping-B value into a full-slot setup allocation.
grant.MappingType = string(sixgr.util.structGet(s, "MappingType", "A"));
grant.MCS = double(s.MCS);
grant.Modulation = string(s.Modulation);
grant.TargetCodeRate = double(s.TargetCodeRate);
grant.RV = double(s.RV);
grant.NLayers = double(s.NLayers);
grant.TransformPrecoding = logical(s.TransformPrecoding);
grant.EnablePTRS = logical(sixgr.util.structGet(s, "EnablePTRS", false));
grant.PTRSPortSet = double(sixgr.util.structGet(s, "PTRSPortSet", 0));
grant.PTRSTimeDensity = double(sixgr.util.structGet(s, "PTRSTimeDensity", 1));
grant.PTRSFrequencyDensity = double(sixgr.util.structGet(s, "PTRSFrequencyDensity", 2));
grant.PTRSREOffset = string(sixgr.util.structGet(s, "PTRSREOffset", "00"));
grant.TemporaryCRNTI = double(raCfg.FinalCRNTI);
end

function bits = localPadBits(src, nBits)
src = int8(src(:) ~= 0);
nBits = round(double(nBits));
if numel(src) > nBits
    error("sixgr:phy:ra:RRCSetupCompletePayloadTooLarge", ...
        "RRCSetupComplete has %d bits but configured PUSCH TBS is %d.", ...
        numel(src), nBits);
end
bits = zeros(nBits, 1, "int8");
bits(1:numel(src)) = src;
end
