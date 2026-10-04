function contexts = validateSharedDCIConfiguration(cfg)
%VALIDATESHAREDDCICONFIGURATION Validate receiver policy before sample execution.
% Shared scheduled data and independent HARQ reception need the same installed
% paired DCI context. A layout reconstructed from a transmitted grant is not
% receiver configuration. This check consumes no samples and installs nothing.
contexts = struct();
dataEnabled = logical(sixgr.util.structGet(cfg,'phy.pdsch.enable',false)) || ...
    logical(sixgr.util.structGet(cfg,'phy.pusch.enable',false));
if ~dataEnabled
    return;
end
% Both formats participate in monitored-size alignment, including DL-only
% traffic. Use the same factory as independent HARQ/PUSCH receive planning.
contexts.DL = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
contexts.UL = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(contexts.DL);
sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(contexts.UL);
% A valid bit schema alone does not make a connected PDSCH executable.
% With no TCI field, the receiver requires the installed scheduling CORESET
% association. Validate its identity before access/sample generation, not
% after the first successfully decoded data DCI. Activation time is still
% checked at the actual received control occasion by fromInstalled.
if logical(sixgr.util.structGet(cfg,'phy.pdsch.enable',false)) && ...
        ~contexts.DL.Data.ConnectedPolicy.tci_present
    sixgr.pdsch.CORESETQCLReference.policyForContext(cfg,contexts.DL);
end
% SR IDs alone cannot define an independent receive obligation. Validate
% the complete installed calendar before creating the physical clock. The
% calendar validates every resource even when slot 1 is not an SR occasion;
% no positive SR, UE queue state, or transmitted payload is consulted here.
srIDs=sixgr.util.structGet(cfg,'validation.pucch_resources.sr_resource_ids',[]);
srConfigs=sixgr.util.structGet(cfg,'validation.pucch_resources.scheduling_request_resources',struct([]));
if logical(sixgr.util.structGet(cfg,'phy.pucch.enable',false)) && ...
        (~isempty(srIDs) || ~isempty(srConfigs))
    identity=cfg.phy.frame.DefaultIdentity;
    % DCI serving-cell indices are zero-based; runtime cell IDs are one-based.
    cellID=double(contexts.DL.Data.ScheduledServingCell)+1;
    ue=struct('UEID',double(sixgr.util.structGet(cfg,'lls6g.userContext.UEIndex',1)), ...
        'RNTI',double(contexts.DL.Data.RNTIValue),'ServingCell',cellID,'PUCCHCell',cellID, ...
        'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
    sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,1);
end
end
