classdef RARReceiveWindow
    % UE-owned Type1 monitoring. No gNB detector result or TX waveform is
    % accepted by this receiver. All attempts consume complete RX buffers.
    properties (SetAccess=private)
        Config struct
        RAConfig struct
        Window struct
        Status string = "waiting"
        SeenSlots double = zeros(0,1)
        LastCompletionSample double = -1
        Observations table = table()
        Candidates table = table()
        DecodedFields table = table()
        AcceptedResponse struct = struct()
        PreambleBackoff_ms double = 0
        BackoffSource string = "mac_initialization_no_rar_received"
    end
    methods
        function obj=RARReceiveWindow(cfg,ra)
            obj.Config=cfg; obj.RAConfig=ra; obj.Window=ra.RARMonitoringWindow;
            % Re-resolve receiver control from its broadcast authority.
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            [~,common]=sixgr.phy.ra.resolveRARCommonControl(cfg,carrier);
            if common.SearchSpaceID~=obj.Window.SearchSpaceID || common.CORESETID~=obj.Window.CORESETID
                error('sixgr:phy:ra:RARReceiverWindowAuthority','Receiver common control differs from its armed window.');
            end
        end

        function [obj,outcome]=receive(obj,slot,observation,cfgRx)
            if obj.Status~="waiting"
                error('sixgr:phy:ra:RARWindowNotRunning','A stopped RAR window cannot run another decoder.');
            end
            validateattributes(slot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            if ~ismember(slot,obj.Window.MonitoringSlots) || ismember(slot,obj.SeenSlots)
                error('sixgr:phy:ra:UnexpectedRARObservation','The receive slot must be an unconsumed Type1 occasion.');
            end
            if ~isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') || ~observation.isComplete()
                error('sixgr:phy:ra:IncompleteRARObservation','RAR decoding requires a complete actual received observation.');
            end
            expected=obj.Window.MonitoringSlots(numel(obj.SeenSlots)+1);
            if slot~=expected
                error('sixgr:phy:ra:SkippedRARObservation','Every earlier Type1 receive opportunity must be consumed first.');
            end
            spec=obj.Window.Numerology;
            start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,0,spec);
            fs=observation.SampleRateHz;
            tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
            clockOffsetTicks=sixgr.util.structGet(obj.Window,'ClockOffsetTicks',int64(0));
            carrier=sixgr.phy.grid.makeCarrier(obj.Config); info=nrOFDMInfo(carrier);
            if fs~=double(info.SampleRate) || tc~=fix(tc) || ...
                    int64(observation.StartSample)*int64(tc)~=start.Ticks+clockOffsetTicks || ...
                    observation.EndSampleExclusive<=obj.LastCompletionSample
                error('sixgr:phy:ra:RARObservationClockMismatch','RAR samples must retain their physical slot, rate and chronological completion.');
            end
            % Only measured/implementation receiver synchronization may be
            % refreshed; the UE's decoded common/configuration state stays frozen.
            frozen=cfgRx;
            if isfield(frozen,'lls6g') && isfield(frozen.lls6g,'receiverSync')
                frozen.lls6g=rmfield(frozen.lls6g,'receiverSync');
            end
            original=obj.Config;
            if isfield(original,'lls6g') && isfield(original.lls6g,'receiverSync')
                original.lls6g=rmfield(original.lls6g,'receiverSync');
            end
            if ~isequaln(frozen,original)
                error('sixgr:phy:ra:RARReceiverConfigChanged','Only receiverSync may change inside the UE response window.');
            end
            ra=obj.RAConfig; ra.Msg2Slot=slot;
            [rx,rar]=sixgr.phy.ra.recoverMsg2RAR(observation.readComplete(),cfgRx,ra,struct(),struct());
            info=rx.PDCCHInfo;
            dciOK=isfinite(sixgr.util.structGet(info,'SelectedCandidateIndex',NaN));
            tbOK=logical(sixgr.util.structGet(rx,'Ok',false));
            rapidOK=tbOK && isfield(rar,'RAPID') && rar.RAPID==ra.PreambleIndex;
            grant=struct('Valid',false);
            if tbOK && ~isempty(fieldnames(rar.ULGrant))
                grant=sixgr.mac.ra.validateRARULGrant(rar.ULGrant,ra);
            end
            completeTicks=int64(observation.EndSampleExclusive)*int64(tc);
            within=completeTicks<=obj.Window.ExpiryTicksExclusive;
            allocationComplete=true;
            if isfield(rx,'RecoveredSchedule')
                allocation=double(rx.RecoveredSchedule.PDSCH.SymbolAllocation);
                pdschStart=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,allocation(1),spec);
                pdschEnd=pdschStart.plusSymbols(allocation(2),spec);
                allocationComplete=completeTicks>=pdschEnd.Ticks+clockOffsetTicks;
                within=within && pdschStart.Ticks+clockOffsetTicks>=obj.Window.StartTicks && ...
                    pdschEnd.Ticks+clockOffsetTicks<=obj.Window.ExpiryTicksExclusive;
            end
            accepted=dciOK && tbOK && rapidOK && grant.Valid && within && allocationComplete;
            if dciOK && tbOK && within && allocationComplete
                % Normal CBRA initialization sets SCALING_FACTOR_BI=1.
                % Prioritized/LTM/NTN procedures require their own decoded
                % MAC context and are not qualified by this receiver.
                obj.PreambleBackoff_ms=rar.BackoffParameter_ms;
                obj.BackoffSource="decoded_mac_rar_without_bi_zero_ms";
                if rar.BackoffIndicatorPresent, obj.BackoffSource="decoded_mac_rar_bi_table_7_2_1"; end
            end
            reason="dci_crc_fail";
            if dciOK, reason="rar_tb_crc_fail"; end
            if tbOK, reason="rapid_mismatch"; end
            if rapidOK, reason="invalid_rar_ul_grant"; end
            if ~allocationComplete, reason="incomplete_rar_pdsch_observation"; end
            if ~within, reason="reception_after_response_window"; end
            if accepted, reason="matching_rar_received"; end
            identity=struct('RunId',ra.RunId,'CellId',ra.CellId,'UEId',ra.UEId,'AttemptId',ra.AttemptId);
            candidates=sixgr.phy.ra.rarPDCCHCandidateEvidence(identity,ra,info);
            candidates.AbsoluteSlot=repmat(slot,height(candidates),1);
            fields=sixgr.phy.ra.rarDCIFieldEvidence(identity,ra,struct(),rx);
            row=table(string(ra.RunId),double(ra.UEId),double(ra.AttemptId),slot, ...
                double(ra.RARNTI),observation.StartSample,observation.EndSampleExclusive,fs, ...
                double(obj.Window.StartTicks),double(obj.Window.ExpiryTicksExclusive), ...
                height(candidates),dciOK,tbOK,rapidOK,logical(grant.Valid),accepted,reason, ...
                "actual_received_samples_ue_rar_monitoring",false,false, ...
                'VariableNames',{'RunId','UEId','AttemptId','AbsoluteSlot','RARNTI', ...
                'ObservationStartSample','ObservationEndSampleExclusive','SampleRateHz', ...
                'WindowStartTicks','WindowExpiryTicksExclusive','CandidatesAttempted', ...
                'DCICrcPass','PDSCHCrcPass','RAPIDMatches','ULGrantValid','RARAccepted', ...
                'Result','Source','ProxyUsed','FallbackUsed'});
            row.PreambleBackoff_ms=obj.PreambleBackoff_ms;
            row.BackoffSource=obj.BackoffSource;
            obj.Observations=localAppend(obj.Observations,row);
            obj.Candidates=localAppend(obj.Candidates,candidates);
            obj.DecodedFields=localAppend(obj.DecodedFields,fields);
            obj.SeenSlots(end+1,1)=slot;
            obj.LastCompletionSample=observation.EndSampleExclusive;
            outcome=struct('Accepted',accepted,'Receiver',rx,'RAR',rar,'RAConfig',ra, ...
                'Observation',row,'CandidateEvidence',candidates,'DecodedFieldEvidence',fields);
            if accepted
                obj.Status="matched"; obj.AcceptedResponse=outcome;
            end
        end

        function obj=expire(obj,nowTicks)
            now=sixgr.phy.frame.AbsoluteTime.fromTicks(nowTicks);
            if obj.Status=="matched", return; end
            if obj.Status~="waiting" || now.Ticks<obj.Window.ExpiryTicksExclusive
                error('sixgr:phy:ra:PrematureRARTimeout','UE failure cannot precede its response-window expiry.');
            end
            if ~isequal(obj.SeenSlots,obj.Window.MonitoringSlots(:))
                error('sixgr:phy:ra:UnexecutedRARMonitoring','A timer cannot conceal missing Type1 receiver execution.');
            end
            obj.Status="expired";
        end
    end
end

function out=localAppend(previous,current)
if isempty(previous), out=current; else, out=[previous;current]; end
end
