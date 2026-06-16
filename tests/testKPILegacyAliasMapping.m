function ok = testKPILegacyAliasMapping()
%TESTKPILEGACYALIASMAPPING Legacy aliases must come from canonical formulas.

setup6GRSimToolkit("Verbose", false);

raw = struct();
raw.UL = localDirectionTable("UL", 7.952);
raw.DL = localDirectionTable("DL", 40.137091);
out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw);

requiredAliases = ["Goodput_UL_max_Mbps","Goodput_DL_max_Mbps","BLER_UL_min","BLER_DL_min"];
assert(all(ismember(requiredAliases, string(out.LegacyAliasMap.LegacyAliasName))), ...
    "Every exported legacy KPI alias must have a mapping row.");
assert(all(logical(out.LegacyAliasMap.Equal)), ...
    "Legacy aliases must exactly equal their canonical reconstruction values.");

ok = true;
end

function T = localDirectionTable(direction, goodput)
T = table( ...
    repmat(string(direction), 2, 1), [goodput; 0], [true; false], [0; 1], [1000; 1000], ...
    [1000; 1000], [1000; 0], [1; 1], [1; 2], string([direction + "_tb_1"; direction + "_tb_2"]), ...
    [0; 0], [0; 0], [0; 1], [1; 1], [1; 2], ...
    'VariableNames', {'Direction','Goodput_Mbps','CRCPass','BitErrors','BitsCompared', ...
    'TBSize_bits','GoodBits','Frame','Slot','TransportBlockId','HARQProcessId','RV','NDI', ...
    'AirInterfaceObservation_ms','TrialId'});
end
