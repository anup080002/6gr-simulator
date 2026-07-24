classdef OFDMSamplingResolver
%OFDMSAMPLINGRESOLVER Canonical strict NR OFDM sampling policy.
%
% Standard waveform settings come from the installed 5G Toolbox
% nrOFDMInfo implementation.  Explicit Nfft or SampleRate values are
% accepted only when that API accepts them and all carrier invariants pass.
% There is no next-power-of-two fallback.

    methods (Static)
        function result = resolve(carrierInput, varargin)
            localRequireToolbox();
            opts = localParseOptions(varargin{:});
            [carrier, carrierState] = localCarrier(carrierInput);

            nrb = double(carrier.NSizeGrid);
            scsKHz = double(carrier.SubcarrierSpacing);
            cp = lower(string(carrier.CyclicPrefix));
            occupiedSubcarriers = 12 * nrb;
            if opts.NfftSpecified && opts.Nfft < occupiedSubcarriers
                error("sixgr:phy:frame:OFDMAliasing", ...
                    "Configured Nfft=%d is smaller than %d occupied subcarriers.", ...
                    opts.Nfft, occupiedSubcarriers);
            end
            numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
                scsKHz, cp, "generic_waveform_test", "");

            infoArgs = localInfoArguments(opts);
            try
                toolboxInfo = nrOFDMInfo(carrier, infoArgs{:});
            catch ME
                wrapped = MException( ...
                    "sixgr:phy:frame:InvalidOFDMSamplingConfiguration", ...
                    "nrOFDMInfo rejected the standard OFDM configuration: %s", ...
                    ME.message);
                wrapped = addCause(wrapped, ME);
                throw(wrapped);
            end

            nfft = localPositiveIntegerField(toolboxInfo, "Nfft");
            sampleRate = localPositiveScalarField(toolboxInfo, "SampleRate");
            if nfft < occupiedSubcarriers
                error("sixgr:phy:frame:OFDMAliasing", ...
                    "Resolved Nfft=%d is smaller than %d occupied subcarriers.", ...
                    nfft, occupiedSubcarriers);
            end
            expectedSampleRate = nfft * scsKHz * 1e3;
            if abs(sampleRate - expectedSampleRate) > ...
                    max(1e-9 * expectedSampleRate, 1e-6)
                error("sixgr:phy:frame:InconsistentOFDMSampleRate", ...
                    "Resolved sample rate %.15g Hz does not equal Nfft*SCS %.15g Hz.", ...
                    sampleRate, expectedSampleRate);
            end

            cpLengths = double(sixgr.util.structGet( ...
                toolboxInfo, "CyclicPrefixLengths", []));
            cpLengths = cpLengths(:).';
            symbolsPerSlot = numerology.SymbolsPerSlot;
            expectedCPCount = symbolsPerSlot * numerology.SlotsPerSubframe;
            if isempty(cpLengths) || any(~isfinite(cpLengths)) || ...
                    any(cpLengths <= 0) || any(cpLengths ~= round(cpLengths)) || ...
                    numel(cpLengths) ~= expectedCPCount
                error("sixgr:phy:frame:InvalidOFDMCyclicPrefixLengths", ...
                    "nrOFDMInfo must return a positive integer CP-length vector " + ...
                    "for exactly one subframe; got %d entries, expected %d.", ...
                    numel(cpLengths), expectedCPCount);
            end
            if double(sixgr.util.structGet(toolboxInfo, ...
                    "SymbolsPerSlot", NaN)) ~= symbolsPerSlot || ...
                    double(sixgr.util.structGet(toolboxInfo, ...
                    "SlotsPerSubframe", NaN)) ~= numerology.SlotsPerSubframe
                error("sixgr:phy:frame:InconsistentOFDMNumerology", ...
                    "nrOFDMInfo timing fields disagree with NumerologyCatalog.");
            end

            symbolLengths = double(sixgr.util.structGet( ...
                toolboxInfo, "SymbolLengths", []));
            symbolLengths = symbolLengths(:).';
            if isempty(symbolLengths)
                symbolLengths = nfft + cpLengths;
            end
            if numel(symbolLengths) ~= numel(cpLengths) || ...
                    any(~isfinite(symbolLengths)) || ...
                    any(symbolLengths ~= nfft + cpLengths)
                error("sixgr:phy:frame:InvalidOFDMSymbolLengths", ...
                    "nrOFDMInfo symbol lengths must equal Nfft plus each CP length.");
            end

            windowingSamples = localWindowingScalar(opts.WindowingSamples);
            occupiedBandwidthHz = occupiedSubcarriers * scsKHz * 1e3;
            aliasingMarginHz = sampleRate - occupiedBandwidthHz;
            if aliasingMarginHz < -max(1e-9 * sampleRate, 1e-6)
                error("sixgr:phy:frame:OFDMAliasing", ...
                    "Occupied bandwidth %.15g Hz exceeds sample rate %.15g Hz.", ...
                    occupiedBandwidthHz, sampleRate);
            end
            localValidateChannelFit(carrierState, occupiedBandwidthHz);

            slotInSubframe = mod(double(carrier.NSlot), ...
                numerology.SlotsPerSubframe) + 1;
            symbolMatrix = reshape(symbolLengths, symbolsPerSlot, []);
            cpMatrix = reshape(cpLengths, symbolsPerSlot, []);
            currentSymbolLengths = symbolMatrix(:, slotInSubframe).';
            [waveformSamples, modulationInfo] = localValidateWaveformLength( ...
                carrier, nfft, sampleRate, windowingSamples, ...
                symbolsPerSlot, currentSymbolLengths);

            samplesPerSlot = sum(symbolMatrix, 1);
            source = "nrOFDMInfo";
            if opts.NfftSpecified || opts.SampleRateSpecified
                source = "explicit_validated";
            end

            result = struct( ...
                "Nfft", double(nfft), ...
                "SampleRateHz", double(sampleRate), ...
                "SampleRate", double(sampleRate), ...
                "CyclicPrefixLengths", double(cpLengths), ...
                "CyclicPrefixLengthsPerSlot", ...
                    double(cpMatrix(:, slotInSubframe).'), ...
                "CyclicPrefixLengthsBySlot", double(cpMatrix), ...
                "SymbolLengths", double(symbolLengths), ...
                "SamplesPerSlot", double(samplesPerSlot), ...
                "CurrentSlotSamples", double(waveformSamples), ...
                "SymbolsPerSlot", double(symbolsPerSlot), ...
                "SlotsPerSubframe", double(numerology.SlotsPerSubframe), ...
                "NSizeGrid", double(nrb), ...
                "OccupiedSubcarrierCount", double(occupiedSubcarriers), ...
                "OccupiedBandwidthHz", double(occupiedBandwidthHz), ...
                "AliasingMarginHz", double(aliasingMarginHz), ...
                "WindowingSamples", double(windowingSamples), ...
                "Source", char(source), ...
                "ToolboxOFDMInfo", toolboxInfo, ...
                "ToolboxModulationInfo", modulationInfo, ...
                "IndexConvention", "zero_based_phy_indices");
        end

        function info = validateWindowing(carrierInput, windowingSamples)
        %VALIDATEWINDOWING Validate one explicit OFDM windowing sample count.
            windowingSamples = localWindowingScalar(windowingSamples);
            if windowingSamples == 0
                info = struct( ...
                    "WindowingSamples", 0, ...
                    "ValidatedBy", "zero_windowing_no_api_override", ...
                    "WaveformSamples", NaN);
                return;
            end
            sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
                carrierInput, "WindowingSamples", windowingSamples);
            info = struct( ...
                "WindowingSamples", double(windowingSamples), ...
                "ValidatedBy", "nrOFDMModulate", ...
                "WaveformSamples", double(sampling.CurrentSlotSamples));
        end
    end
