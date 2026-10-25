classdef DLMeasurementInstallation
% Explicit bounded-LLS higher-layer configuration, NOT decoded dedicated RRC.
% Cold shared access installs it only after received DL acquisition/SIB1.
% Original early CSI/TRS remains diagnostic; no PHY is executed here.
methods (Static)
    function tf=required(state)
        tf=isa(sixgr.util.structGet(state,'SharedWaveformStream',[]), ...
            'sixgr.truth.CoupledWaveformStream') && ...
            logical(sixgr.util.structGet(state,'ControlGating.PBCHRequired',false));
    end

    function state=install(state,ue,cfg)
        if ~sixgr.truth.DLMeasurementInstallation.required(state), return; end
        validateattributes(ue,{'double'},{'scalar','integer','positive','<=',state.NumUsers});
        owner=state.SharedWaveformStream; now=owner.Events.NextSampleIndex;
        common=state.UECommonCellConfigurationByUE{ue};
        dl=sixgr.util.structGet(common,'ReceivedDLTimingReference',struct());
        meta=sixgr.util.structGet(cfg,'lls6g.userContext',struct());
        assert(state.CellAcquisitionState(ue)=="acquired" && ...
            isfinite(state.LastSuccessfulPBCHSlotByUE(ue)) && ...
            state.LastSuccessfulPBCHSlotByUE(ue)<=state.CurrentSlot && ...
            string(sixgr.util.structGet(common,'Source',""))=="decoded_sib1" && ...
            sixgr.util.structGet(common,'ServingCell',NaN)==state.CurrentServingIdx(ue) && ...
            sixgr.util.structGet(common,'ConfigurationEpoch',NaN)==cfg.initial_access.configuration_epoch && ...
            sixgr.util.structGet(common,'AvailableSlot',Inf)<=state.CurrentSlot && ...
            strlength(string(sixgr.util.structGet(common,'TreeHash',"")))>0 && ...
            string(sixgr.util.structGet(dl,'Source',""))=="received_SSB_timing_and_decoded_BCH" && ...
            sixgr.util.structGet(dl,'SampleRateHz',NaN)==owner.SampleRateHz && ...
            sixgr.util.structGet(dl,'NCellID',NaN)==cfg.phy.carrier.NCellID && ...
            sixgr.util.structGet(meta,'UEIndex',NaN)==ue && ...
            sixgr.util.structGet(meta,'RuntimeServingCell',NaN)==state.CurrentServingIdx(ue), ...
            'sixgr:truth:DLMeasurementAcquisitionRequired', ...
            'Install supplied dedicated measurement configuration only after this UE received DL acquisition and common SIB1.');
        localClock(dl.ObservationStartSample); localClock(dl.AvailableAtSample); localClock(now);
        carrier=sixgr.phy.grid.makeCarrier(cfg);
        available=sixgr.phy.frame.slotStartSample(carrier,common.AvailableSlot-1,owner.SampleRateHz);
        assert(dl.ObservationStartSample<dl.AvailableAtSample && dl.AvailableAtSample<=now && available<=now, ...
            'sixgr:truth:DLMeasurementInstallationFuture','Installation cannot precede received acquisition availability.');
        r=struct('ContractVersion',"sixgr.truth.preconfigured_DL_measurement_installation/v1", ...
            'Source',"preconfigured_LLS_higher_layer_after_received_DL_acquisition", ...
            'DecodedDedicatedRRC',false,'UEIndex',ue,'ServingCell',double(state.CurrentServingIdx(ue)), ...
            'NCellID',double(dl.NCellID),'AcquisitionConfigurationEpoch',double(common.ConfigurationEpoch), ...
            'PhysicalConfigurationEpoch',double(owner.Physical.ConfigurationEpoch), ...
            'SampleRateHz',double(owner.SampleRateHz),'EffectiveSample',double(now), ...
            'EffectiveSlot',double(state.CurrentSlot),'SIB1TreeHash',string(common.TreeHash), ...
            'AcquisitionAvailableAtSample',double(dl.AvailableAtSample), ...
            'AcquisitionReferenceSHA256',localHash(dl), ...
            'CSIConfigurationSHA256',sixgr.truth.DLMeasurementInstallation.configurationSHA(cfg,"CSI-RS"), ...
            'TRSConfigurationSHA256',sixgr.truth.DLMeasurementInstallation.configurationSHA(cfg,"TRS"));
        items=sixgr.util.structGet(state,'PreconfiguredDLMeasurementInstallationByUE',cell(state.NumUsers,1));
        if numel(items)>=ue && ~isempty(items{ue})
            old=items{ue};
            % Repeated delivery of the same installation never refreshes
            % the measurement lower-bound or backdates a changed contract.
            names=setdiff(string(fieldnames(r)),["EffectiveSample","EffectiveSlot","AcquisitionAvailableAtSample"]);
            same=all(isfield(old,cellstr(names)));
            if same
                for name=names.', same=same && isequaln(old.(name),r.(name)); end
            end
            if same
                localReceipt(old); return;
            end
        end
        r.SHA256=localHash(r); items{ue}=r;
        state.PreconfiguredDLMeasurementInstallationByUE=items;
    end

    function hash=configurationSHA(cfg,family)
        family=string(family);
        assert(isscalar(family) && any(family==["CSI-RS","TRS"]), ...
            'sixgr:truth:DLMeasurementFamily','Use CSI-RS or TRS.');
        c=sixgr.phy.grid.makeCarrier(cfg);
        % PCI is receiver/cell identity below, not the base layout's PCI.
        % Time counters, traffic, current CQI/CRI and active TCI codepoints
        % are not higher-layer resource configuration.
        m=struct('Family',family,'NSizeGrid',c.NSizeGrid,'NStartGrid',c.NStartGrid, ...
            'SubcarrierSpacing',c.SubcarrierSpacing,'CyclicPrefix',string(c.CyclicPrefix), ...
            'FrameIdentity',sixgr.util.structGet(cfg,'phy.frame.DefaultIdentity',struct()));
        m.CSIRSScramblingID=sixgr.util.structGet(cfg,'reference_signals.csi_rs_scrambling_id',[]);
        if family=="CSI-RS"
            m.Resources=sixgr.util.structGet(cfg,'phy.csirs',struct());
            m.CSIIM=sixgr.util.structGet(cfg,'phy.csiim',struct());
            m.Reporting=sixgr.util.structGet(cfg,'phy.csi',struct());
            if isfield(m.Reporting,'selectedCRI'), m.Reporting=rmfield(m.Reporting,'selectedCRI'); end
        else
            m.Resources=sixgr.util.structGet(cfg,'phy.trs',struct());
            q=sixgr.util.structGet(cfg,'phy.pdsch.qclTCI',struct());
            m.TimingQCL=struct();
            for name=["enabled","configuration_epoch", ...
                    "source_max_age_slots","timing_search_radius_samples"]
                m.TimingQCL.(name)=sixgr.util.structGet(q,name,[]);
            end
            m.TimingQCL.EffectiveTimingSourceResourceID=sixgr.util.structGet(q, ...
                'timing_source_resource_id',sixgr.util.structGet(q,'source_resource_id',[]));
        end
        hash=localHash(m);
    end

    function [ok,status,r]=current(state,ue,family)
        ok=true; status="standalone_preconfigured_boundary_not_shared_acquisition"; r=struct();
        if ~sixgr.truth.DLMeasurementInstallation.required(state), return; end
        ok=false; status="awaiting_received_DL_acquisition_and_configuration";
        items=sixgr.util.structGet(state,'PreconfiguredDLMeasurementInstallationByUE',{});
        if numel(items)<ue || isempty(items{ue}), return; end
        r=items{ue}; localReceipt(r);
        owner=state.SharedWaveformStream;
        status="DL_measurement_installation_identity_or_configuration_changed";
        if r.UEIndex~=ue || r.ServingCell~=state.CurrentServingIdx(ue), return; end
        cfg=sixgr.truth.CoupledTruthRuntime.measurementConfigurationForUE(state,ue);
        common=sixgr.util.structGet(state,'UECommonCellConfigurationByUE',{});
        if numel(common)<ue || isempty(common{ue}), return; end
        common=common{ue};
        status="DL_measurement_installation_identity_or_configuration_changed";
        if state.CellAcquisitionState(ue)~="acquired" || r.UEIndex~=ue || ...
                r.ServingCell~=state.CurrentServingIdx(ue) || ...
                r.PhysicalConfigurationEpoch~=owner.Physical.ConfigurationEpoch || r.SampleRateHz~=owner.SampleRateHz || ...
                r.AcquisitionConfigurationEpoch~=cfg.initial_access.configuration_epoch || ...
                r.AcquisitionConfigurationEpoch~=sixgr.util.structGet(common,'ConfigurationEpoch',NaN) || ...
                r.ServingCell~=sixgr.util.structGet(common,'ServingCell',NaN) || ...
                string(sixgr.util.structGet(common,'Source',""))~="decoded_sib1" || ...
                r.SIB1TreeHash~=string(sixgr.util.structGet(common,'TreeHash',"")) || ...
                r.AcquisitionReferenceSHA256~=localHash(sixgr.util.structGet(common,'ReceivedDLTimingReference',struct())) || ...
                r.NCellID~=sixgr.util.structGet(common,'ReceivedDLTimingReference.NCellID',NaN) || ...
                r.NCellID~=cfg.phy.carrier.NCellID
            return;
        end
        field="CSIConfigurationSHA256"; if string(family)=="TRS", field="TRSConfigurationSHA256"; end
        if r.(field)~=sixgr.truth.DLMeasurementInstallation.configurationSHA(cfg,family), return; end
        known=owner.Events.NextSampleIndex;
        if string(sixgr.util.structGet(state,'RuntimeViewMode',"execution"))=="future_ul_grant_planning"
            known=state.PlanningDecisionSample;
        end
        status="DL_measurement_installation_not_yet_available";
        if r.EffectiveSample>known || r.EffectiveSlot>state.CurrentSlot, return; end
        ok=true; status="received_acquisition_preconfigured_LLS_measurement_authority";
    end

    function [ok,status]=trackingCurrent(state,ue)
        [ok,status,r]=sixgr.truth.DLMeasurementInstallation.current(state,ue,"TRS");
        if ~ok || ~sixgr.truth.DLMeasurementInstallation.required(state), return; end
        bindings=sixgr.util.structGet(state,'TRSMeasurementInstallationSHA256ByUE',strings(0,1));
        ok=numel(bindings)>=ue && string(bindings(ue))==r.SHA256;
        if ~ok, status="no_TRS_observation_for_current_measurement_installation"; end
    end

    function row=stamp(state,row,cfg,ue,family)
        assert(istable(row) && height(row)==1,'sixgr:truth:DLMeasurementRow','Bind one original receiver row.');
        row.DLMeasurementConfigurationFamily=string(family);
        row.DLMeasurementConfigurationSHA256=sixgr.truth.DLMeasurementInstallation.configurationSHA(cfg,family);
        row.DLMeasurementNCellID=double(cfg.phy.carrier.NCellID);
        [installed,~,r]=sixgr.truth.DLMeasurementInstallation.current(state,ue,family);
        row.DLMeasurementInstallationSHA256="";
        if installed && ~isempty(fieldnames(r)), row.DLMeasurementInstallationSHA256=r.SHA256; end
        [eligible,status]=sixgr.truth.DLMeasurementInstallation.eligible(state,ue,row,family);
        row.DLMeasurementAuthorityRequired=sixgr.truth.DLMeasurementInstallation.required(state);
        row.DLMeasurementAuthorityEligible=eligible;
        row.DLMeasurementAuthorityStatus=status;
        row.DLMeasurementAuthoritySource="preconfigured_LLS_not_decoded_dedicated_RRC";
    end

    function [ok,status]=eligible(state,ue,row,family)
        [ok,status,r]=sixgr.truth.DLMeasurementInstallation.current(state,ue,family);
        if ~ok || ~sixgr.truth.DLMeasurementInstallation.required(state), return; end
        ok=false;
        names=["UEIndex","ServingCell","ObservationStartSample","ObservationEndSampleExclusive", ...
            "ObservationSampleRateHz","MeasurementClockEpoch","DLMeasurementConfigurationFamily", ...
            "DLMeasurementConfigurationSHA256","DLMeasurementNCellID","DLMeasurementInstallationSHA256"];
        status="missing_original_DL_measurement_configuration_binding";
        if ~istable(row) || height(row)~=1 || ~all(ismember(names,string(row.Properties.VariableNames))), return; end
        for name=names([1:6 9])
            value=row.(name);
            assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value), ...
                'sixgr:truth:DLMeasurementIdentity','Original measurement identity/clock must be numeric scalar.');
        end
        for name=names([7:8 10])
            value=row.(name);
            assert((isstring(value)||ischar(value)) && isscalar(string(value)) && ~ismissing(string(value)), ...
                'sixgr:truth:DLMeasurementIdentity','Original configuration bindings must be scalar text.');
        end
        status="DL_measurement_configuration_or_owner_mismatch";
        field="CSIConfigurationSHA256"; if string(family)=="TRS", field="TRSConfigurationSHA256"; end
        if row.UEIndex~=ue || row.ServingCell~=r.ServingCell || row.DLMeasurementNCellID~=r.NCellID || ...
                row.MeasurementClockEpoch~=r.PhysicalConfigurationEpoch || row.ObservationSampleRateHz~=r.SampleRateHz || ...
                string(row.DLMeasurementConfigurationFamily)~=string(family) || ...
                string(row.DLMeasurementConfigurationSHA256)~=r.(field) || ...
                string(row.DLMeasurementInstallationSHA256)~=r.SHA256, return; end
        localClock(row.ObservationStartSample); localClock(row.ObservationEndSampleExclusive);
        assert(row.ObservationEndSampleExclusive>row.ObservationStartSample, ...
            'sixgr:truth:DLMeasurementIdentity','Retain a nonempty original observation interval.');
        status="diagnostic_observation_started_before_configuration_installation";
        if row.ObservationStartSample<r.EffectiveSample, return; end
        available=row.ObservationEndSampleExclusive;
        if ismember('ResultAvailableAtSample',row.Properties.VariableNames), available=row.ResultAvailableAtSample; end
        localClock(available);
        assert(available>=row.ObservationEndSampleExclusive,'sixgr:truth:DLMeasurementIdentity', ...
            'A result cannot precede its original complete observation.');
        known=state.SharedWaveformStream.Events.NextSampleIndex;
        if string(sixgr.util.structGet(state,'RuntimeViewMode',"execution"))=="future_ul_grant_planning"
            known=state.PlanningDecisionSample;
        end
        status="DL_measurement_not_yet_available";
        if available>known, return; end
        ok=true; status="post_installation_original_received_measurement";
    end
