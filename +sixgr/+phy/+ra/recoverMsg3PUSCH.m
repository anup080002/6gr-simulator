function [rx, msg3] = recoverMsg3PUSCH(rxWaveform, cfg, raCfg, grant, tx)
%RECOVERMSG3PUSCH Decode Msg3 PUSCH/UL-SCH at gNB.
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.ra.recoverMsg3PUSCH","MSG3","UL",struct("Stage","RX"));
rx=sixgr.phy.ra.receiveMsg3PUSCHPhysical(rxWaveform,cfg,raCfg,grant);
puschRx=rx;
if logical(puschRx.Ok)
    if string(sixgr.util.structGet(raCfg,'RRCEncodingProfile',""))=="nr_rrc_access_base_srb1_uper_v1"
        bits=reshape(double(puschRx.TransportBlock),8,[]).';
        bytes=uint8(bits*(2.^(7:-1:0)).');
        msg3=sixgr.mac.ra.parseNRInitialAccessMACPDU("UL",bytes);
    else
        payloadBits = int8(puschRx.TransportBlock(1:double(tx.Msg3BitLength)));
        msg3 = sixgr.mac.ra.parseMsg3Payload(payloadBits);
    end
else
    msg3 = struct();
end
end
