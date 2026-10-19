function row=bindServingPowerEvidence(row,state,ue,cellIndex)
% Separate a large-scale model calculation from actual calibrated RX IQ.
% Does not change cell selection, waveform scaling, or measurement samples.
model=double(state.LargeScaleState.RxPower_dBm(ue,cellIndex));
mode=string(sixgr.util.structGet(state,'NoiseOperatingMode', ...
    sixgr.util.structGet(state,'CfgMobility.run.noiseOperatingMode','')));
row.ModelPredictedRxPower_dBm=model;
row.ModelPredictedRxPowerSource="large_scale_model_not_receiver_sample_measurement";
row.PowerEvidenceContractVersion="ServingPower/v2";
row.RxPower_dBm=NaN;
row.RxPowerSource="unavailable_no_calibrated_receiver_power_observation";
% This compatibility alias may represent an explicitly absolute model,
% never a measured waveform power. Path loss alone does not calibrate IQ.
if lower(mode)=="receiver_noise_figure_thermal_noise" && ...
        logical(sixgr.util.structGet(state,'LargeScaleState.PathlossEnabled',false))
    row.RxPower_dBm=model;
    row.RxPowerSource="model_link_budget_not_receiver_sample_measurement";
end
row.RxPowerValueRole="model_or_unavailable_not_waveform_measurement";
end
