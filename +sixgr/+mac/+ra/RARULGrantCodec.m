classdef RARULGrantCodec
    % Licensed-spectrum RAR grant: TS 38.213 v18.8.0, 8.2/8.3.
    % FDRA is type-1 RIV, not a private PRB-start/length packing. The
    % TDRA resolves default-A from the received index and UL numerology.
    % This codec does not certify the caller's absolute Msg3 schedule or
    % duplex availability. A configured common TDRA list is not implemented.
    methods (Static)
        function grant = encode(raCfg, mcsIndex)
            if nargin < 2, mcsIndex = raCfg.Msg3PUSCH.MCS; end
            c = localContext(raCfg);
            s = raCfg.Msg3PUSCH;
            start = localInteger(s.PRBStart, 0, c.NSizeGrid-1, "PRBStart");
            count = localInteger(s.NumPRB, 1, c.NSizeGrid-start, "NumPRB");
            allocation = localTDRA(c, c.TDRAIndex);
            if s.SymbolStart ~= allocation.StartSymbol || s.NumSymbols ~= allocation.NumSymbols
                error("sixgr:mac:ra:RARTDRAAllocationMismatch", ...
                    "Configured Msg3 symbols must match the signalled default-A row %d: [%d %d].", ...
                    allocation.RowIndex, allocation.StartSymbol, allocation.NumSymbols);
            end
            if s.NLayers ~= 1 || s.RV ~= 0
                error("sixgr:mac:ra:UnsupportedRARTransmission", ...
                    "Initial Msg3 supports one layer and RV=0; these are not RAR bit fields.");
            end
            riv = localEncodeRIV(c.NSizeGrid, start, count);
            if riv >= 2^14
                error("sixgr:mac:ra:UnrepresentableRARFDRA", ...
                    "Type-1 RIV %d cannot be represented by this non-hopping 14-bit RAR grant.", riv);
            end
            mcsIndex = localInteger(mcsIndex, 0, 15, "MCS");
            tpc = localInteger(raCfg.RARGrantConfig.tpc_command, 0, 7, "TPCCommand");
            bits = [int8(0); localBits(riv,14); localBits(c.TDRAIndex,4); ...
                localBits(mcsIndex,4); localBits(tpc,3); int8(0)];
            grant = sixgr.mac.ra.RARULGrantCodec.decode(bits, raCfg);
        end

        function grant = decode(bits, raCfg)
            c = localContext(raCfg);
            if ~(isnumeric(bits) || islogical(bits)) || ~isreal(bits) || ...
                    numel(bits) ~= 27 || any(~isfinite(bits(:))) || ...
                    any(bits(:) ~= 0 & bits(:) ~= 1)
                error("sixgr:mac:ra:InvalidULGrantBits", "RAR UL grant must contain exactly 27 binary bits.");
            end
            bits = int8(bits(:));
            if bits(1)
                error("sixgr:mac:ra:UnsupportedRARHopping", ...
                    "RAR frequency hopping requires hop-offset resource materialization; it cannot be ignored.");
            end
            fdra = localValue(bits(2:15));
            % 38.213 8.3: for <=180 RB use only the RIV-width LSBs.
            riv = fdra;
            if c.NSizeGrid <= 180
                width = ceil(log2(c.NSizeGrid*(c.NSizeGrid+1)/2));
                riv = mod(fdra, 2^width);
            end
            [start, count] = localDecodeRIV(c.NSizeGrid, riv);
            tdra = localValue(bits(16:19));
            allocation = localTDRA(c, tdra);
            mcs = localValue(bits(20:23));
            profile = sixgr.phy.ul.pusch.PUSCHMCSResolver.resolve( ...
                c.MCSTable, mcs, c.TransformPrecoding);
            tpc = localValue(bits(24:26));
            grant = struct("FrequencyHoppingFlag", false, ...
                "FrequencyAssignment", fdra, "ResourceIndicationValue", riv, ...
                "PRBStart", start, "NumPRB", count, ...
                "TimeResourceAssignment", tdra, ...
                "SymbolStart", allocation.StartSymbol, "NumSymbols", allocation.NumSymbols, ...
                "MappingType", allocation.MappingType, "K2", allocation.K2, ...
                "Msg3AdditionalDelaySlots", allocation.Msg3AdditionalDelaySlots, ...
                "TimeDomainAllocation", allocation, ...
                "MCS", mcs, "MCSTable", string(profile.MCSTable), ...
                "Modulation", string(profile.Modulation), ...
                "TargetCodeRate", double(profile.TargetCodeRate), ...
                "TPCCommand", tpc, "TPCDelta_dB", 2*tpc-6, ...
                "CSIRequest", logical(bits(27)), ...
                "CSIRequestInterpretation", "reserved_not_an_instruction", ...
                "TransformPrecoding", c.TransformPrecoding, ...
                "TransformPrecodingSource", "configured_msg3_waveform_not_a_rar_bit", ...
                "EnablePTRS", c.EnablePTRS, "RV", 0, "NLayers", 1, ...
                "BitVector", bits, "ULGrantHex", sixgr.rrc.asn1.bitsToHex(bits), ...
                "GrantFormat", "ts38213_v18_8_0_table8_2_1_licensed_27bit", ...
                "MCSAuthority", "decoded_rar_index_and_configured_pusch_table", ...
                "Valid", true, "ValidationStatus", "decoded_fields_not_schedule_qualification");
        end
    end
