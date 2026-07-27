classdef WaveformFrequencyReference
    %WAVEFORMFREQUENCYREFERENCE Absolute sample/NCO phase convention.
    methods (Static)
        function phase = phaseAt(sampleIndex,frequencyHz,sampleRateHz,initialPhase)
            if nargin<4, initialPhase=0; end
            phase = mod(double(initialPhase) + 2*pi*double(frequencyHz).* ...
                double(sampleIndex)/double(sampleRateHz)+pi,2*pi)-pi;
        end
    end
end
