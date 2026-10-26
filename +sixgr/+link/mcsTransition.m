function [state, result] = mcsTransition(action, cfg, state, input)
%MCSTRANSITION Applied-MCS policy; measurements and HARQ coding stay separate.
% Preview is pure. Only actual new-data TX and delivered feedback mutate state.
if isempty(state), state=struct('Entries',{{}}); end
policy=sixgr.util.structGet(cfg,'phy.linkAdaptation.mcsTransition',struct());
result=struct('Enabled',logical(sixgr.util.structGet(policy,'enabled',false)));
if ~result.Enabled, return; end
up=double(policy.maxUpStep); down=double(policy.maxDownStep); required=double(policy.increaseAckCount);
assert(all(isfinite([up down required])) && all([up down required]>=1) && ...
    all([up down required]==fix([up down required])), ...
    'sixgr:link:MCSTransitionPolicy','MCS transition steps and ACK count must be positive integers.');
action=string(action);
key=localKey(input);
index=[];
for k=1:numel(state.Entries)
    if state.Entries{k}.Key==key, index=k; break; end
end
if isempty(index)
    entry=struct('Key',key,'LastMCS',NaN,'LastPoint',"",'LastSlot',NaN,'Generation',0,'Version',0, ...
        'ACKs',strings(0,1),'NACKs',strings(0,1),'ACKDeliverySlots',zeros(0,1), ...
        'NACKDeliverySlots',zeros(0,1),'SeenFeedback',strings(0,1), ...
        'Transmissions',{{}});
else
    entry=state.Entries{index};
end
if action=="preview"
    target=double(input.MCSIndex);
    assert(isscalar(target)&&isfinite(target)&&target>=0&&target==fix(target), ...
        'sixgr:link:MCSTransitionTarget','Transition preview requires a valid target MCS.');
    point=localPoint(cfg,input);
    decisionSlot=double(input.Slot);
    control=double(sixgr.util.structGet(input,'ControlAbsoluteSlot',NaN));
    scheduled=double(sixgr.util.structGet(input,'ScheduledAbsoluteSlot',NaN));
    if isfinite(control)&&isfinite(scheduled)
        decisionSlot=control+(double(input.Slot)-scheduled);
    end
    assert(~isfinite(entry.LastSlot)||entry.LastSlot<=decisionSlot, ...
        'sixgr:link:MCSTransitionFutureAnchor','MCS preview cannot use a TX committed after its control decision.');
    previous=entry.LastMCS;
    if ~isfinite(previous)
        previous=double(sixgr.util.structGet(cfg,'phy.linkAdaptation.bootstrapMCSIndex',1));
    end
    samePoint=entry.LastPoint==point;
    ackMask=samePoint & entry.ACKDeliverySlots<=decisionSlot;
    nackMask=samePoint & entry.NACKDeliverySlots<=decisionSlot;
    ackCount=nnz(ackMask); nackCount=nnz(nackMask);
    selected=min(target,previous); reason="hold_without_current_point_ACK_confirmation";
    if nackCount>0
        selected=min(target,max(0,previous-down)); reason="received_NACK_down_step";
        if previous-target>down, reason="resolved_AMC_ceiling_overrides_down_step"; end
    elseif target<previous
        selected=target; reason="lower_resolved_AMC_target";
        if previous-target>down, reason="resolved_AMC_ceiling_overrides_down_step"; end
    elseif samePoint && ackCount>=required && target>previous
        selected=min(target,previous+up); reason="received_ACK_confirmed_up_step";
    elseif target==previous
        reason="target_equals_committed_MCS";
    elseif ~samePoint && isfinite(entry.LastMCS)
        reason="new_spatial_point_requires_own_ACKs";
    end
    result=struct('Enabled',true,'ScopeKey',key,'EffectivePreviousMCS',previous, ...
        'OperatingPointGeneration',entry.Generation,'RawTargetMCS',target,'PreviousCommittedMCS',entry.LastMCS, ...
        'AppliedMCS',selected,'Reason',reason,'SpatialPoint',point, ...
        'ACKCount',ackCount,'NACKCount',nackCount,'RequiredACKCount',required, ...
        'MaxUpStep',up,'MaxDownStep',down,'ACKIdentities',entry.ACKs(ackMask),'NACKIdentities',entry.NACKs(nackMask), ...
        'StateVersion',entry.Version,'DecisionSlot',decisionSlot,'RawTargetAuthority', ...
        string(sixgr.util.structGet(input,'MCSSelectionSource','resolved_scheduler_AMC_before_transition')));
    return;
end
if action=="commit"
    if sixgr.phy.grant.isExplicitHARQRetransmission(input), result.Reason="HARQ_retry_preserved"; return; end
    slot=double(input.Slot); mcs=double(input.MCSIndex); point=localPoint(cfg,input);
    pid=double(sixgr.util.structGet(input,'HARQ.HarqID',sixgr.util.structGet(input,'HARQProcess',NaN)));
    assert(all(isfinite([slot mcs pid])) && slot>=0 && mcs>=0, ...
        'sixgr:link:MCSTransitionCommitIdentity','Actual TX needs slot, MCS and HARQ process identity.');
    id=key+"|slot="+string(slot)+"|pid="+string(pid);
    for k=1:numel(entry.Transmissions)
        if entry.Transmissions{k}.ID==id
            assert(entry.Transmissions{k}.MCS==mcs && entry.Transmissions{k}.Point==point, ...
                'sixgr:link:MCSTransitionDuplicateCommit','Conflicting repeated TX commit.');
            result.Reason="duplicate_actual_TX_commit"; return;
        end
    end
    assert(~isfinite(entry.LastSlot)||slot>=entry.LastSlot, ...
        'sixgr:link:MCSTransitionCommitClock','Actual TX commit cannot move backwards.');
    if entry.LastPoint~=point || ~isequal(entry.LastMCS,mcs)
        entry.ACKs=strings(0,1); entry.NACKs=strings(0,1);
        entry.ACKDeliverySlots=zeros(0,1); entry.NACKDeliverySlots=zeros(0,1);
        entry.Generation=entry.Generation+1;
    elseif mcs==0
        entry.NACKs=strings(0,1);
        entry.NACKDeliverySlots=zeros(0,1);
    end
    entry.LastMCS=mcs; entry.LastPoint=point; entry.LastSlot=slot;
    entry.Transmissions{end+1,1}=struct('ID',id,'Slot',slot,'HarqID',pid,'MCS',mcs,'Point',point, ...
        'Generation',entry.Generation);
    result.Reason="actual_new_data_TX_committed";
