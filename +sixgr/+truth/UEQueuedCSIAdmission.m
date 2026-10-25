classdef UEQueuedCSIAdmission
% UE-local pre-binding policy, not network CSI reconfiguration or NR RRC.
% Typed report bits may wait in the queue across private reacquisition.
% Only new waveform preparation is gated; original IQ and gNB evidence are
% immutable. None of these private fields belongs in a receiver hypothesis.
methods (Static)
    function report=stamp(state,report,measurement)
        if ~sixgr.truth.DLMeasurementInstallation.required(state), return; end
        assert(isstruct(report) && isscalar(report) && string(report.Direction)=="DL", ...
            'sixgr:truth:UECSIAdmissionBinding','Bind one original UE DL report.');
        [ok,~]=sixgr.truth.DLMeasurementInstallation.eligible( ...
            state,report.UEIndex,measurement,"CSI-RS");
        assert(ok,'sixgr:truth:UECSIAdmissionBinding', ...
            'A queued payload must retain its eligible original measurement installation.');
        report.UECSIMeasurementInstallationSHA256=string(measurement.DLMeasurementInstallationSHA256);
        report.UECSIMeasurementConfigurationSHA256=string(measurement.DLMeasurementConfigurationSHA256);
        report.UECSIPayloadRetired=false;
        report.UECSIPayloadAdmissionStatus="original_UE_measurement_installation_bound";
    end

    function [ok,status]=eligible(state,report)
        ok=true; status="standalone_preconfigured_UE_payload";
        if string(report.Direction)~="DL" || ...
                ~sixgr.truth.DLMeasurementInstallation.required(state), return; end
        localUE(report.UEIndex,state.NumUsers);
        ok=false; status="missing_original_UE_measurement_installation_binding";
        names=["UECSIMeasurementInstallationSHA256","UECSIMeasurementConfigurationSHA256"];
        if ~all(isfield(report,cellstr(names))), return; end
        for name=names
            v=report.(name);
            assert((isstring(v)||ischar(v)) && isscalar(string(v)) && ~ismissing(string(v)), ...
                'sixgr:truth:UECSIAdmissionBinding','Private installation hashes must be scalar text.');
            if strlength(string(v))==0, return; end
            assert(~isempty(regexp(char(string(v)),'^[0-9a-fA-F]{64}$','once')), ...
                'sixgr:truth:UECSIAdmissionBinding','Retain the exact original installation/configuration SHA256.');
        end
        if isfield(report,'UECSIPayloadRetired')
            assert(islogical(report.UECSIPayloadRetired) && isscalar(report.UECSIPayloadRetired), ...
                'sixgr:truth:UECSIAdmissionBinding','Retirement is an explicit scalar logical policy flag.');
            if report.UECSIPayloadRetired
                status="retired_before_transport_binding_local_installation_changed"; return;
            end
        end
        [installed,status,r]=sixgr.truth.DLMeasurementInstallation.current(state,report.UEIndex,"CSI-RS");
        if ~installed, return; end
        status="retired_before_transport_binding_local_installation_changed";
        if string(report.UECSIMeasurementInstallationSHA256)~=r.SHA256 || ...
                string(report.UECSIMeasurementConfigurationSHA256)~=r.CSIConfigurationSHA256, return; end
        ok=true; status="current_original_UE_measurement_installation";
    end

    function tf=waveformBound(state,report)
        tf=false;
        owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
        if ~isa(owner,'sixgr.truth.CoupledWaveformStream'), return; end
        id=string(report.ReportIdentity);
        for p=reshape(owner.Pending,1,[])
            if p.UE~=report.UEIndex || ~isfield(p.Context,'Prepared'), continue; end
            prepared=p.Context.Prepared;
            if p.Kind=="PUSCH" && isa(prepared,'sixgr.link.PreparedDataTransmission')
                original=prepared.RequestBinding.Grant;
                if string(sixgr.util.structGet(original,'UCIOnPUSCHCSIReportIdentity',""))==id
                    sixgr.truth.validatePreparedPUSCHUCI(original,prepared);
                    tf=true; return;
                end
            elseif any(p.Kind==["PUCCH","PUCCHNotSelected"]) && isa(prepared,'sixgr.link.PreparedUplinkControlTransmission') && ...
                    string(sixgr.util.structGet(p.Context,'CSIReport.ReportIdentity',""))==id
                tf=true; return;
            end
        end
        % A missed UL command can leave an actually encoded PUCCH whose
        % gNB decoder is not selected. Its original producer outlives the
        % PUCCH observation until independent PUSCH completion audits it.
        completed=sixgr.util.structGet(state,'SharedUnselectedPUCCHObservations',{});
        for k=1:numel(completed)
            p=completed{k}.Context;
            if isa(sixgr.util.structGet(p,'Prepared',[]),'sixgr.link.PreparedUplinkControlTransmission') && ...
                    sixgr.util.structGet(p,'CSIReport.UEIndex',NaN)==report.UEIndex && ...
                    string(sixgr.util.structGet(p,'CSIReport.ReportIdentity',""))==id
                sixgr.truth.validateUnselectedPUCCHTransmission(state,p.TransportSelection,p);
                tf=true; return;
            end
        end
    end

    function state=reconcile(state)
        % Only pending producer rows change. No HARQ, receive obligation,
        % latest feedback, grant trace, or physical-owner mutation occurs.
        if ~sixgr.truth.DLMeasurementInstallation.required(state), return; end
        pending=sixgr.util.structGet(state,'PendingCSITable',table());
        if ~ismember('UECSIPayloadRetired',pending.Properties.VariableNames)
            pending.UECSIPayloadRetired=false(height(pending),1);
        end
        if ~ismember('UECSIPayloadAdmissionStatus',pending.Properties.VariableNames)
            pending.UECSIPayloadAdmissionStatus=repmat("not_bound",height(pending),1);
        end
        for k=1:height(pending)
            report=table2struct(pending(k,:));
            if string(report.Direction)~="DL" || report.Processed || report.RightCensored || ...
                    any(string(report.CSIUCITransport)==["pucch_decoded","pusch_decoded"]) || ...
                    sixgr.truth.UEQueuedCSIAdmission.waveformBound(state,report), continue; end
            [ok,status]=sixgr.truth.UEQueuedCSIAdmission.eligible(state,report);
            if ok || sixgr.util.structGet(report,'UECSIPayloadRetired',false), continue; end
            original=string(jsonencode(sixgr.util.jsonSafeValue(report)));
            audit=struct('ReportIdentity',string(report.ReportIdentity),'UEIndex',report.UEIndex, ...
                'SourceSlot',report.SourceSlot,'DueSlot',report.DueSlot, ...
                'RetiredAtSlot',double(state.CurrentSlot),'Reason',status, ...
                'Source',"UE_local_prebinding_policy_not_network_reconfiguration", ...
                'OriginalUEReportJSON',original,'OriginalUEReportSHA256', ...
                string(sixgr.util.sha256Hex(original)));
            history=sixgr.util.structGet(state,'UECSIPayloadRetirements',struct([]));
            if isempty(history), history=audit; else, history(end+1)=audit; end
            state.UECSIPayloadRetirements=history;
            pending.UECSIPayloadRetired(k)=true;
            pending.UECSIPayloadAdmissionStatus=string(pending.UECSIPayloadAdmissionStatus);
            pending.UECSIPayloadAdmissionStatus(k)=status;
        end
        state.PendingCSITable=pending;
    end

    function ids=retiredGrantIDs(state)
        ids=strings(0,1); t=sixgr.util.structGet(state,'PendingCSITable',table());
        if isempty(t) || ~ismember('UECSIPayloadRetired',t.Properties.VariableNames), return; end
        assert(islogical(t.UECSIPayloadRetired) && size(t.UECSIPayloadRetired,2)==1, ...
            'sixgr:truth:UECSIAdmissionBinding','Retirement must remain a logical column.');
        ids="PUCCH-CSI-"+string(t.ReportIdentity(t.UECSIPayloadRetired));
    end

    function t=auditTable(state)
        rows=sixgr.util.structGet(state,'UECSIPayloadRetirements',struct([]));
        t=table(); if isempty(rows), return; end
        for k=1:numel(rows)
            assert(rows(k).Source=="UE_local_prebinding_policy_not_network_reconfiguration" && ...
                rows(k).OriginalUEReportSHA256==string(sixgr.util.sha256Hex(rows(k).OriginalUEReportJSON)), ...
                'sixgr:truth:UECSIAdmissionAudit','Preserve the original retired UE row and its digest.');
        end
        t=struct2table(rows(:),'AsArray',true);
    end
end
end

function localUE(x,n)
assert(isa(x,'double') && isscalar(x) && isreal(x) && isfinite(x) && ...
    x==fix(x) && x>=1 && x<=n,'sixgr:truth:UECSIAdmissionBinding', ...
    'A queued UE payload must retain its original numeric owner.');
end
