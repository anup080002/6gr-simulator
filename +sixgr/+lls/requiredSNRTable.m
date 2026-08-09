function tableOut = requiredSNRTable(cfg, summaryTable)
%REQUIREDSNRTABLE Interpolate target BLER only inside simulated crossings.

targets = double(sixgr.util.structGet(cfg, "comparison.targetBLER", [0.1 0.01 0.001]));
rows = repmat(struct("TargetBLER",0,"RequiredSNRdB",NaN,"Valid",false,"Status",""), numel(targets), 1);
for idx = 1:numel(targets)
    value = sixgr.lls.stats.interpolateRequiredSNR( ...
        summaryTable.SNRdB, summaryTable.BLER, targets(idx));
    rows(idx) = struct("TargetBLER",targets(idx), ...
        "RequiredSNRdB",value.RequiredSNR_dB, ...
        "Valid",logical(value.Valid), ...
        "Status",string(value.Status));
end
tableOut = struct2table(rows);
end
