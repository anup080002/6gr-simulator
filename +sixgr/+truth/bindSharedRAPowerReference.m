function [cfg,decision]=bindSharedRAPowerReference(cfg,state,ue,slot)
% Bind the selected SSB's retained physical-reference measurement, never
% geometry. Freshness limits are configured implementation policy, not an
% NR constant. This does NOT qualify the separate SIB1 reference-power and
% higher-layer RSRP-filter signalling contract.
validateattributes(ue,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(slot,{'numeric'},{'scalar','integer','positive','finite'});
if slot~=state.CurrentSlot
    error('sixgr:truth:RAPowerReferenceKnowledgeClock','PRACH reference selection must use the current scheduler knowledge boundary.');
end
selected=cfg.random_access.associated_ssb_index;
validateattributes(selected,{'numeric'},{'scalar','integer','nonnegative','finite'});
age=sixgr.util.structGet(cfg,'phy.pusch.powerControl.maxPathlossMeasurementAgeSlots', ...
    sixgr.util.structGet(cfg,'phy.pusch.power_control.max_pathloss_measurement_age_slots',Inf));
validateattributes(age,{'numeric'},{'scalar','real','nonnegative','nonnan'});
configured=sixgr.phy.refsig.resolveConfiguredPathlossReference(cfg);
if configured.Available, age=min(age,configured.MaximumAgeSlots); end
measurement=sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalPathlossRuntime( ...
    state,'SSB','UE',ue,slot,age,selected);
% Clear an earlier generic/model pathloss before considering the actual
% reference. A deferred attempt must not retain a usable numeric substitute.
meta=cfg.lls6g.userContext;
meta.RuntimeServingPathloss_dB=NaN;
meta.RuntimeServingPathlossSource='unavailable_selected_ssb_measurement';
meta.RuntimeServingPathlossReferenceRS='';
meta.RuntimeServingPathlossMeasurementId='';
meta.RuntimeServingPathlossMeasurementSlot=NaN;
meta.RuntimeServingPathlossMeasurementAgeSlots=NaN;
meta.RuntimeServingPathlossReferenceSignalType='SSB';
meta.RuntimeServingPathlossReferenceSignalId=selected;
pathloss=NaN; txEPRE=NaN; rsrp=NaN;
if measurement.Usable
    row=measurement.SelectedRow;
    pathloss=double(row.Pathloss_dB); txEPRE=double(row.ReferenceSignalTxEPRE_dBm);
    rsrp=double(row.RSRP_dBm);
    if string(row.Direction)~="DL" || any(~isfinite([pathloss txEPRE rsrp])) || ...
            abs(pathloss-(txEPRE-rsrp))>1e-8
        error('sixgr:truth:InvalidRAPowerReference','Selected SSB physical-reference powers and pathloss must close on the same measured row.');
    end
    meta.RuntimeServingPathloss_dB=pathloss;
    meta.RuntimeServingPathlossSource=char(string(row.PathlossSource));
    meta.RuntimeServingPathlossReferenceRS=char(string(row.PathlossReferenceRS));
    meta.RuntimeServingPathlossMeasurementId=char(measurement.MeasurementId);
    meta.RuntimeServingPathlossMeasurementSlot=measurement.ProducerSlot;
    meta.RuntimeServingPathlossMeasurementAgeSlots=measurement.AgeSlots;
end
cfg.lls6g.userContext=meta;
decision=table(double(ue),double(slot),double(selected),logical(measurement.Usable), ...
    string(measurement.Status),string(measurement.Blocker),measurement.MeasurementId, ...
    measurement.ProducerSlot,measurement.AvailableSlot,measurement.AgeSlots,measurement.MinAgeSlots, ...
    double(age),pathloss,txEPRE,rsrp,"actual_scheduler_physical_reference_selection",false,false, ...
    'VariableNames',{'UEId','Slot','SelectedSSBIndex','ReferenceUsable','Status','Blocker', ...
    'MeasurementId','ProducerSlot','AvailableSlot','AgeSlots','MinimumAvailableAgeSlots', ...
    'MaximumAgeSlots','Pathloss_dB','ReferenceSignalTxEPRE_dBm','MeasuredRSRP_dBm','Source','ProxyUsed','FallbackUsed'});
end
