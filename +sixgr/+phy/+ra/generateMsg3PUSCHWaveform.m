function [tx, pusch] = generateMsg3PUSCHWaveform(cfg, raCfg, grant, msg3)
%GENERATEMSG3PUSCHWAVEFORM Transmit Msg3 using the decoded RAR UL grant.
a=sixgr.phy.ra.resolveMsg3PUSCHAllocation(cfg,raCfg,grant);
cfgTx=a.Config;carrier=a.Carrier;pusch=a.PUSCH;
if string(sixgr.util.structGet(msg3,'EncodingProfile',""))=="nr_rrc_access_base_srb1_uper_v1"
    mac=sixgr.l2.mac.MACPDUAssembler.assemble("UL",msg3.MACSubPDUs,a.TransportBlockSize/8);
    tbBits=reshape(int8(bitget(repmat(mac.Bytes(:),1,8),repmat(8:-1:1,numel(mac.Bytes),1))).',[],1);
else
    tbBits = localPadBits(msg3.PayloadBits,a.TransportBlockSize);
end
[puschTx, info] = sixgr.phy.ul.PUSCH_Tx(cfgTx, "Carrier", carrier, "PUSCH", pusch, ...
    "TransportBlockBits", tbBits, ...
    "TargetCodeRate", double(grant.TargetCodeRate), "RV", double(grant.RV), ...
    "XOverhead",a.XOverhead, ...
    "InitialIMCSPerCodeword", double(grant.MCS), ...
    "ExecutionProfile", "ra_msg3");
tx = puschTx;
tx.Msg3 = msg3;
tx.Msg3BitLength = double(numel(msg3.PayloadBits));
tx.TransportBlockBits = tbBits;
tx.Info = info;
assert(tx.TransportBlockSize==a.TransportBlockSize,'sixgr:phy:ra:Msg3TBSChanged', ...
    'Exact original allocation must survive the transmitter boundary.');
tx.AllocationSource=a.Source;
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
