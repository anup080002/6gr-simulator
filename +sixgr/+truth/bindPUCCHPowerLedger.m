function row=bindPUCCHPowerLedger(row,trial)
% Copy executed PUCCH ledger values without creating RF measurements.
% Shared node-composite post-RF power is not isolated PUCCH power.
numeric=["PUCCHRequestedTxPower_dBm","PUCCHAppliedTxPower_dBm", ...
    "PUCCHPCMAX_dBm","PUCCHPowerHeadroom_dB","PUCCHPowerControlPathloss_dB", ...
    "PUCCHConfiguredPathloss_dB","PUCCHPathlossMeasurementSlot", ...
    "PUCCHPowerControlMRB","PUCCHPowerControlMu","PUCCHPowerBandwidthTerm_dB", ...
    "PUCCHPowerControlTargetHeadroom_dB"];
labels=["PUCCHPowerBandwidthSource","PUCCHAppliedTxPowerReferencePlane", ...
    "PUCCHPathlossSource","PUCCHPathlossReferenceRS","PUCCHPathlossMeasurementId", ...
    "PUCCHPowerHeadroomSource"];
if isfield(trial,'PUCCHPowerHeadroomApplicable')
    row.PUCCHPowerHeadroomApplicable=logical(trial.PUCCHPowerHeadroomApplicable);
end
for name=numeric
    if isfield(trial,name), row.(name)=double(trial.(name)); end
end
for name=labels
    if isfield(trial,name), row.(name)=string(trial.(name)); end
end
end
