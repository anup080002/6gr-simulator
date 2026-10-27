function plan=prepareInitialNRMACReset(state,ue,expiry)
% non-mutating initial-establishment reset preflight.
id='sixgr:truth:NRRRCInitialReset';
assert(expiry.Expired && ~expiry.ResetExecuted && expiry.Context.UEIndex==ue && ...
    expiry.ExpirySample==state.SharedWaveformStream.Events.NextSampleIndex,id, ...
    'Reset only at the original expired timer sample.');
for name=["NRSRB1RuntimeByUE","NRSetupCompleteByUE","SharedUEMACScopes", ...
        "SharedUEPHRStates","SharedUEBSRStates"]
    values=sixgr.util.structGet(state,name,{});
    assert(numel(values)<ue || isempty(values{ue}), ...
        'sixgr:truth:NRRRCReestablishmentNotIntegrated', ...
        'Initial T300 cannot substitute release for existing bearer/MAC re-establishment.');
end
bridge=sixgr.util.structGet(state,'ProtocolBridge',[]);
assert(isempty(bridge) || ~bridge.hasInstalledRuntime(ue), ...
    'sixgr:truth:NRRRCReestablishmentNotIntegrated', ...
    'An installed target-UE RLC bearer requires its own re-establishment transaction.');
bindings=sixgr.util.structGet(state,'RadioIdentityBindings',struct([]));
assert(isempty(bindings)||~any([bindings.UEIndex]==ue),id, ...
    'Initial T300 cannot clear an already adopted connected radio identity.');
plan=struct('Context',expiry.Context,'ExpirySample',expiry.ExpirySample, ...
    'RequestSHA256',expiry.RequestSHA256,'Archive',struct(),'HARQOwners',{{}}, ...
    'HARQRNTIs',zeros(0,1));
% Preserve the original owner snapshots, including pending received rows.
for name=["PendingRAAttempts","RARetryByUE","ConnectedULTimingByUE", ...
        "SharedUEULPowerControlStates"]
    values=sixgr.util.structGet(state,name,{});
    if numel(values)>=ue,plan.Archive.(name)=values{ue};end
end
if isfield(state,'UEConfiguredSRProcedures') && size(state.UEConfiguredSRProcedures,1)>=ue
    plan.Archive.UEConfiguredSRProcedures=state.UEConfiguredSRProcedures(ue,:);
end
% Before received Setup/C-RNTI adoption, these shared data entities are keyed
% by the explicit configured bootstrap map. The temporary RAR C-RNTI belongs
% only to the pending RA owner; never use it to look up a peer's HARQ entry.
start=double(state.MultiUser.RNTIStart);
assert(isfinite(start)&&start==fix(start)&&start>=1&&start+state.NumUsers-1<=65535,id, ...
    'Require the original installed bootstrap identity map.');
rntis=start+ue-1;
% The shared HARQ object currently keys entries by RNTI without a cell key.
% Even a peer in another cell must not be reached by this target-only reset.
for other=1:state.NumUsers
    if other==ue,continue;end
    otherCell=state.CurrentServingIdx(other);
    otherRNTI=sixgr.truth.CoupledRadioIdentity.resolve(state,other,otherCell);
    assert(otherRNTI~=rntis,'sixgr:truth:NRRRCResetPeerIdentityCollision', ...
        'The target bootstrap HARQ key also identifies a different live UE.');
end
active=sixgr.util.structGet(plan.Archive,'PendingRAAttempts',[]);
if ~isempty(active)
    ra=active.Continuation.RAConfig;
    assert(ra.UEId==ue&&ra.ServingCell==expiry.Context.ServingCell && ...
        any(state.NRRRCSetupAttemptsByUE{ue}.MACAttemptRunIDs==string(ra.RunId)),id, ...
        'The pending MAC attempt must belong to this initial RRC procedure.');
end
% Scheduler/HARQ entities combine endpoint functions. In this initial-only
% domain no connected TB may exist: do not teach gNB HARQ a UE-local expiry.
for name=["DLHarq","ULHarq"]
    h=sixgr.util.structGet(state,name,[]);
    if isempty(h),continue;end
    assert(isa(h,'sixgr.l2.mac.HARQEntity'),id,'Require the actual retained HARQ owner.');
    for rnti=reshape(rntis,1,[])
        idx=find(h.UEList==rnti);
        if isempty(idx),continue;end
        p=h.UEProcs{idx};
        assert(~any([p.Active])&&~any([p.TxCount]>0), ...
            'sixgr:truth:NRRRCReestablishmentNotIntegrated', ...
            'Active connected HARQ needs endpoint-separated reset, not initial-access cleanup.');
        plan.HARQOwners{end+1,1}=h;
        plan.HARQRNTIs(end+1,1)=rnti;
    end
end
end
