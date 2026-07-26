classdef AGCState < handle
%AGCSTATE Explicit stateful attack/release/hold receiver AGC.

    properties(SetAccess=private)
        TargetRMS (1,1) double
        MinGain_dB (1,1) double
        MaxGain_dB (1,1) double
        Attack (1,1) double
        Release (1,1) double
        HoldSamples (1,1) double
        Gain_dB (1,1) double=0
        Step (1,1) double=0
        State (1,1) string="HOLD"
        StateEpoch (1,1) double
    end

    methods
        function obj=AGCState(profile,stateEpoch)
            required=["TargetRMS","MinGain_dB","MaxGain_dB", ...
                "Attack","Release","HoldSamples"];
            if ~isstruct(profile)||~all(isfield(profile,required))
                error("RF:ImplicitAGCForbidden", ...
                    "AGC must be created from an explicit state profile.");
            end
            values=double([profile.TargetRMS profile.MinGain_dB ...
                profile.MaxGain_dB profile.Attack profile.Release ...
                profile.HoldSamples]);
            if any(~isfinite(values))||profile.TargetRMS<=0|| ...
                    profile.MinGain_dB>profile.MaxGain_dB|| ...
                    profile.Attack<=0||profile.Attack>1|| ...
                    profile.Release<=0||profile.Release>1|| ...
                    profile.HoldSamples<0
                error("RF:ImplicitAGCForbidden","AGC profile values are invalid.");
            end
            obj.TargetRMS=profile.TargetRMS;
            obj.MinGain_dB=profile.MinGain_dB;
            obj.MaxGain_dB=profile.MaxGain_dB;
            obj.Attack=profile.Attack;
            obj.Release=profile.Release;
            obj.HoldSamples=profile.HoldSamples;
            if nargin<2, stateEpoch=1; end
            obj.StateEpoch=stateEpoch;
        end

        function [y,trace]=apply(obj,x,fullScale,expectedEpoch)
            if nargin>=4&&expectedEpoch~=obj.StateEpoch
                error("RF:StateEpochMismatch","AGC state epoch mismatch.");
            end
            if isempty(x)||any(~isfinite(x(:)))||~isfinite(fullScale)||fullScale<=0
                error("RF:NonFiniteSamples","AGC input/full scale is invalid.");
            end
            inputRMS=sqrt(mean(abs(double(x(:))).^2));
            desired=20*log10(obj.TargetRMS/max(inputRMS,realmin));
            if desired<obj.Gain_dB
                coefficient=obj.Attack; obj.State="ATTACK";
            else
                coefficient=obj.Release; obj.State="RELEASE";
            end
            obj.Gain_dB=obj.Gain_dB+coefficient*(desired-obj.Gain_dB);
            obj.Gain_dB=min(max(obj.Gain_dB,obj.MinGain_dB),obj.MaxGain_dB);
            gain=10^(obj.Gain_dB/20);
            y=x.*cast(gain,"like",x);
            clipping=mean(abs(double(y(:)))>=double(fullScale));
            obj.Step=obj.Step+1;
            if clipping>0.25 && obj.Gain_dB<=obj.MinGain_dB+eps
                error("RF:AGCOverload", ...
                    "AGC cannot recover from overload within its gain range.");
            end
            trace=struct("Step",obj.Step,"InputRMS",inputRMS, ...
                "TargetRMS",obj.TargetRMS,"Gain_dB",obj.Gain_dB, ...
                "OutputRMS",sqrt(mean(abs(double(y(:))).^2)), ...
                "ClippingRatio",clipping,"State",obj.State, ...
                "StateEpoch",obj.StateEpoch);
        end
    end
end
