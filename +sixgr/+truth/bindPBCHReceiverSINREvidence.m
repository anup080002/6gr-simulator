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
replay=sixgr.util.structGet(receiver,'RuntimeChannelReplay',struct());
if isstruct(replay) && isscalar(replay) && ~isempty(fieldnames(replay))
    variance=double(sixgr.util.structGet(replay,'InjectedNoiseVariance',NaN));
    row.RuntimeNoiseApplied=isfinite(variance) && variance>0;
    row.RuntimeNoiseVarianceMean=variance;
    row.RuntimeNoiseVarianceDomain="time_sample_per_receive_branch";
    row.RuntimeChannelStateUsed=logical(sixgr.util.structGet(replay,'RuntimeChannelStateUsed',false));
    row.RuntimeChannelLinkKeys=string(sixgr.util.structGet(replay,'RuntimeChannelLinkKey',""));
    row.AppliedAWGNSNR_dB=double(sixgr.util.structGet(replay,'AppliedAWGNSNR_dB',NaN));
    row.AppliedAWGNSNRSource=string(sixgr.util.structGet(replay,'AppliedAWGNSNRSource', ...
        sixgr.util.structGet(replay,'NoiseOperatingMode',"")));
end
end