end

function opts = localParseOptions(varargin)
opts = struct( ...
    "Nfft", [], ...
    "SampleRate", [], ...
    "WindowingSamples", 0, ...
    "NfftSpecified", false, ...
    "SampleRateSpecified", false);
if mod(numel(varargin), 2) ~= 0
    error("sixgr:phy:frame:InvalidOFDMSamplingArguments", ...
        "OFDM sampling arguments must occur in name-value pairs.");
end
for i = 1:2:numel(varargin)
    name = lower(strtrim(string(varargin{i})));
    value = varargin{i + 1};
    switch name
        case {"nfft", "fftlength"}
            opts.Nfft = value;
            opts.NfftSpecified = true;
        case {"samplerate", "sampleratehz"}
            opts.SampleRate = value;
            opts.SampleRateSpecified = true;
        case {"windowing", "windowingsamples"}
            opts.WindowingSamples = value;
        otherwise
            error("sixgr:phy:frame:InvalidOFDMSamplingArguments", ...
                "Unknown OFDMSamplingResolver option '%s'.", char(name));
    end
end
if opts.NfftSpecified
    opts.Nfft = localPositiveInteger(opts.Nfft, "Nfft");
end
if opts.SampleRateSpecified
    opts.SampleRate = localPositiveScalar(opts.SampleRate, "SampleRate");
