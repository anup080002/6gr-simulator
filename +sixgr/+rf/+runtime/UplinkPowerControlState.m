classdef UplinkPowerControlState < handle
%UPLINKPOWERCONTROLSTATE Event-sourced bounded TS 38.213 UL power state.

    properties(SetAccess=private)
        AccumulatedTPC_dB (1,1) double = 0
        StateEpoch (1,1) double
        LastEventSlot (1,1) double = -Inf
        EventCount (1,1) double = 0
    end

    methods
        function obj=UplinkPowerControlState(stateEpoch)
            arguments
                stateEpoch (1,1) double {mustBeFinite}=1
            end
            obj.StateEpoch=stateEpoch;
        end

        function event=applyTPC(obj,command_dB,slot,configurationEpoch,mode)
            if configurationEpoch~=obj.StateEpoch || slot<obj.LastEventSlot
                error("RF:TPCStateStale", ...
                    "TPC event is stale or has the wrong configuration epoch.");
            end
            command_dB=double(command_dB);
            if ~(isscalar(command_dB)&&isfinite(command_dB))
                error("RF:TPCStateStale","TPC command must be finite.");
            end
            mode=lower(strtrim(string(mode)));
            if mode=="accumulation"
                obj.AccumulatedTPC_dB=obj.AccumulatedTPC_dB+command_dB;
            elseif mode=="absolute"
                obj.AccumulatedTPC_dB=command_dB;
            else
                error("RF:UnsupportedCombination","Unsupported TPC mode '%s'.",mode);
            end
            obj.LastEventSlot=slot;
            obj.EventCount=obj.EventCount+1;
            event=struct("Command_dB",command_dB, ...
                "AccumulatedTPC_dB",obj.AccumulatedTPC_dB, ...
                "Slot",slot,"StateEpoch",obj.StateEpoch, ...
                "Source","decoded_control_event");
        end

        function result=resolve(obj,request)
            required=["Channel","Mu","MRB","MeasuredPathloss_dB", ...
                "PathlossSource","P0_dBm","Alpha","DeltaTF_dB","PCMAX_dBm"];
            if ~isstruct(request)||~all(isfield(request,required))
                error("RF:MissingPowerParameter", ...
                    "UL power control request is incomplete.");
            end
            if ~contains(upper(string(request.PathlossSource)), ...
                    ["MEASURED","REFERENCE_RS","RUNTIME_GEOMETRY"])
                error("RF:MeasuredPathlossUnavailable", ...
                    "UL pathloss must come from measured reference-RS state.");
            end
            numbers=[request.Mu request.MRB request.MeasuredPathloss_dB ...
                request.P0_dBm request.Alpha request.DeltaTF_dB request.PCMAX_dBm];
            if any(~isfinite(double(numbers)))||request.MRB<1|| ...
                    request.Mu<0||request.Mu~=round(request.Mu)|| ...
                    request.Alpha<0||request.Alpha>1
                error("RF:MissingPowerParameter", ...
                    "UL power-control parameters are invalid.");
            end
            bandwidthTerm=10*log10(2^double(request.Mu)*double(request.MRB));
            requested=double(request.P0_dBm)+bandwidthTerm+ ...
                double(request.Alpha)*double(request.MeasuredPathloss_dB)+ ...
                double(request.DeltaTF_dB)+obj.AccumulatedTPC_dB;
            applied=min(double(request.PCMAX_dBm),requested);
            result=struct( ...
                "Channel",upper(string(request.Channel)), ...
                "BandwidthTerm_dB",bandwidthTerm, ...
                "RequestedPower_dBm",requested, ...
                "AppliedPower_dBm",applied, ...
                "PowerHeadroom_dB",max(0,double(request.PCMAX_dBm)-applied), ...
                "Clipped",requested>double(request.PCMAX_dBm), ...
                "AccumulatedTPC_dB",obj.AccumulatedTPC_dB, ...
                "PathlossSource",string(request.PathlossSource), ...
                "StateEpoch",obj.StateEpoch);
        end

        function [waveform,evidence]=applyToWaveform(~,waveform,result,referencePower_dBm)
            if isempty(waveform)||any(~isfinite(waveform(:)))
                error("RF:NonFiniteSamples", ...
                    "Power control requires a finite nonempty waveform.");
            end
            currentPower=10*log10(max(mean(abs(double(waveform(:))).^2),realmin));
            target=double(result.AppliedPower_dBm);
            scale=10.^((target-currentPower)/20);
            waveform=waveform.*cast(scale,"like",waveform);
            measured=10*log10(max(mean(abs(double(waveform(:))).^2),realmin));
            evidence=struct("ReferencePower_dBm",double(referencePower_dBm), ...
                "Scale",scale,"MeasuredPower_dBm",measured, ...
                "PowerError_dB",measured-target);
            if abs(evidence.PowerError_dB)>0.05
                error("RF:PowerControlEquationMismatch", ...
                    "Applied waveform power differs from the resolved target.");
            end
        end
    end
end
