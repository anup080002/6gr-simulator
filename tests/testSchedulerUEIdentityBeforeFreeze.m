function ok = testSchedulerUEIdentityBeforeFreeze()
% Reproduce the two-UE TDD failure at the actual scheduler/freeze boundary.
% Inputs are declared scheduler states, not claimed physical CSI/ACK samples.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(string(cfg.validation.pucch_resources.multi_user_assignment.mode)== ...
    "ue_ordinal_modulo_resource_set");
% Slot 56 in the run log is absolute slot 55. No access simulation or
% report-richness campaign is needed to exercise this scheduler boundary.
slot=55;
budget=struct('PRBSet',cfg.phy.pdsch.prbSet, ...
    'SymbolAllocation',cfg.phy.pdsch.symbolAllocation, ...
    'ControlAbsoluteSlot',slot, ...
    'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
    'PDCCHCCEBudget',8,'DefaultPDCCHAggregationLevel',8,'MaxUEPerSlot',1);
ue=repmat(struct('RNTI',0,'UEIndex',0,'ServingCell',1, ...
    'DLBufferBytes',0,'ULBufferBytes',0,'CQI',8,'RI',1,'PMI',0,'CRI',0, ...
    'HeadOfLineDelay_ms',1,'ControlEligible',true,'GrantControlState','ok', ...
    'PDCCHAggregationLevel',8,'ReceivedCSIReport',struct()),1,2);
% Deliberately different from both array positions and each other. Radio
% identifiers are not UE ordinals; a missing ordinal cannot use the RNTI.
ue(1).RNTI=4660; ue(1).UEIndex=1;
ue(2).RNTI=4661; ue(2).UEIndex=2;
checked=0;
for kind=["PF","RR"]
    for selected=1:2
        states=ue([2 1]);
        owner=find([states.UEIndex]==selected);
        states(owner).DLBufferBytes=20000;
        sch=localScheduler(cfg,kind,[]);
        [grants,~]=sch.schedule(slot,states,budget);
        assert(isscalar(grants),'Exactly one declared active UE must receive a grant.');
        g=grants(1);
        localAssertIdentity(g,states(owner));
        assert(g.PUCCHResourceIndicator==selected-1 && ...
            g.DCI.FieldValues.pucch_resource_indicator==selected-1, ...
            'PUCCH and packed DCI must use the installed UE-ordinal assignment.');
        assert(isempty(fieldnames(sixgr.util.structGet(g,'ReceivedCSIReport',struct()))), ...
            'Identity binding must not manufacture a received CSI report.');
        unchanged=sixgr.l2.mac.bindSchedulerGrantUEIdentity(g,states(owner));
        assert(isequaln(unchanged,g),'Rebinding the same owner must preserve the frozen grant.');
        wrong=states(owner); wrong.UEIndex=3-selected;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(g,wrong), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');
        wrong=states(owner); wrong.RNTI=wrong.RNTI+10;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(g,wrong), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');
        wrong=states(owner); wrong.ServingCell=2;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(g,wrong), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');
        wrong=g; wrong.PHYGrant.ChannelStateKey.UEIndex=3-selected;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(wrong,states(owner)), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');
        wrong=g; wrong.PHYGrant.ChannelStateKey.ServingCell=2;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(wrong,states(owner)), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');
        wrong=g; wrong.PHYGrant.ChannelStateKey.RNTI=states(owner).RNTI+10;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(wrong,states(owner)), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');
        wrong=g; wrong.PHYGrant.HARQProcessKey.RNTI=states(owner).RNTI+10;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(wrong,states(owner)), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');
        % A top-level alias must not rescue absent canonical ownership.
        wrong=g; wrong.PHYGrant=rmfield(wrong.PHYGrant,'ChannelStateKey');
        wrong.PHYGrant.RNTI=states(owner).RNTI;
        localReject(@()sixgr.l2.mac.bindSchedulerGrantUEIdentity(wrong,states(owner)), ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch');

        % A missing UE ordinal must still fail; neither a list position nor
        % a protocol RNTI is permission to invent the configured identity.
        bad=states; bad(owner).UEIndex=NaN;
        localReject(@()localSchedule(cfg,kind,slot,bad,budget), ...
            'sixgr:phy:pucch:MissingUEForResourceAssignment');
        checked=checked+1;
    end
end
fprintf('SCHEDULER_UE_IDENTITY_BEFORE_FREEZE_PASS TDD_cases=%d no_CSI_oracle=1\n',checked);
ok=true;
end

function sch=localScheduler(cfg,kind,harq)
if kind=="PF"
    sch=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL','HARQ',harq);
else
    sch=sixgr.l2.mac.SchedulerRR(cfg,'Direction','DL','HARQ',harq);
end
end

function localSchedule(cfg,kind,slot,ue,budget)
sch=localScheduler(cfg,kind,[]);
sch.schedule(slot,ue,budget);
end

function localAssertIdentity(grant,ue)
assert(grant.UEIndex==ue.UEIndex && grant.ServingCell==ue.ServingCell && ...
    grant.RNTI==ue.RNTI,'Scheduler grant must retain the exact owner before freezing.');
key=grant.PHYGrant.ChannelStateKey;
assert(grant.PHYGrant.IsFrozen && key.UEIndex==ue.UEIndex && ...
    key.ServingCell==ue.ServingCell && key.RNTI==ue.RNTI && ...
    grant.PHYGrant.HARQProcessKey.RNTI==ue.RNTI, ...
    'The frozen physical contract must carry the same UE, cell and radio identity.');
end

function localReject(call,id)
try
    call();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s', ...
        id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
