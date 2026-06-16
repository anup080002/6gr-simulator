function auditT = validateMIMOConfigStrict(cfgOrTable)
%VALIDATEMIMOCONFIGSTRICT Fail-closed validation of nominal MIMO config.

if istable(cfgOrTable)
    cfgT = cfgOrTable;
else
    cfgT = sixgr.mimo.buildMIMOConfigFromScenario(cfgOrTable);
end
rows = repmat(localRow(), 0, 1);
for i = 1:height(cfgT)
    cfgRow = cfgT(i, :);
    dir = string(cfgRow.Direction);
    rows(end+1, 1) = localCheck(cfgRow, dir, "physical_antenna_counts_present", ...
        isfinite(double(cfgRow.PhysicalTxAntennaCount)) && isfinite(double(cfgRow.PhysicalRxAntennaCount)), ...
        "physical_tx_rx_antenna_counts_missing"); %#ok<AGROW>
    rows(end+1, 1) = localCheck(cfgRow, dir, "antenna_ports_present", ...
        isfinite(double(cfgRow.TxAntennaPortCount)) && isfinite(double(cfgRow.RxAntennaPortCount)), ...
        "tx_rx_antenna_ports_missing"); %#ok<AGROW>
    supportedRank = min([ ...
        double(cfgRow.PhysicalTxAntennaCount), double(cfgRow.PhysicalRxAntennaCount), ...
        double(cfgRow.TxRFChainCount), double(cfgRow.RxRFChainCount), ...
        double(cfgRow.TxAntennaPortCount), double(cfgRow.RxAntennaPortCount), ...
        double(cfgRow.DMRSPortCount)]);
    rows(end+1, 1) = localCheck(cfgRow, dir, "configured_rank_supported_by_ports", ...
        isfinite(supportedRank) && double(cfgRow.ConfiguredRank) <= supportedRank, ...
        "configured_rank_exceeds_tx_rx_dmrs_port_support"); %#ok<AGROW>
    rows(end+1, 1) = localCheck(cfgRow, dir, "configured_layers_supported_by_ports", ...
        isfinite(supportedRank) && double(cfgRow.ConfiguredLayers) <= supportedRank, ...
        "configured_layers_exceed_tx_rx_dmrs_port_support"); %#ok<AGROW>
    rows(end+1, 1) = localCheck(cfgRow, dir, "dmrs_ports_cover_layers", ...
        double(cfgRow.DMRSPortCount) >= double(cfgRow.ConfiguredLayers), ...
        "dmrs_port_count_less_than_configured_layers"); %#ok<AGROW>
    supportedCodebook = ~contains(lower(string(cfgRow.CodebookType) + "|" + string(cfgRow.CodebookMode)), ["typeii","multi-panel","multipanel"]);
    rows(end+1, 1) = localCheck(cfgRow, dir, "unsupported_codebook_modes_fail_closed", ...
        supportedCodebook, "unsupported_codebook_or_multipanel_mode"); %#ok<AGROW>
end
auditT = struct2table(rows);
end

function row = localCheck(cfgRow, direction, rule, pass, reason)
row = localRow();
row.RunId = string(cfgRow.RunId);
row.ScenarioName = string(cfgRow.ScenarioName);
row.Direction = string(direction);
row.ValidationRule = string(rule);
row.Pass = logical(pass);
row.Status = string(localTernary(pass, "pass", "fail"));
row.FailureReason = string(localTernary(pass, "", reason));
row.ConfigHash = string(cfgRow.ConfigHash);
end

function row = localRow()
row = struct("RunId","", "ScenarioName","", "Direction","", "ValidationRule","", ...
    "Pass",false, "Status","not_evaluated", "FailureReason","", "ConfigHash","");
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