end
opts.WindowingSamples = localWindowingScalar(opts.WindowingSamples);
end

function args = localInfoArguments(opts)
args = {"Windowing", opts.WindowingSamples};
if opts.NfftSpecified
    args = [args, {"Nfft", opts.Nfft}]; %#ok<AGROW>
end
if opts.SampleRateSpecified
    args = [args, {"SampleRate", opts.SampleRate}]; %#ok<AGROW>
end
end

function [carrier, state] = localCarrier(input)
state = struct();
if isa(input, "nrCarrierConfig")
    carrier = input;
    return;
end
if ~(isstruct(input) && isscalar(input))
    error("sixgr:phy:frame:InvalidCarrierGrid", ...
        "Carrier input must be nrCarrierConfig or a scalar resolved carrier struct.");
end
state = input;
if isfield(input, "Carrier") && isa(input.Carrier, "nrCarrierConfig")
    carrier = input.Carrier;
    return;
end

nSizeGrid = localFirstField(input, ["NSizeGrid", "N_RB", "NRB"], []);
scsKHz = localFirstField(input, ...
    ["SubcarrierSpacingKHz", "SubcarrierSpacing", "SCSKHz"], []);
nStartGrid = localFirstField(input, ["NStartGrid"], 0);
cyclicPrefix = localFirstField(input, ["CyclicPrefix"], "normal");
nCellID = localFirstField(input, ["NCellID"], 0);

try
    carrier = nrCarrierConfig;
    carrier.NSizeGrid = localPositiveInteger(nSizeGrid, "NSizeGrid");
    carrier.NStartGrid = localNonnegativeInteger(nStartGrid, "NStartGrid");
    carrier.SubcarrierSpacing = localPositiveScalar( ...
        scsKHz, "SubcarrierSpacingKHz");
    carrier.CyclicPrefix = char(lower(strtrim(string(cyclicPrefix))));
    carrier.NCellID = localNonnegativeInteger(nCellID, "NCellID");
catch ME
    wrapped = MException("sixgr:phy:frame:InvalidCarrierGrid", ...
        "Cannot construct nrCarrierConfig from the resolved carrier state: %s", ...
        ME.message);
    wrapped = addCause(wrapped, ME);
    throw(wrapped);
end
end

function value = localFirstField(input, names, defaultValue)
value = defaultValue;
fields = fieldnames(input);
for i = 1:numel(names)
    index = find(strcmpi(names(i), fields), 1);
    if ~isempty(index)
        value = input.(fields{index});
        return;
    end
end
end

function localValidateChannelFit(state, occupiedBandwidthHz)
if isempty(fieldnames(state))
    return;
end
channelBandwidthHz = localFirstField(state, ...
    ["ChannelBandwidthHz"], []);
if isempty(channelBandwidthHz)
    channelBandwidthMHz = localFirstField(state, ...
        ["ChannelBandwidthMHz"], []);
    if ~isempty(channelBandwidthMHz)
        channelBandwidthHz = double(channelBandwidthMHz) * 1e6;
    end
end
if isempty(channelBandwidthHz)
    return;
end
channelBandwidthHz = localPositiveScalar( ...
    channelBandwidthHz, "ChannelBandwidthHz");
lowGuardHz = localFirstField(state, ...
    ["MinimumLowGuardbandHz", "GuardbandLowHz"], 0);
highGuardHz = localFirstField(state, ...
    ["MinimumHighGuardbandHz", "GuardbandHighHz"], 0);
lowGuardHz = localNonnegativeScalar(lowGuardHz, "MinimumLowGuardbandHz");
highGuardHz = localNonnegativeScalar(highGuardHz, "MinimumHighGuardbandHz");
requiredHz = occupiedBandwidthHz + lowGuardHz + highGuardHz;
if requiredHz > channelBandwidthHz + max(1e-9 * channelBandwidthHz, 1e-6)
    error("sixgr:phy:frame:CarrierDoesNotFitChannelBandwidth", ...
        "Occupied bandwidth plus configured minimum guardbands is %.15g Hz, " + ...
        "which exceeds channel bandwidth %.15g Hz.", ...
        requiredHz, channelBandwidthHz);
