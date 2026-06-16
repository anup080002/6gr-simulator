function ok = testKPIUnitConversion()
%TESTKPIUNITCONVERSION Bits/sec to Mbps conversion must be exact.

setup6GRSimToolkit("Verbose", false);

raw = struct();
raw.UL = localDirectionTable("UL", 1);
raw.DL = localDirectionTable("DL", 1);

out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, "StrictMode", true);
ulSched = out.ReconstructionSummary(strcmp(string(out.ReconstructionSummary.KPIName), ...
    "UL_PHY_ScheduledThroughput_Mbps"), :);
assert(abs(double(ulSched.ReconstructionValue(1)) - 1) < 1e-12, ...
    "1000 bits over 1 ms must equal 1 Mbps.");
assert(all(logical(out.UnitConversionAudit.Pass)), ...
    "All throughput/goodput unit-conversion audit rows must pass.");

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
