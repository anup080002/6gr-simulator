classdef SSBPowerReferenceLifecycle
% Retained UE SSB-filter authority, separate from spatial-relation age.
% No PHY, filter arithmetic, measurement replacement or age expiry here.
% The production callers retain the original capture configuration fields
% before delivery and copy the returned context onto the filtered row.
methods (Static)
    function [state,r]=install(state,ue,common)
        % Called with an actually delivered decoded common configuration,
        % before replacing UECommonCellConfigurationByUE. Initial SSB input
        % may precede first SIB1 delivery; a later power change may not reuse
        % that input. Repeated equal power does not reset a retained filter.
        cfg=state.CfgMobility;
        [base,clock]=localContext(state,cfg,ue);
        assert(string(sixgr.util.structGet(state,'RuntimeViewMode',"execution"))~="future_ul_grant_planning", ...
            'sixgr:truth:SSBPowerLifecyclePlanningInstall','Install only at original delivery, not in a planning view.');
        [available,~]=localCommon(common,base,clock);
        assert(available,'sixgr:truth:SSBPowerLifecycleCommon', ...
            'Install only received common power available in this exact reference context.');
        old=localRecord(state,ue);
        if ~isempty(fieldnames(old)) && old.ContextSHA256==base.SHA256 && ...
                old.ReferencePower_dBm==common.SSPBCHBlockPower_dBm
            r=old; return;
        end
        changed=~isempty(fieldnames(old)) && old.ContextSHA256==base.SHA256;
        if changed
            first=clock.Now;
            generation=localHash(struct('Context',base.SHA256,'Previous',old.GenerationSHA256, ...
                'ReferencePower_dBm',common.SSPBCHBlockPower_dBm,'Effective',first));
            reason="decoded_reference_power_changed";
        else
            if clock.Shared
                first=common.ReceivedDLTimingReference.ObservationStartSample;
            else
                first=base.SweepPointStartSlot;
            end
            generation=localInitialGeneration(base,first);
            reason="first_received_power_for_reference_context";
        end
        r=struct('ContractVersion',"sixgr.truth.SSB_power_reference_lifecycle/v1", ...
            'Source',"received_common_power_and_original_filtered_SSB_context", ...
            'Context',base,'ContextSHA256',base.SHA256,'GenerationSHA256',generation, ...
            'ReferencePower_dBm',double(common.SSPBCHBlockPower_dBm), ...
            'FirstSIB1TreeHash',string(common.TreeHash),'InstalledSlot',double(common.AvailableSlot), ...
            'InstalledAt',clock.Now,'MinimumObservationStart',double(first), ...
            'ClockDomain',clock.Domain,'Reason',reason,'AgeExpiryApplied',false);
        r.SHA256=localHash(r);
        items=sixgr.util.structGet(state,'SSBPowerReferenceLifecycleByUE',cell(state.NumUsers,1));
        assert(iscell(items),'sixgr:truth:SSBPowerLifecycleState','Lifecycle storage must be a cell array.');
        items{ue}=r;
        state.SSBPowerReferenceLifecycleByUE=items;
    end

    function [ok,c]=filterContext(state,measurement)
        % Before ReferenceRSRPFilter.observe: no old-generation input is
        % allowed to contaminate a new filter. Missing authority is not a
        % fabricated measurement. Malformed supplied clocks fail loudly.
        m=localMeasurement(measurement);
        [base,clock]=localContext(state,state.CfgMobility,m.TargetId);
        c=struct('Eligible',false,'Status',"reference_context_mismatch", ...
            'ContextSHA256',base.SHA256,'GenerationSHA256',"", ...
            'ClockDomain',clock.Domain,'ReferenceConfigurationEpoch',base.ReferenceConfigurationEpoch);
        ok=false;
        if m.ServingCell~=base.ServingCell || m.ProducerSlot<base.SweepPointStartSlot, return; end
        [valid,start,status]=localObservation(m,base,clock);
        if ~valid, c.Status=status; return; end
        r=localRecord(state,m.TargetId);
        if isempty(fieldnames(r)) || r.ContextSHA256~=base.SHA256
            % Only the original full acquisition producer may provisionally
            % filter before first received common power. Each capture has a
            % distinct key; earlier unknown-power captures cannot mix in.
            if clock.Shared && string(sixgr.util.structGet(m,'MeasurementSource',""))~= ...
                    "CoupledTruthRuntime.applyPBCHTrial.exact_sss_power_measurement"
                c.Status="awaiting_received_common_power_for_capture"; return;
            end
            first=start;
            if ~clock.Shared, first=base.SweepPointStartSlot; end
            c.GenerationSHA256=localInitialGeneration(base,first);
            c.Status="provisional_original_acquisition_capture";
        else
            if start<r.MinimumObservationStart
                c.Status="observation_precedes_reference_power_generation"; return;
            end
            c.GenerationSHA256=r.GenerationSHA256;
            c.Status="retained_reference_power_generation";
        end
        ok=true; c.Eligible=true;
    end

    function [T,status,r]=select(state,cfg,ue,selected,T)
        % Filter original retained rows only. The normal causal consumer
        % still selects the latest delivered row and applies sample clocks.
        localInteger(selected,0,'reference ID');
        assert(istable(T),'sixgr:truth:SSBPowerLifecycleRows','Supply the original measurement table.');
        [base,clock]=localContext(state,cfg,ue);
        r=localRecord(state,ue); status="no_received_reference_power_lifecycle";
        if isempty(fieldnames(r)), T=T([],:); return; end
        if r.ContextSHA256~=base.SHA256
            status="reference_configuration_changed"; T=T([],:); return;
        end
        acquired=string(sixgr.util.structGet(state,'CellAcquisitionState',strings(0,1)));
        if numel(acquired)<ue || ~any(acquired(ue)==["acquired","not_required"])
            status="serving_reference_not_synchronized"; T=T([],:); return;
        end
        common=sixgr.util.structGet(state,'UECommonCellConfigurationByUE',{});
        if ~iscell(common) || numel(common)<ue || isempty(common{ue})
            T=T([],:); return;
        end
        common=common{ue};
        [available,commonStatus]=localCommon(common,base,clock);
        if ~available
            status=commonStatus; T=T([],:); return;
        end
        if r.InstalledAt>clock.Now || r.InstalledSlot>clock.KnownSlot
            status="future_lifecycle_installation_not_available"; T=T([],:); return;
        end
        if common.SSPBCHBlockPower_dBm~=r.ReferencePower_dBm
            status="received_power_change_not_installed"; T=T([],:); return;
        end
        names=["SignalType","TargetType","TargetId","ServingCell","ResourceId", ...
            "SSBPowerReferenceContextSHA256","SSBPowerReferenceGenerationSHA256", ...
            "SSBPowerReferenceClockDomain","UEFilteredRSRP_dBm","UERSRPFilterConfigHash"];
        if ~all(ismember(names,string(T.Properties.VariableNames)))
            status="missing_original_filtered_reference_context"; T=T([],:); return;
        end
        mask=false(height(T),1);
        for k=1:height(T)
            q=table2struct(T(k,:));
            if string(q.SignalType)~="SSB" || string(q.TargetType)~="UE", continue; end
            localInteger(q.TargetId,1,'target UE'); localInteger(q.ServingCell,1,'serving cell');
            localInteger(q.ResourceId,0,'reference ID');
            if q.TargetId~=ue || q.ServingCell~=base.ServingCell || q.ResourceId~=selected, continue; end
            if string(q.SSBPowerReferenceContextSHA256)~=r.ContextSHA256 || ...
                    string(q.SSBPowerReferenceGenerationSHA256)~=r.GenerationSHA256 || ...
                    string(q.SSBPowerReferenceClockDomain)~=clock.Domain || ...
                    string(q.UERSRPFilterConfigHash)~=base.FilterConfigHash, continue; end
            m=localMeasurement(q);
            [valid,start]=localObservation(m,base,clock);
            mask(k)=valid && start>=r.MinimumObservationStart && ...
                isnumeric(q.UEFilteredRSRP_dBm) && isreal(q.UEFilteredRSRP_dBm) && ...
                isscalar(q.UEFilteredRSRP_dBm) && isfinite(q.UEFilteredRSRP_dBm);
        end
        T=T(mask,:);
        status="retained_filtered_reference_available";
        if isempty(T), status="no_observation_for_current_reference_power_generation"; end
    end
