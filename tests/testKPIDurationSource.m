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

raw = struct();
raw.UL = localDirectionTable("UL", 1);
raw.DL = localDirectionTable("DL", 1);
raw.DL.AirInterfaceObservation_ms(:) = NaN;
raw.DL.AirInterfaceTTI_ms = 0.5;
out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, "StrictMode", true);
dlDuration = out.DurationSourceAudit(strcmp(string(out.DurationSourceAudit.Direction), "DL"), :);
assert(height(dlDuration) == 1 && logical(dlDuration.Pass(1)) && ...
        contains(string(dlDuration.DurationSource(1)), "air_interface_tti_ms_unique_slot"), ...
    "A blank AirInterfaceObservation_ms column must fall through to finite AirInterfaceTTI_ms.");

raw = struct();
raw.UL = [localDirectionTable("UL", 1); localDirectionTable("UL", 1)];
raw.DL = localDirectionTable("DL", 1);
out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, "StrictMode", true);
ulRecon = out.ReconstructionSummary(strcmp(string(out.ReconstructionSummary.KPIName), "UL_TB_Delivery_Goodput_Mbps"), :);
assert(height(ulRecon) == 1 && abs(double(ulRecon.AggregationDurationSec(1)) - 0.001) < 1e-12, ...
    "Multiple grants in one slot must use one radio-slot duration, not row-count duration.");
ulContribDuration = sum(double(out.RowContributionsUL.DurationContributionSec), "omitnan");
assert(abs(ulContribDuration - double(ulRecon.AggregationDurationSec(1))) < 1e-12, ...
    "Per-row KPI duration contributions must sum to the unique-slot radio duration.");

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
