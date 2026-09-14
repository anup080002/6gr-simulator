function [cfg,decision]=bindSharedSSBPowerReference(cfg,state,ue,slot,selected)
% TS 38.213 clause 7: decoded referenceSignalPower minus UE-filtered RSRP.
% TX EPRE and physical pathloss are diagnostics, never UE input authority.
% Freshness and preconnection filtering are explicit implementation policy.
validateattributes(ue,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(slot,{'numeric'},{'scalar','integer','positive','finite'});
if slot~=state.CurrentSlot
    error('sixgr:truth:SSBPowerReferenceKnowledgeClock','SSB reference selection must use the current scheduler view.');
end
validateattributes(selected,{'numeric'},{'scalar','integer','nonnegative','finite'});
knowledgeSlot=slot;
if string(sixgr.util.structGet(state,'RuntimeViewMode','execution'))=="future_ul_grant_planning"
    knowledgeSlot=state.PlanningDecisionSlot;
    validateattributes(knowledgeSlot,{'numeric'},{'scalar','integer','positive','finite','<=',slot});
end
age=sixgr.util.structGet(cfg,'phy.pusch.powerControl.maxPathlossMeasurementAgeSlots', ...
    sixgr.util.structGet(cfg,'phy.pusch.power_control.max_pathloss_measurement_age_slots',Inf));
validateattributes(age,{'numeric'},{'scalar','real','nonnegative','nonnan'});
configured=sixgr.phy.refsig.resolveConfiguredPathlossReference(cfg);
if configured.Available, age=min(age,configured.MaximumAgeSlots); end
epoch=sixgr.util.structGet(cfg,'initial_access.configuration_epoch',NaN);
policy=sixgr.rrc.resolvePreconnectionRSRPFilter(cfg);
cellId=NaN;
if isfield(state,'CurrentServingIdx') && numel(state.CurrentServingIdx)>=ue
    cellId=state.CurrentServingIdx(ue);
end
T=sixgr.util.structGet(state,'ReferenceSignalMeasurementTable',table());
required=["ResourceId","ServingCell","ReferenceConfigurationEpoch", ...
    "UEFilteredRSRP_dBm","UERSRPFilterSource","UERSRPFilterConfigHash","MeasurementId"];
if ~isempty(fieldnames(policy)) && all(ismember(required,string(T.Properties.VariableNames)))
    mask=T.ResourceId==selected & T.ServingCell==cellId & ...
        T.ReferenceConfigurationEpoch==epoch & isfinite(T.UEFilteredRSRP_dBm) & ...
        string(T.UERSRPFilterSource)==policy.Source & string(T.UERSRPFilterConfigHash)==policy.ConfigHash & ...
        strlength(string(T.MeasurementId))>0;
    T=T(mask,:);
else
    T=T([],:);
end
filteredState=state; filteredState.ReferenceSignalMeasurementTable=T;
measurement=sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime( ...
    filteredState,'SSB','UE',ue,slot,age);
common=struct();
items=sixgr.util.structGet(state,'UECommonCellConfigurationByUE',{});
if iscell(items) && numel(items)>=ue && isstruct(items{ue}), common=items{ue}; end
power=sixgr.util.structGet(common,'SSPBCHBlockPower_dBm',NaN);
powerSlot=sixgr.util.structGet(common,'AvailableSlot',NaN);
treeHash=string(sixgr.util.structGet(common,'TreeHash',''));
commonUsable=string(sixgr.util.structGet(common,'Source',''))=="decoded_sib1" && ...
    strlength(treeHash)>0 && isfinite(power) && power==fix(power) && power>=-60 && power<=50 && ...
    isfinite(powerSlot) && powerSlot>=1 && powerSlot<=knowledgeSlot && ...
    sixgr.util.structGet(common,'ServingCell',NaN)==cellId && ...
    sixgr.util.structGet(common,'ConfigurationEpoch',NaN)==epoch;
if ~commonUsable
    measurement.Usable=false;
    measurement.Status="no_available_decoded_sib1_power";
    measurement.Blocker="selected_cell_requires_received_sib1_power_at_current_epoch_and_knowledge_slot";
end
fixedNormalizedEsN0 = strcmpi(string(sixgr.util.structGet( ...
    cfg,'integration.run_mode','')),'FIXED_SNR_SWEEP') && ...
    logical(sixgr.util.structGet(cfg, ...
    'integration.configured_snr_is_link_authority',false));
if fixedNormalizedEsN0
    % Unit-RE Es/N0 execution has no applied absolute device/link budget.
    % In particular, a numerical SSB reference minus a normalized fading
    % measurement is not a physical pathloss input. Do not clamp it, use a
    % model substitute, or evaluate a physical-power guard before this mode
    % boundary. SIB1 cell/epoch/knowledge checks above remain applicable.
    measurement.Usable=false;
    measurement.Status="not_applicable_normalized_fixed_esn0";
    measurement.Blocker="absolute_power_reference_not_applied_in_this_operating_mode";
end
% Clear every earlier model/reference result before considering this attempt.
meta=cfg.lls6g.userContext;
meta.RuntimeServingPathloss_dB=NaN;
meta.RuntimeServingPathlossSource='unavailable_ue_decoded_filtered_ssb_reference';
meta.RuntimeServingPathlossReferenceRS='';
meta.RuntimeServingPathlossMeasurementId='';
meta.RuntimeServingPathlossMeasurementSlot=NaN;
meta.RuntimeServingPathlossMeasurementAgeSlots=NaN;
meta.RuntimeServingPathlossReferenceSignalType='SSB';
meta.RuntimeServingPathlossReferenceSignalId=selected;
if fixedNormalizedEsN0
    meta.RuntimeServingPathlossSource='not_applicable_normalized_fixed_esn0';
end
pathloss=NaN; txEPRE=NaN; rsrp=NaN; filteredRSRP=NaN; physicalPL=NaN;
filterSource=""; filterHash=""; filterAlpha=NaN; filterCount=NaN;
source="ue_decoded_sib1_power_minus_filtered_ssb_rsrp";
if measurement.Usable
    row=measurement.SelectedRow;
    rsrp=double(row.RSRP_dBm); filteredRSRP=double(row.UEFilteredRSRP_dBm);
    pathloss=double(power)-filteredRSRP;
    if string(row.Direction)~="DL" || any(~isfinite([rsrp filteredRSRP pathloss])) || pathloss<0
        error('sixgr:truth:InvalidSSBPowerReference','Selected UE SSB reference must have finite received powers and nonnegative pathloss.');
    end
    % These fields may legitimately be unavailable; do not gate UE decisions.
    if ismember('ReferenceSignalTxEPRE_dBm',row.Properties.VariableNames), txEPRE=double(row.ReferenceSignalTxEPRE_dBm); end
    if ismember('Pathloss_dB',row.Properties.VariableNames), physicalPL=double(row.Pathloss_dB); end
    filterSource=string(row.UERSRPFilterSource); filterHash=string(row.UERSRPFilterConfigHash);
    filterAlpha=double(row.UERSRPFilterEffectiveAlpha); filterCount=double(row.UERSRPFilterUpdateCount);
    meta.RuntimeServingPathloss_dB=pathloss;
    meta.RuntimeServingPathlossSource=char(source);
    meta.RuntimeServingPathlossReferenceRS=char("SSB-"+string(selected));
    meta.RuntimeServingPathlossMeasurementId=char(measurement.MeasurementId);
    meta.RuntimeServingPathlossMeasurementSlot=measurement.ProducerSlot;
    meta.RuntimeServingPathlossMeasurementAgeSlots=measurement.AgeSlots;
end
cfg.lls6g.userContext=meta;
decision=table(double(ue),double(slot),double(selected),logical(measurement.Usable), ...
    string(measurement.Status),string(measurement.Blocker),measurement.MeasurementId, ...
    measurement.ProducerSlot,measurement.AvailableSlot,measurement.AgeSlots,measurement.MinAgeSlots, ...
    double(age),pathloss,txEPRE,rsrp,source,false,false, ...
    'VariableNames',{'UEId','Slot','SelectedSSBIndex','ReferenceUsable','Status','Blocker', ...
    'MeasurementId','ProducerSlot','AvailableSlot','AgeSlots','MinimumAvailableAgeSlots', ...
    'MaximumAgeSlots','Pathloss_dB','ReferenceSignalTxEPRE_dBm','MeasuredRSRP_dBm','Source','ProxyUsed','FallbackUsed'});
decision.FilteredRSRP_dBm=filteredRSRP;
decision.KnowledgeSlot=double(knowledgeSlot);
decision.PhysicalDiagnosticPathloss_dB=physicalPL;
decision.SignalledSSPBCHBlockPower_dBm=NaN;
decision.SIB1AvailableSlot=NaN; decision.SIB1RxTreeHash="";
if commonUsable
    decision.SignalledSSPBCHBlockPower_dBm=double(power);
    decision.SIB1AvailableSlot=double(powerSlot); decision.SIB1RxTreeHash=treeHash;
end
decision.ServingCell=double(cellId); decision.ReferenceConfigurationEpoch=double(epoch);
decision.UERSRPFilterSource=filterSource; decision.UERSRPFilterConfigHash=filterHash;
decision.UERSRPFilterEffectiveAlpha=filterAlpha; decision.UERSRPFilterUpdateCount=filterCount;
decision.AbsolutePowerReferenceApplicable=~fixedNormalizedEsN0;
decision.OperatingPointAuthority="received_sib1_and_filtered_absolute_rsrp";
if fixedNormalizedEsN0
    decision.Source(:)="normalized_fixed_esn0_no_absolute_power_reference";
    decision.OperatingPointAuthority(:)="configured_occupied_re_esn0";
end
end