end
end

function [base,c]=localContext(state,cfg,ue)
localInteger(ue,1,'UE'); localInteger(state.NumUsers,1,'UE population');
assert(ue<=state.NumUsers && numel(state.CurrentServingIdx)>=ue, ...
    'sixgr:truth:SSBPowerLifecycleIdentity','UE must belong to the original runtime population.');
cellId=state.CurrentServingIdx(ue); localInteger(cellId,1,'serving cell');
epoch=sixgr.util.structGet(cfg,'initial_access.configuration_epoch',NaN);
localInteger(epoch,0,'reference configuration epoch');
policy=sixgr.rrc.resolvePreconnectionRSRPFilter(cfg);
assert(~isempty(fieldnames(policy)),'sixgr:truth:SSBPowerLifecycleFilter','Retain the configured UE filter.');
point=sixgr.util.structGet(state,'SweepPointStartSlot',1); localInteger(point,1,'sweep origin');
c=localClock(state);
carrier=sixgr.phy.grid.makeCarrier(cfg);
pci=carrier.NCellID;
installedPCI=sixgr.util.structGet(state,'Layout.bs.nCellId',[]);
if ~isempty(installedPCI)
    assert(isnumeric(installedPCI) && isreal(installedPCI) && isvector(installedPCI) && numel(installedPCI)>=cellId, ...
        'sixgr:truth:SSBPowerLifecycleIdentity','Keep the installed physical-cell identity, not runtime index arithmetic.');
    pci=installedPCI(cellId);
