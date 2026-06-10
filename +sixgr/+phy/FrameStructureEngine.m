classdef FrameStructureEngine
%FRAMESTRUCTUREENGINE Resolve NR/6G-study frame, grid, and occasion metadata.
%
% This resolver keeps deterministic configuration-derived timing metadata in
% one place. It does not create PHY measurements; it resolves standard table
% values and slot-symbol ownership so downstream runtime/export code can stop
% carrying divergent NRB, FFT, PDSCH, and PRACH interpretations.

    properties
        Config struct = struct()
        BandwidthHz (1,1) double = NaN
        CenterFrequencyHz (1,1) double = NaN
        FrequencyRange (1,1) string = "FR1"
        SCSkHz (1,1) double = 30
        Mu (1,1) double = 1
        CyclicPrefix (1,1) string = "normal"
        SymbolsPerSlot (1,1) double = 14
        SlotsPerFrame (1,1) double = 20
        SlotDuration_ms (1,1) double = 0.5
        ConfiguredGridNumRBs (1,1) double = NaN
        NRB (1,1) double = NaN
        ActiveGridSource (1,1) string = "unresolved"
        FFTSize (1,1) double = NaN
        SampleRate_Hz (1,1) double = NaN
        DuplexMode (1,1) string = "TDD"
        TDDPattern (1,1) string = "DDDSU"
        SpecialSlotDLSymbols (1,1) double = 12
        SpecialSlotGuardSymbols (1,1) double = 1
        SpecialSlotULSymbols (1,1) double = 1
        CORESETDuration (1,1) double = 1
        CORESETBandwidth_RB (1,1) double = NaN
        PDSCHStartSymbol (1,1) double = 1
        PDSCHNumSymbols (1,1) double = 13
        SSBCase (1,1) string = "C"
        SSBLmax (1,1) double = 8
        SSBCandidateSymbols double = []
        SSBCandidateSlots1Based double = []
        PRACHConfigurationIndex (1,1) double = NaN
        PRACHFormat (1,1) string = ""
        PRACHStartSymbol (1,1) double = NaN
        PRACHDurationSymbols (1,1) double = NaN
        PRACHValidSlots1Based double = []
        PRACHValidSlots0Based double = []
        PRACHValidationStatus (1,1) string = "unresolved"
        ValidationLog string = strings(0, 1)
    end

    methods
        function obj = FrameStructureEngine(cfg)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            if ~(isstruct(cfg) && isscalar(cfg))
                cfg = struct();
            end
            obj.Config = cfg;
            obj = obj.resolve();
        end

        function obj = resolve(obj)
            cfg = obj.Config;
            obj.CenterFrequencyHz = obj.firstNumeric([ ...
                "frequency.center_frequency_hz", "phy.fc_Hz", "channel.fc_Hz", ...
                "prach_lls.CarrierFrequencyHz", "carrier.center_frequency_hz"], NaN);
            obj.FrequencyRange = upper(string(obj.firstText([ ...
                "frequency.range_name", "phy.frequencyRange", "prach_lls.FrequencyRange"], "")));
            if strlength(obj.FrequencyRange) == 0
                obj.FrequencyRange = sixgr.phy.FrameStructureEngine.deriveFrequencyRange(obj.CenterFrequencyHz);
            end

            obj.BandwidthHz = obj.firstNumeric([ ...
                "frequency.bandwidth_hz", "phy.bandwidth_Hz", "carrier.bandwidth_hz", ...
                "pdsch6gr.ChannelBandwidthMHz"], NaN);
            if isfinite(obj.BandwidthHz) && obj.BandwidthHz < 1e6
                obj.BandwidthHz = obj.BandwidthHz * 1e6;
            end

            obj.SCSkHz = obj.firstNumeric([ ...
                "frame.scs_khz", "phy.carrier.SubcarrierSpacing_kHz", ...
                "phy.carrier.SubcarrierSpacing", "prach_lls.CarrierSCSkHz"], obj.SCSkHz);
            obj.SCSKHzSanity();
            obj.Mu = round(log2(obj.SCSkHz / 15));
            obj.SlotsPerFrame = 10 * 2^double(obj.Mu);
            obj.SlotDuration_ms = 1 / 2^double(obj.Mu);
            obj.CyclicPrefix = lower(string(obj.firstText([ ...
                "frame.cp_type", "phy.carrier.CyclicPrefix", "carrier.cyclic_prefix"], char(obj.CyclicPrefix))));
            if obj.CyclicPrefix == "extended" && obj.SCSkHz == 60
                obj.SymbolsPerSlot = 12;
            else
                obj.SymbolsPerSlot = 14;
            end

            obj.ConfiguredGridNumRBs = obj.firstNumeric([ ...
                "frequency.n_size_grid", "phy.numerology.configuredGridNumRBs", ...
                "phy.carrier.NSizeGrid", "carrier.n_rb", "prach_lls.NSizeGrid"], NaN);
            tableNRB = sixgr.phy.FrameStructureEngine.lookupNRB(obj.BandwidthHz, obj.SCSkHz, obj.FrequencyRange);
            if isfinite(tableNRB)
                obj.NRB = tableNRB;
                obj.ActiveGridSource = "ts38101_5_3_2_bandwidth_scs_lookup";
            elseif isfinite(obj.ConfiguredGridNumRBs) && obj.ConfiguredGridNumRBs > 0
                obj.NRB = round(obj.ConfiguredGridNumRBs);
                obj.ActiveGridSource = "configured_grid_no_standard_bandwidth_scs_match";
                obj.ValidationLog(end+1, 1) = sprintf("No TS 38.101 NRB table entry for BW=%g Hz, SCS=%g kHz, FR=%s; preserving configured NSizeGrid=%g.", ...
                    obj.BandwidthHz, obj.SCSkHz, char(obj.FrequencyRange), obj.ConfiguredGridNumRBs);
            else
                error("sixgr:phy:FrameStructureEngine:UnresolvedNRB", ...
                    "Cannot resolve active NRB: provide a standard bandwidth/SCS pair or configured NSizeGrid.");
            end
            obj.FFTSize = sixgr.phy.FrameStructureEngine.defaultFFTSize(obj.NRB);
            obj.SampleRate_Hz = obj.FFTSize * obj.SCSkHz * 1e3;

            obj.DuplexMode = upper(string(obj.firstText([ ...
                "frequency.duplex_mode", "global_radio_scope.duplex_mode", ...
                "phy.duplex.mode", "scenario.duplexMode"], char(obj.DuplexMode))));
            pattern = obj.firstValue([ ...
                "frame_timing.tdd_pattern", "frame.tdd_pattern", ...
                "phy.duplex.tddPattern", "scenario.tddPattern"], char(obj.TDDPattern));
            obj.TDDPattern = string(sixgr.phy.FrameStructureEngine.expandTDDPattern(pattern));

            obj = obj.resolveSpecialSlot();
            obj = obj.resolveControlAndDataSymbols();
            obj = obj.resolveSSB();
            obj = obj.resolvePRACH();
        end

        function s = toStruct(obj)
            s = struct();
            names = properties(obj);
            for i = 1:numel(names)
                name = names{i};
                if strcmp(name, "Config")
                    continue;
                end
                s.(name) = obj.(name);
            end
        end

        function token = TDDToken(obj, slotIdx)
            if upper(obj.DuplexMode) == "FDD"
                token = 'F';
                return;
            end
            tokens = char(obj.TDDPattern);
            if isempty(tokens)
                tokens = 'DDDSU';
            end
            idx = mod(max(0, round(double(slotIdx)) - 1), numel(tokens)) + 1;
            token = upper(tokens(idx));
        end

        function partition = SlotPartition(obj, slotIdx)
            token = obj.TDDToken(slotIdx);
            partition = struct( ...
                "DuplexMode", char(obj.DuplexMode), ...
                "CanonicalSlot", double(round(double(slotIdx))), ...
                "SlotToken", char(token), ...
                "SlotLabel", "", ...
                "SymbolsPerSlot", double(obj.SymbolsPerSlot), ...
                "AllowDL", false, ...
                "AllowUL", false, ...
                "IsSpecialSlot", false, ...
                "DLSymbolAllocation", zeros(1, 2), ...
                "GuardSymbolAllocation", zeros(1, 2), ...
                "ULSymbolAllocation", zeros(1, 2), ...
                "SpecialSlotDLSymbols", 0, ...
                "SpecialSlotGuardSymbols", 0, ...
                "SpecialSlotULSymbols", 0);
            if token == 'F'
                partition.SlotLabel = "FDD_DLUL";
                partition.AllowDL = true;
                partition.AllowUL = true;
                partition.DLSymbolAllocation = [0 double(obj.SymbolsPerSlot)];
                partition.ULSymbolAllocation = [0 double(obj.SymbolsPerSlot)];
            elseif token == 'D'
                partition.SlotLabel = "DL";
                partition.AllowDL = true;
                partition.DLSymbolAllocation = [0 double(obj.SymbolsPerSlot)];
            elseif token == 'U'
                partition.SlotLabel = "UL";
                partition.AllowUL = true;
                partition.ULSymbolAllocation = [0 double(obj.SymbolsPerSlot)];
            else
                partition.SlotLabel = "S";
                partition.IsSpecialSlot = true;
                partition.AllowDL = obj.SpecialSlotDLSymbols > 0;
                partition.AllowUL = obj.SpecialSlotULSymbols > 0;
                partition.DLSymbolAllocation = [0 double(obj.SpecialSlotDLSymbols)];
                partition.GuardSymbolAllocation = [double(obj.SpecialSlotDLSymbols) double(obj.SpecialSlotGuardSymbols)];
                partition.ULSymbolAllocation = [double(obj.SpecialSlotDLSymbols + obj.SpecialSlotGuardSymbols) double(obj.SpecialSlotULSymbols)];
                partition.SpecialSlotDLSymbols = double(obj.SpecialSlotDLSymbols);
                partition.SpecialSlotGuardSymbols = double(obj.SpecialSlotGuardSymbols);
                partition.SpecialSlotULSymbols = double(obj.SpecialSlotULSymbols);
            end
        end

        function tf = IsDLSlot(obj, slotIdx)
            p = obj.SlotPartition(slotIdx);
            tf = logical(p.AllowDL);
        end

        function tf = IsULSlot(obj, slotIdx)
            p = obj.SlotPartition(slotIdx);
            tf = logical(p.AllowUL);
        end

        function tf = IsSpecialSlot(obj, slotIdx)
            p = obj.SlotPartition(slotIdx);
            tf = logical(p.IsSpecialSlot);
        end

        function tf = IsDLAllocation(obj, slotIdx, symAlloc)
            p = obj.SlotPartition(slotIdx);
            tf = sixgr.phy.FrameStructureEngine.allocationWithin(symAlloc, p.DLSymbolAllocation);
        end

        function tf = IsULAllocation(obj, slotIdx, symAlloc)
            p = obj.SlotPartition(slotIdx);
            tf = sixgr.phy.FrameStructureEngine.allocationWithin(symAlloc, p.ULSymbolAllocation);
        end

        function tf = IsPRACHSlot(obj, slotIdx)
            tf = false;
            if ~(isfinite(double(slotIdx)) && double(slotIdx) >= 1)
                return;
            end
            slots = double(obj.PRACHValidSlots1Based(:));
            if isempty(slots)
                return;
            end
            canonical = mod(round(double(slotIdx)) - 1, max(1, round(double(obj.SlotsPerFrame)))) + 1;
            tf = any(slots == canonical);
        end
    end

    methods (Access = private)
        function value = firstValue(obj, paths, defaultValue)
            value = defaultValue;
            for i = 1:numel(paths)
                candidate = sixgr.util.structGet(obj.Config, paths(i), []);
                if obj.hasValue(candidate)
                    value = candidate;
                    return;
                end
            end
        end

        function value = firstNumeric(obj, paths, defaultValue)
            value = defaultValue;
            raw = obj.firstValue(paths, []);
            if isempty(raw)
                return;
            end
            try
                v = double(raw);
                v = v(isfinite(v));
                if ~isempty(v)
                    value = double(v(1));
                end
            catch
            end
        end

        function value = firstText(obj, paths, defaultValue)
            value = string(defaultValue);
            raw = obj.firstValue(paths, []);
            if isempty(raw)
                return;
            end
            try
                value = string(raw);
                if numel(value) > 1
                    value = value(1);
                end
            catch
                value = string(defaultValue);
            end
        end

        function SCSKHzSanity(obj)
            if ~(isscalar(obj.SCSkHz) && isfinite(obj.SCSkHz) && obj.SCSkHz > 0)
                error("sixgr:phy:FrameStructureEngine:BadSCS", ...
                    "Subcarrier spacing must be a positive finite scalar.");
            end
            mu = log2(obj.SCSkHz / 15);
            if abs(mu - round(mu)) > 1e-9
                error("sixgr:phy:FrameStructureEngine:BadSCS", ...
                    "Subcarrier spacing %.6g kHz is not an NR 15*2^mu numerology.", obj.SCSkHz);
            end
        end

        function obj = resolveSpecialSlot(obj)
            dl = obj.firstNumeric(["phy.duplex.specialSlot.numDLSymbols", ...
                "frame.special_slot_downlink_symbols", "frame_timing.special_slot_downlink_symbols"], NaN);
            guard = obj.firstNumeric(["phy.duplex.specialSlot.numGuardSymbols", ...
                "frame.ul_dl_guard_symbols", "frame_timing.ul_dl_guard_symbols"], NaN);
            ul = obj.firstNumeric(["phy.duplex.specialSlot.numULSymbols", ...
                "frame.special_slot_uplink_symbols", "frame_timing.special_slot_uplink_symbols"], NaN);
            if ~all(isfinite([dl guard ul]))
                if obj.SymbolsPerSlot == 14
                    dl = 12;
                    guard = 1;
                    ul = 1;
                else
                    dl = max(0, obj.SymbolsPerSlot - 2);
                    guard = 1;
                    ul = 1;
                end
            end
            counts = round(double([dl guard ul]));
            if any(counts < 0) || sum(counts) ~= obj.SymbolsPerSlot
                error("sixgr:phy:FrameStructureEngine:BadSpecialSlot", ...
                    "Special-slot DL/guard/UL symbols must be non-negative integers that sum to SymbolsPerSlot=%d.", ...
                    round(double(obj.SymbolsPerSlot)));
            end
            obj.SpecialSlotDLSymbols = counts(1);
            obj.SpecialSlotGuardSymbols = counts(2);
            obj.SpecialSlotULSymbols = counts(3);
        end

        function obj = resolveControlAndDataSymbols(obj)
            duration = obj.firstNumeric(["phy.pdcch.coreset.duration", ...
                "phy.pdcch.numSymbols", "control.coreset_duration", ...
                "ctrl6gr.CORESET.DurationSymbols"], 1);
            duration = max(1, min(3, round(double(duration))));
            if obj.SCSkHz >= 120
                duration = min(duration, 1);
            end
            obj.CORESETDuration = duration;
            freqResources = obj.firstValue(["phy.pdcch.coreset.frequencyResources", ...
                "control.coreset_frequency_resources"], []);
            rb = NaN;
            if isnumeric(freqResources) || islogical(freqResources)
                rb = 6 * sum(double(freqResources(:)) > 0);
            end
            if ~(isfinite(rb) && rb > 0)
                rb = min(obj.NRB, 48);
            end
            obj.CORESETBandwidth_RB = min(obj.NRB, max(1, round(double(rb))));
            obj.PDSCHStartSymbol = min(max(1, obj.CORESETDuration), max(0, obj.SymbolsPerSlot - 1));
            obj.PDSCHNumSymbols = max(1, obj.SymbolsPerSlot - obj.PDSCHStartSymbol);
        end

        function obj = resolveSSB(obj)
            [ssbCase, lmax, symbols] = sixgr.phy.FrameStructureEngine.resolveSSBCase( ...
                obj.CenterFrequencyHz, obj.SCSkHz);
            obj.SSBCase = ssbCase;
            obj.SSBLmax = lmax;
            obj.SSBCandidateSymbols = symbols(:).';
            slots = unique(floor(double(symbols(:)).' / obj.SymbolsPerSlot) + 1);
            slots = slots(slots >= 1 & slots <= obj.SlotsPerFrame);
            if isempty(slots)
                slots = 1:min(obj.SlotsPerFrame, max(1, obj.SSBLmax));
            end
            obj.SSBCandidateSlots1Based = slots;
        end

        function obj = resolvePRACH(obj)
            obj.PRACHConfigurationIndex = obj.firstNumeric(["phy.prach.configurationIndex", ...
                "prach_lls.PRACHConfigurationIndex", "random_access.configuration_index"], NaN);
            configuredFormat = string(obj.firstText(["phy.prach.preambleFormat", ...
                "prach_lls.PRACHFormat", "random_access.prach_format", "prach.format"], ""));
            info = sixgr.phy.FrameStructureEngine.resolvePRACHIndexInfo(obj.PRACHConfigurationIndex, obj.SCSkHz);
            obj.PRACHStartSymbol = info.StartSymbol;
            obj.PRACHDurationSymbols = info.DurationSymbols;
            candidateSlots = sixgr.phy.FrameStructureEngine.slotsForSubframe(info.Subframe, obj.SCSkHz, obj.SlotsPerFrame);
            [toolboxSlots, toolboxFormat, toolboxStart, toolboxDuration] = ...
                sixgr.phy.FrameStructureEngine.materializedPRACHSlots(obj, max(80, obj.SlotsPerFrame * 4));
            if strlength(toolboxFormat) > 0
                obj.PRACHFormat = toolboxFormat;
                if strlength(configuredFormat) > 0 && upper(strtrim(configuredFormat)) ~= upper(strtrim(toolboxFormat))
                    obj.ValidationLog(end+1, 1) = sprintf("Requested PRACH format %s differs from nrPRACHConfig format %s for configuration index %g.", ...
                        char(configuredFormat), char(toolboxFormat), double(obj.PRACHConfigurationIndex));
                end
            elseif strlength(configuredFormat) > 0
                obj.PRACHFormat = configuredFormat;
            else
                obj.PRACHFormat = info.Format;
            end
            if isfinite(toolboxStart)
                obj.PRACHStartSymbol = toolboxStart;
            end
            if isfinite(toolboxDuration)
                obj.PRACHDurationSymbols = toolboxDuration;
            end
            if ~isempty(toolboxSlots)
                candidateSlots = unique(mod(double(toolboxSlots(:).'), round(double(obj.SlotsPerFrame))) + 1, "stable");
            end
            if isempty(candidateSlots)
                candidateSlots = 1:obj.SlotsPerFrame;
            end
            valid = [];
            for slot = candidateSlots
                    p = obj.SlotPartition(slot);
                    if p.AllowUL && ~p.IsSpecialSlot
                        valid(end+1) = slot; %#ok<AGROW>
                    elseif p.IsSpecialSlot && p.AllowUL && isfinite(obj.PRACHStartSymbol) && isfinite(obj.PRACHDurationSymbols)
                        alloc = [double(obj.PRACHStartSymbol), max(1, double(obj.PRACHDurationSymbols))];
                    if sixgr.phy.FrameStructureEngine.allocationWithin(alloc, p.ULSymbolAllocation)
                        valid(end+1) = slot; %#ok<AGROW>
                    end
                end
            end
            valid = unique(valid);
            if isempty(valid)
                obj.PRACHValidationStatus = "no_ul_safe_prach_occasion_for_configured_index";
            else
                obj.PRACHValidationStatus = "ul_slot_validated";
            end
            obj.PRACHValidSlots1Based = double(valid(:).');
            obj.PRACHValidSlots0Based = double(valid(:).' - 1);
        end
    end

    methods (Static)
        function nrb = lookupNRB(bandwidthHz, scsKHz, frequencyRange)
            nrb = NaN;
            if ~(isfinite(double(bandwidthHz)) && bandwidthHz > 0 && isfinite(double(scsKHz)))
                return;
            end
            bwMHz = round(double(bandwidthHz) / 1e6);
            scs = round(double(scsKHz));
            fr = upper(string(frequencyRange));
            if fr == "FR2"
                table = [ ...
                    50 60 66; 100 60 132; 200 60 264; ...
                    50 120 32; 100 120 66; 200 120 132; 400 120 264; ...
                    100 240 32; 200 240 66; 400 240 132];
            else
                table = [ ...
                    5 15 25; 10 15 52; 15 15 79; 20 15 106; 25 15 133; 30 15 160; 40 15 216; 50 15 270; ...
                    5 30 11; 10 30 24; 15 30 38; 20 30 51; 25 30 65; 30 30 78; 40 30 106; 50 30 133; ...
                    60 30 162; 70 30 189; 80 30 217; 90 30 245; 100 30 273; ...
                    10 60 11; 15 60 18; 20 60 24; 25 60 31; 30 60 38; 40 60 51; 50 60 65; ...
                    60 60 79; 80 60 107; 90 60 121; 100 60 135];
            end
            idx = find(table(:,1) == bwMHz & table(:,2) == scs, 1);
            if ~isempty(idx)
                nrb = double(table(idx, 3));
            end
        end

        function nfft = defaultFFTSize(nrb)
            occupied = max(1, round(double(nrb)) * 12);
            nfft = 2^nextpow2(occupied);
            nfft = max(128, double(nfft));
        end

        function range = deriveFrequencyRange(fcHz)
            if ~(isfinite(double(fcHz)) && fcHz > 0)
                range = "FR1";
            elseif fcHz <= 7.125e9
                range = "FR1";
            elseif fcHz >= 24.25e9 && fcHz <= 52.6e9
                range = "FR2";
            else
                range = "FR3";
            end
        end

        function tokens = expandTDDPattern(pattern)
            if isstruct(pattern)
                dl = max(0, round(double(sixgr.util.structGet(pattern, "dlSlots", 4))));
                sp = max(0, round(double(sixgr.util.structGet(pattern, "specialSlots", 0))));
                ul = max(0, round(double(sixgr.util.structGet(pattern, "ulSlots", 1))));
                tokens = [repmat('D', 1, dl), repmat('S', 1, sp), repmat('U', 1, ul)];
            elseif isstring(pattern) || ischar(pattern)
                tokens = regexprep(upper(char(string(pattern))), "[^DUSF]", "");
                tokens = strrep(tokens, "F", "D");
            elseif isnumeric(pattern)
                p = double(pattern(:).');
                tokens = repmat('S', 1, numel(p));
                tokens(p > 0) = 'D';
                tokens(p < 0) = 'U';
            else
                tokens = '';
            end
            if isempty(tokens)
                tokens = 'DDDSU';
            end
        end

        function [ssbCase, lmax, symbols] = resolveSSBCase(fcHz, scsKHz)
            if isfinite(double(fcHz)) && fcHz > 24.25e9
                if round(double(scsKHz)) >= 240
                    ssbCase = "E";
                    symbols = [8 12 16 20 32 36 40 44];
                else
                    ssbCase = "D";
                    symbols = [4 8 16 20 32 36 44 48];
                end
                lmax = 64;
            elseif round(double(scsKHz)) >= 30
                ssbCase = "C";
                symbols = [2 8 16 22 30 36 44 50];
                lmax = 8;
            else
                ssbCase = "A";
                symbols = [2 8 16 22];
                lmax = 4;
            end
        end

        function info = resolvePRACHIndexInfo(index, scsKHz)
            info = struct("Format", "", "Subframe", NaN, "StartSymbol", NaN, "DurationSymbols", NaN);
            if ~(isfinite(double(index)) && index >= 0)
                info.Format = "A1";
                return;
            end
            idx = round(double(index));
            if round(double(scsKHz)) == 30
                switch idx
                    case 80
                        info = struct("Format", "A1", "Subframe", NaN, "StartSymbol", 0, "DurationSymbols", 2);
                    case {84, 86}
                        info = struct("Format", "A1", "Subframe", NaN, "StartSymbol", 0, "DurationSymbols", 2);
                    case {87, 88}
                        info = struct("Format", "A2", "Subframe", NaN, "StartSymbol", 0, "DurationSymbols", 4);
                    case 167
                        info = struct("Format", "B4", "Subframe", NaN, "StartSymbol", 0, "DurationSymbols", 12);
                    otherwise
                        info = struct("Format", "A1", "Subframe", NaN, "StartSymbol", 0, "DurationSymbols", 2);
                end
            else
                if idx <= 27
                    info = struct("Format", "0", "Subframe", NaN, "StartSymbol", 0, "DurationSymbols", 1);
                else
                    info = struct("Format", "A1", "Subframe", NaN, "StartSymbol", 0, "DurationSymbols", 6);
                end
            end
        end

        function slots = slotsForSubframe(subframe, scsKHz, slotsPerFrame)
            slots = [];
            if ~(isfinite(double(subframe)) && subframe >= 0 && subframe <= 9)
                return;
            end
            mu = round(log2(double(scsKHz) / 15));
            slotsPerSubframe = max(1, 2^double(mu));
            firstSlot0 = round(double(subframe)) * slotsPerSubframe;
            slots = firstSlot0 + (1:slotsPerSubframe);
            slots = slots(slots >= 1 & slots <= round(double(slotsPerFrame)));
        end

        function [slots0, prachFormat, symbolLocation, duration] = materializedPRACHSlots(obj, scanSlots)
            slots0 = [];
            prachFormat = "";
            symbolLocation = NaN;
            duration = NaN;
            if ~(exist("nrPRACHConfig", "class") == 8 || exist("nrPRACHConfig", "file") == 2) || ...
                    ~(isfinite(double(obj.PRACHConfigurationIndex)) && obj.PRACHConfigurationIndex >= 0)
                return;
            end
            try
                carrier = nrCarrierConfig;
                carrier.SubcarrierSpacing = double(obj.SCSkHz);
                carrier.NSizeGrid = double(obj.NRB);
                carrier.NStartGrid = 0;
                carrier.NCellID = 1;

                prach = nrPRACHConfig;
                if upper(obj.FrequencyRange) == "FR2"
                    prach.FrequencyRange = "FR2";
                else
                    prach.FrequencyRange = "FR1";
                end
                if upper(obj.DuplexMode) == "FDD"
                    prach.DuplexMode = "FDD";
                else
                    prach.DuplexMode = "TDD";
                end
                prach.ConfigurationIndex = double(obj.PRACHConfigurationIndex);
                prach.SubcarrierSpacing = double(obj.firstNumeric(["phy.prach.subcarrierSpacing_kHz", ...
                    "prach_lls.PRACHSubcarrierSpacing", "random_access.subcarrier_spacing_khz"], obj.SCSkHz));
                prach.SequenceIndex = double(max(0, round(obj.firstNumeric(["phy.prach.rootSeqIndex", ...
                    "prach_lls.SequenceIndex", "random_access.sequence_index", "random_access.root_sequence_index"], 0))));
                prach.PreambleIndex = double(max(0, round(obj.firstNumeric(["phy.prach.preambleIndex", ...
                    "prach_lls.PreambleIndex", "random_access.preamble_index"], 0))));
                prach.RestrictedSet = char(string(obj.firstText(["phy.prach.restrictedSet", ...
                    "prach_lls.RestrictedSet", "random_access.restricted_set"], "UnrestrictedSet")));
                prach.ZeroCorrelationZone = double(max(0, round(obj.firstNumeric(["phy.prach.zeroCorrelationZone", ...
                    "prach_lls.ZeroCorrelationZone", "random_access.zero_correlation_zone"], 0))));
                prach.FrequencyStart = double(max(0, round(obj.firstNumeric(["phy.prach.frequencyStart", ...
                    "prach_lls.FrequencyStart", "random_access.frequency_start"], 0))));
                prachFormat = upper(strtrim(string(prach.Format)));
                symbolLocation = double(prach.SymbolLocation);
                duration = double(prach.PRACHDuration);
                for slotCandidate = 0:max(0, round(double(scanSlots)) - 1)
                    carrier.NSlot = double(slotCandidate);
                    prach.NPRACHSlot = double(slotCandidate);
                    try
                        symbols = nrPRACH(carrier, prach);
                    catch
                        symbols = [];
                    end
                    if ~isempty(symbols)
                        slots0(end+1) = slotCandidate; %#ok<AGROW>
                    end
                end
            catch
                slots0 = [];
                prachFormat = "";
                symbolLocation = NaN;
                duration = NaN;
            end
        end
    end

    methods (Static, Access = private)
        function tf = hasValue(value)
            tf = false;
            if isempty(value)
                return;
            end
            if isstring(value)
                tf = any(strlength(value) > 0);
            elseif ischar(value)
                tf = ~isempty(strtrim(value));
            elseif isnumeric(value) || islogical(value)
                tf = ~isempty(value);
            elseif isstruct(value)
                tf = true;
            else
                tf = true;
            end
        end

        function tf = allocationWithin(symAlloc, ownerAlloc)
            tf = false;
            a = double(symAlloc(:).');
            b = double(ownerAlloc(:).');
            if numel(a) < 2 || numel(b) < 2
                return;
            end
            a0 = a(1);
            a1 = a(1) + max(0, a(2));
            b0 = b(1);
            b1 = b(1) + max(0, b(2));
            tf = isfinite(a0) && isfinite(a1) && isfinite(b0) && isfinite(b1) && ...
                a(2) > 0 && b(2) > 0 && a0 >= b0 && a1 <= b1;
        end
    end
end
