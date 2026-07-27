classdef WaveformStreamComposer
    %WAVEFORMSTREAMCOMPOSER Canonical chunk processing on one state object.
    methods (Static)
        function [chunk,state]=frequencyShift(samples,frequencyHz,sampleRateHz,state)
            start=state.NextSampleIndex;
            [samples,state]=sixgr.phy.waveform.DigitalUpconverter.process( ...
                samples,frequencyHz,sampleRateHz,state);
            chunk=sixgr.phy.waveform.WaveformChunk(samples,start);
        end
    end
end
