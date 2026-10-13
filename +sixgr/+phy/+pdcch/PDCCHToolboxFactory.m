classdef PDCCHToolboxFactory
    %PDCCHTOOLBOXFACTORY Materialize validated strict config for Toolbox.

    methods (Static)
        function carrier = atAbsoluteSlot(carrier,absoluteSlot)
            % Waveform clock, not merely an event label; zero-based API.
            validateattributes(absoluteSlot,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'});
            slotsPerFrame=double(carrier.SlotsPerFrame);
            carrier.NSlot=mod(double(absoluteSlot),slotsPerFrame);
            carrier.NFrame=mod(floor(double(absoluteSlot)/slotsPerFrame),1024);
        end

        function result = create(carrier, coresetDefinition, ...
                searchSpaceDefinition, aggregationLevel, rnti, nCellID, ...
                nStartBWP, nSizeBWP)
            if ~isa(coresetDefinition, "sixgr.phy.pdcch.CORESETDefinition") || ...
                    ~isa(searchSpaceDefinition, "sixgr.phy.pdcch.SearchSpaceDefinition")
                error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
                    "Validated CORESETDefinition and SearchSpaceDefinition are required.");
            end
            sixgr.phy.pdcch.PDCCHSpecificationProfile.encodedBits(aggregationLevel);
            coresetData = coresetDefinition.Data;
            searchData = searchSpaceDefinition.Data;
            if coresetData.RBStart + coresetData.NRB > nSizeBWP
                error("sixgr:phy:pdcch:CORESETOutsideBWP", ...
                    "CORESET interval [%g,%g) exceeds the %g-RB BWP.", ...
                    coresetData.RBStart,coresetData.RBStart+coresetData.NRB,nSizeBWP);
            end
            rbOffset = mod(coresetData.RBStart,6);
            if coresetData.CORESETID == 0 && rbOffset ~= 0
                error("sixgr:phy:pdcch:CORESETZeroOffsetUnsupported", ...
                    ["CORESET0 ignores rb-Offset-r16. Use its MIB-derived BWP " + ...
                     "anchor, or a nonzero dedicated CORESET ID; do not round RBStart."]);
            end

            coreset = nrCORESETConfig;
            coreset = localSet(coreset, ["CORESETID","ID"], coresetData.CORESETID, true);
            coreset.Duration = coresetData.DurationSymbols;
            frequencyResources = zeros(1, floor(coresetData.RBStart/6) + coresetData.NRB/6);
            firstGroup = floor(coresetData.RBStart/6) + 1;
            groupCount = coresetData.NRB/6;
            frequencyResources(firstGroup:firstGroup+groupCount-1) = 1;
            coreset.FrequencyResources = frequencyResources;
            % Preserve the explicit BWP-relative origin, including a
            % non-six-aligned start. The native empty value instead aligns
            % the bitmap to CRBs and cannot represent this configuration.
            defaultRBOffset = 6*ceil(double(nStartBWP)/6)-double(nStartBWP);
            if coresetData.CORESETID ~= 0 && rbOffset ~= defaultRBOffset
                coreset = localSet(coreset,"RBOffset",rbOffset,true);
            end
            if coresetData.MappingType == "interleaved"
                coreset.CCEREGMapping = "interleaved";
                coreset.REGBundleSize = coresetData.REGBundleSize;
                coreset.InterleaverSize = coresetData.InterleaverSize;
            else
                coreset.CCEREGMapping = "noninterleaved";
            end
            coreset.ShiftIndex = coresetData.ShiftIndex;
            coreset = localSet(coreset, "PrecoderGranularity", ...
                char(coresetData.PrecoderGranularity), false);

            searchSpace = nrSearchSpaceConfig;
            searchSpace = localSet(searchSpace, ["SearchSpaceID","ID"], ...
                searchData.SearchSpaceID, true);
            searchSpace.CORESETID = coresetData.CORESETID;
            searchSpace.SearchSpaceType = 'common';
            if searchData.SearchSpaceType == "USS"
                searchSpace.SearchSpaceType = 'ue';
            end
            searchSpace.StartSymbolWithinSlot = find( ...
                searchData.MonitoringSymbolsWithinSlot, 1, "first") - 1;
            searchSpace.SlotPeriodAndOffset = ...
                [searchData.PeriodSlots searchData.OffsetSlots];
            searchSpace.Duration = searchData.DurationSlots;
            searchSpace.NumCandidates = searchData.NumCandidates;

            pdcch = nrPDCCHConfig;
            pdcch = localSet(pdcch, ["NCellID","DMRSScramblingID"], nCellID, true);
            pdcch.RNTI = localToolboxRNTI(rnti);
            pdcch.CORESET = coreset;
            pdcch.SearchSpace = searchSpace;
            pdcch.AggregationLevel = aggregationLevel;
            pdcch = localSet(pdcch, "NStartBWP", nStartBWP, false);
            pdcch = localSet(pdcch, "NSizeBWP", nSizeBWP, false);

            result = struct("Carrier", carrier, "CORESET", coreset, ...
                "SearchSpace", searchSpace, "PDCCH", pdcch, ...
                "CORESETDigest", coresetDefinition.Digest, ...
                "SearchSpaceDigest", searchSpaceDefinition.Digest, ...
                "Status", "PASS");
        end
    end
end

function obj = localSet(obj, names, value, required)
names = string(names);
for ii = 1:numel(names)
    name = char(names(ii));
    if isprop(obj, name)
        obj.(name) = value;
        return;
    end
end
if required
    error("sixgr:phy:pdcch:toolbox_release_mismatch", ...
        "Installed Toolbox object %s lacks required property %s.", ...
        class(obj), strjoin(names, "|"));
end
end

function value = localToolboxRNTI(rnti)
value = double(rnti);
if value == 65535
    value = 0;
end
end