end
localInteger(pci,0,'installed PCI');
assert(pci<=1007,'sixgr:truth:SSBPowerLifecycleIdentity','Installed PCI must be in the NR domain.');
layout=struct('NCellID',double(pci),'NSizeGrid',carrier.NSizeGrid,'NStartGrid',carrier.NStartGrid, ...
    'SubcarrierSpacing',carrier.SubcarrierSpacing,'CyclicPrefix',string(carrier.CyclicPrefix), ...
    'CenterFrequencyHz',sixgr.util.structGet(cfg,'phy.fc_Hz',NaN));
base=struct('UEIndex',double(ue),'ServingCell',double(cellId), ...
    'ReferenceConfigurationEpoch',double(epoch),'FilterConfigHash',policy.ConfigHash, ...
    'SweepPointStartSlot',double(point),'CarrierLayout',layout, ...
    'ClockDomain',c.Domain,'SampleRateHz',c.Fs,'PhysicalEpoch',c.Epoch);
base.SHA256=localHash(base);
end

function c=localClock(state)
slot=state.CurrentSlot; localInteger(slot,1,'current slot');
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
shared=isa(owner,'sixgr.truth.CoupledWaveformStream');
c=struct('Shared',shared,'Domain',"declared_slot_clock_not_shared_PHY", ...
    'Now',double(slot),'KnownSlot',double(slot),'Fs',NaN,'Epoch',NaN);
if shared
    c.Domain="shared_receiver_sample_clock/v1";
    c.Now=owner.Events.NextSampleIndex; c.Fs=owner.SampleRateHz; c.Epoch=owner.Physical.ConfigurationEpoch;
    localInteger(c.Now,0,'physical clock'); localInteger(c.Epoch,0,'physical epoch');
    localReal(c.Fs,'sample rate'); assert(c.Fs>0,'sixgr:truth:SSBPowerLifecycleClock','Sample rate must be positive.');
elseif ~isempty(owner)
    error('sixgr:truth:SSBPowerLifecycleClock','A supplied shared owner must have its actual runtime type.');
end
if string(sixgr.util.structGet(state,'RuntimeViewMode',"execution"))=="future_ul_grant_planning"
    known=state.PlanningDecisionSlot; localInteger(known,1,'planning slot');
    assert(known<=slot,'sixgr:truth:SSBPowerLifecycleClock','Planning knowledge cannot exceed the requested slot.');
    c.KnownSlot=double(known);
    if shared
        now=state.PlanningDecisionSample; localInteger(now,0,'planning sample');
        assert(now<=c.Now && isequal(state.PlanningDecisionSampleRateHz,c.Fs) && ...
            isequal(state.PlanningDecisionClockEpoch,c.Epoch), ...
            'sixgr:truth:SSBPowerLifecycleClock','Use the original frozen planning clock.');
        c.Now=double(now);
    else
        c.Now=double(known);
    end
end
end

