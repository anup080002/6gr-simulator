function ok=testH4100CausalAuditAuthority()
% Exact H4 configuration and real builder-entry evidence, no waveform run.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()localCleanup(folder)); %#ok<NASGU>
identity=struct('RunId',"h4_audit_preflight",'ExecutionID',"preflight_only", ...
    'ConfigHash',string(source.ConfigHash));
sixgr.runtime.RuntimeCallLedger.configure(folder,identity);
cfg=sixgr.lls6g.buildInternalConfig(source,folder);
ledger=sixgr.runtime.RuntimeCallLedger.flush();
out=sixgr.truth.exportCausalPHYChainAudit(folder,source,cfg, ...
    'RunId',identity.RunId,'WriteArtifacts',false);
bindings=out.ParameterBindingTable;
bad=~(bindings.ConfiguredPresent & bindings.ResolvedPresent & bindings.ValueMatch);
assert(~any(bad),'sixgr:test:H4CausalParameterMapping', ...
    'H4 configuration-to-runtime audit mismatches: %s',strjoin(bindings.ParameterID(bad),', '));
assert(all(out.DetailTable.ConfigMappingMatch) && ...
    ~any(bindings.Status=="FEATURE_AUTHORITY_MISSING"));
% Every H4 binding without an explicit feature condition is applicable.
unconditional=strlength(string(bindings.FeatureAuthority))==0;
assert(all(bindings.RequiredForScenario(unconditional)) && ...
    ~any(bindings.Status(unconditional)=="DISABLED_BY_YAML"));
frame=out.DetailTable(out.DetailTable.StageID=="frame_grid_runtime",:);
assert(height(frame)==1 && frame.ConsumerObserved && frame.LedgerCallCount>=1 && ...
    frame.StageOutcome=="CALLED_NO_MEASUREMENT");
assert(any(ledger.FunctionName=="sixgr.phy.frame.FrameRuntimeStateBuilder.build") && ...
    any(endsWith(replace(ledger.SourceFile,'\','/'), ...
    '+sixgr/+phy/+frame/FrameRuntimeStateBuilder.m')));
access=ismember(out.DetailTable.StageID, ...
    ["ssb_waveform_tx","pss_sss_cell_search","pbch_mib_recovery","sib1_type0_pdcch_pdsch"]);
assert(nnz(access)==4 && ...
    all(out.DetailTable.MeasurementArtifact(access)=="air_interface/csv/pbch_trials.csv"));
assert(~out.Ok,'Configuration construction must never pass an unexecuted PHY scenario.');
fprintf('H4_CAUSAL_AUDIT_AUTHORITY_PASS bindings=%d frame_entry=%d waveform_executed=0\n', ...
    height(bindings),frame.LedgerCallCount);
ok=true;
end

function localCleanup(folder)
sixgr.runtime.RuntimeCallLedger.reset();
if isfolder(folder), rmdir(folder,'s'); end
end
