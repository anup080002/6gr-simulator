function obs = normalizeCSIRSPowerReference(obs, cfg)
% Convert the numerical power reference without changing measurement authority.
fixedNormalizedEsN0 = strcmpi(string(sixgr.util.structGet( ...
    cfg, "integration.run_mode", "")), "FIXED_SNR_SWEEP") && ...
    logical(sixgr.util.structGet(cfg, ...
    "integration.configured_snr_is_link_authority", false));
if ~fixedNormalizedEsN0
    return;
end
assert(~logical(sixgr.util.structGet(obs,'MeasurementPowerReferenceNormalized',false)), ...
    'sixgr:phy:CSIRSPowerReferenceAlreadyNormalized', ...
    'Normalize CSI-RS power references exactly once; do not replace retained relative measurements.');
available=string(sixgr.util.structGet(obs,'PhysicalMeasurementStatus',"not_attempted"))=="available";
rsrp=double(sixgr.util.structGet(obs,'MeasurementRSRP_dBm',NaN));
assert(isscalar(available) && (~available || (isscalar(rsrp) && isfinite(rsrp))), ...
    'sixgr:phy:MissingCSIRSPowerMeasurement', ...
    'An available selected-resource CSI-RSRP claim requires its finite measurement.');
% The producer measures grid/(Nfft*sqrt(1000)) and returns dBm. Thus its
% numerical value is 10*log10(grid power)-20*log10(Nfft). A unit occupied-RE
% reference requires undoing that FFT scale; renaming dBm alone is wrong.
% This changes only reported units, never waveform power, noise or RSRQ.
nfft=double(sixgr.util.structGet(obs,'MeasurementFFTSize',NaN));
scale=double(sixgr.util.structGet(obs,'MeasurementGridScaleToSqrtW',NaN));
numeric=["MeasurementRSRP","MeasurementRSSI", ...
    "MeasurementRSRQNumeratorRSRP","MeasurementRSRQDenominatorRSSI"];
textual=["MeasurementRSRPPerReceiveAntenna","MeasurementRSRPPerResource", ...
    "MeasurementRSSIPerReceiveAntenna"];
for name=numeric
    value=double(sixgr.util.structGet(obs,name+"_dBm",NaN));
    [obs.(name+"_dB_re_UnitOccupiedRE_Es"),offset]= ...
        sixgr.phy.refsig.convertCSIRSPowerToUnitRE(value,nfft,scale);
end
for name=textual
    value=string(sixgr.util.structGet(obs,name+"_dBm",""));
    obs.(name+"_dB_re_UnitOccupiedRE_Es")= ...
        sixgr.phy.refsig.convertCSIRSPowerToUnitRE(value,nfft,scale);
end
obs.MeasurementPowerReferenceOffset_dB=offset;
obs.MeasurementRSRP_dBm = NaN;
obs.MeasurementRSRPPerReceiveAntenna_dBm = "";
obs.MeasurementRSRPPerResource_dBm = "";
obs.MeasurementRSRPPerResourceValues_dBm = [];
obs.MeasurementRSRPPerAntennaByResource_dBm = {};
obs.MeasurementRSSI_dBm = NaN;
obs.MeasurementRSSIPerReceiveAntenna_dBm = "";
obs.MeasurementRSRQNumeratorRSRP_dBm = NaN;
obs.MeasurementRSRQDenominatorRSSI_dBm = NaN;
obs.MeasurementPhysicalResources = {};
obs.MeasurementPhysicalResourcesJSON = "";
obs.MeasurementGridScaleToSqrtW = NaN;
obs.MeasurementReceiverGainCorrectionSource = ...
    "not_applicable_normalized_fixed_esn0";
obs.PowerReferencePlane = "normalized_fixed_esn0_unit_occupied_re_es";
obs.MeasurementPowerReferenceNormalized = true;
if available
    obs.MeasurementSource = ...
        "actual_csirs_re_measurement_relative_to_unit_occupied_re_es";
    obs.PhysicalMeasurementStatus = ...
        "available_normalized_fixed_esn0_not_absolute_dbm";
end
end
