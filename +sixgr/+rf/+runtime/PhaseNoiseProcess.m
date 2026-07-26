classdef PhaseNoiseProcess < handle
%PHASENOISEPROCESS Persistent multi-chain correlated phase process.

    properties(SetAccess=private)
        Profile struct
        Phase_rad double
        SampleIndex (1,1) double=0
        StateEpoch (1,1) double
    end

    properties(Access=private)
        Stream
        PoleCoefficients double
        ComponentWeights double
        ComponentState double
    end

    methods
        function obj=PhaseNoiseProcess(profile,chainCount,stateEpoch)
            arguments
                profile (1,1) struct
                chainCount (1,1) double {mustBeInteger,mustBePositive}=1
                stateEpoch (1,1) double {mustBeFinite}=1
            end
            obj.Profile=sixgr.rf.runtime.PhaseNoiseProfile.validate(profile);
            obj.Phase_rad=zeros(1,chainCount);
            obj.StateEpoch=stateEpoch;
            obj.Stream=RandStream("Threefry","Seed",double(obj.Profile.Seed));
            correlationState=sixgr.rf.runtime.PhaseNoiseCorrelationState. ...
                factor(chainCount,double(obj.Profile.LOCorrelation)); %#ok<NASGU>
            [obj.PoleCoefficients,obj.ComponentWeights]= ...
                sixgr.rf.runtime.PhaseNoiseProcess. ...
                designMaskComponents(obj.Profile);
            obj.ComponentState=zeros(numel(obj.PoleCoefficients),chainCount);
        end

        function [y,trace]=apply(obj,x,expectedEpoch)
            if nargin>=3 && expectedEpoch~=obj.StateEpoch
                error("RF:StateEpochMismatch", ...
                    "Phase-noise state epoch mismatch.");
            end
            if isempty(x)||any(~isfinite(x(:)))||size(x,2)~=numel(obj.Phase_rad)
                error("RF:NonFiniteSamples", ...
                    "Phase-noise input must be finite and match the chain count.");
            end
            n=size(x,1); chains=size(x,2);
            rho=double(obj.Profile.LOCorrelation);
            phase=zeros(n,chains);
            nextState=zeros(size(obj.ComponentState));
            for component=1:numel(obj.PoleCoefficients)
                independent=randn(obj.Stream,n,chains);
                innovations=sixgr.rf.runtime.PhaseNoiseCorrelationState.apply( ...
                    independent,rho);
                pole=obj.PoleCoefficients(component);
                numerator=sqrt(max(0,1-pole^2));
                for chain=1:chains
                    [colored,nextState(component,chain)]=filter( ...
                        numerator,[1 -pole],innovations(:,chain), ...
                        obj.ComponentState(component,chain));
                    phase(:,chain)=phase(:,chain)+ ...
                        sqrt(obj.ComponentWeights(component)).*colored;
                end
            end
            obj.ComponentState=nextState;
            obj.Phase_rad=phase(end,:);
            obj.SampleIndex=obj.SampleIndex+n;
            y=x.*cast(exp(1j.*phase),"like",x);
            measuredCorrelation=1;
            if chains>1
                C=corrcoef(phase);
                measuredCorrelation=mean(C(triu(true(chains),1)),"omitnan");
            end
            trace=struct("Phase_rad",phase, ...
                "EndPhase_rad",obj.Phase_rad, ...
                "SampleIndex",obj.SampleIndex, ...
                "ExpectedCorrelation",rho, ...
                "MeasuredCorrelation",measuredCorrelation, ...
                "IntegratedRMS_rad",sqrt(mean(phase(:).^2)), ...
                "MaskOffsets_Hz",obj.Profile.MaskOffsets_Hz, ...
                "MaskLevels_dBcHz",obj.Profile.MaskLevels_dBcHz, ...
                "MaskComponentCount",numel(obj.PoleCoefficients), ...
                "StateEpoch",obj.StateEpoch);
        end
    end

    methods(Static,Access=private)
        function [poles,weights]=designMaskComponents(profile)
            persistent componentCache
            if isempty(componentCache)
                componentCache=containers.Map("KeyType","char","ValueType","any");
            end
            key=char(string(profile.SampleRate_Hz)+"|"+ ...
                join(string(profile.MaskOffsets_Hz(:).'),",")+"|"+ ...
                join(string(profile.MaskLevels_dBcHz(:).'),","));
            if isKey(componentCache,key)
                cached=componentCache(key);
                poles=cached.Poles;
                weights=cached.Weights;
                return;
            end
            fs=double(profile.SampleRate_Hz);
            maskOffsets=double(profile.MaskOffsets_Hz(:));
            targetLevels=double(profile.MaskLevels_dBcHz(:));
            poles=[exp(-2*pi*maskOffsets/fs);0];
            basis=sixgr.rf.runtime.PhaseNoiseProcess.psdBasis( ...
                poles,maskOffsets,fs);
            target=10.^(targetLevels/10);
            initial=zeros(numel(poles),1);
            for k=1:numel(maskOffsets)
                initial(k)=target(k)/max(basis(k,k),realmin)/ ...
                    numel(maskOffsets);
            end
            initial(end)=target(end)*fs;
            objective=@(theta)sum((10*log10(max( ...
                basis*exp(theta),realmin))-targetLevels).^2);
            options=optimset("Display","off","MaxIter",5000, ...
                "MaxFunEvals",20000,"TolX",1e-10,"TolFun",1e-10);
            theta=fminsearch(objective,log(max(initial,realmin)),options);
            weights=exp(theta);
            error_dB=10*log10(max(basis*weights,realmin))-targetLevels;
            if any(~isfinite(weights))||max(abs(error_dB))>1
                error("RF:PhaseNoiseMaskFitFailed", ...
                    "Runtime phase-noise model cannot fit the explicit mask within 1 dB.");
            end
            cached=struct("Poles",poles,"Weights",weights);
            componentCache(key)=cached;
        end

        function basis=psdBasis(poles,offsets,fs)
            poles=double(poles(:));
            offsets=double(offsets(:));
            basis=zeros(numel(offsets),numel(poles));
            for k=1:numel(offsets)
                omega=2*pi*offsets(k)/fs;
                basis(k,:)=(1-poles.^2).'./ ...
                    abs(1-poles.*exp(-1j*omega)).'.^2/fs;
            end
        end
    end

    methods(Static)
        function levels_dBcHz=evaluateModelPSD(profile,offsetsHz)
            profile=sixgr.rf.runtime.PhaseNoiseProfile.validate(profile);
            offsets=double(offsetsHz(:));
            if isempty(offsets)||any(~isfinite(offsets))||any(offsets<=0)|| ...
                    any(offsets>=double(profile.SampleRate_Hz)/2)
                error("RF:PhaseNoiseMaskMissing", ...
                    "Phase-noise PSD evaluation offsets are invalid.");
            end
            [poles,weights]=sixgr.rf.runtime.PhaseNoiseProcess. ...
                designMaskComponents(profile);
            basis=sixgr.rf.runtime.PhaseNoiseProcess.psdBasis( ...
                poles,offsets,double(profile.SampleRate_Hz));
            psd=basis*weights;
            levels_dBcHz=10*log10(max(psd,realmin));
        end
    end
end
