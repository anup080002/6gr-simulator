function ok = testKPIRawTableSchemaValidation()
%TESTKPIRAWTABLESCHEMAVALIDATION Raw KPI tables must be direction/schema valid.

setup6GRSimToolkit("Verbose", false);

raw = localRawFixture();
audit = sixgr.kpi.validateRawKPITables(raw);
assert(all(strcmp(string(audit.Status), "pass")), ...
    "Valid UL/DL raw KPI fixtures must pass the schema audit.");

bad = raw;
bad.UL.Direction(1) = "DL";
badAudit = sixgr.kpi.validateRawKPITables(bad);
ulDirection = badAudit(strcmp(string(badAudit.Direction), "UL") & ...
    strcmp(string(badAudit.RequiredColumn), "Direction"), :);
assert(height(ulDirection) == 1 && strcmp(string(ulDirection.Status(1)), "invalid"), ...
    "Wrong-direction rows must fail the raw KPI schema audit.");

missing = raw;
missing.UL.Direction = [];
missingAudit = sixgr.kpi.validateRawKPITables(missing);
missingDirection = missingAudit(strcmp(string(missingAudit.Direction), "UL") & ...
    strcmp(string(missingAudit.RequiredColumn), "Direction"), :);
assert(height(missingDirection) == 1 && strcmp(string(missingDirection.Status(1)), "missing_required_column"), ...
    "Missing Direction must fail the raw KPI schema audit.");

proxyOnly = raw;
proxyOnly.UL.ProxyUsed = true(height(proxyOnly.UL), 1);
out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(proxyOnly, "StrictMode", true);
assert(~logical(out.SummaryAliases.KPIReconciliationPass(1)), ...
    "Proxy-only UL rows must not pass strict KPI reconstruction.");

ok = true;
end

function raw = localRawFixture()
raw = struct();
raw.UL = localDirectionTable("UL", 7.952);
raw.DL = localDirectionTable("DL", 40.137091);
end

function T = localDirectionTable(direction, goodput)
T = table( ...
    repmat(string(direction), 2, 1), [goodput; 0], [true; false], [0; 1], [1000; 1000], ...
    [1000; 1000], [1000; 0], [1; 1], [1; 2], string([direction + "_tb_1"; direction + "_tb_2"]), ...
    [0; 0], [0; 0], [0; 0], [1; 1], [1; 2], ...
    'VariableNames', {'Direction','Goodput_Mbps','CRCPass','BitErrors','BitsCompared', ...
    'TBSize_bits','GoodBits','Frame','Slot','TransportBlockId','HARQProcessId','RV','NDI', ...
    'AirInterfaceObservation_ms','TrialId'});
end
