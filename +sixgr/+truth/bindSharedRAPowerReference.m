function [cfg,decision]=bindSharedRAPowerReference(cfg,state,ue,slot)
% PRACH power and, for an actual shared owner, selected-beam clock admission.
% This is called BEFORE retry preparation, LastPRACH or pending-attempt mutation.
[cfg,decision]=sixgr.truth.bindSharedSSBPowerReference( ...
    cfg,state,ue,slot,cfg.random_access.associated_ssb_index);
fixedNormalizedEsN0 = sixgr.rf.isNormalizedFixedSNRPowerReference(cfg);
if fixedNormalizedEsN0
    % Initial-access configuration and SSB association remain receiver
    % owned. Absolute pathloss is deliberately not an input to a normalized
    % configured-Es/N0 LLS, so lack of dBm-calibrated RSRP must not block a
    % legal PRACH occasion or trigger a geometry/model fallback.
    sib1Usable = isfinite(double(decision.SIB1AvailableSlot)) && ...
        double(decision.SIB1AvailableSlot) <= double(slot) && ...
        strlength(strtrim(string(decision.SIB1RxTreeHash))) > 0;
    decision.ReferenceUsable(:) = logical(sib1Usable);
    decision.Pathloss_dB(:) = NaN;
    decision.ReferenceSignalTxEPRE_dBm(:) = NaN;
    decision.MeasuredRSRP_dBm(:) = NaN;
    decision.FilteredRSRP_dBm(:) = NaN;
    decision.PhysicalDiagnosticPathloss_dB(:) = NaN;
    decision.Source(:) = ...
        "decoded_sib1_ssb_association_fixed_esn0_no_power_reference";
    decision.OperatingPointAuthority = repmat( ...
        "configured_occupied_re_esn0",height(decision),1);
    if sib1Usable
        decision.Status(:) = ...
            "available_decoded_sib1_fixed_esn0_power_not_applicable";
        decision.Blocker(:) = "";
    else
        decision.Status(:) = "no_available_decoded_sib1";
        decision.Blocker(:) = ...
            "fixed_esn0_prach_still_requires_received_sib1_current_epoch";
    end
end
if isfield(state,'SharedWaveformStream')
    assert(isa(state.SharedWaveformStream,'sixgr.truth.CoupledWaveformStream'), ...
        'sixgr:truth:ReceivedSSBTimingOwnerRequired','Use the installed original shared receiver owner.');
    for name=["SharedULTimingContext","SharedRATimingBinding"]
        if isfield(cfg,name), cfg=rmfield(cfg,name); end
    end
    decision.SelectedSSBTimingAvailable=false;
    decision.SelectedSSBTimingStatus="not_evaluated_before_received_SI_and_power_admission";
    decision.SelectedSSBTimingObservationID="";
    decision.SelectedSSBTimingBindingSHA256="";
    decision.SelectedSSBTimingCaptureEndSample=NaN;
    decision.SelectedSSBTimingDeliveredAtSample=NaN;
    decision.SelectedSSBTimingAcquisitionGenerationID="";
    if decision.ReferenceUsable
        [available,status,timing]=sixgr.truth.ReceivedSSBTimingDelivery.current( ...
            state,ue,cfg,cfg.random_access.associated_ssb_index);
        decision.SelectedSSBTimingAvailable=available;
        decision.SelectedSSBTimingStatus=status;
        if ~available
            decision.ReferenceUsable=false;
            decision.Status="no_available_selected_ssb_timing";
            decision.Blocker=status;
            return;
        end
        common=state.UECommonCellConfigurationByUE{ue};
        assert(common.ServingCell==timing.OriginalBCHBinding.ServingCell && ...
            isfield(common,'ULTimingAdvanceOffset'), ...
            'sixgr:truth:ULTimingReferenceIdentity', ...
            'Selected received timing and the received common UL offset must belong to the same serving cell.');
        cfg.SharedULTimingContext=struct('DLReference',timing.ReceivedDLTimingReference, ...
            'Offset',common.ULTimingAdvanceOffset);
        cfg.SharedRATimingBinding=timing;
        decision.SelectedSSBTimingObservationID=timing.OriginalBCHBinding.ObservationID;
        decision.SelectedSSBTimingBindingSHA256=timing.BindingSHA256;
        decision.SelectedSSBTimingCaptureEndSample=timing.OriginalBCHBinding.CaptureEndSampleExclusive;
        decision.SelectedSSBTimingDeliveredAtSample=timing.DeliveredAvailableSample;
        decision.SelectedSSBTimingAcquisitionGenerationID=timing.AcquisitionGenerationID;
    end
end
end
