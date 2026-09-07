function [state,measurement]=filterUEReferenceMeasurement(state,measurement)
% Retain UE-owned filter state, separate from TX/pathloss diagnostic fields.
% Preconnection policy is explicit UE implementation, not received RRC.
if string(measurement.SignalType)~="SSB" || string(measurement.TargetType)~="UE" || ~measurement.Valid, return; end
cfg=sixgr.util.structGet(state,'CfgMobility',struct());
policy=sixgr.rrc.resolvePreconnectionRSRPFilter(cfg);
if isempty(fieldnames(policy)), return; end
epoch=policy.Epoch;
cellId=measurement.ServingCell;
% Epoch zero is valid per the catalog; cell and UE indices are one-based.
validateattributes([cellId measurement.TargetId],{'numeric'},{'finite','integer','positive'});
validateattributes(measurement.ResourceId,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(state.SlotDuration_s,{'numeric'},{'scalar','real','finite','positive'});
source=policy.Source; hash=policy.ConfigHash;
pointStart=sixgr.util.structGet(state,'SweepPointStartSlot',1);
validateattributes(pointStart,{'numeric'},{'scalar','integer','positive','finite'});
key=char("ue_"+string(measurement.TargetId)+"_cell_"+string(cellId)+ ...
    "_ssb_"+string(measurement.ResourceId)+"_start_"+string(pointStart)+"_"+extractBefore(hash,17));
if ~isfield(state,'UEReferenceRSRPFilters'), state.UEReferenceRSRPFilters=struct(); end
if isfield(state.UEReferenceRSRPFilters,key)
    filter=state.UEReferenceRSRPFilters.(key);
else
    filter=sixgr.rrc.ReferenceRSRPFilter(policy.CoefficientK,policy.ReferencePeriod_ms/1000,source);
end
filter=filter.observe(measurement.MeasurementId,measurement.RSRP_dBm, ...
    (measurement.ProducerSlot-1)*state.SlotDuration_s, ...
    (measurement.AvailableSlot-1)*state.SlotDuration_s,(state.CurrentSlot-1)*state.SlotDuration_s);
state.UEReferenceRSRPFilters.(key)=filter;
measurement.UEFilteredRSRP_dBm=filter.FilteredRSRP_dBm;
measurement.UEPreviousFilteredRSRP_dBm=filter.PreviousFilteredRSRP_dBm;
measurement.UERSRPFilterEffectiveAlpha=filter.EffectiveAlpha;
measurement.UERSRPFilterUpdateCount=filter.UpdateCount;
measurement.UERSRPFilterSource=char(source);
measurement.UERSRPFilterConfigHash=char(hash);
measurement.ReferenceConfigurationEpoch=epoch;
end
