function [wideband, perRE, info] = applyPostEqSINRResidualBound(wideband, perRE, info, residual)
%APPLYPOSTEQSINRRESIDUALBOUND Receiver-only residual ceiling, not EVM truth.
% Keep the executed equalizer estimate immutable across successive pilot
% and decision-directed bounds. Apply measured layer ceilings independently
% and reduce the resulting RE values using the same mean-dB convention.
% No TX bits, reference channel, injected SNR or CRC outcome is consumed.
if ~logical(sixgr.util.structGet(residual,'Available',false)), return; end
if isempty(perRE) || any(~isfinite(perRE(:))), return; end
layers=size(perRE,2);
ceiling=double(sixgr.util.structGet(residual,'PerLayerSINR_dB',[]));
if isempty(ceiling) && layers==1
    ceiling=double(sixgr.util.structGet(residual,'SINR_dB',NaN));
end
if numel(ceiling)~=layers || any(~isfinite(ceiling))
    error('sixgr:phy:rx:ResidualSINRLayerMismatch', ...
        'A residual bound requires one measured finite ceiling per transmitted layer.');
end
bounded=min(double(perRE),reshape(ceiling,1,[]));
if ~any(bounded(:)<perRE(:)), return; end
kind=string(sixgr.util.structGet(residual,'BoundKind','dmrs_residual'));
if ~any(kind==["dmrs_residual","decision_residual"])
    error('sixgr:phy:rx:UnknownResidualSINRBound','Unknown residual bound kind: %s.',kind);
end
if ~isfield(info,'RawEqualizerSINR_dB')
    info.RawEqualizerSINR_dB=double(sixgr.util.structGet(info,'RawSINR_dB',wideband));
    info.UnboundedSource=string(sixgr.util.structGet(info,'Source','unavailable'));
    info.UnboundedValueStatus=string(sixgr.util.structGet(info,'ValueStatus','unavailable'));
    info.UnboundedNAReason=string(sixgr.util.structGet(info,'NAReason',''));
end
perRE=bounded;
info.PerLayerSINR_dB=mean(perRE,1);
wideband=mean(info.PerLayerSINR_dB);
info.SINR_dB=wideband;
token=string(sixgr.util.structGet(residual,'BoundSourceToken',kind));
info.Source="post_equalization_sinr_from_"+token+"_bounded_equalizer_channel_estimate";
info.ValueRole="measured_post_equalization_scheduling_input";
info.ValueStatus="OK_"+kind+"_bounded";
info.NAReason="receiver_residual_per_layer_ceiling_applied_to_per_RE_equalizer_sinr";
info.ResidualBoundReduction="mean_dB_over_bounded_data_RE_then_layers";
if kind=="dmrs_residual"
    info.DMRSResidualBoundApplied=true;
    info.DMRSResidualSINR_dB=double(sixgr.util.structGet(residual,'SINR_dB',NaN));
    info.DMRSResidualNoiseVariance=double(sixgr.util.structGet(residual,'NoiseVariance',NaN));
else
    info.DecisionResidualBoundApplied=true;
end
info.ReceiverResidualBoundKind=kind;
info.ReceiverResidualBoundSource=string(sixgr.util.structGet(residual,'Source','unavailable'));
end
