classdef Msg4ReceiveWindow
    % UE Type1 CSS receiver during CCCH contention, independent of gNB TX.
    properties (SetAccess=private)
        Config struct
        RAConfig struct
        Window struct
        MAC sixgr.mac.ra.ContentionResolutionState
        SeenSlots double = zeros(0,1)
        Observations table = table()
        LastOutcome struct = struct()
    end
    methods
        function obj=Msg4ReceiveWindow(cfg,ra,grant,identity,physicalTiming)
            assert(physicalTiming.Source=="received_DL_reference_received_RAR_TA_and_common_offset" && ...
                physicalTiming.WaveformTimingApplied, ...
                'sixgr:phy:ra:ContentionTransmitClock','Use the actual UE Msg3 symbol clock, not its gNB decode result.');
            obj.Config=cfg; obj.RAConfig=ra;
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            [~,control]=sixgr.phy.ra.resolveRARCommonControl(cfg,carrier);
            frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
            spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(frame.Numerology);
            first=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(ra.Msg3Slot,grant.SymbolStart,spec);
            finish=first.plusSymbols(grant.NumSymbols,spec);
            tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/physicalTiming.SampleRateHz;
            assert(tc==fix(tc),'sixgr:phy:ra:ContentionSampleClock','Sample boundaries must preserve exact Tc.');
            shift=int64(physicalTiming.TransmitStartSample-physicalTiming.NominalStartSample)*int64(tc);
            finish=finish.plusTicks(shift);
            duration=int64(ra.RAContentionResolutionTimerSlots)* ...
                idivide(sixgr.phy.frame.AbsoluteTime.TicksPerFrame,int64(spec.SlotsPerFrame));
            obj.MAC=sixgr.mac.ra.ContentionResolutionState(identity,ra.TempCRNTI,finish.Ticks,duration);
            offset=int64(physicalTiming.DLReference.DLPhaseOffsetSamples)*int64(tc);
            beginRadio=finish.plusTicks(-offset);
            [f,s,~,~]=beginRadio.toNumerology(spec);
            firstSlot=double(f)*spec.SlotsPerFrame+double(s);
            slots=zeros(0,1);
            for slot=firstSlot:firstSlot+ra.RAContentionResolutionTimerSlots+1
                t=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,control.StartSymbol,spec);
                if t.Ticks+offset>=obj.MAC.ExpiryTicksExclusive, break; end
                p=control.SlotPeriodAndOffset;
                if t.Ticks+offset>=obj.MAC.StartTicks && ...
                        mod(slot-p(2),p(1))<control.MonitoringDurationSlots && ...
                        frame.IsDLAllocation(slot,[control.StartSymbol control.DurationSymbols])
                    slots(end+1,1)=slot; %#ok<AGROW>
                end
            end
            obj.Window=struct('StartTicks',obj.MAC.StartTicks, ...
                'ExpiryTicksExclusive',obj.MAC.ExpiryTicksExclusive,'ClockOffsetTicks',offset, ...
                'Numerology',spec,'MonitoringSlots',slots,'SearchSpaceID',control.SearchSpaceID, ...
                'CORESETID',control.CORESETID,'Source',"UE_Msg3_end_symbol_and_Type1_monitoring");
        end
        function obj=start(obj,nowTicks)
            obj.MAC=obj.MAC.start(nowTicks);
        end
        function [obj,outcome]=receive(obj,slot,observation,cfgRx)
            assert(obj.MAC.Status=="waiting" && numel(obj.SeenSlots)<numel(obj.Window.MonitoringSlots) && ...
                slot==obj.Window.MonitoringSlots(numel(obj.SeenSlots)+1), ...
                'sixgr:phy:ra:UnexpectedContentionObservation','Receive every configured opportunity once and in order.');
            assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && observation.isComplete(), ...
                'sixgr:phy:ra:IncompleteContentionObservation','No invented or padded receive samples.');
            fs=observation.SampleRateHz; tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
            info=nrOFDMInfo(sixgr.phy.grid.makeCarrier(obj.Config));
            assert(fs==double(info.SampleRate), ...
                'sixgr:phy:ra:ContentionSampleRate','The observation must use the configured carrier sample rate.');
            start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,0,obj.Window.Numerology);
            assert(tc==fix(tc) && int64(observation.StartSample)*int64(tc)==start.Ticks+obj.Window.ClockOffsetTicks, ...
                'sixgr:phy:ra:ContentionObservationClock','The UE receive clock must match its measured DL reference.');
            frozen=cfgRx; original=obj.Config;
            for key={'receiverSync'}
                name=key{1};
                if isfield(frozen,'lls6g') && isfield(frozen.lls6g,name), frozen.lls6g=rmfield(frozen.lls6g,name); end
                if isfield(original,'lls6g') && isfield(original.lls6g,name), original.lls6g=rmfield(original.lls6g,name); end
            end
            assert(isequaln(frozen,original),'sixgr:phy:ra:ContentionConfigChanged','Only received synchronization may change within a window.');
            ra=obj.RAConfig; ra.Msg4Slot=slot;
            [control,data,message]=sixgr.phy.ra.recoverMsg4Waveform(observation.readComplete(),cfgRx,ra,struct(),struct());
            dci=logical(sixgr.util.structGet(control,'CausalGrantDecodeOk',false));
            tb=logical(sixgr.util.structGet(data,'Ok',false));
            identity=string(sixgr.util.structGet(message,'ContentionIdentity',""));
            complete=int64(observation.EndSampleExclusive)*int64(tc);
            obj.MAC=obj.MAC.receive(complete,ra.TempCRNTI,dci,tb,identity);
            row=table(string(ra.RunId),double(ra.UEId),double(ra.AttemptId),slot, ...
                observation.StartSample,observation.EndSampleExclusive,fs, ...
                double(obj.Window.StartTicks),double(obj.Window.ExpiryTicksExclusive), ...
                dci,tb,identity,obj.MAC.IdentityMatches,obj.MAC.Status, ...
                "actual_received_samples_ue_contention_monitoring",false,false, ...
                'VariableNames',{'RunId','UEId','AttemptId','AbsoluteSlot','ObservationStartSample', ...
                'ObservationEndSampleExclusive','SampleRateHz','WindowStartTicks','WindowExpiryTicksExclusive', ...
                'DCICrcPass','PDSCHCrcPass','ReceivedIdentity','IdentityMatches','Status','Source','ProxyUsed','FallbackUsed'});
            obj.Observations=[obj.Observations;row]; obj.SeenSlots(end+1,1)=slot;
            outcome=struct('PDCCH',control,'PDSCH',data,'Message',message,'RAConfig',ra, ...
                'Observation',row,'Status',obj.MAC.Status);
            obj.LastOutcome=outcome;
        end
        function obj=expire(obj,nowTicks)
            assert(isequal(obj.SeenSlots,obj.Window.MonitoringSlots), ...
                'sixgr:phy:ra:SkippedContentionMonitoring','A timer cannot substitute for unexecuted receive opportunities.');
            obj.MAC=obj.MAC.expire(nowTicks);
        end
    end
end
