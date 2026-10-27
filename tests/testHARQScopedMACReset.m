function ok=testHARQScopedMACReset()
% Declared MAC events verify reset ownership; no RF outcome is authored.
for direction=["DL","UL"]
    h=sixgr.l2.mac.HARQEntity(struct(),'Direction',direction,'NumProcesses',2);
    a=h.allocate(321,1,100);g=grant(direction,a.HARQ,"old");
    h.onTx(321,a.HARQ.HarqID,uint8(zeros(800,1)),g,1);
    h.storeSoftBuffer(321,0,struct('LLRSum',[1;2;3],'ObservationWeight',1));
    peer=h.allocate(654,2,100);pg=grant(direction,peer.HARQ,"peer");
    h.onTx(654,peer.HARQ.HarqID,uint8(zeros(800,1)),pg,2);
    peerBefore=h.UEProcs{h.UEList==654}; ledger=h.DeliveryLedger;stats=h.Stats;
    ctx=struct('ResetSample',30000,'SampleRateHz',30.72e6,'ClockEpoch',1, ...
        'Reason',"initial_T300_expiry",'SourceEventID',"original_T300_UE321");
    r=h.resetUE(321,ctx);p=h.UEProcs{h.UEList==321};
    assert(all(~[p.Active]) && all(~[p.NDI]) && all([p.FeedbackIdentityRequired]));
    assert(isequal(r.NextProcessEpochs,r.PreviousProcessEpochs+1) && ...
        r.SoftBuffersCleared==1 && r.ActualTXProcessesRetired==1 && r.ApplicationBytesDropped==0);
    assert(isequaln(peerBefore,h.UEProcs{h.UEList==654}) && isequaln(ledger,h.DeliveryLedger));
    assert(h.Stats.Tx==stats.Tx && h.Stats.Drop==stats.Drop && height(h.TerminalLedger)==1);
    assert(h.TerminalLedger.TerminalReason=="mac_reset_initial_T300_expiry");
    after=h.UEProcs;assert(isequaln(r,h.resetUE(321,ctx)) && isequaln(after,h.UEProcs));
    changed=ctx;changed.ResetSample=changed.ResetSample+1;
    mustFail(@()h.resetUE(321,changed),'sixgr:mac:HARQResetAuthority');
    assert(~h.onFeedback(321,0,"ACK",'SourceSlot',1,'FeedbackSlot',3));
    fresh=h.allocate(321,5,100);ng=grant(direction,fresh.HARQ,"fresh");
    assert(fresh.HARQ.NDI && fresh.HARQ.NDIEpoch>a.HARQ.NDIEpoch);
    mustFail(@()h.onTx(321,0,uint8(zeros(800,1)),g,1), ...
        'sixgr:mac:StaleHARQTransmissionAfterReset');
    h.onTx(321,0,uint8(zeros(800,1)),ng,5);
    assert(~h.onFeedback(321,0,"ACK"));
    assert(~h.onFeedback(321,0,"ACK",'SourceSlot',1,'FeedbackSlot',6));
    assert(~h.onFeedback(321,0,"ACK",'SourceSlot',5,'FeedbackSlot',6,'NDIEpoch',a.HARQ.NDIEpoch));
    assert(h.onFeedback(321,0,"ACK",'SourceSlot',5,'FeedbackSlot',6,'NDIEpoch',fresh.HARQ.NDIEpoch));
    % Untouched peers retain their original identity and legacy API policy.
    assert(h.onFeedback(654,0,"ACK",'SourceSlot',2,'FeedbackSlot',6));
    assert(height(h.DeliveryLedger)==3 && height(h.TerminalLedger)==3);
end
ok=true;fprintf('HARQ_SCOPED_MAC_RESET_PASS peer_preserved=1 historical_rows_retained=1 stale_feedback_rejected=1 RF=0\n');
end
function g=grant(direction,harq,label)
layout=sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',0,'Modulation','QPSK', ...
    'NumLayers',1,'RateMatchedBitCount',2748);
g=struct('TBSBits',800,'Direction',direction,'Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout, ...
    'HARQ',harq,'TransportBlockId',direction+"-"+label);
end
function mustFail(f,id)
try,f();catch e,assert(string(e.identifier)==string(id),e.message);return;end
error('sixgr:test:ExpectedFailure','Expected %s.',id);
end
