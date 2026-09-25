function ok=testHARQTransmitterLifecycle()
% Declared MAC lifecycle events; not a physical feedback qualification.
setup6GRSimToolkit('Verbose',false);
for direction=["DL","UL"]
    h=sixgr.l2.mac.HARQEntity(struct(),'Direction',direction, ...
        'NumProcesses',1,'MaxRetx',1);
    assert(isempty(h.getTransmitterLifecycle()));
    g=grant(direction,0);
    h.allocate(321,1,100,'NewData',true);
    h.onTx(321,0,uint8(ones(800,1)),g,1);
    t=h.getTransmitterLifecycle();
    assert(height(t)==1 && ~t.TransmitterTerminal && ...
        ~t.FeedbackObserved && isnan(t.FeedbackAck));
    assert(t.TBId==direction+"-tb-1" && t.PHYGrantContextId=="grant-0-tb-1");
    assert(~any(ismember(["CrcPass","FirstSuccessDelivery","CountedGoodputBits"], ...
        string(t.Properties.VariableNames))));
    assert(h.onFeedback(321,0,"NACK",'SourceSlot',1,'FeedbackSlot',2));
    t=h.getTransmitterLifecycle();
    assert(t.FeedbackObserved && t.FeedbackAck==0 && ~t.TransmitterTerminal);
    h.allocate(321,3,100,'NewData',false);
    h.onTx(321,0,uint8(ones(800,1)),grant(direction,2),3);
    assert(h.onFeedback(321,0,"DTX",'SourceSlot',3,'FeedbackSlot',4));
    t=h.getTransmitterLifecycle();
    assert(height(t)==2 && isequal(t.TransmitterTerminal,[false;true]));
    assert(t.TransmitterTerminalReason(2)=="retry_limit_release");
    assert(t.TBId(1)==t.TBId(2));
    before=t;
    assert(~h.onFeedback(321,0,"ACK",'SourceSlot',3,'FeedbackSlot',5));
    assert(isequaln(before,h.getTransmitterLifecycle()), ...
        'Duplicate/stale feedback cannot rewrite the terminal evidence.');
    h.allocate(321,6,100,'NewData',true);
    h.onTx(321,0,uint8(ones(800,1)),grant(direction,0,2),6);
    assert(h.onFeedback(321,0,"ACK",'SourceSlot',6,'FeedbackSlot',7));
    t=h.getTransmitterLifecycle();
    assert(t.FeedbackAck(3)==1 && t.TransmitterTerminal(3) && ...
        t.TransmitterTerminalReason(3)=="observed_ack_release");
    assert(t.TBId(3)~=t.TBId(1));
    assert(all(t.Source=="transmitter_HARQ_state_not_receiver_CRC"));
    s=struct('CurrentSweepPointIndex',1,'CurrentSNR_dB',-10);
    s.(char(direction+"Harq"))=h;
    snapshot=sixgr.truth.captureHARQTransmitterLifecycle(s);
    assert(height(snapshot)==3 && all(snapshot.SweepPointIndex==1));
    assert(isequaln(snapshot,sixgr.truth.captureHARQTransmitterLifecycle(s)), ...
        'Repeated publication must not append duplicate lifecycle rows.');
    s.HARQTransmitterLifecycleArchive=snapshot;
    s.(char(direction+"Harq"))=sixgr.l2.mac.HARQEntity(struct(),'Direction',direction);
    s.CurrentSweepPointIndex=2; s.CurrentSNR_dB=20;
    assert(isequaln(snapshot,sixgr.truth.captureHARQTransmitterLifecycle(s)), ...
        'An independent sweep reset must retain old point identities.');
end
scheduledOnlyTerminal();
fprintf('HARQ_TRANSMITTER_LIFECYCLE_PASS declared_MAC_only=1\n');
ok=true;
end

function scheduledOnlyTerminal()
root=fileparts(which('setup6GRSimToolkit'));
saved=load(fullfile(root,'docs','lls','evidence_20260913', ...
    'scheduled_ul_dai_03','scheduled_ul_dai_0.mat'),'fixed');
g=saved.fixed;
if isfield(g,'HARQTBContext'), g=rmfield(g,'HARQTBContext'); end
h=sixgr.l2.mac.HARQEntityUL(struct(),'NumProcesses',1,'MaxRetx',1);
a=h.allocate(g.RNTI,g.Slot,g.TBSBytes); g.HARQ=a.HARQ;
h.onScheduledULGrant(g,"initial_command");
h.onTx(g.RNTI,0,uint8(mod((1:g.TBSBits)',2)),g,g.Slot);
assert(h.onFeedback(g.RNTI,0,"NACK",'SourceSlot',g.Slot,'FeedbackSlot',g.Slot+1));
r=h.peekRetx(g.RNTI); missed=g; missed.Slot=g.Slot+10; missed.HARQ=r.HARQ;
missed.PHYGrant.GrantContextId="missed_retransmission_command";
h.onScheduledULGrant(missed,"missed_command");
assert(h.onFeedback(g.RNTI,0,"DTX",'SourceSlot',missed.Slot,'FeedbackSlot',missed.Slot+1));
t=h.getTransmitterLifecycle();
assert(height(t)==1 && t.AttemptSlot==g.Slot && t.TransmitterTerminal);
assert(t.TransmitterTerminalReason=="retry_limit_release" && ...
    t.TerminalAtSlot==missed.Slot+1 && t.TerminalFeedbackSourceSlot==missed.Slot && ...
    t.TerminalFeedbackOutcome=="DTX" && t.TerminalScheduledAttemptCount==2);
assert(h.Stats.Tx==1 && h.Stats.Drop==1 && height(h.TerminalLedger)==1, ...
    'Missed retransmission DCI must not add a fake physical TX to the population.');
end

function g=grant(direction,rv,epoch)
if nargin<3, epoch=1; end
layout=sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',rv,'Modulation','QPSK', ...
    'NumLayers',1,'RateMatchedBitCount',2748);
g=struct('TBSBits',800,'Direction',direction,'Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout, ...
    'TransportBlockId',direction+"-tb-"+string(epoch), ...
    'PHYGrantContextId',"grant-"+string(rv)+"-tb-"+string(epoch));
end
