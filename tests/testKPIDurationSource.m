function ok = testKPIDurationSource()
%TESTKPIDURATIONSOURCE Radio duration is mandatory and cannot be wall-clock.

setup6GRSimToolkit("Verbose", false);

raw = struct();
raw.UL = localDirectionTable("UL", 1);
raw.DL = localDirectionTable("DL", 1);
raw.UL.AirInterfaceObservation_ms = [];

out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, "StrictMode", true);
ulDuration = out.DurationSourceAudit(strcmp(string(out.DurationSourceAudit.Direction), "UL"), :);
assert(height(ulDuration) == 1 && ~logical(ulDuration.Pass(1)), ...
    "Missing radio duration must fail the duration-source audit.");
assert(~logical(out.SummaryAliases.KPIReconciliationPass(1)), ...
    "A strict KPI summary cannot pass without a radio-duration denominator.");

raw = struct();
raw.UL = localDirectionTable("UL", 1);
raw.DL = localDirectionTable("DL", 1);
out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, "StrictMode", true);
assert(all(logical(out.DurationSourceAudit.Pass)), ...
    "Raw radio observation duration must pass duration-source audit.");
assert(~any(logical(out.DurationSourceAudit.WallClockUsedForRadioThroughput)), ...
    "Wall-clock duration must not be used as the radio throughput denominator.");

ok = true;
end

function T = localDirectionTable(direction, goodput)
T = table( ...
    repmat(string(direction), 1, 1), goodput, true, 0, 1000, ...
    1000, 1000, 1, 1, string(direction + "_tb_1"), 0, 0, 0, 1, 1, ...
    'VariableNames', {'Direction','Goodput_Mbps','CRCPass','BitErrors','BitsCompared', ...
    'TBSize_bits','GoodBits','Frame','Slot','TransportBlockId','HARQProcessId','RV','NDI', ...
    'AirInterfaceObservation_ms','TrialId'});
end
