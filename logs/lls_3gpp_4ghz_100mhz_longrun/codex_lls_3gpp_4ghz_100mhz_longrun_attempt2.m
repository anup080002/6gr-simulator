cd('C:\Anup\6gsimulation\sixgr_foundation_v2 (2)');
addpath(pwd,'-begin');
rehash;
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_3gpp_4ghz_100mhz_longrun.yaml','results','codex_lls_3gpp_4ghz_100mhz_longrun_attempt2');
ok=isfield(out,'Ok') && logical(out.Ok);
fprintf('CodexLongRunResultOk=%d\n', double(ok));
if isfield(out,'Manifest')
    try
        fprintf('CodexLongRunResultOkManifest=%d\n', double(logical(out.Manifest.ResultOk)));
        fprintf('CodexLongRunRequiredFailureCount=%g\n', double(out.Manifest.RequiredFailureCount));
    catch
    end
end
assert(ok, 'Long-run scenario returned Ok=false; inspect truth-contract artifacts and logs.');
