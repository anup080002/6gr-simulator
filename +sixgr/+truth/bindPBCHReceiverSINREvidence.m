function row = bindPBCHReceiverSINREvidence(row, receiver, pbch)
%BINDPBCHRECEIVERSINREVIDENCE Preserve actual PBCH receiver values and validity.
% This adapter performs no SINR calculation and supplies no missing metric.
for metric = ["ReceiverHestSINR", "MeasuredTrialSINR", "PostEqSINR"]
    name = metric + "_dB";
    row.(name) = double(sixgr.util.structGet(receiver,name, ...
        sixgr.util.structGet(pbch,name,NaN)));
    for suffix = ["Source", "ValueRole", "ValueStatus", "NAReason"]
        name = metric + suffix;
        row.(name) = string(sixgr.util.structGet(receiver,name, ...
            sixgr.util.structGet(pbch,name,"")));
    end
end
row.ReceiverHestSINRApplicable = logical(row.ChannelEstimateAvailable) && ...
    isfinite(row.ReceiverHestSINR_dB) && ...
    sixgr.util.isAcceptableSINRStatus(row.ReceiverHestSINRValueStatus);
row.PostEqSINRAvailable = logical(sixgr.util.structGet(receiver, ...
    "PostEqSINRAvailable",sixgr.util.structGet(pbch,"PostEqSINRAvailable",false)));
% The availability flag comes from the receiver, not from a finite-number
% test. Missing or contradictory receiver evidence must stay visible.
row.PostEqSINRReceiverDerived = row.PostEqSINRAvailable && ...
    logical(row.EqualizationAvailable) && isfinite(row.PostEqSINR_dB) && ...
    sixgr.util.isAcceptableSINRStatus(row.PostEqSINRValueStatus) && ...
    row.PostEqSINRSource == ...
        "pbch_mmse_harmonic_mean_channel_power_over_pre_equalization_noise";
row.MeasuredSINR_dB = row.MeasuredTrialSINR_dB;
row.SINRValueRole = row.MeasuredTrialSINRValueRole;
row.SINRSource = row.MeasuredTrialSINRSource;
row.SINRValueStatus = row.MeasuredTrialSINRValueStatus;
row.SINRValueDefinition = "measured_trial_sinr_from_pbch_dmrs_channel_estimate";
end
