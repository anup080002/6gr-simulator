classdef BlockerScenario
%BLOCKERSCENARIO Sample-domain wanted/blocker and intermodulation planning.

    methods(Static)
        function scenario=validate(scenario)
            required=["WantedPower_dBm","BlockerPower_dBm","BlockerOffset_Hz", ...
                "IIP2_dBm","IIP3_dBm","CarrierFrequency_Hz"];
            if ~isstruct(scenario)||~all(isfield(scenario,required))
                error("RF:BlockerScenarioInvalid", ...
                    "Blocker scenario is incomplete.");
            end
            values=double([scenario.WantedPower_dBm scenario.BlockerPower_dBm ...
                scenario.BlockerOffset_Hz scenario.IIP2_dBm scenario.IIP3_dBm ...
                scenario.CarrierFrequency_Hz]);
            if any(~isfinite(values))||scenario.BlockerOffset_Hz<=0|| ...
                    scenario.CarrierFrequency_Hz<=0
                error("RF:BlockerScenarioInvalid", ...
                    "Blocker scenario values are invalid.");
            end
            scenario.ExpectedIM3Lower_Hz=scenario.CarrierFrequency_Hz- ...
                scenario.BlockerOffset_Hz;
            scenario.ExpectedIM3Upper_Hz=scenario.CarrierFrequency_Hz+ ...
                2*scenario.BlockerOffset_Hz;
        end

        function result=analyticalProducts(scenario)
            scenario=sixgr.rf.runtime.BlockerScenario.validate(scenario);
            im2=2*double(scenario.BlockerPower_dBm)-double(scenario.IIP2_dBm);
            im3=3*double(scenario.BlockerPower_dBm)-2*double(scenario.IIP3_dBm);
            result=struct("IM2Power_dBm",im2,"IM3Power_dBm",im3, ...
                "IM3Lower_Hz",scenario.ExpectedIM3Lower_Hz, ...
                "IM3Upper_Hz",scenario.ExpectedIM3Upper_Hz);
        end

        function [waveform,evidence]=inject(wanted,scenario,sampleRateHz)
            scenario=sixgr.rf.runtime.BlockerScenario.validate(scenario);
            if isempty(wanted)||any(~isfinite(wanted(:)))|| ...
                    sampleRateHz<=2*scenario.BlockerOffset_Hz
                error("RF:BlockerScenarioInvalid", ...
                    "Blocker waveform/sample rate is invalid.");
            end
            n=(0:size(wanted,1)-1).';
            wantedPower=mean(abs(double(wanted(:))).^2);
            targetRatio=10^((scenario.BlockerPower_dBm- ...
                scenario.WantedPower_dBm)/10);
            amplitude=sqrt(max(wantedPower,realmin)*targetRatio);
            blocker=amplitude.*exp(1j*2*pi*scenario.BlockerOffset_Hz*n/sampleRateHz);
            waveform=wanted+cast(blocker,"like",wanted);
            evidence=struct("BlockerWaveform",blocker, ...
                "MeasuredBlockerPower_dB",10*log10(mean(abs(blocker).^2)), ...
                "ReferencePlane", ...
                sixgr.rf.runtime.RFReferencePlane.RX_ANTENNA_CONNECTOR_OR_DECLARED_TAB);
        end
    end
end
