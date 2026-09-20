function [tx, pusch] = generateMsg3PUSCHWaveform(cfg, raCfg, grant, msg3)
%GENERATEMSG3PUSCHWAVEFORM Transmit Msg3 using the decoded RAR UL grant.
slot = sixgr.phy.ra.resolveMsg3SlotFromRAR(raCfg,grant);
cfgTx = sixgr.phy.ra.localizeRAPUSCHConfig(cfg, raCfg, grant, slot);
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgTx);
pusch = sixgr.phy.ra.localPUSCHConfigFromGrant(raCfg, grant);
probe = sixgr.phy.ul.PUSCH_Tx(cfgTx, "Carrier", carrier, "PUSCH", pusch, ...
    "TargetCodeRate", double(grant.TargetCodeRate), "RV", double(grant.RV), ...
    "InitialIMCSPerCodeword", double(grant.MCS), ...
    "CompactOutput", true, "ExecutionProfile", "ra_msg3");
tbBits = localPadBits(msg3.PayloadBits, probe.TransportBlockSize);
[puschTx, info] = sixgr.phy.ul.PUSCH_Tx(cfgTx, "Carrier", carrier, "PUSCH", pusch, ...
    "TransportBlockBits", tbBits, ...
    "TargetCodeRate", double(grant.TargetCodeRate), "RV", double(grant.RV), ...
    "InitialIMCSPerCodeword", double(grant.MCS), ...
    "ExecutionProfile", "ra_msg3");
tx = puschTx;
tx.Msg3 = msg3;
tx.Msg3BitLength = double(numel(msg3.PayloadBits));
tx.TransportBlockBits = tbBits;
tx.Info = info;
end

function bits = localPadBits(src, nBits)
src = int8(src(:) ~= 0);
nBits = round(double(nBits));
if numel(src) > nBits
    error("sixgr:phy:ra:Msg3PayloadTooLarge", "Msg3 payload has %d bits but TBS is %d.", numel(src), nBits);
end
bits = zeros(nBits, 1, "int8");
bits(1:numel(src)) = src;
end
