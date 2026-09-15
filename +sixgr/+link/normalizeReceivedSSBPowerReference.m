function rec=normalizeReceivedSSBPowerReference(rec,cfg)
% One scale contract for full-burst acquisition and per-occasion tracking.
fixed=strcmpi(string(sixgr.util.structGet(cfg,'integration.run_mode','')),'FIXED_SNR_SWEEP') && ...
    logical(sixgr.util.structGet(cfg,'integration.configured_snr_is_link_authority',false));
if ~fixed, return; end
assert(~isfield(rec,'SSPhysicalMeasurementStatus') || ...
    string(rec.SSPhysicalMeasurementStatus)~="available_normalized_fixed_esn0_not_absolute_dbm", ...
    'sixgr:link:SSBPowerReferenceAlreadyNormalized','Normalize received power exactly once.');
numeric=["SS_RSRP","SS_RSRPRawObserved","ReferenceSignalTxEPRE"];
textual=["SS_RSRPPerReceiveAntenna","SS_RSRPRawObservedPerReceiveAntenna", ...
    "SSBWindowRSSIPerReceiveAntenna","ReferenceSignalTxEPREPerAntenna"];
for name=numeric
    rec.(name+"_dB_re_UnitOccupiedRE_Es")=double(sixgr.util.structGet(rec,name+"_dBm",NaN));
    rec.(name+"_dBm")=NaN;
end
for name=textual
    rec.(name+"_dB_re_UnitOccupiedRE_Es")=string(sixgr.util.structGet(rec,name+"_dBm",""));
    rec.(name+"_dBm")="";
end
rec.MeasuredReferenceSignalChannelGain_dB= ...
    rec.SS_RSRP_dB_re_UnitOccupiedRE_Es-rec.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es;
rec.SSBWindowPowerMeasurementJSON=""; % Its schema declares dBm, unavailable here.
rec.SSSTxPowerDeltaFromSignalled_dB=NaN;
rec.MeasuredReferenceSignalPathloss_dB=NaN;
rec.MeasuredReferenceSignalPathlossSource="unavailable_normalized_fixed_esn0_has_no_absolute_link_budget";
rec.ReferenceSignalTxMeasurementSource="actual_ifft_sss_epre_relative_to_unit_occupied_re_es";
rec.PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es";
rec.SSPhysicalMeasurementStatus="available_normalized_fixed_esn0_not_absolute_dbm";
end
