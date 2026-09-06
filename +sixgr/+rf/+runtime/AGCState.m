classdef AGCState < handle
%AGCSTATE Explicit stateful attack/release/hold receiver AGC.

    properties(SetAccess=private)
        TargetRMS (1,1) double
        MinGain_dB (1,1) double
        MaxGain_dB (1,1) double
        Attack (1,1) double
        Release (1,1) double
        HoldSamples (1,1) double
        UpdatePeriodSamples (1,1) double
        SamplesProcessed (1,1) double=0
        DetectorSamples (1,1) double=0
        DetectorEnergy (1,1) double=0
        DetectorClipped (1,1) double=0
        DetectorAtMinimumGain (1,1) logical=true
        HoldRemainingSamples (1,1) double=0
        InputColumns (1,1) double=0
        Gain_dB (1,1) double=0
        Step (1,1) double=0
        State (1,1) string="HOLD"
        StateEpoch (1,1) double
    end

    methods
        function obj=AGCState(profile,stateEpoch)
            required=["TargetRMS","MinGain_dB","MaxGain_dB", ...
                "Attack","Release","HoldSamples","UpdatePeriodSamples"];
            if ~isstruct(profile)||~all(isfield(profile,required))
                error("RF:ImplicitAGCForbidden", ...
                    "AGC must be created from an explicit state profile.");
            end
            values=double([profile.TargetRMS profile.MinGain_dB ...
                profile.MaxGain_dB profile.Attack profile.Release ...
                profile.HoldSamples profile.UpdatePeriodSamples]);
            if any(~isfinite(values))||profile.TargetRMS<=0|| ...
                    profile.MinGain_dB>profile.MaxGain_dB|| ...
                    profile.Attack<=0||profile.Attack>1|| ...
                    profile.Release<=0||profile.Release>1|| ...
                    profile.HoldSamples<0||profile.HoldSamples~=fix(profile.HoldSamples)|| ...
                    profile.UpdatePeriodSamples<1||profile.UpdatePeriodSamples~=fix(profile.UpdatePeriodSamples)
                error("RF:ImplicitAGCForbidden","AGC profile values are invalid.");
            end
            obj.TargetRMS=profile.TargetRMS;
            obj.MinGain_dB=profile.MinGain_dB;
            obj.MaxGain_dB=profile.MaxGain_dB;
            obj.Attack=profile.Attack;
            obj.Release=profile.Release;
            obj.HoldSamples=profile.HoldSamples;
            obj.UpdatePeriodSamples=profile.UpdatePeriodSamples;
            obj.Gain_dB=min(max(0,obj.MinGain_dB),obj.MaxGain_dB);
            if nargin<2, stateEpoch=1; end
            obj.StateEpoch=stateEpoch;
        end

        function [y,trace]=apply(obj,x,fullScale,expectedEpoch)
            if nargin>=4&&expectedEpoch~=obj.StateEpoch
                error("RF:StateEpochMismatch","AGC state epoch mismatch.");
            end
            if ~isfloat(x)||~ismatrix(x)||isempty(x)||any(~isfinite(x(:)))|| ...
                    ~isscalar(fullScale)||~isreal(fullScale)||~isfinite(fullScale)||fullScale<=0
                error("RF:NonFiniteSamples","AGC input/full scale is invalid.");
            end
            if obj.InputColumns~=0 && obj.InputColumns~=size(x,2)
                error("RF:AGCStateMismatch","AGC receive-channel layout changed within one epoch.");
            end
            startSample=obj.SamplesProcessed;
            gainDb=obj.Gain_dB;
            count=obj.DetectorSamples; energy=obj.DetectorEnergy;
            clippedCount=obj.DetectorClipped; atFloor=obj.DetectorAtMinimumGain;
            holdRemaining=obj.HoldRemainingSamples;
            step=obj.Step; state=obj.State;
            y=zeros(size(x),'like',x);
            appliedGain=zeros(size(x,1),1);
            for k=1:size(x,1)
                % The current sample uses gain determined by PAST samples.
                % The fixed detector period is independent of API calls.
                appliedGain(k)=gainDb;
                y(k,:)=x(k,:).*cast(10^(gainDb/20),'like',x);
                energy=energy+mean(abs(double(x(k,:))).^2);
                clippedCount=clippedCount+sum(abs(real(double(y(k,:))))>=fullScale | ...
                    abs(imag(double(y(k,:))))>=fullScale);
                atFloor=atFloor && gainDb<=obj.MinGain_dB+eps;
                count=count+1;
                holdRemaining=max(0,holdRemaining-1);
                if count==obj.UpdatePeriodSamples
                    if clippedCount/(count*size(x,2))>0.25 && atFloor
                        error("RF:AGCOverload", ...
                            "AGC cannot recover from overload within its gain range.");
                    end
                    observedRMS=sqrt(energy/count);
                    desired=20*log10(obj.TargetRMS/max(observedRMS,realmin));
                    desired=min(max(desired,obj.MinGain_dB),obj.MaxGain_dB);
                    if desired<gainDb
                        gainDb=gainDb+obj.Attack*(desired-gainDb);
                        holdRemaining=obj.HoldSamples;
                        state="ATTACK";
                    elseif holdRemaining>0 || desired==gainDb
                        state="HOLD";
                    else
                        gainDb=gainDb+obj.Release*(desired-gainDb);
                        state="RELEASE";
                    end
                    gainDb=min(max(gainDb,obj.MinGain_dB),obj.MaxGain_dB);
                    step=step+1;
                    count=0; energy=0; clippedCount=0; atFloor=true;
                end
            end
            obj.InputColumns=size(x,2);
            obj.Gain_dB=gainDb; obj.Step=step; obj.State=state;
            obj.DetectorSamples=count; obj.DetectorEnergy=energy;
            obj.DetectorClipped=clippedCount; obj.DetectorAtMinimumGain=atFloor;
            obj.HoldRemainingSamples=holdRemaining;
            obj.SamplesProcessed=startSample+size(x,1);
            inputRMS=sqrt(mean(abs(double(x(:))).^2));
            % Match the ADC's independent real and imaginary input rails,
            % not a circular complex-envelope clipping boundary.
            clipping=mean(abs(real(double(y(:))))>=double(fullScale) | ...
                abs(imag(double(y(:))))>=double(fullScale));
            trace=struct("Step",obj.Step,"InputRMS",inputRMS, ...
                "TargetRMS",obj.TargetRMS,"Gain_dB",obj.Gain_dB, ...
                "OutputRMS",sqrt(mean(abs(double(y(:))).^2)), ...
                "ClippingRatio",clipping,"FullScale",double(fullScale), ...
                "ClippingReference","separate_I_Q_rails","State",obj.State, ...
                "StateEpoch",obj.StateEpoch, ...
                "StartSample",startSample,"EndSampleExclusive",obj.SamplesProcessed, ...
                "AppliedGain_dB",appliedGain,"GainValueRole","next_sample_gain", ...
                "UpdatePeriodSamples",obj.UpdatePeriodSamples, ...
                "HoldRemainingSamples",holdRemaining, ...
                "CoefficientReference","per_completed_detector_window", ...
                "ControlModel","causal_windowed_joint_rms_attack_hold_release");
        end
    end
end
