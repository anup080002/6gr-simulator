function [cfg,decision]=bindSharedRAPowerReference(cfg,state,ue,slot)
% PRACH selects its associated SSB; power authority is shared with connected UL.
[cfg,decision]=sixgr.truth.bindSharedSSBPowerReference( ...
    cfg,state,ue,slot,cfg.random_access.associated_ssb_index);
fixedNormalizedEsN0 = strcmpi(string(sixgr.util.structGet( ...
    cfg, "integration.run_mode", "")), "FIXED_SNR_SWEEP") && ...
    logical(sixgr.util.structGet(cfg, ...
    "integration.configured_snr_is_link_authority", false));
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
end