function [ok,status]=localCommon(common,b,c)
assert(isstruct(common) && isscalar(common),'sixgr:truth:SSBPowerLifecycleCommon','Supply one decoded common configuration.');
names={'Source','TreeHash','ServingCell','ConfigurationEpoch','AvailableSlot','SSPBCHBlockPower_dBm'};
assert(all(isfield(common,names)),'sixgr:truth:SSBPowerLifecycleCommon','Retain original decoded common identity and power.');
localInteger(common.ServingCell,1,'decoded cell'); localInteger(common.ConfigurationEpoch,0,'decoded epoch');
localInteger(common.AvailableSlot,1,'common availability'); localInteger(common.SSPBCHBlockPower_dBm,-60,'decoded reference power');
assert(common.SSPBCHBlockPower_dBm<=50 && string(common.Source)=="decoded_sib1" && ...
    isscalar(string(common.TreeHash)) && strlength(string(common.TreeHash))>0, ...
    'sixgr:truth:SSBPowerLifecycleCommon','Use received SIB1 power, not transmitter diagnostics or configured substitutes.');
ok=false; status="decoded_common_reference_context_mismatch";
if common.ServingCell~=b.ServingCell || common.ConfigurationEpoch~=b.ReferenceConfigurationEpoch, return; end
status="decoded_common_reference_not_available";
if common.AvailableSlot>c.KnownSlot, return; end
if c.Shared
    assert(isfield(common,'MeasurementClockEpoch'), ...
        'sixgr:truth:SSBPowerLifecycleCommon','Shared common power requires the original completion epoch.');
    localInteger(common.MeasurementClockEpoch,0,'common completion epoch');
    if common.MeasurementClockEpoch~=c.Epoch, status="decoded_common_physical_epoch_changed"; return; end
    d=sixgr.util.structGet(common,'ReceivedDLTimingReference',struct());
    fields={'Source','SampleRateHz','ObservationStartSample','AvailableAtSample','NCellID'};
    assert(isstruct(d) && isscalar(d) && all(isfield(d,fields)), ...
        'sixgr:truth:SSBPowerLifecycleCommon','Shared common power requires its original received acquisition clock.');
    localInteger(d.ObservationStartSample,0,'acquisition start'); localInteger(d.AvailableAtSample,0,'acquisition availability');
    localInteger(d.NCellID,0,'decoded PCI'); localReal(d.SampleRateHz,'acquisition sample rate');
    assert(string(d.Source)=="received_SSB_timing_and_decoded_BCH" && d.NCellID==b.CarrierLayout.NCellID && ...
        d.SampleRateHz==c.Fs && d.ObservationStartSample<d.AvailableAtSample, ...
        'sixgr:truth:SSBPowerLifecycleCommon','Keep the original received acquisition identity and clock.');
    if d.AvailableAtSample>c.Now, return; end
end
ok=true; status="received_common_reference_available";
end

function m=localMeasurement(m)
if istable(m), assert(height(m)==1,'sixgr:truth:SSBPowerLifecycleMeasurement','Use one original measurement.'); m=table2struct(m); end
names={'SignalType','TargetType','TargetId','ServingCell','ResourceId','ProducerSlot','AvailableSlot','Valid'};
assert(isstruct(m) && isscalar(m) && all(isfield(m,names)), ...
    'sixgr:truth:SSBPowerLifecycleMeasurement','Keep original SSB measurement identity, validity and clocks.');
assert(string(m.SignalType)=="SSB" && string(m.TargetType)=="UE", ...
    'sixgr:truth:SSBPowerLifecycleMeasurement','This lifecycle is only for UE SSB power inputs.');
for name=["TargetId","ServingCell","ProducerSlot","AvailableSlot"], localInteger(m.(name),1,name); end
localInteger(m.ResourceId,0,'reference ID');
assert((islogical(m.Valid)||isnumeric(m.Valid)) && isreal(m.Valid) && isscalar(m.Valid) && ...
    isfinite(m.Valid) && any(m.Valid==[0 1]),'sixgr:truth:SSBPowerLifecycleMeasurement','Validity must be scalar binary.');
assert(m.AvailableSlot>=m.ProducerSlot,'sixgr:truth:SSBPowerLifecycleClock','Availability cannot precede source.');
end

