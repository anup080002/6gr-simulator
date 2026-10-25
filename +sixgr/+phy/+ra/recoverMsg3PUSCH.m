function [rx, msg3] = recoverMsg3PUSCH(rxWaveform, cfg, raCfg, grant, tx)
%RECOVERMSG3PUSCH Decode Msg3 PUSCH/UL-SCH at gNB.
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.ra.recoverMsg3PUSCH","MSG3","UL",struct("Stage","RX"));
slot = sixgr.phy.ra.resolveMsg3SlotFromRAR(raCfg,grant);
cfgRx = sixgr.phy.ra.localizeRAPUSCHConfig(cfg, raCfg, grant, slot);
[rxWaveform,observationArgs,timingReceipt]=sixgr.phy.ra.resolveRAPUSCHObservation( ...
    rxWaveform,tx.Carrier,tx.PUSCH,"Msg3");
% Decoded TA and channel implementation-delay trimming do not establish
% residual receive alignment. Let PUSCH_Rx acquire DM-RS timing unless an
% actual upstream aligned-waveform contract says it was already applied.
[puschRx, info] = sixgr.phy.ul.PUSCH_Rx(rxWaveform, cfgRx, ...
    "Carrier", tx.Carrier, ...
    "PUSCH", tx.PUSCH, ...
    "TransportBlockSize", double(tx.TransportBlockSize), ...
    "TargetCodeRate", double(grant.TargetCodeRate), ...
    "RV", double(grant.RV), ...
    "InitialIMCSPerCodeword", double(grant.MCS), ...
    "ExecutionProfile", "ra_msg3",observationArgs{:});
rx = puschRx;
rx.Info = info;
if ~isempty(fieldnames(timingReceipt)), rx.ReceivedULTimingReceipt=timingReceipt; end
if logical(puschRx.Ok)
    payloadBits = int8(puschRx.TransportBlock(1:double(tx.Msg3BitLength)));
    msg3 = sixgr.mac.ra.parseMsg3Payload(payloadBits);
else
    msg3 = struct();
end
end
