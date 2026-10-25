function ok=testCBPreambleOffsetPolicy()
% Configured policy and exact partition arithmetic, not physical detection.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
s=scenario.toStruct();
s.random_access.cb_preamble_selection_policy='fixed_partition_offset';
s.random_access.cb_preamble_offset=1;
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(string(cfg.random_access.cb_preamble_selection_policy)=="fixed_partition_offset" && ...
    cfg.random_access.cb_preamble_offset==1);
before=rng;
choice=sixgr.mac.ra.resolveCBPreambleOffset(cfg.random_access,1,16);
assert(choice.Offset0==1 && choice.ReceivedCBPreambleCount==16 && ...
    ~choice.NormativeUniformRandomSelection && choice.Classification=="optional_research_experiment");
assert(isequal((0:3)*16+choice.Offset0,[1 17 33 49]));
for ue=[1 2 16 17 100]
    legacy=struct('cb_preamble_selection_policy','deterministic_per_ue','cb_preamble_offset',0);
    p=sixgr.mac.ra.resolveCBPreambleOffset(legacy,ue,16);
    assert(p.Offset0==mod(ue-1,16));
end
compat=sixgr.mac.ra.resolveCBPreambleOffset(struct(),1,16);
assert(compat.Offset0==0 && compat.AuthoritySource=="global_yaml_defaults_for_legacy_direct_configuration");
for value={-1,16,1.5,NaN,Inf,'1',true,[1 2],complex(1,1)}
    bad=cfg.random_access; bad.cb_preamble_offset=value{1};
    reject(@()sixgr.mac.ra.resolveCBPreambleOffset(bad,1,16));
end
bad=cfg.random_access; bad.cb_preamble_selection_policy='deterministic_per_ue';
reject(@()sixgr.mac.ra.resolveCBPreambleOffset(bad,1,16));
for value={42,'uniform_random',string(missing)}
    bad=cfg.random_access; bad.cb_preamble_selection_policy=value{1};
    reject(@()sixgr.mac.ra.resolveCBPreambleOffset(bad,1,16));
end
bad=s; bad.random_access.cb_preamble_offset=16;
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname));
assert(isequal(before,rng),'Deterministic test choice must not consume or redraw RNG.');
fprintf('CB_PREAMBLE_OFFSET_POLICY_PASS configured_offset1=1 partitions_1_17_33_49=1 normative_random=0 physical_execution=0\n');
ok=true;
end
function reject(f)
try, f(); catch e
    assert(strcmp(e.identifier,'sixgr:mac:ra:InvalidCBPreamblePolicy'),e.message); return;
end
error('test:MissingRejection','Invalid CB preamble policy was accepted.');
end