elseif action=="feedback"
    result.Reason="unmatched_or_ineligible_feedback";
    if isempty(index) || logical(sixgr.util.structGet(input,'IsRetransmission',false)), return; end
    source=double(sixgr.util.structGet(input,'SourceSlot',NaN));
    delivered=double(sixgr.util.structGet(input,'DeliveredSlot',NaN));
    now=double(sixgr.util.structGet(input,'CurrentSlot',NaN));
    pid=double(sixgr.util.structGet(input,'HarqID',NaN));
    outcome=upper(string(sixgr.util.structGet(input,'Outcome',"")));
    if ~all(isfinite([source delivered now pid])) || source>delivered || delivered>now || ...
            ~any(outcome==["ACK","NACK"]), return; end
    id=key+"|slot="+string(source)+"|pid="+string(pid);
    if any(entry.SeenFeedback==id), result.Reason="duplicate_feedback"; return; end
    match=[];
    for k=1:numel(entry.Transmissions)
        if entry.Transmissions{k}.ID==id, match=entry.Transmissions{k}; break; end
    end
    if isempty(match), return; end
    entry.SeenFeedback(end+1,1)=id;
    if match.Point==entry.LastPoint && match.MCS==entry.LastMCS && match.Generation==entry.Generation
        if outcome=="NACK"
            entry.NACKs(end+1,1)=id; entry.ACKs=strings(0,1);
            entry.NACKDeliverySlots(end+1,1)=delivered; entry.ACKDeliverySlots=zeros(0,1);
        elseif isempty(entry.NACKs)
            entry.ACKs(end+1,1)=id;
            entry.ACKDeliverySlots(end+1,1)=delivered;
        end
        result.Reason="received_current_operating_point_"+outcome;
    else
        result.Reason="old_operating_point_feedback";
    end
else
    error('sixgr:link:MCSTransitionAction','Unknown MCS transition action.');
end
if isempty(index), index=numel(state.Entries)+1; end
entry.Version=entry.Version+1;
state.Entries{index,1}=entry;
end

function key=localKey(x)
rnti=double(sixgr.util.structGet(x,'RNTI',NaN));
cellID=double(sixgr.util.structGet(x,'ServingCell',NaN));
direction=upper(string(sixgr.util.structGet(x,'Direction',"")));
assert(all(isfinite([rnti cellID]))&&any(direction==["DL","UL"]), ...
    'sixgr:link:MCSTransitionIdentity','MCS policy requires RNTI/cell/direction.');
key=direction+"|cell="+string(cellID)+"|rnti="+string(rnti);
end

function point=localPoint(cfg,g)
direction=upper(string(g.Direction));
rank=double(sixgr.util.structGet(g,'NumLayers',sixgr.util.structGet(g,'Layers',NaN)));
pmi=double(sixgr.util.structGet(g,'TPMI',NaN));
if direction=="DL" || ~isfinite(pmi), pmi=double(sixgr.util.structGet(g,'PMI',NaN)); end
cri=double(sixgr.util.structGet(g,'CRI',NaN));
basis="";
operator="";
matrices=sixgr.util.structGet(cfg,'phy.csirs.precoderMatrices',[]);
if direction=="DL" && isfinite(cri) && cri>=0 && cri==fix(cri) && cri<size(matrices,3) && ~isempty(matrices)
    basis=string(sixgr.phy.mimo.MatrixContract.digest(double(matrices(:,:,cri+1))));
end
if ~isfinite(pmi) || logical(sixgr.util.structGet(g,'MUMIMOEnabled',false))
    physical=sixgr.util.structGet(g,'PrecodingMatrix',[]);
    logicalMatrix=sixgr.util.structGet(g,'PrecodingMatrixLogicalPorts',[]);
    if isempty(physical) && ~isempty(logicalMatrix)
        F=sixgr.util.structGet(g,'HybridElementToPortMatrix',[]);
        if isempty(F)
            if direction=="DL", role="bs"; signal="PDSCH"; else, role="ue"; signal="PUSCH"; end
            arch=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,role, ...
                'Signal',signal,'NumPorts',size(logicalMatrix,1),'MinimumPorts',rank);
            if arch.HybridBeamformingEnabled, F=arch.HybridElementToPortMatrix; end
        end
        if isempty(F), physical=logicalMatrix; else, physical=F*logicalMatrix; end
    end
    if ~isempty(physical)
        operator=string(sixgr.phy.mimo.MatrixContract.digest(double(physical)));
    end
end
point=string(jsonencode(struct('Rank',rank,'PMI',pmi,'CRI',cri,'Basis',basis, ...
    'ExplicitOperator',operator, ...
    'MCSTable',string(sixgr.link.resolveConfiguredMCSTable(cfg,direction)), ...
    'Configuration',string(sixgr.util.structGet(cfg,'meta.configHash',"")), ...
    'Epoch',sixgr.util.structGet(cfg,'phy.csi.reportConfigurationEpoch',0))));
end
