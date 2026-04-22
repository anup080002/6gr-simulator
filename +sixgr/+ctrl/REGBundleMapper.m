function bundleTable = REGBundleMapper(regTable, coresetCfg)
%REGBundleMapper Group REGs into explicit REG bundles.

if ~(istable(regTable) && ~isempty(regTable))
    bundleTable = table();
    return;
end

bundleSize = max(1, round(double(coresetCfg.REGBundleSize)));
regIdx = double(regTable.REGIndex);
bundleId = ceil(regIdx / bundleSize);
u = unique(bundleId(:));
rows = repmat(struct("BundleID", NaN, "StartREG", NaN, "EndREG", NaN, "NumREG", NaN), 0, 1);
for i = 1:numel(u)
    mask = bundleId == u(i);
    regs = regIdx(mask);
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "BundleID", u(i), ...
        "StartREG", min(regs), ...
        "EndREG", max(regs), ...
        "NumREG", numel(regs));
end
bundleTable = struct2table(rows);
end