end
end

function [waveformSamples, modulationInfo] = localValidateWaveformLength( ...
        carrier, nfft, sampleRate, windowingSamples, symbolsPerSlot, ...
        currentSlotSymbolLengths)
grid = complex(zeros(12 * double(carrier.NSizeGrid), symbolsPerSlot));
try
    [waveform, modulationInfo] = nrOFDMModulate( ...
        carrier, grid, ...
        "Nfft", double(nfft), ...
        "SampleRate", double(sampleRate), ...
        "Windowing", double(windowingSamples));
catch ME
    wrapped = MException( ...
        "sixgr:phy:frame:InvalidOFDMSamplingConfiguration", ...
        "nrOFDMModulate rejected the resolved OFDM configuration: %s", ...
        ME.message);
    wrapped = addCause(wrapped, ME);
    throw(wrapped);
end
waveformSamples = size(waveform, 1);
appliedWindowing = double(sixgr.util.structGet( ...
    modulationInfo, "Windowing", NaN));
if ~(isscalar(appliedWindowing) && isfinite(appliedWindowing) && ...
        appliedWindowing == windowingSamples)
    error("sixgr:phy:frame:WindowingNotAppliedExactly", ...
        "nrOFDMModulate reported Windowing=%g after %d samples were requested.", ...
        appliedWindowing, windowingSamples);
end
expectedSamples = sum(double(currentSlotSymbolLengths));
if waveformSamples ~= expectedSamples
    error("sixgr:phy:frame:UnexpectedOFDMSlotLength", ...
        "nrOFDMModulate produced %d samples for one slot; nrOFDMInfo " + ...
        "symbol lengths require %d samples.", waveformSamples, expectedSamples);
end
end

function value = localPositiveIntegerField(input, name)
value = localPositiveInteger(sixgr.util.structGet(input, name, []), name);
end

function value = localPositiveScalarField(input, name)
value = localPositiveScalar(sixgr.util.structGet(input, name, []), name);
end

function value = localWindowingScalar(raw)
if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
        ~isfinite(double(raw)) || double(raw) < 0 || ...
        double(raw) ~= round(double(raw))
    error("sixgr:phy:frame:InvalidWindowingSamples", ...
        "WindowingSamples must be a nonnegative integer sample count.");
end
value = round(double(raw));
end

function value = localPositiveScalar(raw, fieldName)
if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
        ~isfinite(double(raw)) || double(raw) <= 0
    error("sixgr:phy:frame:InvalidOFDMSamplingValue", ...
        "%s must be a positive finite numeric scalar.", fieldName);
end
value = double(raw);
end

function value = localNonnegativeScalar(raw, fieldName)
if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
        ~isfinite(double(raw)) || double(raw) < 0
    error("sixgr:phy:frame:InvalidOFDMSamplingValue", ...
        "%s must be a nonnegative finite numeric scalar.", fieldName);
end
value = double(raw);
end

function value = localPositiveInteger(raw, fieldName)
value = localPositiveScalar(raw, fieldName);
if value ~= round(value)
    error("sixgr:phy:frame:InvalidOFDMSamplingValue", ...
        "%s must be a positive integer.", fieldName);
end
value = round(value);
end

function value = localNonnegativeInteger(raw, fieldName)
if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
        ~isfinite(double(raw)) || double(raw) < 0 || double(raw) ~= round(double(raw))
    error("sixgr:phy:frame:InvalidOFDMSamplingValue", ...
        "%s must be a nonnegative integer.", fieldName);
end
value = round(double(raw));
end

function localRequireToolbox()
if exist("nrOFDMInfo", "file") ~= 2 || ...
        ~(exist("nrCarrierConfig", "class") == 8 || ...
          exist("nrCarrierConfig", "file") == 2)
    error("sixgr:phy:frame:OFDMToolboxDependencyUnavailable", ...
        "Strict standard OFDM sampling requires nrCarrierConfig and " + ...
        "nrOFDMInfo from MATLAB 5G Toolbox. No heuristic fallback is used.");
end
end
