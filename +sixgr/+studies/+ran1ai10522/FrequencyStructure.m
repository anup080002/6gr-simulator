classdef FrequencyStructure
    %FREQUENCYSTRUCTURE Exact zero-based PRB bundle/region study mappings.

    methods (Static)
        function T = bundles(regions, bundleSizePrb)
            regions = double(regions); bundleSizePrb = double(bundleSizePrb);
            if size(regions, 2) ~= 2 || isempty(regions) || ...
                    any(~isfinite(regions), "all") || any(regions ~= fix(regions), "all") || ...
                    any(regions(:, 1) < 0) || any(regions(:, 2) < regions(:, 1))
                error("sixgr:ran1ai10522:InvalidRegions", ...
                    "Regions must be nonempty zero-based inclusive integer [start,end] rows.");
            end
            if ~(isscalar(bundleSizePrb) && isfinite(bundleSizePrb) && ...
                    bundleSizePrb >= 1 && bundleSizePrb == fix(bundleSizePrb))
                error("sixgr:ran1ai10522:InvalidBundleSize", ...
                    "Bundle size must be a positive integer number of PRBs.");
            end
            sorted = sortrows(regions, 1);
            if any(sorted(2:end, 1) <= sorted(1:end-1, 2))
                error("sixgr:ran1ai10522:OverlappingRegions", ...
                    "Processing regions must be nonoverlapping.");
            end
            rows = repmat(struct("RegionId", 0, "BundleId", 0, ...
                "StartPRB", 0, "EndPRB", 0, "NumPRB", 0, ...
                "ShortenedEdgeBundle", false, "CrossesRegion", false, ...
                "EvidenceClass", "ANALYTICAL_DERIVATION", "Status", "PASS"), 0, 1);
            globalId = 0;
            for regionId = 1:size(regions, 1)
                first = regions(regionId, 1); last = regions(regionId, 2);
                starts = first:bundleSizePrb:last;
                for localId = 1:numel(starts)
                    stop = min(starts(localId) + bundleSizePrb - 1, last);
                    rows(end + 1, 1) = struct( ... %#ok<AGROW>
                        "RegionId", regionId - 1, "BundleId", globalId, ...
                        "StartPRB", starts(localId), "EndPRB", stop, ...
                        "NumPRB", stop - starts(localId) + 1, ...
                        "ShortenedEdgeBundle", stop - starts(localId) + 1 < bundleSizePrb, ...
                        "CrossesRegion", false, "EvidenceClass", "ANALYTICAL_DERIVATION", ...
                        "Status", "PASS");
                    globalId = globalId + 1;
                end
            end
            T = struct2table(rows, "AsArray", true);
            for regionId = unique(T.RegionId).'
                if nnz(T.ShortenedEdgeBundle(T.RegionId == regionId)) > 1
                    error("sixgr:ran1ai10522:MultipleShortenedEdgeBundles", ...
                        "A region may have at most one shortened edge bundle.");
                end
            end
        end

        function T = rbgCompatibility(Pvalues, Nvalues, regionStarts)
            Pvalues = double(Pvalues(:)); Nvalues = double(Nvalues(:));
            regionStarts = double(regionStarts(:));
            rows = repmat(struct("RBGSizePRB",0,"BundleSizePRB",0, ...
                "RegionStartPRB",0,"SizeDivisible",false,"StartAligned",false, ...
                "Compatible",false,"EvidenceClass","ANALYTICAL_DERIVATION", ...
                "Status","PASS"),0,1);
            for P = Pvalues.'
                for N = Nvalues.'
                    for start = regionStarts.'
                        sizeOk = mod(P, N) == 0; startOk = mod(start, N) == 0;
                        rows(end + 1, 1) = struct("RBGSizePRB",P, ... %#ok<AGROW>
                            "BundleSizePRB",N,"RegionStartPRB",start, ...
                            "SizeDivisible",sizeOk,"StartAligned",startOk, ...
                            "Compatible",sizeOk && startOk, ...
                            "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS");
                    end
                end
            end
            T = struct2table(rows, "AsArray", true);
        end

        function T = interleave(bundleTable, mode, capability)
            mode = lower(string(mode)); capability = logical(capability);
            if ~any(mode == ["none","bundle_local_region","bundle_cross_region"])
                error("sixgr:ran1ai10522:InvalidInterleaverMode", ...
                    "Interleaver mode is unsupported.");
            end
            if mode == "bundle_cross_region" && ~capability
                error("sixgr:ran1ai10522:CrossRegionCapabilityRequired", ...
                    "Cross-region bundle mapping requires explicit receiver capability.");
            end
            required = ["RegionId","BundleId","StartPRB","EndPRB"];
            if ~all(ismember(required, string(bundleTable.Properties.VariableNames)))
                error("sixgr:ran1ai10522:BadBundleTable", ...
                    "Bundle table lacks required mapping fields.");
            end
            order = (1:height(bundleTable)).';
            switch mode
                case "bundle_local_region"
                    for region = unique(bundleTable.RegionId).'
                        idx = find(bundleTable.RegionId == region);
                        order(idx) = flipud(idx);
                    end
                case "bundle_cross_region"
                    order = flipud(order);
            end
            T = table(bundleTable.BundleId, bundleTable.RegionId, order - 1, ...
                bundleTable.BundleId(order), bundleTable.RegionId(order), ...
                repmat(mode,height(bundleTable),1), ...
                repmat("ANALYTICAL_DERIVATION",height(bundleTable),1), ...
                repmat("PASS",height(bundleTable),1), ...
                'VariableNames',{'InputBundleId','InputRegionId','OutputPosition', ...
                'OutputBundleId','OutputRegionId','Mode','EvidenceClass','Status'});
        end

        function index = sequenceIndex(mode, bundleId, regionId)
            mode = lower(string(mode)); bundleId = double(bundleId(:)); regionId = double(regionId(:));
            if numel(bundleId) ~= numel(regionId)
                error("sixgr:ran1ai10522:SequenceShapeMismatch", ...
                    "Bundle and region vectors must have equal length.");
            end
            switch mode
                case "common_grid"
                    index = (0:numel(bundleId)-1).';
                case "reset_per_bundle"
                    index = localResetIndex(bundleId);
                case "reset_per_region"
                    index = localResetIndex(regionId);
                otherwise
                    error("sixgr:ran1ai10522:InvalidSequenceIndexing", ...
                        "Sequence indexing mode is unsupported.");
            end
        end

        function phaseRad = residualPhase(deltaFHz, symbolTimeS, delayS, regionIndex)
            values = double([deltaFHz symbolTimeS delayS regionIndex]);
            if any(~isfinite(values))
                error("sixgr:ran1ai10522:InvalidPhaseModel", ...
                    "Residual phase model inputs must be finite.");
            end
            phaseRad = 2*pi*(deltaFHz*symbolTimeS - deltaFHz*delayS*regionIndex);
        end
    end
end

function index = localResetIndex(labels)
index = zeros(numel(labels),1);
seen = containers.Map('KeyType','char','ValueType','double');
for k = 1:numel(labels)
    key = sprintf('%.17g',labels(k));
    if ~isKey(seen,key), seen(key)=0; end
    index(k)=seen(key); seen(key)=seen(key)+1;
end
end
