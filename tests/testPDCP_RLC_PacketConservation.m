function ok = testPDCP_RLC_PacketConservation()
%TESTPDCP_RLC_PACKETCONSERVATION Basic byte conservation across PDCP+RLC.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;

pdcpTx = sixgr.l2.pdcp.PDCP(cfg, "Direction", "DL", "DRBID", 1);
pdcpRx = sixgr.l2.pdcp.PDCP(cfg, "Direction", "DL", "DRBID", 1);
rlcTx = sixgr.l2.rlc.RLC_UM(cfg, "Direction", "DL", "LCID", 4);
rlcRx = sixgr.l2.rlc.RLC_UM(cfg, "Direction", "DL", "LCID", 4);

numPkts = 30;
inBytes = 0;
outBytes = 0;
for k = 1:numPkts
    sdu = uint8(randi([0 255], randi([80 600]), 1));
    inBytes = inBytes + numel(sdu);
    pdu = pdcpTx.tx(sdu);
    rlcTx.addSDU(pdu);
end

for k = 1:120
    macSdus = rlcTx.buildMACSDUs(1000);
    if isempty(macSdus)
        break;
    end
    for i = 1:numel(macSdus)
        if isfield(macSdus(i), "Payload") && ~isempty(macSdus(i).Payload)
            rlcRx.receivePDU(uint8(macSdus(i).Payload(:)));
        end
    end
end

rxSdus = rlcRx.pullSDUs();
if iscell(rxSdus)
    for i = 1:numel(rxSdus)
        pdcpRx.rx(rxSdus{i});
    end
end
appSdus = pdcpRx.pullSDUs();
if iscell(appSdus)
    for i = 1:numel(appSdus)
        outBytes = outBytes + numel(appSdus{i});
    end
end

assert(outBytes >= 0, "Output bytes must be non-negative.");
assert(outBytes <= inBytes, "Delivered app bytes cannot exceed generated app bytes.");
assert(outBytes > 0, "No bytes were delivered through PDCP/RLC chain.");
ok = true;
end
