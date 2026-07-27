classdef OFDMStreamState < handle
    %OFDMSTREAMSTATE Persistent sample, phase, overlap and epoch state.
    properties (SetAccess=private)
        NextSampleIndex (1,1) double = 0
        NextTime_s (1,1) double = 0
        NCOPhase_rad (1,1) double = 0
        Frame (1,1) double = 0
        Slot (1,1) double = 0
        Symbol (1,1) double = 0
        ConfigurationEpoch (1,1) double = 0
        WindowOverlap = complex(zeros(0,1))
        FilterState = complex(zeros(0,1))
        ResamplerState = complex(zeros(0,1))
    end
    methods
        function obj=OFDMStreamState(sampleRate,epoch)
            if nargin<2,epoch=0;end
            if ~isscalar(sampleRate)||~isfinite(sampleRate)||sampleRate<=0
                error("WAVEFORM:InvalidOFDMParameters","Stream sample rate must be positive.");
            end
            obj.ConfigurationEpoch=double(epoch);
            obj.NextTime_s=0;
        end
        function advance(obj,count,sampleRate,phase)
            count=double(count);
            if count<0||count~=fix(count)
                error("WAVEFORM:StreamDiscontinuity","Stream advance must be a sample count.");
            end
            obj.NextSampleIndex=obj.NextSampleIndex+count;
            obj.NextTime_s=obj.NextSampleIndex/double(sampleRate);
            obj.NCOPhase_rad=mod(double(phase)+pi,2*pi)-pi;
        end
        function setOverlap(obj,value),obj.WindowOverlap=value;end
        function setFilterState(obj,value),obj.FilterState=value;end
        function setResamplerState(obj,value),obj.ResamplerState=value;end
        function setRadioTime(obj,frame,slot,symbol)
            obj.Frame=double(frame);obj.Slot=double(slot);obj.Symbol=double(symbol);
        end
        function value=snapshot(obj)
            value=struct("NextSampleIndex",obj.NextSampleIndex, ...
                "NextTime_s",obj.NextTime_s,"NCOPhase_rad",obj.NCOPhase_rad, ...
                "Frame",obj.Frame,"Slot",obj.Slot,"Symbol",obj.Symbol, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "WindowOverlap",obj.WindowOverlap, ...
                "FilterState",obj.FilterState,"ResamplerState",obj.ResamplerState);
        end
    end
end
