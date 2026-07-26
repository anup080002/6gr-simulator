classdef TimingFrequencyTracker < handle
    %TIMINGFREQUENCYTRACKER Causal measured timing/CFO correction loop.

    properties (SetAccess=immutable)
        LoopGain double
    end
    properties (SetAccess=private)
        CFOEstimateHz double = 0
        TimingEstimateSamples double = 0
        LastUpdate double = 0
        Confidence double = 0
        UpdateCount double = 0
    end

    methods
        function obj = TimingFrequencyTracker(loopGain)
            if ~(isscalar(loopGain)&&isfinite(loopGain)&&loopGain>0&&loopGain<=1)
                error("RSLA:TrackingEstimateUnavailable", ...
                    "Tracking loop gain must lie in (0,1].");
            end
            obj.LoopGain = loopGain;
        end

        function state = update(obj,measuredCFOHz,measuredTimingSamples, ...
                confidence,absoluteSlot)
            values = [measuredCFOHz measuredTimingSamples confidence absoluteSlot];
            if any(~isfinite(values)) || confidence<=0 || confidence>1
                error("RSLA:TrackingEstimateUnavailable", ...
                    "Tracker update requires finite receiver estimates and confidence.");
            end
            obj.CFOEstimateHz = (1-obj.LoopGain)*obj.CFOEstimateHz+ ...
                obj.LoopGain*double(measuredCFOHz);
            obj.TimingEstimateSamples = ...
                (1-obj.LoopGain)*obj.TimingEstimateSamples+ ...
                obj.LoopGain*double(measuredTimingSamples);
            obj.Confidence = confidence;
            obj.LastUpdate = absoluteSlot;
            obj.UpdateCount = obj.UpdateCount+1;
            state = obj.snapshot(absoluteSlot);
        end

        function [corrected,lineage] = apply(obj,waveform,sampleRateHz,absoluteSlot)
            if obj.UpdateCount<1 || obj.Confidence<=0
                error("RSLA:TrackingEstimateUnavailable", ...
                    "No measured tracking estimate is available.");
            end
            if ~(isscalar(sampleRateHz)&&isfinite(sampleRateHz)&&sampleRateHz>0)
                error("RSLA:TrackingCorrectionNotApplied", ...
                    "A finite waveform sample rate is required.");
            end
            n = (0:size(waveform,1)-1).';
            corrected = waveform.*exp(-1j*2*pi*obj.CFOEstimateHz*n/sampleRateHz);
            shift = -round(obj.TimingEstimateSamples);
            corrected = circshift(corrected,shift,1);
            lineage = struct("CorrectionApplied",true, ...
                "AppliedCFOHz",obj.CFOEstimateHz, ...
                "AppliedTimingSamples",obj.TimingEstimateSamples, ...
                "EstimateSlot",obj.LastUpdate,"AppliedSlot",absoluteSlot, ...
                "EstimateSHA256",sixgr.phy.rsla.RSLAUtil.hash( ...
                    obj.snapshot(absoluteSlot)), ...
                "Source","received_trs_samples");
        end

        function value = snapshot(obj,absoluteSlot)
            value = struct("CFOEstimateHz",obj.CFOEstimateHz, ...
                "TimingEstimateSamples",obj.TimingEstimateSamples, ...
                "Confidence",obj.Confidence, ...
                "AgeSlots",double(absoluteSlot)-obj.LastUpdate, ...
                "UpdateCount",obj.UpdateCount);
        end
    end
end
