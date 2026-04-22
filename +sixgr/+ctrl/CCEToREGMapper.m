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
    shift = max(0, round(double(coreset.ShiftIndex)));
    perm = mod((0:numel(bundleIDs)-1) * interleaverSize + shift, numel(bundleIDs)) + 1;
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
