classdef FrameStructureEngine
%FRAMESTRUCTUREENGINE Compatibility facade over the canonical frame package.
%
% The facade owns no physical lookup tables and performs no heuristic
% repair.  It delegates carrier, numerology, OFDM, duplex, SSB, and PRACH
% resolution to +sixgr/+phy/+frame.  PHY-facing slot and symbol indices are
% zero based.

    properties (SetAccess = private)
        Config struct = struct()
        CarrierGrid struct = struct()
        Numerology struct = struct()
        OFDMSampling struct = struct()
        SlotState = []
        FDDContexts = []
        SSBTiming struct = struct()
        PRACHTiming struct = struct()

        BandwidthHz (1,1) double = NaN
        CenterFrequencyHz (1,1) double = NaN
        FrequencyRange (1,1) string = ""
        SCSkHz (1,1) double = NaN
        Mu (1,1) double = NaN
        CyclicPrefix (1,1) string = ""
        SymbolsPerSlot (1,1) double = NaN
        SlotsPerFrame (1,1) double = NaN
        SlotDuration_ms (1,1) double = NaN
        ConfiguredGridNumRBs (1,1) double = NaN
        NRB (1,1) double = NaN
        ActiveGridSource (1,1) string = ""
        FFTSize (1,1) double = NaN
        SampleRate_Hz (1,1) double = NaN
        DuplexMode (1,1) string = ""
        TDDPattern (1,1) string = ""

        SSBCase (1,1) string = ""
        SSBLmax (1,1) double = NaN
        SSBCandidateSymbols double = []
        SSBCandidateSlots1Based double = []

        PRACHConfigurationIndex (1,1) double = NaN
        PRACHFormat (1,1) string = ""
        PRACHStartSymbol (1,1) double = NaN
        PRACHDurationSymbols (1,1) double = NaN
        PRACHValidSlots1Based double = []
        PRACHValidSlots0Based double = []
        PRACHValidationStatus (1,1) string = "not_configured"
        ValidationLog string = strings(0, 1)
        IndexConvention (1,1) string = "zero_based_phy_indices"
        ResolveSignalTiming (1,1) logical = true
    end

    methods
        function obj = FrameStructureEngine(cfg, varargin)
            if nargin < 1 || ~(isstruct(cfg) && isscalar(cfg))
                error("sixgr:phy:FrameStructureEngine:InvalidConfig", ...
                    "FrameStructureEngine requires one scalar resolved configuration struct.");
            end
            parser = inputParser;
            parser.FunctionName = "sixgr.phy.FrameStructureEngine";
            parser.addParameter("FrameCoreOnly", false, ...
                @(value) islogical(value) && isscalar(value));
            parser.parse(varargin{:});
            obj.ResolveSignalTiming = ~logical(parser.Results.FrameCoreOnly);
            obj.Config = cfg;
            obj = obj.resolve();
        end

        function obj = resolve(obj)
            cfg = obj.Config;
            obj.CenterFrequencyHz = localRequiredFrequency(cfg);
            configuredRange = localFirstText(cfg, [ ...
                "frequency.range_name", "phy.frequencyRange", ...
                "phy.carrier.FrequencyRange"], "");
            rangeArgs = {"CenterFrequencyHz", obj.CenterFrequencyHz};
            if strlength(configuredRange) > 0
                rangeArgs = [rangeArgs, {"FrequencyRange", configuredRange}]; %#ok<AGROW>
            end
            rangeInfo = sixgr.phy.frame.FrequencyRangeResolver.resolve(rangeArgs{:});
            obj.FrequencyRange = string(rangeInfo.FrequencyRange);

            obj.BandwidthHz = localRequiredBandwidthHz(cfg);
            obj.SCSkHz = localRequiredNumeric(cfg, [ ...
                "frame.scs_khz", "phy.carrier.SubcarrierSpacing_kHz", ...
                "phy.carrier.SubcarrierSpacing", ...
                "carrier.SubcarrierSpacing"], ...
                "sixgr:phy:FrameStructureEngine:MissingSCS", ...
                "A carrier subcarrier spacing is required.");
            obj.CyclicPrefix = lower(localFirstText(cfg, [ ...
                "frame.cp_type", "phy.carrier.CyclicPrefix", ...
                "carrier.CyclicPrefix"], ""));
            if strlength(obj.CyclicPrefix) == 0
                error("sixgr:phy:FrameStructureEngine:MissingCyclicPrefix", ...
                    "An explicit normal or extended cyclic prefix is required.");
            end

            configuredGrid = localOptionalNumeric(cfg, [ ...
                "frequency.n_size_grid", "phy.carrier.NSizeGrid", ...
                "carrier.NSizeGrid"]);
            obj.ConfiguredGridNumRBs = configuredGrid;
            nStartGrid = localOptionalNumeric(cfg, [ ...
                "frequency.n_start_grid", "phy.carrier.NStartGrid", ...
                "carrier.NStartGrid"]);
            if ~isfinite(nStartGrid)
                nStartGrid = 0;
            end
            nStartBWP = localOptionalNumeric(cfg, [ ...
                "phy.bwp.dl.NStartBWP", "frequency.n_start_bwp"]);
            nSizeBWP = localOptionalNumeric(cfg, [ ...
                "phy.bwp.dl.NSizeBWP", "frequency.n_size_bwp"]);
            bwpSCSKHz = localOptionalNumeric(cfg, [ ...
                "phy.bwp.dl.SCSKHz", ...
                "phy.bwp.dl.SubcarrierSpacing_kHz", ...
                "phy.bwp.dl.SubcarrierSpacingKHz"]);

            gridArgs = { ...
                "Role", "gNB", ...
                "FrequencyRange", obj.FrequencyRange, ...
                "CenterFrequencyHz", obj.CenterFrequencyHz, ...
                "ChannelBandwidthMHz", obj.BandwidthHz / 1e6, ...
                "SubcarrierSpacingKHz", obj.SCSkHz, ...
                "NStartGrid", nStartGrid, ...
                "CyclicPrefix", obj.CyclicPrefix};
            if isfinite(configuredGrid)
                gridArgs = [gridArgs, {"ConfiguredNSizeGrid", configuredGrid}]; %#ok<AGROW>
            end
            if isfinite(nStartBWP) || isfinite(nSizeBWP)
                gridArgs = [gridArgs, ...
                    {"NStartBWP", nStartBWP, "NSizeBWP", nSizeBWP}]; %#ok<AGROW>
                if isfinite(bwpSCSKHz)
                    gridArgs = [gridArgs, ...
                        {"BWPSubcarrierSpacingKHz", bwpSCSKHz}]; %#ok<AGROW>
                end
            end
            obj.CarrierGrid = sixgr.phy.frame.CarrierGridConfig.resolve(gridArgs{:});
            obj.Numerology = obj.CarrierGrid.Numerology;
            obj.NRB = double(obj.CarrierGrid.NSizeGrid);
            obj.ActiveGridSource = string(obj.CarrierGrid.SourceTable);
            obj.Mu = double(obj.Numerology.Mu);
            obj.SymbolsPerSlot = double(obj.Numerology.SymbolsPerSlot);
            obj.SlotsPerFrame = double(obj.Numerology.SlotsPerFrame);
            obj.SlotDuration_ms = double(obj.Numerology.SlotDurationMilliseconds);

            ofdmArgs = localExplicitOFDMArguments(cfg);
            obj.OFDMSampling = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
                obj.CarrierGrid, ofdmArgs{:});
            obj.FFTSize = double(obj.OFDMSampling.Nfft);
            obj.SampleRate_Hz = double(obj.OFDMSampling.SampleRateHz);

            obj.DuplexMode = upper(localFirstText(cfg, [ ...
                "frequency.duplex_mode", "global_radio_scope.duplex_mode", ...
                "phy.duplex.mode", "scenario.duplexMode"], ""));
            if strlength(obj.DuplexMode) > 0 && ...
                    ~any(obj.DuplexMode == ["TDD", "FDD"])
                error("sixgr:phy:FrameStructureEngine:InvalidDuplexMode", ...
                    "Duplex mode must be TDD or FDD.");
            end
            if obj.DuplexMode == "TDD"
                obj.SlotState = localResolveTDDState(cfg, obj.SCSkHz, ...
                    obj.CyclicPrefix);
                obj.TDDPattern = string(obj.SlotState.compactMap());
            elseif obj.DuplexMode == "FDD"
                obj.FDDContexts = localResolveFDDContexts(cfg, obj);
                obj.TDDPattern = "not_applicable";
            end

            if obj.ResolveSignalTiming && localSSBConfigured(cfg)
                obj.SSBTiming = sixgr.phy.frame.SSBTimingResolver. ...
                    resolveFromConfig(localAugmentCanonicalAliases(cfg, obj));
                obj.SSBCase = string(obj.SSBTiming.Case);
                obj.SSBLmax = double(obj.SSBTiming.Lmax);
                obj.SSBCandidateSymbols = double( ...
                    obj.SSBTiming.CandidateStartSymbolsWithinHalfFrame);
                obj.SSBCandidateSlots1Based = double( ...
                    obj.SSBTiming.CandidateSlotsWithinHalfFrame) + 1;
            end

            if obj.ResolveSignalTiming && localPRACHConfigured(cfg)
                prachCfg = localAugmentCanonicalAliases(cfg, obj);
                prachArgs = {};
                if obj.DuplexMode == "TDD"
                    prachArgs = { ...
                        "CommonDirection", obj.SlotState.CommonDirection, ...
                        "ResolvedDirection", obj.SlotState.ResolvedDirection};
                end
                obj.PRACHTiming = sixgr.phy.frame.PRACHOccasionResolver. ...
                    resolveFromConfig(prachCfg, prachArgs{:});
                obj = obj.publishPRACHAliases();
            end
        end

        function s = toStruct(obj)
            s = struct( ...
                "ContractVersion", "sixgr_frame_structure_facade/v2", ...
                "IndexConvention", obj.IndexConvention, ...
                "CarrierGrid", obj.CarrierGrid, ...
                "Numerology", obj.Numerology, ...
                "OFDMSampling", localOFDMSnapshot(obj.OFDMSampling), ...
                "SlotState", localSlotStateSnapshot(obj.SlotState), ...
                "FDDContexts", localFDDContextSnapshot(obj.FDDContexts), ...
                "SSBTiming", obj.SSBTiming, ...
                "PRACHTiming", obj.PRACHTiming, ...
                "BandwidthHz", obj.BandwidthHz, ...
                "CenterFrequencyHz", obj.CenterFrequencyHz, ...
                "FrequencyRange", obj.FrequencyRange, ...
                "SCSkHz", obj.SCSkHz, ...
                "Mu", obj.Mu, ...
                "CyclicPrefix", obj.CyclicPrefix, ...
                "SymbolsPerSlot", obj.SymbolsPerSlot, ...
                "SlotsPerFrame", obj.SlotsPerFrame, ...
                "SlotDuration_ms", obj.SlotDuration_ms, ...
                "ConfiguredGridNumRBs", obj.ConfiguredGridNumRBs, ...
                "NRB", obj.NRB, ...
                "ActiveGridSource", obj.ActiveGridSource, ...
                "FFTSize", obj.FFTSize, ...
                "SampleRate_Hz", obj.SampleRate_Hz, ...
                "DuplexMode", obj.DuplexMode, ...
                "TDDPattern", obj.TDDPattern, ...
                "SSBCase", obj.SSBCase, ...
                "SSBLmax", obj.SSBLmax, ...
                "SSBCandidateSymbols", obj.SSBCandidateSymbols, ...
                "PRACHConfigurationIndex", obj.PRACHConfigurationIndex, ...
                "PRACHFormat", obj.PRACHFormat, ...
                "PRACHStartSymbol", obj.PRACHStartSymbol, ...
                "PRACHDurationSymbols", obj.PRACHDurationSymbols, ...
                "PRACHValidSlots0Based", obj.PRACHValidSlots0Based, ...
                "PRACHValidationStatus", obj.PRACHValidationStatus, ...
                "ValidationLog", obj.ValidationLog, ...
                "SignalTimingResolved", obj.ResolveSignalTiming);
        end

        function token = TDDToken(obj, absoluteSlot)
            if obj.DuplexMode ~= "TDD"
                error("sixgr:phy:frame:FDDHasNoTDDToken", ...
                    "FDD has separate DL and UL grids and no TDD slot token.");
            end
            token = sixgr.phy.FrameStructureEngine. ...
                TDDTokenFromState(obj.SlotState, absoluteSlot);
        end

        function partition = SlotPartition(obj, absoluteSlot)
            if obj.DuplexMode ~= "TDD"
                error("sixgr:phy:frame:TDDResolverCalledForFDD", ...
                    "SlotPartition is a TDD operation; use the explicit FDD context.");
            end
            partition = sixgr.phy.FrameStructureEngine. ...
                SlotPartitionFromState(obj.SlotState, absoluteSlot);
        end

        function tf = IsDLSlot(obj, absoluteSlot)
            partition = obj.SlotPartition(absoluteSlot);
            tf = partition.AllowDL;
        end

        function tf = IsULSlot(obj, absoluteSlot)
            partition = obj.SlotPartition(absoluteSlot);
            tf = partition.AllowUL;
        end

        function tf = IsSpecialSlot(obj, absoluteSlot)
            tf = obj.SlotPartition(absoluteSlot).IsSpecialSlot;
        end

        function tf = IsDLAllocation(obj, absoluteSlot, symbolAllocation)
            tf = localAllocationAvailable( ...
                obj.SlotState, absoluteSlot, symbolAllocation, "DL");
        end

        function tf = IsULAllocation(obj, absoluteSlot, symbolAllocation)
            tf = localAllocationAvailable( ...
                obj.SlotState, absoluteSlot, symbolAllocation, "UL");
        end

        function tf = IsPRACHSlot(obj, absoluteSlot)
            validateattributes(absoluteSlot, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            tf = false;
            if isempty(fieldnames(obj.PRACHTiming)) || ...
                    ~istable(obj.PRACHTiming.Occasions)
                return;
            end
            period = double(obj.PRACHTiming.PeriodCarrierSlots);
            canonical = mod(double(absoluteSlot), period);
            tf = any(double(obj.PRACHTiming.Occasions.AbsoluteSlot) == canonical);
        end
    end

    methods (Static)
        function token = TDDTokenFromState(state, absoluteSlot)
            common = localTDDRow(state, absoluteSlot, "CommonDirection");
            if all(common == 'D')
                token = 'D';
            elseif all(common == 'U')
                token = 'U';
            else
                token = 'F';
            end
        end

        function partition = SlotPartitionFromState(state, absoluteSlot)
            common = localTDDRow(state, absoluteSlot, "CommonDirection");
            resolved = string(localTDDRow( ...
                state, absoluteSlot, "ResolvedDirection"));
            dl = find(resolved == "D" | resolved == "DL") - 1;
            ul = find(resolved == "U" | resolved == "UL") - 1;
            guard = find(resolved == "GUARD") - 1;
            unresolved = find(resolved == "UNRESOLVED_FLEX") - 1;
            token = sixgr.phy.FrameStructureEngine. ...
                TDDTokenFromState(state, absoluteSlot);
            if token == 'D'
                label = "DL";
            elseif token == 'U'
                label = "UL";
            else
                label = "FLEXIBLE_OR_MIXED";
            end
            partition = struct( ...
                "DuplexMode", "TDD", ...
                "CanonicalSlot", double(absoluteSlot), ...
                "SlotToken", token, ...
                "SlotLabel", label, ...
                "SymbolsPerSlot", double(size(common, 2)), ...
                "CommonDirection", common, ...
                "ResolvedDirection", resolved, ...
                "AllowDL", ~isempty(dl), ...
                "AllowUL", ~isempty(ul), ...
                "IsSpecialSlot", token == 'F', ...
                "DLSymbolIndices0Based", double(dl), ...
                "GuardSymbolIndices0Based", double(guard), ...
                "ULSymbolIndices0Based", double(ul), ...
                "UnresolvedFlexibleSymbolIndices0Based", double(unresolved), ...
                "DLSymbolAllocation", localContiguousAllocation(dl), ...
                "GuardSymbolAllocation", localContiguousAllocation(guard), ...
                "ULSymbolAllocation", localContiguousAllocation(ul), ...
                "SpecialSlotDLSymbols", numel(dl), ...
                "SpecialSlotGuardSymbols", numel(guard), ...
                "SpecialSlotULSymbols", numel(ul), ...
                "IndexConvention", "zero_based_phy_indices");
        end
    end

    methods (Access = private)
        function obj = publishPRACHAliases(obj)
            obj.PRACHConfigurationIndex = ...
                double(obj.PRACHTiming.ConfigurationIndex);
            obj.PRACHFormat = string(obj.PRACHTiming.Format);
            occasions = obj.PRACHTiming.Occasions;
            obj.PRACHStartSymbol = double(occasions.StartSymbol(1));
            obj.PRACHDurationSymbols = double(occasions.DurationSymbols(1));
            obj.PRACHValidSlots0Based = unique( ...
                double(occasions.AbsoluteSlot(:)).', "stable");
            obj.PRACHValidSlots1Based = obj.PRACHValidSlots0Based + 1;
            obj.PRACHValidationStatus = "resolved_exact_repetition_period";
        end
    end
end

function value = localRequiredFrequency(cfg)
value = localRequiredNumeric(cfg, [ ...
    "frequency.center_frequency_hz", "phy.carrier.centerFrequency_Hz", ...
    "phy.fc_Hz", "channel.fc_Hz"], ...
    "sixgr:phy:FrameStructureEngine:MissingCenterFrequency", ...
    "A standard carrier center frequency is required.");
end

function value = localRequiredBandwidthHz(cfg)
value = localOptionalNumeric(cfg, [ ...
    "frequency.bandwidth_hz", "channel.bandwidth_Hz", ...
    "carrier.bandwidth_hz"]);
if ~isfinite(value)
    mhz = localOptionalNumeric(cfg, [ ...
        "phy.channelBandwidth_MHz", "pdsch6gr.ChannelBandwidthMHz"]);
    if isfinite(mhz)
        value = mhz * 1e6;
    end
end
if ~(isscalar(value) && isfinite(value) && value > 0)
    error("sixgr:phy:FrameStructureEngine:MissingChannelBandwidth", ...
        "A positive standard channel bandwidth with explicit units is required.");
end
end

function value = localRequiredNumeric(cfg, paths, id, message)
value = localOptionalNumeric(cfg, paths);
if ~(isscalar(value) && isfinite(value) && value > 0)
    error(id, "%s", message);
end
end

function value = localOptionalNumeric(cfg, paths)
value = NaN;
for path = paths
    raw = sixgr.util.structGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
            ~isfinite(double(raw))
        error("sixgr:phy:FrameStructureEngine:InvalidNumericConfig", ...
            "%s must be a finite numeric scalar.", path);
    end
    value = double(raw);
    return;
end
end

function value = localFirstText(cfg, paths, defaultValue)
value = string(defaultValue);
for path = paths
    raw = sixgr.util.structGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
        error("sixgr:phy:FrameStructureEngine:InvalidTextConfig", ...
            "%s must be scalar text.", path);
    end
    candidate = strtrim(string(raw));
    if strlength(candidate) > 0
        value = candidate;
        return;
    end
end
end

function args = localExplicitOFDMArguments(cfg)
args = {};
nfft = localOptionalNumeric(cfg, [ ...
    "phy.ofdm.explicitNfft", "waveform.explicit_fft_size"]);
sampleRate = localOptionalNumeric(cfg, [ ...
    "phy.ofdm.explicitSampleRate_Hz", ...
    "waveform.explicit_sample_rate_hz"]);
windowing = localOptionalNumeric(cfg, [ ...
    "phy.ofdm.windowingSamples", ...
    "phy.waveform.windowingSamples", ...
    "waveform.windowing_samples"]);
if isfinite(nfft)
    args = [args, {"Nfft", nfft}]; %#ok<AGROW>
end
if isfinite(sampleRate)
    args = [args, {"SampleRate", sampleRate}]; %#ok<AGROW>
end
if isfinite(windowing)
    args = [args, {"WindowingSamples", windowing}]; %#ok<AGROW>
else
    args = [args, {"WindowingSamples", 0}]; %#ok<AGROW>
end
end

function state = localResolveTDDState(cfg, activeSCS, cyclicPrefix)
node = localFirstStruct(cfg, [ ...
    "phy.duplex.tddCommon", "frame.tdd_common", ...
    "frame_timing.tdd_common"]);
if isempty(fieldnames(node))
    error("sixgr:phy:frame:MissingTDDCommonConfig", ...
        "TDD requires a canonical tdd-UL-DL-ConfigurationCommon " + ...
        "snapshot; no compact-pattern default is used.");
end
referenceSCS = localStructNumeric(node, [ ...
    "ReferenceSubcarrierSpacingKHz", ...
    "referenceSubcarrierSpacingKHz", "reference_scs_khz"]);
if ~isfinite(referenceSCS)
    error("sixgr:phy:frame:MissingTDDCommonPatternField", ...
        "tddCommon.ReferenceSubcarrierSpacingKHz is required.");
end
pattern1 = localStructValue(node, ["Pattern1", "pattern1"], struct());
pattern2 = localStructValue(node, ["Pattern2", "pattern2"], struct());
dedicated = localFirstValue(cfg, [ ...
    "phy.duplex.tddDedicated", "frame.tdd_dedicated", ...
    "frame_timing.tdd_dedicated"], struct([]));
state = sixgr.phy.frame.SlotFormatResolver.resolve( ...
    "ReferenceSubcarrierSpacingKHz", referenceSCS, ...
    "ActiveSubcarrierSpacingKHz", activeSCS, ...
    "CyclicPrefix", cyclicPrefix, ...
    "Pattern1", pattern1, ...
    "Pattern2", pattern2, ...
    "DedicatedOverrides", dedicated);
end

function contexts = localResolveFDDContexts(cfg, obj)
dlFc = localOptionalNumeric(cfg, [ ...
    "phy.duplex.fdd.dlCenterFrequencyHz", ...
    "frequency.dl_center_frequency_hz"]);
ulFc = localOptionalNumeric(cfg, [ ...
    "phy.duplex.fdd.ulCenterFrequencyHz", ...
    "frequency.ul_center_frequency_hz"]);
if ~isfinite(dlFc) && ~isfinite(ulFc)
    contexts = [];
    return;
end
if ~isfinite(dlFc) || ~isfinite(ulFc)
    error("sixgr:phy:frame:FDDRequiresSeparateFrequencies", ...
        "FDD requires both explicit DL and UL center frequencies.");
end
contexts = sixgr.phy.frame.FDDCarrierContexts.create( ...
    "CellID", localNumericOrDefault(cfg, "phy.carrier.NCellID", 0), ...
    "DLCCID", localNumericOrDefault(cfg, "phy.duplex.fdd.dlCCID", 0), ...
    "ULCCID", localNumericOrDefault(cfg, "phy.duplex.fdd.ulCCID", 0), ...
    "DLBWPID", localNumericOrDefault(cfg, "phy.duplex.fdd.dlBWPID", 0), ...
    "ULBWPID", localNumericOrDefault(cfg, "phy.duplex.fdd.ulBWPID", 0), ...
    "DLCenterFrequencyHz", dlFc, ...
    "ULCenterFrequencyHz", ulFc, ...
    "SubcarrierSpacingKHz", obj.SCSkHz, ...
    "DLNumRB", obj.NRB, ...
    "ULNumRB", localNumericOrDefault(cfg, ...
        "phy.duplex.fdd.ulNSizeGrid", obj.NRB), ...
    "CyclicPrefix", obj.CyclicPrefix, ...
    "ULTimingAdvanceSamples", localNumericOrDefault(cfg, ...
        "phy.duplex.fdd.ulTimingAdvanceSamples", 0));
end

function tf = localSSBConfigured(cfg)
enabled = sixgr.util.structGet(cfg, "phy.ssb.enable", []);
caseValue = localFirstText(cfg, [ ...
    "phy.ssb.blockPattern", "phy.ssb.case"], "");
tf = strlength(caseValue) > 0 && ...
    (isempty(enabled) || (isscalar(enabled) && logical(enabled)));
end

function tf = localPRACHConfigured(cfg)
enabled = sixgr.util.structGet(cfg, "phy.prach.enable", []);
index = localOptionalNumeric(cfg, [ ...
    "phy.prach.configurationIndex", ...
    "random_access.configuration_index"]);
scs = localOptionalNumeric(cfg, [ ...
    "phy.prach.subcarrierSpacing_kHz", ...
    "phy.prach.subcarrierSpacingKHz", ...
    "random_access.subcarrier_spacing_khz"]);
tf = isfinite(index) && isfinite(scs) && ...
    (isempty(enabled) || (isscalar(enabled) && logical(enabled)));
end

function cfg = localAugmentCanonicalAliases(cfg, obj)
cfg = sixgr.util.structSet(cfg, "phy.frequencyRange", char(obj.FrequencyRange));
cfg = sixgr.util.structSet(cfg, ...
    "phy.carrier.centerFrequency_Hz", obj.CenterFrequencyHz);
cfg = sixgr.util.structSet(cfg, ...
    "phy.carrier.SubcarrierSpacing_kHz", obj.SCSkHz);
cfg = sixgr.util.structSet(cfg, ...
    "phy.carrier.CyclicPrefix", char(obj.CyclicPrefix));
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", obj.NRB);
cfg = sixgr.util.structSet(cfg, ...
    "phy.carrier.NStartGrid", obj.CarrierGrid.NStartGrid);
prachSCS = localOptionalNumeric(cfg, [ ...
    "phy.prach.subcarrierSpacing_kHz", ...
    "phy.prach.subcarrierSpacingKHz", ...
    "random_access.subcarrier_spacing_khz"]);
if isfinite(prachSCS)
    cfg = sixgr.util.structSet(cfg, ...
        "phy.prach.subcarrierSpacing_kHz", prachSCS);
end
end

function row = localTDDRow(state, absoluteSlot, fieldName)
validateattributes(absoluteSlot, {'numeric'}, ...
    {'scalar','integer','nonnegative','finite'});
map = state.(fieldName);
rowIndex = mod(double(absoluteSlot), size(map, 1)) + 1;
row = map(rowIndex, :);
end

function allocation = localContiguousAllocation(indices)
if isempty(indices)
    allocation = zeros(1, 2);
elseif all(diff(indices) == 1)
    allocation = [double(indices(1)), double(numel(indices))];
else
    allocation = [NaN, NaN];
end
end

function tf = localAllocationAvailable(state, absoluteSlot, allocation, direction)
values = double(allocation(:).');
if numel(values) ~= 2
    error("sixgr:phy:frame:InvalidTDRA", ...
        "Symbol allocation must be [zeroBasedStart, NumSymbols].");
end
result = sixgr.phy.frame.SlotFormatResolver.isAvailable( ...
    state, absoluteSlot, values(1), values(2), direction);
tf = logical(result.Available);
end

function snapshot = localOFDMSnapshot(value)
snapshot = value;
if isfield(snapshot, "ToolboxOFDMInfo")
    snapshot = rmfield(snapshot, "ToolboxOFDMInfo");
end
if isfield(snapshot, "ToolboxModulationInfo")
    snapshot = rmfield(snapshot, "ToolboxModulationInfo");
end
end

function snapshot = localSlotStateSnapshot(state)
snapshot = struct();
if isempty(state)
    return;
end
snapshot = struct( ...
    "Class", class(state), ...
    "DuplexMode", string(state.DuplexMode), ...
    "IndexConvention", string(state.IndexConvention), ...
    "CommonDirection", state.CommonDirection, ...
    "ResolvedDirection", state.ResolvedDirection, ...
    "SymbolsPerSlot", double(size(state.CommonDirection, 2)), ...
    "SlotsPerPattern", double(size(state.CommonDirection, 1)));
if isprop(state, "DedicatedDirection")
    snapshot.DedicatedDirection = state.DedicatedDirection;
end
end

function snapshot = localFDDContextSnapshot(value)
if isempty(value)
    snapshot = struct();
else
    snapshot = struct( ...
        "DuplexMode", value.DuplexMode, ...
        "Downlink", value.Downlink, ...
        "Uplink", value.Uplink, ...
        "SlotsPerFrame", value.SlotsPerFrame, ...
        "SymbolsPerSlot", value.SymbolsPerSlot, ...
        "IndexConvention", value.IndexConvention);
end
end

function node = localFirstStruct(cfg, paths)
node = struct();
for path = paths
    value = sixgr.util.structGet(cfg, path, []);
    if isempty(value)
        continue;
    end
    if ~(isstruct(value) && isscalar(value))
        error("sixgr:phy:frame:InvalidTDDCommonConfig", ...
            "%s must be a scalar struct.", path);
    end
    node = value;
    return;
end
end

function value = localFirstValue(cfg, paths, defaultValue)
value = defaultValue;
for path = paths
    candidate = sixgr.util.structGet(cfg, path, []);
    if ~isempty(candidate)
        value = candidate;
        return;
    end
end
end

function value = localStructNumeric(s, names)
value = localStructValue(s, names, NaN);
if isempty(value)
    value = NaN;
elseif ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ...
        ~isfinite(double(value))
    error("sixgr:phy:frame:InvalidTDDCommonConfig", ...
        "%s must be a finite numeric scalar.", names(1));
else
    value = double(value);
end
end

function value = localStructValue(s, names, defaultValue)
value = defaultValue;
fields = string(fieldnames(s));
for name = names
    index = find(strcmpi(fields, name), 1);
    if ~isempty(index)
        value = s.(char(fields(index)));
        return;
    end
end
end

function value = localNumericOrDefault(cfg, path, defaultValue)
value = sixgr.util.structGet(cfg, path, defaultValue);
if isempty(value)
    value = defaultValue;
end
if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ...
        ~isfinite(double(value))
    error("sixgr:phy:FrameStructureEngine:InvalidNumericConfig", ...
        "%s must be a finite numeric scalar.", path);
end
value = double(value);
end
