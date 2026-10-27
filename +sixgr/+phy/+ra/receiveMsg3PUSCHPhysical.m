function rx=receiveMsg3PUSCHPhysical(input,cfg,ra,grant)
% Actual PHY decoder, independent of MAC parsing.
% No Msg3 transmitter payload, intended identity or private length is input.
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.ra.receiveMsg3PUSCHPhysical","MSG3","UL",struct("Stage","RX"));
a=sixgr.phy.ra.resolveMsg3PUSCHAllocation(cfg,ra,grant);
[samples,args,timing]=sixgr.phy.ra.resolveRAPUSCHObservation(input,a.Carrier,a.PUSCH,"Msg3");
[rx,info]=sixgr.phy.ul.PUSCH_Rx(samples,a.Config,'Carrier',a.Carrier,'PUSCH',a.PUSCH, ...
    'TransportBlockSize',a.TransportBlockSize,'TargetCodeRate',double(grant.TargetCodeRate), ...
    'RV',double(grant.RV),'InitialIMCSPerCodeword',double(grant.MCS), ...
    'ExecutionProfile','ra_msg3',args{:});
rx.Info=info;
if ~isempty(fieldnames(timing)),rx.ReceivedULTimingReceipt=timing;end
end
