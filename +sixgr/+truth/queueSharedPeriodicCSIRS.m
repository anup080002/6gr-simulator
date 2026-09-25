function [state, queued, reason, prepared] = queueSharedPeriodicCSIRS( ...
        state, cfg, ueIdx, slotIdx, frameIdx, rnti, servingCell, snr_dB)
%QUEUESHAREDPERIODICCSIRS Enqueue one configured cell-common CSI-RS receive obligation.
% This boundary is deliberately independent of PDSCH grant/DCI/HARQ state.
arguments
    state (1,1) struct
    cfg (1,1) struct
    ueIdx (1,1) double {mustBeInteger,mustBePositive}
    slotIdx (1,1) double {mustBeInteger,mustBePositive}
    frameIdx (1,1) double {mustBeInteger,mustBePositive}
    rnti (1,1) double {mustBeInteger,mustBePositive}
    servingCell (1,1) double
    snr_dB (1,1) double {mustBeFinite}
end
queued=false;
prepared=struct();
owner=sixgr.util.structGet(state,"SharedWaveformStream",[]);
if ~isa(owner,"sixgr.truth.CoupledWaveformStream")
    reason="shared_physical_stream_unavailable";
    return;
end
if ~logical(sixgr.util.structGet(cfg,"phy.csirs.enable",false))
    reason="csirs_disabled";
    return;
end
dlAllowed=logical(sixgr.util.structGet(state,"CurrentSlotDLAllowed",false)) && ...
    double(sixgr.util.structGet(state,"CurrentSlotDLNumSymbols",0))>0;
if ~dlAllowed
    reason="no_dl_symbols_in_current_tdd_slot";
    return;
end
[scheduled,~]=sixgr.phy.refsig.csirsOccasion(cfg,slotIdx-1);
if ~scheduled
    reason="outside_configured_csirs_calendar";
    return;
end
if ~(isfinite(servingCell) && servingCell>=1 && servingCell==fix(servingCell))
    reason="serving_cell_unresolved";
    return;
end
if owner.hasPending("CSIRS",ueIdx)
    error("sixgr:truth:DuplicatePendingCSIRS", ...
        "UE %d already owns an incomplete CSI-RS observation.",ueIdx);
end
resolvedSNR=sixgr.truth.resolveWaveformOperatingPointMetadata(cfg,snr_dB);
prepared=sixgr.link.prepareCSIRSTransmission(cfg,resolvedSNR, ...
    "RuntimeSlot",slotIdx,"Frame",frameIdx);
context=struct("Config",cfg,"Slot",slotIdx,"Frame",frameIdx, ...
    "RNTI",rnti,"ServingCell",servingCell,"SNR",resolvedSNR, ...
    "UEIndex",ueIdx);
owner.queueDownlink("CSIRS",ueIdx,prepared,context);
queued=true;
reason="configured_periodic_csirs_queued_on_shared_physical_stream";
end