end

function c = localContext(ra)
if ~isfield(ra, "RARGrantConfig") || ~isstruct(ra.RARGrantConfig)
    error("sixgr:mac:ra:MissingRARGrantConfig", "Explicit random_access.rar_grant configuration is required.");
end
g = ra.RARGrantConfig;
if string(g.field_layout) ~= "licensed_27bit"
    error("sixgr:mac:ra:UnsupportedRARLayout", "Only licensed_27bit RAR layout is implemented; shared-spectrum layout must not be relabelled.");
end
hop = localInteger(g.frequency_hopping, 0, 1, "frequency_hopping");
if hop ~= 0
    error("sixgr:mac:ra:UnsupportedRARHopping", "Configured RAR frequency hopping is not yet materialized.");
end
tdra = localInteger(g.time_resource_assignment, 0, 15, "time_resource_assignment");
% Initial non-repeated Msg3 does not inherit the dedicated data-PUSCH
% 256QAM/low-SE table selection (38.214 6.1.4.1).
mcsTable = lower(strrep(strtrim(string(ra.Msg3PUSCH.MCSTable)),"-",""));
if ~any(mcsTable == ["qam64","table1","64qam"])
    error("sixgr:mac:ra:InvalidRARMCSTable", ...
        "Initial Msg3 requires the applicable qam64 table, not a dedicated data-PUSCH table.");
end
c = struct("NSizeGrid", localInteger(ra.NSizeGrid, 1, 275, "NSizeGrid"), ...
    "TDRAIndex", tdra, "MCSTable", string(ra.Msg3PUSCH.MCSTable), ...
    "SubcarrierSpacingKHz", ra.CarrierSCSkHz, "CyclicPrefix", ra.CarrierCyclicPrefix, ...
    "TransformPrecoding", logical(ra.Msg3PUSCH.TransformPrecoding), ...
    "EnablePTRS", logical(ra.Msg3PUSCH.EnablePTRS));
end

function allocation = localTDRA(c, index)
allocation = sixgr.phy.frame.TimeDomainResourceAllocationCatalog.resolvePUSCHDefaultA( ...
    index, c.SubcarrierSpacingKHz, c.CyclicPrefix);
end

function value = localInteger(value, lo, hi, name)
if ~(isnumeric(value) || islogical(value)) || ~isreal(value) || ...
        ~isscalar(value) || ~isfinite(value) || value ~= fix(value) || value < lo || value > hi
    error("sixgr:mac:ra:InvalidRARULGrant", "%s must be an integer in [%d,%d].", name, lo, hi);
end
value = double(value);
end

function riv = localEncodeRIV(n, start, count)
if count-1 <= floor(n/2)
    riv = n*(count-1)+start;
else
    riv = n*(n-count+1)+(n-1-start);
end
end

function [start, count] = localDecodeRIV(n, riv)
q = floor(riv/n); r = mod(riv,n);
candidates = [r q+1; n-1-r n-q+1];
for k = 1:2
    start = candidates(k,1); count = candidates(k,2);
    if start >= 0 && count >= 1 && start+count <= n && ...
            localEncodeRIV(n,start,count) == riv
        return;
    end
end
error("sixgr:mac:ra:InvalidRARFDRA", "Decoded RIV %d is invalid for an initial UL BWP of %d RB.", riv, n);
end

function bits = localBits(value, width)
bits = int8(bitget(uint32(value), width:-1:1).');
end

function value = localValue(bits)
value = sum(double(bits(:).').*2.^((numel(bits)-1):-1:0));
end
