classdef Type0TableCatalog
    %TYPE0TABLECATALOG Release-18 Type-0 CORESET/search-space constants.

    methods (Static)
        function row = coreset0(tableID, index, kSSB)
            tableID = upper(string(tableID));
            index = localInteger(index, 0, 15, "controlResourceSetZero");
            kSSB = localInteger(kSSB, 0, 31, "kSSB");
            [rows, patterns] = localCORESETRows(tableID);
            if index + 1 > size(rows, 1) || any(~isfinite(rows(index+1,:)))
                error("sixgr:phy:pdcch:type0_reserved_index", ...
                    "controlResourceSetZero=%d is reserved in Table %s.", ...
                    index, tableID);
            end
            values = rows(index+1,:);
            offset = localResolveOffset(values(3), kSSB);
            row = struct("Table", tableID, ...
                "ControlResourceSetZero", index, ...
                "MultiplexingPattern", patterns(index+1), ...
                "CORESETRBs", values(1), ...
                "CORESETSymbols", values(2), ...
                "OffsetRB", offset, ...
                "Status", "PASS");
        end

        function row = searchSpace0(index, varargin)
            p = inputParser;
            addParameter(p, "TableID", "13-11", @(x) ischar(x) || isstring(x));
            addParameter(p, "PDCCHSCSKHz", 30, @(x) isnumeric(x) && isscalar(x));
            parse(p, varargin{:});
            tableID = upper(string(p.Results.TableID));
            index = localInteger(index, 0, 15, "searchSpaceZero");
            switch tableID
                case "13-11"
                    o = [0 0 2 2 5 5 7 7 0 5 0 0 2 2 5 5];
                    sets = [1 2 1 2 1 2 1 2 1 1 1 1 1 1 1 1];
                    m = [1 .5 1 .5 1 .5 1 .5 2 2 1 1 1 1 1 1];
                    symbols = ["0";"0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0";"0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0";"0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0";"0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0";"0";"1";"2";"1";"2";"1";"2"];
                    x = NaN;
                case {"13-12","13-12A"}
                    if index >= 14
                        error("sixgr:phy:pdcch:type0_searchspace_reserved_index", ...
                            "searchSpaceZero=%d is reserved in Table %s.", index, tableID);
                    end
                    sets = [1 2 1 2 1 2 2 2 2 1 2 2 1 1 NaN NaN];
                    m = [1 .5 1 .5 1 .5 .5 .5 .5 1 .5 .5 2 2 NaN NaN];
                    symbols = ["0";"0_if_i_even|7_if_i_odd"; ...
                        "0";"0_if_i_even|7_if_i_odd"; ...
                        "0";"0_if_i_even|7_if_i_odd"; ...
                        "0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0";"0_if_i_even|7_if_i_odd"; ...
                        "0_if_i_even|NsymbCORESET_if_i_odd"; ...
                        "0";"0";"reserved";"reserved"];
                    if tableID == "13-12"
                        o = [0 0 2.5 2.5 5 5 0 2.5 5 7.5 7.5 7.5 0 5 NaN NaN];
                        x = NaN;
                    else
                        scs = double(p.Results.PDCCHSCSKHz);
                        if ~ismember(scs, [480 960])
                            error("sixgr:phy:pdcch:type0_context_not_supported", ...
                                "Table 13-12A requires PDCCH SCS 480 or 960 kHz.");
                        end
                        x = 600/scs;
                        oTail = 5 + x;
                        o = [0 0 x x 5 5 0 x 5 oTail oTail oTail 0 5 NaN NaN];
                    end
                otherwise
                    error("sixgr:phy:pdcch:type0_context_not_supported", ...
                        "Unsupported Type-0 monitoring table %s.", tableID);
            end
            row = struct("Table", tableID, "SearchSpaceZero", index, ...
                "X", x, "O", o(index+1), ...
                "SearchSpaceSetsPerSlot", sets(index+1), ...
                "M", m(index+1), "FirstSymbolRule", symbols(index+1), ...
                "Status", "PASS");
        end

        function row = pattern23Monitoring(tableID, searchSpaceZero, ssbIndex)
            tableID = upper(string(tableID));
            searchSpaceZero = localInteger(searchSpaceZero, 0, 15, ...
                "searchSpaceZero");
            ssbIndex = localInteger(ssbIndex, 0, intmax("int32"), "SSBIndex");
            if searchSpaceZero ~= 0
                error("sixgr:phy:pdcch:type0_pattern23_reserved_index", ...
                    "searchSpaceZero=%d is reserved in Table %s.", ...
                    searchSpaceZero, tableID);
            end
            switch tableID
                case "13-13"
                    symbols = [0 1 6 7];
                    firstSymbol = symbols(mod(ssbIndex,4)+1);
                    pattern = 2;
                    rule = "SFNc=SFNSSB_i|nc=nSSB_i";
                case "13-14"
                    mod8 = mod(ssbIndex,8);
                    symbols = [0 1 2 3 12 13 0 1];
                    firstSymbol = symbols(mod8+1);
                    pattern = 2;
                    rule = "SFNc=SFNSSB_i|nc=nSSB_i_or_nSSB_i-1";
                case "13-15"
                    symbols = [4 8 2 6];
                    firstSymbol = symbols(mod(ssbIndex,4)+1);
                    pattern = 3;
                    rule = "SFNc=SFNSSB_i|nc=nSSB_i";
                case "13-15A"
                    symbols = [2 9];
                    firstSymbol = symbols(mod(ssbIndex,2)+1);
                    pattern = 3;
                    rule = "SFNc=SFNSSB_i|nc=nSSB_i";
                otherwise
                    error("sixgr:phy:pdcch:type0_context_not_supported", ...
                        "Table %s is not a pattern-2/3 monitoring table.", tableID);
            end
            row = struct("Table", tableID, ...
                "SearchSpaceZero", searchSpaceZero, ...
                "MultiplexingPattern", pattern, ...
                "MonitoringOccasionRule", rule, ...
                "FirstSymbol", firstSymbol, "Status", "PASS");
        end

        function offset = gscnOffset(frequencyRange, kSSB, combinedIndex)
            frequencyRange = upper(string(frequencyRange));
            kSSB = localInteger(kSSB, 0, 31, "kSSB");
            combinedIndex = localInteger(combinedIndex, 0, 255, ...
                "16*controlResourceSetZero+searchSpaceZero");
            switch frequencyRange
                case "FR1"
                    if ismember(kSSB, 24:26)
                        offset = (kSSB-24)*256 + combinedIndex + 1;
                    elseif ismember(kSSB, 27:29)
                        offset = -((kSSB-27)*256 + combinedIndex + 1);
                    else
                        error("sixgr:phy:pdcch:no_type0_coreset_in_gscn_range", ...
                            "FR1 kSSB=%d has no associated Type-0 CORESET.", kSSB);
                    end
                case {"FR2","FR2-1","FR2-2","FR2-NTN"}
                    if kSSB == 12
                        offset = combinedIndex + 1;
                    elseif kSSB == 13
                        offset = -(combinedIndex + 1);
                    else
                        error("sixgr:phy:pdcch:no_type0_coreset_in_gscn_range", ...
                            "FR2 kSSB=%d has no associated Type-0 CORESET.", kSSB);
                    end
                otherwise
                    error("sixgr:phy:pdcch:type0_context_not_supported", ...
                        "Unsupported frequency range %s.", frequencyRange);
            end
        end
    end
