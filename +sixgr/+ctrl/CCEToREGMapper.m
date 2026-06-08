function cceMap = CCEToREGMapper(ctrlCfg, regTable, bundleTable)
%CCEToREGMapper Build the reproducible CCE-to-REG mapping for the study.

if nargin < 3
    bundleTable = sixgr.ctrl.REGBundleMapper(regTable, ctrlCfg.CORESET);
end
coreset = ctrlCfg.CORESET;
regsPerCCE = max(1, round(double(coreset.NumREGPerCCE)));
if isempty(bundleTable)
    cceMap = table();
    return;
end

bundleIDs = double(bundleTable.BundleID(:).');
bundleOrder = bundleIDs;
if strcmpi(coreset.MappingType, "interleaved") || logical(coreset.InterleavingEnabled)
    interleaverSize = max(1, round(double(coreset.InterleaverSize)));
    if ~ismember(interleaverSize, [2 3 6])
        error("sixgr:ctrl:CCEToREGMapper:BadInterleaverSize", ...
            "InterleaverSize=%d is invalid; NR PDCCH interleaving uses {2,3,6}.", interleaverSize);
    end
    nBundles = numel(bundleIDs);
    if mod(nBundles, interleaverSize) ~= 0
        error("sixgr:ctrl:CCEToREGMapper:InterleaverSizeMismatch", ...
            "N_REG_Bundles=%d is not divisible by InterleaverSize=%d.", nBundles, interleaverSize);
    end
    shift = mod(round(double(coreset.ShiftIndex)), max(nBundles, 1));
    rowsInInterleaver = nBundles / interleaverSize;
    perm = zeros(1, nBundles);
    idx = 1;
    for c = 0:(interleaverSize - 1)
        for r = 0:(rowsInInterleaver - 1)
            perm(idx) = mod(r * interleaverSize + c + shift, nBundles) + 1;
            idx = idx + 1;
        end
    end
    bundleOrder = bundleIDs(perm);
end

orderedREG = [];
for i = 1:numel(bundleOrder)
    row = bundleTable(bundleTable.BundleID == bundleOrder(i), :);
    orderedREG = [orderedREG row.StartREG:row.EndREG]; %#ok<AGROW>
end

numCCE = floor(numel(orderedREG) / regsPerCCE);
rows = repmat(struct("CCEIndex", NaN, "REGIndices", "", "MappingType", "", "BundleOrder", ""), 0, 1);
for c = 1:numCCE
    idxStart = (c - 1) * regsPerCCE + 1;
    idxStop = c * regsPerCCE;
    regs = orderedREG(idxStart:idxStop);
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "CCEIndex", c - 1, ...
        "REGIndices", join(string(regs(:).'), " "), ...
        "MappingType", string(coreset.MappingType), ...
        "BundleOrder", join(string(bundleOrder), " "));
end
if isempty(rows)
    cceMap = table();
else
    cceMap = struct2table(rows);
end
end
