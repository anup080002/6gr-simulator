function ok=testScheduledType2DAI()
% Scheduling/packed-DCI procedure tests; no UE RX or waveform PASS implied.
setup6GRSimToolkit('Verbose',false);
ledger=struct(); raw=zeros(1,8); semantic=zeros(1,8);
for k=1:8
    a=assignment(k-1,8,1);
    [candidate,entry]=sixgr.truth.nextScheduledType2DAI(ledger,a);
    if k==1
        assert(isempty(fieldnames(ledger)),'A rejected candidate must not advance the input ledger.');
        [retry,retryEntry]=sixgr.truth.nextScheduledType2DAI(ledger,a);
        assert(isequal(retry,candidate) && isequal(retryEntry,entry));
    end
    ledger=candidate; raw(k)=entry.RawDAI; semantic(k)=entry.CounterDAI;
    [retry,same]=sixgr.truth.nextScheduledType2DAI(ledger,a);
    assert(isequal(retry,ledger) && isequal(same,entry));
end
assert(isequal(raw,[0 1 2 3 0 1 2 3]) && isequal(semantic,[1 2 3 4 1 2 3 4]));
% A separate feedback slot/UE does not inherit another codebook's count.
[~,entry]=sixgr.truth.nextScheduledType2DAI(ledger,assignment(8,9,1));
assert(entry.Ordinal==1 && entry.RawDAI==0);
[~,entry]=sixgr.truth.nextScheduledType2DAI(ledger,assignment(7,8,2));
assert(entry.Ordinal==1 && entry.RawDAI==0);
% An unaccepted candidate is discarded. A different accepted next assignment
% still receives the same next ordinal, not a phantom missed-assignment gap.
a=assignment(8,9,1); [~,discarded]=sixgr.truth.nextScheduledType2DAI(ledger,a);
a.GrantID='replacement'; [~,replacement]=sixgr.truth.nextScheduledType2DAI(ledger,a);
assert(replacement.Ordinal==discarded.Ordinal);
a=assignment(7,8,1); a.FeedbackAbsoluteSlot=9;
rejects(@()sixgr.truth.nextScheduledType2DAI(ledger,a),'sixgr:truth:ChangedDAIAssignment');
a=assignment(7,8,1); a.GrantID='second-same-pair';
rejects(@()sixgr.truth.nextScheduledType2DAI(ledger,a),'sixgr:truth:UnsupportedDAIMonitoringPair');
a=assignment(6,8,1); a.GrantID='new-out-of-order';
rejects(@()sixgr.truth.nextScheduledType2DAI(ledger,a),'sixgr:truth:OutOfOrderDAIAssignment');
a=assignment(8,9,1); a.ExpectedACK=true;
rejects(@()sixgr.truth.nextScheduledType2DAI(ledger,a),'sixgr:truth:InvalidDAIAssignment');
[retired,entry]=sixgr.truth.nextScheduledType2DAI(ledger,assignment(10,11,1));
assert(numel(retired.Entries)==1 && entry.Ordinal==1,'Expired groups must not accumulate during long runs.');

% The actual configured connected scheduler packer starts with an authored
% candidate. Finalization changes DAI only; timing, PRI, TBS and frozen PHY
% allocation must remain untouched. This fixture is not an access run.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,1);
grant=sixgr.link.resolveWaveformGrant(cfg,'DL',1,'Slot',1,'SFN',0,'ControlAbsoluteSlot',0);
grant.ServingCell=grant.BaseStationID;
before=grant;
fprintf('SCHEDULED_DAI_INPUT valid=%d required=%d ack_valid=%d format=%s\n', ...
    grant.TimingDecision.Valid,grant.TimingDecision.HARQACKRequired, ...
    grant.TimingDecision.HARQACKDecision.Valid,string(grant.DCI.Format));
[fixed,next]=sixgr.truth.prepareScheduledDLDAI(struct(),cfg,grant);
assert(fixed.DAI==0 && fixed.DAICounterValue==1 && fixed.DAIOrdinal==1);
assert(isequaln(fixed.PHYGrant,before.PHYGrant) && isequaln(fixed.TimingDecision,before.TimingDecision));
old=sixgr.phy.pdcch.decodeDCIPayload(before.DCI.Bits,'1_1',before.DCI.ContextData);
parsed=sixgr.phy.pdcch.decodeDCIPayload(fixed.DCI.Bits,'1_1',fixed.DCI.ContextData);
assert(parsed.Fields.dai==0 && fixed.DCI.FieldValues.DAI==0 && fixed.DCI.FieldValues.dai==0);
for field=string(fieldnames(old.Fields)).'
    if field=="dai", continue; end
    assert(isequaln(old.Fields.(field),parsed.Fields.(field)),'Unrelated decoded field changed: %s',field);
end
assert(string(fixed.DCI.PayloadHash)==parsed.PayloadHash && string(fixed.DCI.PayloadHex)==parsed.PayloadHex);
[again,same]=sixgr.truth.prepareScheduledDLDAI(next,cfg,fixed);
assert(isequaln(again,fixed) && isequaln(same,next));
received=grant; received.ControlDecodeOk=true; received.CRCPass=true; received.ExpectedAck=true;
[other,same]=sixgr.truth.prepareScheduledDLDAI(struct(),cfg,received);
assert(isequal(same,next) && isequal(other.DCI.Bits,fixed.DCI.Bits));
bad=grant; bad.PHYGrant.CodingLayout.NumCodewords=2;
rejects(@()sixgr.truth.prepareScheduledDLDAI(struct(),cfg,bad),'sixgr:truth:UnsupportedScheduledDAIPolicy');
bad=cfg; bad.phy.pdcch.operatorControl.connected_dci.configuration_epoch=2;
rejects(@()sixgr.truth.prepareScheduledDLDAI(struct(),bad,grant),'sixgr:truth:ScheduledDAIContextMismatch');
fprintf('SCHEDULED_TYPE2_DAI_PASS: ordinal wrap, rejected candidates, identity, retirement and real contextual packing\n');
ok=true;
end

function a=assignment(control,feedback,rnti)
a=struct('GrantID',"grant-"+control+"-"+rnti,'RNTI',rnti,'PhysicalServingCell',1, ...
    'ScheduledCCID','CC0','FeedbackAbsoluteSlot',feedback,'ControlAbsoluteSlot',control, ...
    'ControlStartSymbol',0,'ConfigurationEpoch',1);
end

function rejects(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s',id);
end