end

function [rows, patterns] = localCORESETRows(tableID)
nanrow = [NaN NaN NaN];
switch tableID
    case "13-0"
        rows = [12 2 0;12 3 0;24 2 0;24 2 2;24 3 0;24 3 2; ...
            24 2 0;24 2 2;24 3 0;24 3 2;24 2 0;24 3 0];
        patterns = ones(1,12);
    case "13-1"
        rows = [24 2 0;24 2 2;24 2 4;24 3 0;24 3 2;24 3 4; ...
            48 1 12;48 1 16;48 2 12;48 2 16;48 3 12;48 3 16; ...
            96 1 38;96 2 38;96 3 38];
        patterns = ones(1,15);
    case "13-1A"
        rows = [96 1 10;96 1 12;96 1 14;96 1 16; ...
            96 2 10;96 2 12;96 2 14;96 2 16];
        patterns = ones(1,8);
    case "13-2"
        rows = [24 2 5;24 2 6;24 2 7;24 2 8;24 3 5;24 3 6; ...
            24 3 7;24 3 8;48 1 18;48 1 20;48 2 18;48 2 20; ...
            48 3 18;48 3 20];
        patterns = ones(1,14);
    case "13-3"
        rows = [48 1 2;48 1 6;48 2 2;48 2 6;48 3 2;48 3 6; ...
            96 1 28;96 2 28;96 3 28];
        patterns = ones(1,9);
    case "13-4"
        rows = [24 2 0;24 2 1;24 2 2;24 2 3;24 2 4;24 3 0; ...
            24 3 1;24 3 2;24 3 3;24 3 4;48 1 12;48 1 14; ...
            48 1 16;48 2 12;48 2 14;48 2 16];
        patterns = ones(1,16);
    case "13-4A"
        rows = [48 1 0;48 1 1;48 1 2;48 1 3; ...
            48 2 0;48 2 1;48 2 2;48 2 3];
        patterns = ones(1,8);
    case "13-5"
        rows = [48 1 4;48 2 4;48 3 4;96 1 0;96 1 56; ...
            96 2 0;96 2 56;96 3 0;96 3 56];
        patterns = ones(1,9);
    case "13-6"
        rows = [24 2 0;24 2 4;24 3 0;24 3 4;48 1 0; ...
            48 1 28;48 2 0;48 2 28;48 3 0;48 3 28];
        patterns = ones(1,10);
    case "13-7"
        rows = [48 1 0;48 1 8;48 2 0;48 2 8;48 3 0;48 3 8; ...
            96 1 28;96 2 28;48 1 -41042;48 1 49;96 1 -41042;96 1 97];
        patterns = [ones(1,8) 2 2 2 2];
    case "13-8"
        rows = [24 2 0;24 2 4;48 1 14;48 2 14; ...
            24 2 -20021;24 2 24;48 2 -20021;48 2 48];
        patterns = [ones(1,4) 3 3 3 3];
    case "13-9"
        rows = [96 1 0;96 1 16;96 2 0;96 2 16];
        patterns = ones(1,4);
    case "13-10"
        rows = [48 1 0;48 1 8;48 2 0;48 2 8; ...
            24 1 -41042;24 1 25;48 1 -41042;48 1 49];
        patterns = [ones(1,4) 2 2 2 2];
    case "13-10A"
        rows = [24 2 0;24 2 4;48 1 0;48 1 14;48 1 28;48 2 0; ...
            48 2 14;48 2 28;96 1 0;96 1 76;96 2 0;96 2 76; ...
            24 2 -20021;24 2 24;48 2 -20021;48 2 48];
        patterns = [ones(1,12) 3 3 3 3];
    otherwise
        rows = repmat(nanrow, 16, 1);
        patterns = nan(1,16);
end
end

function offset = localResolveOffset(encoded, kSSB)
if encoded == -41042
    if kSSB == 0
        offset = -41;
    else
        offset = -42;
    end
elseif encoded == -20021
    if kSSB == 0
        offset = -20;
    else
        offset = -21;
    end
else
    offset = encoded;
end
end

function value = localInteger(value, minimum, maximum, name)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= minimum && ...
        value <= maximum && value == fix(value))
    error("sixgr:phy:pdcch:type0_context_not_supported", ...
        "%s must be an integer in [%d,%d].", name, minimum, maximum);
end
end
