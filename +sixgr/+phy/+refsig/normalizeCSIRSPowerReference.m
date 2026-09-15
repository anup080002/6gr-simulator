function obs = normalizeCSIRSPowerReference(obs, cfg)
% Change the unit declaration, never the authority to claim a measurement.
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
% The CSI-RS extraction is from the actual received OFDM waveform, but a
% configured Es/N0 run has no antenna-connector watt calibration. Preserve
% relative measurements and prevent the unit-Es numerical map from being
% exported as dBm.
obs.MeasurementRSRP_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSRP_dBm", NaN));
obs.MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = string( ...
    sixgr.util.structGet(obs, "MeasurementRSRPPerReceiveAntenna_dBm", ""));
obs.MeasurementRSRPPerResource_dB_re_UnitOccupiedRE_Es = string( ...
    sixgr.util.structGet(obs, "MeasurementRSRPPerResource_dBm", ""));
obs.MeasurementRSSI_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSSI_dBm", NaN));
obs.MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = string( ...
    sixgr.util.structGet(obs, "MeasurementRSSIPerReceiveAntenna_dBm", ""));
obs.MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSRQNumeratorRSRP_dBm", NaN));
obs.MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(obs, "MeasurementRSRQDenominatorRSSI_dBm", NaN));
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
