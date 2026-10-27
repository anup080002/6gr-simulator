function [cfg,ra,msg4,proposal]=buildCellMsg4TransmissionContext(cfg,plan,received,slotAvailable)
% No UE checkpoint/window or intended identity input.
% Original cell Msg3 receive result authorizes one common TC-RNTI response.
id='sixgr:truth:CellMsg4ReceiveAuthority';
assert(received.SHA256==hash(rmfield(received,'SHA256')) && plan.SHA256==hash(rmfield(plan,'SHA256')),id,'Retain original completed receive identity.');
assert(isa(slotAvailable,'function_handle') && received.CRCPass && received.SemanticAccepted && ...
    received.PlanSHA256==plan.SHA256 && received.TemporaryCRNTI==plan.TemporaryCRNTI && ...
    received.ServingCell==plan.ServingCell && received.RAPID==plan.RAPID && ...
    received.ObservationEndSampleExclusive==plan.ReceiveEndSampleExclusive && ...
    received.Message.EncodingProfile=="nr_rrc_access_base_srb1_uper_v1" && ...
    received.Message.RRCSetupRequestPresent,id,'Require the original received CCCH request on its cell grant.');
policy=sixgr.lls6g.config.resolveNRAccessPolicy(cfg.initial_access.rrc);
assert(policy.Enabled,id,'The supported NR procedure must remain explicitly configured.');
ra=plan.RAContext;
ra.OriginalCellRARContextSHA256=ra.ContextSHA256;
ra=rmfield(ra,'ContextSHA256');
ra.TempCRNTI=plan.TemporaryCRNTI;
ra.Msg4PDSCH=allocation(cfg.random_access.msg4_pdsch);
ra.Msg4DCI=cfg.random_access.msg4_dci;
ra.RRCEncodingProfile=policy.EncodingProfile;
ra.RequireRRCSetupComplete=false; % No unauthorised future PUSCH reservation.
ra.Msg4DCIReference=sixgr.phy.ra.resolveMsg4DCIReference(cfg);
% The original gNB role is explicit and is rejected by UE receivers.
assert(ra.Msg4DCIReference.AuthorityRole=="original_gNB_transmitter_configuration",id, ...
    'Do not relabel authored common authority as decoded UE authority.');
context=sixgr.phy.pdcch.TCMsg4DCIContext.create(ra.Msg4DCIReference,ra.TempCRNTI, ...
    ra.Msg4DCI.harq_ack_repetitions_configured);
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);ra.Msg4DCIPayloadBits=schema.RawBits;
msg4=sixgr.mac.ra.buildNRMsg4ContentionResolution(received.Message.ContentionIdentityBytes,policy.TransactionID);
carrier=sixgr.phy.grid.makeCarrier(cfg);frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
common=sixgr.phy.frame.CommonDLResourcePlan(cfg);common.validateSIB1References();
[pdcch,~]=sixgr.phy.ra.resolveRARCommonControl(cfg,carrier);
period=pdcch.SearchSpace.SlotPeriodAndOffset;
delay=cfg.random_access.timing.msg4_processing_delay_slots;
timer=sixgr.mac.ra.resolveContentionResolutionTimer(cfg.random_access,carrier.SubcarrierSpacing);
budget=timer.Slots;
validateattributes(delay,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(budget,{'numeric'},{'scalar','real','finite','integer','positive'});
% This is a gNB planning budget based on its own common configuration and
% scheduled Msg3 slot, not an assertion about the UE's independently started
% contention timer, UE transmission time or successful receipt of Msg4.
first=plan.AbsoluteSlot0+delay;last=plan.AbsoluteSlot0+budget;
ra.Msg4Slot=NaN;rejected=struct('AbsoluteSlot0',{},'Reason',{});
for slot=first:last
    if sixgr.phy.frame.slotStartSample(carrier,slot,plan.SampleRateHz)<received.ObservationEndSampleExclusive,continue;end
    if mod(slot-period(2),period(1))>=pdcch.SearchSpace.Duration,continue;end
    if ~frame.IsDLAllocation(slot,[pdcch.SearchSpace.StartSymbolWithinSlot pdcch.CORESET.Duration]) || ...
            ~frame.IsDLAllocation(slot,[ra.Msg4PDSCH.SymbolStart ra.Msg4PDSCH.NumSymbols]),continue;end
    [available,~]=common.checkPDSCH(ra.Msg4PDSCH,slot);
    if ~available || ~slotAvailable(slot)
        rejected(end+1)=struct('AbsoluteSlot0',slot,'Reason',"original_common_or_prior_cell_resource_overlap"); %#ok<AGROW>
        continue;
    end
    ra.Msg4Slot=slot;break;
end
proposal=struct('ContractVersion',"cell_received_Msg3_Msg4_proposal/v1", ...
    'ServingCell',plan.ServingCell,'TemporaryCRNTI',plan.TemporaryCRNTI, ...
    'OriginalRARComponentID',plan.RARComponentID, ...
    'OriginalReceiveReceiptSHA256',received.SHA256,'OriginalMsg3PlanSHA256',plan.SHA256,'OriginalMsg3MACSHA256',received.ReceivedMACSHA256, ...
    'OriginalCCCHSHA256',received.Message.RRCSetupRequestSHA256, ...
    'OriginalReceiveSHA256',received.OriginalReceiveSHA256, ...
    'AvailableAtSample',received.ObservationEndSampleExclusive,'SampleRateHz',plan.SampleRateHz, ...
    'OriginalCommonContentionTimer',timer,'PlanningBudgetSource',"configured_gNB_common_contention_interval_not_UE_timer", ...
    'Msg4Slot',ra.Msg4Slot,'ResponseSchedulable',isfinite(ra.Msg4Slot), ...
    'RejectedResourceCandidates',rejected,'UEIndex',NaN,'UEReceivedRARRequired',false, ...
    'UEContentionWindowRequired',false,'ReceivedSetupClaimed',false);
proposal.SHA256=hash(proposal);ra.CellMsg4ProposalSHA256=proposal.SHA256;
ra.ContextSHA256=hash(ra);
end
function a=allocation(n)
a=struct('PRBStart',n.prb_start,'NumPRB',n.num_prb,'SymbolStart',n.symbol_start, ...
    'NumSymbols',n.num_symbols,'MCS',sixgr.util.structGet(n,'mcs',0),'Modulation',string(n.modulation), ...
    'TargetCodeRate',n.target_code_rate,'NLayers',sixgr.util.structGet(n,'n_layers',1),'RV',sixgr.util.structGet(n,'rv',0), ...
    'MCSTable',string(sixgr.util.structGet(n,'mcs_table',"qam64")),'EnablePTRS',logical(sixgr.util.structGet(n,'ptrs_enabled',false)));
end
function h=hash(v)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(v))));
end
