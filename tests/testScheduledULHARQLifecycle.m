function ok=testScheduledULHARQLifecycle()
% Declared MAC events. No physical command, decode or 12 dB claim.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
saved=load(fullfile(root,'docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
    'scheduled_ul_dai_0.mat'),'fixed');
g=saved.fixed;
% The retained file is an allocation donor, not prior executed UE history
% for this new declared MAC process.
if isfield(g,'HARQTBContext'), g=rmfield(g,'HARQTBContext'); end
entity=sixgr.l2.mac.HARQEntityUL(struct(),'NumProcesses',1,'MaxRetx',2);
a=entity.allocate(g.RNTI,g.Slot,g.TBSBytes);
g.HARQ=a.HARQ;
entity.onScheduledULGrant(g,"declared_command_1");
p=entity.UEProcs{1};
assert(p.AwaitingFeedback && p.ScheduledAttemptCount==1 && p.TxCount==0 && isempty(p.TB) && ...
    isempty(entity.getDeliveryLedger()) && entity.Stats.Tx==0 && entity.Stats.ScheduledUL==1 && ...
    isnan(p.ScheduledTBContext.FirstTxCanonicalSlot) && ...
    p.ScheduledTBContext.EvidenceRole=="scheduled_receive_not_UE_transmission");
assert(~entity.cancelTentativeTx(g.RNTI,g.HARQ.HarqID) && ~entity.hasPendingRetx(g.RNTI));
before=entity.UEProcs;
reject(@()entity.onScheduledULGrant(g,"declared_command_1"),'sixgr:mac:ScheduledULProcessMismatch');
reject(@()entity.onFeedback(g.RNTI,0,"DTX"),'sixgr:mac:ScheduledULFeedbackClockRequired');
assert(isequaln(before,entity.UEProcs));
assert(~entity.onFeedback(g.RNTI,0,"ACK",'SourceSlot',g.Slot-1,'FeedbackSlot',g.Slot+1));
assert(entity.onFeedback(g.RNTI,0,"DTX",'SourceSlot',g.Slot,'FeedbackSlot',g.Slot+1));
retry=entity.peekRetx(g.RNTI);
assert(retry.HARQ.RV==2 && retry.HARQ.NDI==g.HARQ.NDI && ...
    retry.HARQ.NDIEpoch==g.HARQ.NDIEpoch && retry.HARQ.HARQRound==1 && ...
    isempty(retry.TB) && retry.TBContext.TBSBits==g.TBSBits && entity.Stats.Tx==0);
assert(~entity.onFeedback(g.RNTI,0,"ACK",'SourceSlot',g.Slot,'FeedbackSlot',g.Slot+1));
g2=g; g2.Slot=g.Slot+10; g2.HARQ=retry.HARQ;
g2.PHYGrant.GrantContextId="declared_retry_grant";
bad=g2; bad.TBSBits=bad.TBSBits+8;
before=entity.UEProcs;
reject(@()entity.onScheduledULGrant(bad,"declared_command_2"),'sixgr:mac:ScheduledULTBSChanged');
assert(isequaln(before,entity.UEProcs));
entity.onScheduledULGrant(g2,"declared_command_2");
assert(~entity.hasPendingRetx(g.RNTI) && isempty(entity.peekRetx(g.RNTI)));
replay=entity.scheduledULReplay(g2);
assert(isempty(replay.TB) && replay.TBContext.TBSBits==g.TBSBits && replay.HARQ.HARQRound==1);
% First actual TX after the initial command was missed. It is not a second
% UE transmission, and only these actual payload bits enter delivery state.
bits=uint8(mod((1:g.TBSBits)',2));
entity.onTx(g.RNTI,0,bits,g2,g2.Slot);
p=entity.UEProcs{1};
assert(p.TxCount==1 && p.ScheduledAttemptCount==2 && entity.Stats.Tx==1 && entity.Stats.Retx==0 && ...
    p.LastGrant.IsRetransmission && p.LastGrant.HARQ.IsRetransmission && ...
    p.TBContext.FirstTxCanonicalSlot==g2.Slot && ...
    height(entity.getDeliveryLedger())==1 && isequal(entity.getStoredTB(g.RNTI,0),bits), ...
    'Actual TX count=%g scheduled count=%g first TX slot=%g expected=%g ledger rows=%g.', ...
    p.TxCount,p.ScheduledAttemptCount,p.TBContext.FirstTxCanonicalSlot,g2.Slot,height(entity.getDeliveryLedger()));
assert(entity.onFeedback(g.RNTI,0,"ACK",'SourceSlot',g2.Slot,'FeedbackSlot',g2.Slot+1));
ledger=entity.getDeliveryLedger();
assert(entity.Stats.FirstSuccessDelivery==1 && height(ledger)==1 && ...
    ledger.CountedGoodputBits==g.TBSBits && ledger.AttemptIndex==1 && ledger.NewDataFlag);
% All commands missed: bounded gNB retry policy without fake UE TX/drop TB.
empty=sixgr.l2.mac.HARQEntityUL(struct(),'NumProcesses',1,'MaxRetx',2);
a=empty.allocate(g.RNTI,g.Slot,g.TBSBytes); missing=g; missing.HARQ=a.HARQ;
for n=1:3
    missing.Slot=g.Slot+10*(n-1);
    if n>1, r=empty.peekRetx(g.RNTI); missing.HARQ=r.HARQ; end
    empty.onScheduledULGrant(missing,"declared_miss_"+n);
    assert(empty.onFeedback(g.RNTI,0,"DTX",'SourceSlot',missing.Slot,'FeedbackSlot',missing.Slot+1));
end
assert(empty.hasFreeProcess(g.RNTI) && ~empty.hasPendingRetx(g.RNTI) && ...
    empty.Stats.Tx==0 && empty.Stats.Retx==0 && empty.Stats.Drop==0 && ...
    empty.Stats.ScheduledULDrop==1 && isempty(empty.getDeliveryLedger()));
% A receiver false ACK without a data transmission must not fabricate goodput.
a=empty.allocate(g.RNTI,missing.Slot+10,g.TBSBytes); falseAck=g;
falseAck.Slot=missing.Slot+10; falseAck.HARQ=a.HARQ;
empty.onScheduledULGrant(falseAck,"declared_false_ack_command");
assert(empty.onFeedback(g.RNTI,0,"ACK",'SourceSlot',falseAck.Slot,'FeedbackSlot',falseAck.Slot+1));
assert(empty.Stats.FirstSuccessDelivery==0 && isempty(empty.getDeliveryLedger()));
fprintf('SCHEDULED_UL_HARQ_LIFECYCLE_PASS declared_MAC=1 physical_episodes=0\n');
ok=true;
end

function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
