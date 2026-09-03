function ok = testGenericCSIReportYAMLAuthority()
%TESTGENERICCSIREPORTYAMLAUTHORITY Bind ordinary CSI reports before runtime.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
scenarioPath = fullfile(pwd,"simulator","configs","scenarios", ...
    "dl_4ghz_baseline.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
s = scenario.toStruct();
if isfield(s.mimo,"phase07_strict")
    s.mimo = rmfield(s.mimo,"phase07_strict");
end
s.reference_signals.csi_reporting_enabled = true;
s.reference_signals.csi_rs_enabled = true;
s.reference_signals.csi_rs_ports = 1;
s.reference_signals.csi_rs_num_resources = 1;
s.pdsch.layer_count = 1;
s.pdsch.rank = 1;
s.mimo.n_layers = 1;
s.mimo.codebook_type = "type1";

cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
request = sixgr.util.structGet(cfg,"phy.csi.reportConfiguration",struct());
assert(isstruct(request) && ~isempty(fieldnames(request)), ...
    "Generic CSI reporting must resolve a typed report before runtime.");
assert(string(request.ReportConfigID) == "csi-report-default-0" && ...
    request.Ports == 1 && request.Rank == 1 && request.Epoch == 0, ...
    "Generic CSI report identity/port/rank authority is incorrect.");
schema = sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
assert(schema.part1BitCount() == 4 && schema.part2BitCount() == 0, ...
    "Single-port CSI must carry CQI only, without fabricated spatial PMI/LI bits.");

bad = s;
bad.csi_acquisition_and_reporting.report_configuration.report_config_id = "";
localAssertError(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    "sixgr:mimo:MissingCSIReportConfig");

ok = true;
end

function localAssertError(fn,identifier)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,identifier), ...
        "Expected %s, observed %s.",identifier,ME.identifier);
    return;
end
error("testGenericCSIReportYAMLAuthority:MissingError", ...
    "Expected typed failure %s.",identifier);
end