function [ok,start,status]=localObservation(m,b,c)
ok=false; start=double(m.ProducerSlot); status="original_observation_unavailable";
if ~m.Valid || m.AvailableSlot>c.KnownSlot, return; end
if m.ProducerSlot<b.SweepPointStartSlot, status="observation_precedes_sweep"; return; end
if c.Shared
    names={'MeasurementClockDomain','ObservationStartSample','ObservationEndSampleExclusive', ...
        'ObservationSampleRateHz','ResultAvailableAtSample','MeasurementClockEpoch', ...
        'ReferenceConfigurationEpoch','SSBPowerReferenceCaptureFilterConfigHash'};
    if ~all(isfield(m,names)), status="missing_original_capture_configuration"; return; end
    for name=["ObservationStartSample","ObservationEndSampleExclusive","ResultAvailableAtSample", ...
            "MeasurementClockEpoch","ReferenceConfigurationEpoch"], localInteger(m.(name),0,name); end
    localReal(m.ObservationSampleRateHz,'observation sample rate');
    assert(m.ObservationEndSampleExclusive>m.ObservationStartSample && ...
        m.ResultAvailableAtSample>=m.ObservationEndSampleExclusive, ...
        'sixgr:truth:SSBPowerLifecycleClock','Keep original nonempty complete capture and availability.');
    status="original_capture_configuration_changed";
    if string(m.MeasurementClockDomain)~=c.Domain || m.MeasurementClockEpoch~=c.Epoch || ...
        m.ObservationSampleRateHz~=c.Fs || m.ReferenceConfigurationEpoch~=b.ReferenceConfigurationEpoch || ...
        string(m.SSBPowerReferenceCaptureFilterConfigHash)~=b.FilterConfigHash, return; end
    status="original_observation_unavailable";
    if m.ResultAvailableAtSample>c.Now, return; end
    start=double(m.ObservationStartSample);
else
    assert(string(sixgr.util.structGet(m,'MeasurementClockDomain',"slot_only"))~="shared_receiver_sample_clock/v1", ...
        'sixgr:truth:SSBPowerLifecycleClock','A shared observation cannot be admitted through a declared slot-only boundary.');
    if ~isfield(m,'ReferenceConfigurationEpoch') || ...
            (isnumeric(m.ReferenceConfigurationEpoch) && isscalar(m.ReferenceConfigurationEpoch) && isnan(m.ReferenceConfigurationEpoch))
        status="missing_original_capture_configuration"; return;
    end
    localInteger(m.ReferenceConfigurationEpoch,0,'reference epoch');
    if m.ReferenceConfigurationEpoch~=b.ReferenceConfigurationEpoch, return; end
end
ok=true; status="original_observation_available";
end

function r=localRecord(state,ue)
r=struct(); items=sixgr.util.structGet(state,'SSBPowerReferenceLifecycleByUE',{});
assert(iscell(items),'sixgr:truth:SSBPowerLifecycleState','Lifecycle storage must be a cell array.');
if numel(items)<ue || isempty(items{ue}), return; end
r=items{ue};
names={'ContractVersion','Context','ContextSHA256','GenerationSHA256','ReferencePower_dBm', ...
    'InstalledSlot','InstalledAt','MinimumObservationStart','ClockDomain','AgeExpiryApplied','SHA256'};
assert(isstruct(r) && isscalar(r) && all(isfield(r,names)) && ...
    string(r.ContractVersion)=="sixgr.truth.SSB_power_reference_lifecycle/v1" && ...
    islogical(r.AgeExpiryApplied) && isscalar(r.AgeExpiryApplied) && ~r.AgeExpiryApplied && ...
    string(r.ContextSHA256)==localHash(rmfield(r.Context,'SHA256')) && ...
    string(r.Context.SHA256)==string(r.ContextSHA256) && string(r.SHA256)==localHash(rmfield(r,'SHA256')), ...
    'sixgr:truth:SSBPowerLifecycleIntegrity','Retain the original lifecycle receipt without edits.');
end

function h=localInitialGeneration(base,first)
h=localHash(struct('Context',base.SHA256,'OriginalInitialCaptureStart',double(first)));
end
function localInteger(x,minimum,label)
localReal(x,label);
assert(x>=minimum && x==fix(x) && abs(x)<=flintmax, ...
    'sixgr:truth:SSBPowerLifecycleIdentity','%s must be an exact safe integer.',label);
end
function localReal(x,label)
assert(isnumeric(x) && ~islogical(x) && isreal(x) && isscalar(x) && isfinite(x), ...
    'sixgr:truth:SSBPowerLifecycleIdentity','%s must be a finite numeric scalar.',label);
end
function h=localHash(x)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(x))));
end
