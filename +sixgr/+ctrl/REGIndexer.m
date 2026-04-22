function [regTable, reTable] = REGIndexer(ctrlCfg)
%REGIndexer Build explicit REG and RE maps for a 6GR CORESET.

coreset = ctrlCfg.CORESET;
rbList = double(coreset.RBList(:).');
symbols = coreset.StartSymbol + (0:coreset.DurationSymbols-1);
regSizeRE = double(coreset.REGSizeRE);

regRows = repmat(struct("REGIndex", NaN, "Symbol", NaN, "RBStart", NaN, ...
    "RBStop", NaN, "SubcarrierStart", NaN, "SubcarrierStop", NaN, ...
    "RECount", NaN, "BundleHint", NaN), 0, 1);
reRows = repmat(struct("REGIndex", NaN, "Symbol", NaN, "RB", NaN, ...
    "Subcarrier", NaN, "LinearRE", NaN), 0, 1);
regIdx = 0;

for sym = symbols
    subcarrierList = reshape(bsxfun(@plus, rbList(:) * 12, 0:11).', 1, []);
    numSeg = ceil(numel(subcarrierList) / regSizeRE);
    for seg = 1:numSeg
        segStart = (seg - 1) * regSizeRE + 1;
        segStop = min(seg * regSizeRE, numel(subcarrierList));
        scSeg = subcarrierList(segStart:segStop);
        rbSeg = floor(scSeg / 12);
        regIdx = regIdx + 1;
        regRows(end+1,1) = struct( ... %#ok<AGROW>
            "REGIndex", regIdx, ...
            "Symbol", sym, ...
            "RBStart", rbSeg(1), ...
            "RBStop", rbSeg(end), ...
            "SubcarrierStart", scSeg(1), ...
            "SubcarrierStop", scSeg(end), ...
            "RECount", numel(scSeg), ...
            "BundleHint", ceil(regIdx / coreset.REGBundleSize));
        for ii = 1:numel(scSeg)
            reRows(end+1,1) = struct( ... %#ok<AGROW>
                "REGIndex", regIdx, ...
                "Symbol", sym, ...
                "RB", floor(scSeg(ii) / 12), ...
                "Subcarrier", scSeg(ii), ...
                "LinearRE", (sym * ctrlCfg.NSizeGrid * 12) + scSeg(ii) + 1);
        end
    end
end

regTable = struct2table(regRows);
reTable = struct2table(reRows);
end
