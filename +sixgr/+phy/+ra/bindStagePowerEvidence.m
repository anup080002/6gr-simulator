function row=bindStagePowerEvidence(row,context)
%BINDSTAGEPOWEREVIDENCE Export actual normalization planes without rescaling.
names=["PowerNormalizationPolicy","FullBWPActivityFactor", ...
    "ReferenceOutputPower_dBm","ExpectedEmittedPower_mW", ...
    "ReferencePowerDomain","ReferenceSampleCount", ...
    "ActualEmittedPowerBackoffFromBudget_dB"];
required=[names,"TotalTxPower_dBm","OutputTotalPower_dBm","PowerClosureError_dB", ...
    "AmplitudeScale","WaveformAmplitudeUnit","TotalTxPowerSource"];
assert(isstruct(context) && all(isfield(context,required)), ...
    'sixgr:phy:ra:MissingStagePowerReference', ...
    'Stage power evidence requires the actual applied PowerContext normalization ledger.');
for name=names, row.(name)=context.(name); end
row.PowerNormalizationPolicy=string(row.PowerNormalizationPolicy);
row.ReferencePowerDomain=string(row.ReferencePowerDomain);
physicalClaim=logical(sixgr.util.structGet(context,"PhysicalDevicePowerClaim",true));
row.PhysicalDevicePowerClaim=physicalClaim;
row.AppliedTxPower_dB_re_UnitOccupiedRE_Es=NaN;
row.MeasuredTxPowerBeforeRF_dB_re_UnitOccupiedRE_Es=NaN;
row.ReferenceOutputPower_dB_re_UnitOccupiedRE_Es=NaN;
row.ExpectedWaveformPower_re_UnitOccupiedRE_Es=NaN;
if physicalClaim
    row.AppliedTxPower_dBm=double(context.TotalTxPower_dBm);
    row.AppliedTxPowerValueRole="configured_signal_power_budget_not_measured_emitted_power";
    row.MeasuredTxPowerBeforeRF_dBm=double(context.OutputTotalPower_dBm);
else
    row.AppliedTxPower_dB_re_UnitOccupiedRE_Es=double(context.TotalTxPower_dBm);
    row.MeasuredTxPowerBeforeRF_dB_re_UnitOccupiedRE_Es=double(context.OutputTotalPower_dBm);
    row.ReferenceOutputPower_dB_re_UnitOccupiedRE_Es=double(context.ReferenceOutputPower_dBm);
    row.ExpectedWaveformPower_re_UnitOccupiedRE_Es=double(context.ExpectedEmittedPower_mW);
    row.AppliedTxPower_dBm=NaN;
    row.MeasuredTxPowerBeforeRF_dBm=NaN;
    row.ReferenceOutputPower_dBm=NaN;
    row.ExpectedEmittedPower_mW=NaN;
    row.AppliedTxPowerValueRole="normalized_waveform_power_not_physical_dbm";
end
row.TxPowerClosureError_dB=double(context.PowerClosureError_dB);
row.PowerContextAmplitudeScale=double(context.AmplitudeScale);
row.WaveformAmplitudeUnit=string(context.WaveformAmplitudeUnit);
row.TxPowerSource=string(context.TotalTxPowerSource);
end
