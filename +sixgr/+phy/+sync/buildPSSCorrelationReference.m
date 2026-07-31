function ref = buildPSSCorrelationReference(ssbTiming, nid2, sampleRateHz, varargin)
%BUILDPSSCORRELATIONREFERENCE Build the active PSS OFDM-symbol reference.
%
% The reference length is derived from the requested sample rate.  Fixed
% sample truncation is invalid because, at wideband sample rates, a fixed
% prefix can end before the PSS-bearing OFDM symbol begins.
%
% CandidateStartSymbol is the absolute OFDM symbol within the half-frame.
% It is required for an exact cyclic-prefix reference: an SSB beginning at
% symbol 4 must not be correlated against the longer slot-symbol-0 CP.

p = inputParser;
p.addParameter("CandidateStartSymbol", [], ...
    @(x) isempty(x) || (isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 0 && x == round(x)));
p.parse(varargin{:});

if ~(isstruct(ssbTiming) && isscalar(ssbTiming))
    error("sixgr:phy:sync:InvalidSSBTiming", ...
        "SSB timing must be a scalar struct.");
end
if ~(isnumeric(nid2) && isscalar(nid2) && isfinite(nid2) && ...
        nid2 >= 0 && nid2 == round(nid2) && nid2 <= 2)
    error("sixgr:phy:sync:InvalidNID2", ...
        "PSS correlation reference NID2 must be in [0,2].");
end
if ~(isnumeric(sampleRateHz) && isscalar(sampleRateHz) && ...
        isreal(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    error("sixgr:phy:sync:InvalidSampleRate", ...
        "PSS correlation sample rate must be positive and finite.");
end
if ~isfield(ssbTiming, "SSBSubcarrierSpacingKHz")
    error("sixgr:phy:sync:InvalidSSBTiming", ...
        "SSB timing must contain SSBSubcarrierSpacingKHz.");
end
candidateStartSymbol = p.Results.CandidateStartSymbol;
if isempty(candidateStartSymbol)
    candidates = double( ...
        ssbTiming.CandidateStartSymbolsWithinHalfFrame(:));
    candidates = candidates(isfinite(candidates) & candidates >= 0 & ...
        candidates == round(candidates));
    if isempty(candidates)
        error("sixgr:phy:sync:InvalidSSBTiming", ...
            "SSB timing must contain a canonical candidate start symbol.");
    end
    candidateStartSymbol = candidates(1);
end
candidateStartSymbol = double(candidateStartSymbol);

carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = double(ssbTiming.SSBSubcarrierSpacingKHz);
carrier.NSizeGrid = 20;
carrier.NStartGrid = 0;
carrier.CyclicPrefix = "normal";
carrier.NSlot = floor(candidateStartSymbol / 14);

symbolWithinSlot = mod(candidateStartSymbol, 14);
grid = complex(zeros(carrier.NSizeGrid * 12, 14));
pssSubcarriers = mod(double(nrPSSIndices) - 1, ...
    carrier.NSizeGrid * 12) + 1;
grid(pssSubcarriers, symbolWithinSlot + 1) = nrPSS(nid2);
waveform = sixgr.phy.waveform.ofdmModulate( ...
    carrier, grid, "SampleRate", double(sampleRateHz), "Windowing", 0);

samplePower = sum(abs(waveform).^2, 2);
peakPower = max(samplePower, [], "omitnan");
if ~(isscalar(peakPower) && isfinite(peakPower) && peakPower > 0)
    error("sixgr:phy:sync:EmptyPSSReference", ...
        "PSS OFDM modulation did not produce a nonzero reference.");
end
active = find(samplePower > peakPower * 1e-12);
if isempty(active)
    error("sixgr:phy:sync:EmptyPSSReference", ...
        "PSS OFDM modulation did not expose an active sample interval.");
end
ref = waveform(active(1):active(end), 1);
ref = ref(:);
end
