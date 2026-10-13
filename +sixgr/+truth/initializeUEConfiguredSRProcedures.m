function procedures=initializeUEConfiguredSRProcedures(cfg,nUsers,nCells,rntiStart)
% Install UE-owned SR state only for explicitly configured report owners.
% This is procedure initialization, not a positive SR or received UCI.
validateattributes([nUsers nCells rntiStart],{'numeric'}, ...
    {'real','finite','integer','positive','numel',3});
assert(rntiStart+nUsers-1<=65535,'sixgr:truth:InvalidSRRuntimeIdentity', ...
    'The configured runtime RNTI allocation must fit the 16-bit RNTI domain.');
procedures=cell(nUsers,nCells);
identities=sixgr.phy.pucch.validateUEReportBindings(cfg);
if ~isempty(identities)
    assert(cfg.lls6g.users.n_users==nUsers && cfg.lls6g.users.rnti_start==rntiStart, ...
        'sixgr:truth:SRRuntimeBindingMismatch', ...
        'Runtime UE count and RNTI allocation must match the installed report catalog.');
    for ue=reshape(identities,1,[])
        assert(ue.UEID<=nUsers && ue.ServingCell<=nCells && ...
            ue.RNTI==rntiStart+ue.UEID-1, ...
            'sixgr:truth:SRRuntimeBindingMismatch', ...
            'The installed SR owner must exist in this runtime UE/cell topology.');
        procedures{ue.UEID,ue.ServingCell}= ...
            sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
    end
    return;
end
% Preserve the pre-existing explicitly global installation semantics when
% no per-UE catalog is present. Do not synthesize distinct pilot resources.
if isempty(sixgr.util.structGet(cfg, ...
        'validation.pucch_resources.scheduling_request_resources',struct([])))
    return;
end
identity=cfg.phy.frame.DefaultIdentity;
for index=1:nUsers
    for cellID=1:nCells
        ue=struct('UEID',index,'RNTI',rntiStart+index-1, ...
            'ServingCell',cellID,'PUCCHCell',cellID, ...
            'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
        procedures{index,cellID}=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
    end
end
end
