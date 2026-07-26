function [composite, contributions] = composeInterferenceTones(linkTable, sampleRate_Hz)
%COMPOSEINTERFERENCETONES Sample-domain deterministic link superposition.

arguments
    linkTable table
    sampleRate_Hz (1,1) double {mustBeFinite,mustBePositive}
end
required = ["Amplitude","FrequencyOffset_Hz","InitialPhase_rad", ...
    "IntegerTimingOffset_samples","NSamples"];
if ~all(ismember(required, string(linkTable.Properties.VariableNames)))
    error("CHANNEL:InterferenceLinkMissing", ...
        "Every interference link requires amplitude, timing, frequency, phase, and length.");
end
nSamples = max(double(linkTable.NSamples));
contributions = complex(zeros(nSamples, height(linkTable)));
for link = 1:height(linkTable)
    offset = double(linkTable.IntegerTimingOffset_samples(link));
    if offset < 0 || offset >= nSamples
        error("CHANNEL:InterferenceLinkMissing", ...
            "Integer timing offset is outside the composite waveform.");
    end
    localIndex = (0:nSamples-offset-1).';
    phase = double(linkTable.InitialPhase_rad(link)) + 2 .* pi ...
        .* double(linkTable.FrequencyOffset_Hz(link)) .* localIndex ./ sampleRate_Hz;
    contributions(offset + (1:numel(localIndex)), link) = ...
        double(linkTable.Amplitude(link)) .* exp(1i .* phase);
end
composite = sum(contributions, 2);
end
