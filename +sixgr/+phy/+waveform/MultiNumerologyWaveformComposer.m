classdef MultiNumerologyWaveformComposer
    %MULTINUMEROLOGYWAVEFORMCOMPOSER Common-clock sample-domain composition.
    methods (Static)
        function result=compose(components,commonRate)
            n=numel(components); converted=cell(n,1); metadata=cell(n,1);
            maxLength=0;
            for i=1:n
                [samples,rateInfo]=sixgr.phy.waveform.RationalSampleRateConverter.convert( ...
                    components(i).Samples,components(i).SampleRate_Hz,commonRate);
                start=double(components(i).StartSample);
                state=sixgr.phy.waveform.OFDMStreamState(commonRate, ...
                    double(sixgr.util.structGet(components(i),"ConfigurationEpoch",0)));
                [shifted,~,nco]=sixgr.phy.waveform.DigitalUpconverter.process( ...
                    samples,components(i).FrequencyOffset_Hz,commonRate,state);
                shifted=shifted*10^(double(components(i).Power_dB)/20);
                converted{i}=struct("Start",start,"Samples",shifted);
                maxLength=max(maxLength,start+size(shifted,1));
                metadata{i}=struct("ComponentID",string(components(i).ComponentID), ...
                    "Rate",rateInfo,"NCO",nco,"Power_dB",double(components(i).Power_dB));
            end
            contributions=complex(zeros(maxLength,n));
            for i=1:n
                idx=converted{i}.Start+(1:size(converted{i}.Samples,1));
                contributions(idx,i)=converted{i}.Samples;
            end
            composite=sum(contributions,2);
            errorNorm=norm(composite-sum(contributions,2));
            result=struct("Samples",composite,"Contributions",contributions, ...
                "Metadata",{metadata},"CommonSampleRate_Hz",double(commonRate), ...
                "ContributionSumError",errorNorm);
        end
    end
end
