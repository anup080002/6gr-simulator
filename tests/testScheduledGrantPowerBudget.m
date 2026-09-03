function ok = testScheduledGrantPowerBudget()
%TESTSCHEDULEDGRANTPOWERBUDGET Validate cell-vs-endpoint power authority.

setup6GRSimToolkit("Verbose", false);
cfg = struct();
cfg.powerAndRF.bsTxPower_dBm = 23;
cfg.powerAndRF.ueTxPower_dBm = 23;
cfg.phy.pdsch.powerAllocationPolicy = "equal";

grants = repmat(struct("Direction", "DL", "SignalType", "PDSCH", ...
    "ServingCell", 1, "Frame", 0, "Slot", 7, "NumLayers", 2), 2, 1);
grants(1).UEID = 1;
grants(2).UEID = 2;

contexts = cell(2, 1);
for i = 1:2
    [cfgI, grantI, evidence] = sixgr.rf.bindScheduledGrantPowerBudget( ...
        cfg, "DL", grants(i), grants);
    [~, contexts{i}] = sixgr.rf.applyPowerContext(ones(1024, 4), cfgI, "DL", struct());
    assert(evidence.ConcurrentTransmitterGrantCount == 2);
    assert(abs(evidence.GrantPowerFraction - 0.5) < 1e-12);
    assert(abs(evidence.GrantTargetTxPower_dBm - (23 - 10*log10(2))) < 1e-12);
    assert(logical(grantI.SharedCellBudgetApplied));
    assert(strcmp(string(contexts{i}.TotalTxPowerSource), ...
        "runtime_scheduled_power_context.grant_target_tx_power_dbm"));
    assert(logical(contexts{i}.SignalSpecificPowerControl));
    assert(string(contexts{i}.SignalSpecificPowerControlSource) == ...
        "scheduled_grant_power_budget");
end
summedGrantPower_mW = sum(cellfun(@(c) double(c.OutputTotalPower_mW), contexts));
assert(abs(10*log10(summedGrantPower_mW) - 23) < 1e-10, ...
    "Concurrent DL grant powers must close to the configured cell budget.");

ulGrants = grants;
for i = 1:2
    ulGrants(i).Direction = "UL";
    ulGrants(i).SignalType = "PUSCH";
end
for i = 1:2
    [cfgI, ~, evidence] = sixgr.rf.bindScheduledGrantPowerBudget( ...
        cfg, "UL", ulGrants(i), ulGrants);
    [~, ctx] = sixgr.rf.applyPowerContext(ones(1024, 2), cfgI, "UL", struct());
    assert(~logical(evidence.SharedCellBudgetApplied));
    assert(logical(ctx.SignalSpecificPowerControl));
    assert(abs(ctx.OutputTotalPower_dBm - 23) < 1e-10, ...
        "Independent UEs must retain their individual UL transmit budgets.");
end

cfgBad = cfg;
cfgBad.phy.pdsch.powerAllocationPolicy = "unreviewed_policy";
assertThrows(@() sixgr.rf.bindScheduledGrantPowerBudget( ...
    cfgBad, "DL", grants(1), grants), ...
    "sixgr:rf:UnsupportedDLScheduledPowerPolicy");

ok = true;
end

function assertThrows(fcn, expectedIdentifier)
didThrow = false;
try
    fcn();
catch ME
    didThrow = true;
    assert(strcmp(string(ME.identifier), string(expectedIdentifier)), ...
        "Unexpected error identifier: %s", ME.identifier);
end
assert(didThrow, "Expected error %s was not thrown.", expectedIdentifier);
end
