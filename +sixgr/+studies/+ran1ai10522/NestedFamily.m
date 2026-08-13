classdef NestedFamily
    %NESTEDFAMILY Deterministic retain-and-add nested DM-RS start sets.

    methods (Static)
        function family = build(nSym, X, l0, Lmax)
            nSym = double(nSym); X = double(X); l0 = double(l0); Lmax = double(Lmax);
            if ~ismember(X, [1 2 4]) || ~ismember(Lmax, ...
                    sixgr.studies.ran1ai10522.TimeDomainProfile.supportedL(X))
                error("sixgr:ran1ai10522:InvalidNestedFamily", ...
                    "Nested family requires a supported X/Lmax tuple.");
            end
            if l0 + Lmax * X > nSym
                error("sixgr:ran1ai10522:NestedFamilyDoesNotFit", ...
                    "Maximum nested family member does not fit the allocation.");
            end
            lmax = nSym - X;
            family = cell(Lmax, 1);
            family{1} = l0;
            if Lmax == 1, return; end
            family{2} = unique([l0 lmax], "stable");
            for L = 3:Lmax
                current = family{L - 1};
                gaps = diff(current);
                maxGap = max(gaps);
                interval = find(gaps == maxGap, 1, "last");
                candidate = floor((current(interval) + current(interval + 1)) / 2);
                if candidate - current(interval) < X || current(interval + 1) - candidate < X
                    error("sixgr:ran1ai10522:NestedInsertionDoesNotFit", ...
                        "No no-shift midpoint insertion fits L=%d.", L);
                end
                family{L} = sort([current candidate]);
            end
            sixgr.studies.ran1ai10522.NestedFamily.assertNested(family);
        end

        function truncated = truncate(family, allocationStart, allocationEnd)
            allocationStart = double(allocationStart); allocationEnd = double(allocationEnd);
            if allocationStart > allocationEnd
                error("sixgr:ran1ai10522:InvalidAllocationWindow", ...
                    "Allocation start must not exceed allocation end.");
            end
            truncated = cellfun(@(x)x(x >= allocationStart & x <= allocationEnd), ...
                family, "UniformOutput", false);
            sixgr.studies.ran1ai10522.NestedFamily.assertNested(truncated);
        end

        function potential = potentialSet(family, ownL)
            if ~(isscalar(ownL) && ownL == fix(ownL) && ownL >= 1 && ownL <= numel(family))
                error("sixgr:ran1ai10522:InvalidOwnL", "ownL is outside the nested family.");
            end
            potential = setdiff(family{end}, family{ownL}, "stable");
        end

        function assertNested(family)
            for k = 1:numel(family) - 1
                if ~all(ismember(family{k}, family{k + 1}))
                    error("sixgr:ran1ai10522:NonNestedFamily", ...
                        "Nested family member L=%d is not a subset of L=%d.", k, k + 1);
                end
            end
        end
    end
end