end
end

function localReceipt(r)
names={'ContractVersion','Source','DecodedDedicatedRRC','UEIndex','ServingCell','NCellID', ...
    'AcquisitionConfigurationEpoch','PhysicalConfigurationEpoch','SampleRateHz','EffectiveSample', ...
    'EffectiveSlot','SIB1TreeHash','AcquisitionAvailableAtSample','AcquisitionReferenceSHA256', ...
    'CSIConfigurationSHA256','TRSConfigurationSHA256','SHA256'};
assert(isstruct(r) && isscalar(r) && all(isfield(r,names)) && ...
    string(r.ContractVersion)=="sixgr.truth.preconfigured_DL_measurement_installation/v1" && ...
    string(r.Source)=="preconfigured_LLS_higher_layer_after_received_DL_acquisition" && ...
    islogical(r.DecodedDedicatedRRC) && isscalar(r.DecodedDedicatedRRC) && ~r.DecodedDedicatedRRC && ...
    string(r.SHA256)==localHash(rmfield(r,'SHA256')), ...
    'sixgr:truth:DLMeasurementInstallationIntegrity','Retain the original explicit installation receipt.');
for name=["UEIndex","ServingCell","NCellID","AcquisitionConfigurationEpoch", ...
        "PhysicalConfigurationEpoch","EffectiveSample","EffectiveSlot","AcquisitionAvailableAtSample"]
    localClock(r.(name));
end
validateattributes(r.SampleRateHz,{'double'},{'scalar','real','finite','positive'});
end
function localClock(x)
assert(isa(x,'double') && isscalar(x) && isreal(x) && isfinite(x) && x>=0 && x==fix(x) && x<=flintmax, ...
    'sixgr:truth:DLMeasurementClock','Use exact nonnegative double sample/identity coordinates.');
end
function h=localHash(x)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(x))));
end
