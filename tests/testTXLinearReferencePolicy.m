function ok=testTXLinearReferencePolicy()
% YAML/config-only opt-in policy. No RF, channel, waveform or power-accuracy
% execution is performed; enabled does not establish original-owner proof.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
repo=fileparts(fileparts(mfilename('fullpath')));
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> % This unique test directory only.
fixture=fullfile(repo,'simulator','configs','scenarios', ...
    'lls_tdd_four_port_received_rank_transition_fixture.yaml');
base=sixgr.lls6g.config.loadScenarioConfig(fixture);
original=base.Data;
groups={@()localCatalog(repo),@()localPropagation(base,work), ...
    @()localMissing(base,work),@()localInvalid(base), ...
    @()localInheritance(fixture,work),@()localExistingN40(repo,work)};
names=["catalog_defaults","enabled_disabled_propagation","missing_optional_block", ...
    "invalid_and_unknown_declarations","yaml_inheritance","existing_n40_stays_disabled"];
failures=strings(0,1);
for k=1:numel(groups)
    try
        groups{k}();
        fprintf('TX_LINEAR_REFERENCE_POLICY %s PASS\n',names(k));
    catch cause
        failures(end+1)=names(k)+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'TX_LINEAR_REFERENCE_POLICY %s FAIL %s\n',names(k), ...
            getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(isequaln(base.Data,original),'The original resolved scenario must remain unchanged.');
assert(isempty(failures),'test:TXLinearReferencePolicy', ...
    '%d/%d config-only groups failed:\n%s',numel(failures),numel(groups),strjoin(failures,newline));
fprintf('TX_LINEAR_REFERENCE_POLICY_PASS groups=%d RF_executions=0 channel_executions=0 accuracy_qualified=0\n',numel(groups));
ok=true;
end

function localCatalog(repo)
catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
rule=catalog.sections.power_and_rf_frontend.parameters.tx_linear_reference;
defaults=sixgr.lls6g.config.readConfigFile(fullfile(repo,'simulator','configs', ...
    'defaults','top_level_required_sections_01.yaml'));
expected=localDefault();
assert(isequaln(rule.default,expected)&& ...
    isequaln(defaults.power_and_rf_frontend.tx_linear_reference,expected));
assert(~rule.required&&string(rule.type)=="struct"&& ...
    string(rule.nested_rule)=="tx_linear_reference_policy"&& ...
    string(rule.requirement_class)=="IMPLEMENTATION_POLICY");
schema=sixgr.lls6g.config.schema('scenario');
assert(any(schema.AllowedBySection.power_and_rf_frontend=="tx_linear_reference")&& ...
    ~any(schema.RequiredBySection.power_and_rf_frontend=="tx_linear_reference"));
names=["enabled";"model";"classification"];
assert(isequal(sort(schema.NestedAllowed.tx_linear_reference_policy),sort(names)));
rules=catalog.nested_sections.tx_linear_reference_policy.parameters;
for k=1:numel(names), assert(rules.(names(k)).required); end
assert(string(rules.enabled.type)=="boolean"&& ...
    isequal(string(rules.model.allowed_values(:)),string(expected.model))&& ...
    isequal(string(rules.classification.allowed_values(:)),string(expected.classification)));
end

function localPropagation(base,work)
s=base.Data;
assert(isequaln(s.power_and_rf_frontend.tx_linear_reference,localDefault()));
off=sixgr.lls6g.buildInternalConfig(base,fullfile(work,'off'));
localAssertRuntime(off,false);
s.power_and_rf_frontend.tx_linear_reference.enabled=true;
sixgr.lls6g.config.validateScenarioConfig(s);
on=sixgr.lls6g.buildInternalConfig(s,fullfile(work,'on'));
localAssertRuntime(on,true);
% The new policy must not change physical RF configuration, amplitude
% scaling, radiation/spatial instrumentation or another measurement gate.
assert(isequaln(rmfield(off.rf,'txLinearReference'),rmfield(on.rf,'txLinearReference')));
assert(isequaln(off.measurements,on.measurements));
s.power_and_rf_frontend.tx_linear_reference.enabled=false;
sixgr.lls6g.config.validateScenarioConfig(s);
again=sixgr.lls6g.buildInternalConfig(s,fullfile(work,'disabled'));
localAssertRuntime(again,false);
assert(isequaln(again.rf,off.rf));
end

function localMissing(base,work)
s=base.Data;
s.power_and_rf_frontend=rmfield(s.power_and_rf_frontend,'tx_linear_reference');
sixgr.lls6g.config.validateScenarioConfig(s);
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(work,'legacy_without_optional_block'));
localAssertRuntime(cfg,false);
for name=["enabled","model","classification"]
    bad=base.Data;
    bad.power_and_rf_frontend.tx_linear_reference=rmfield(localDefault(),name);
    localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad));
end
% A partial inherited YAML can author one field, but a directly built
% resolved struct cannot silently fill missing fields inside an existing block.
partial=struct('power_and_rf_frontend',struct('tx_linear_reference',struct('enabled',true)));
sixgr.lls6g.config.validateScenarioConfig(partial,'AllowPartial',true);
bad=base.Data; bad.power_and_rf_frontend.tx_linear_reference=struct('enabled',true);
localReject(@()sixgr.lls6g.buildInternalConfig(bad,fullfile(work,'incomplete')));
end

function localInvalid(base)
policy=localDefault();
whole={[],false,"fixed_first_order_pa_identity_dac",repmat(policy,2,1)};
for k=1:numel(whole), localReject(@()localValidatePartial(whole{k})); end
flags={[],0,1,2,NaN,Inf,"true",[true false]};
for k=1:numel(flags)
    p=policy; p.enabled=flags{k}; localReject(@()localValidatePartial(p));
end
models={[],"",string(missing),["fixed_first_order_pa_identity_dac","other"], ...
    "FIXED_FIRST_ORDER_PA_IDENTITY_DAC","trajectory_conditioned", ...
    ['fixed_first_order_pa_identity_dac';'fixed_first_order_pa_identity_dac']};
for k=1:numel(models)
    p=policy; p.model=models{k}; localReject(@()localValidatePartial(p));
end
for value=["baseline_benchmark","agreed_starting_point","OPTIONAL_RESEARCH_EXPERIMENT"]
    p=policy; p.classification=value; localReject(@()localValidatePartial(p));
end
p=policy; p.infer_from_radiation=true; localReject(@()localValidatePartial(p));
p=policy; p.RequirementClass='3GPP_NORMATIVE'; localReject(@()localValidatePartial(p));
% Invalid model still fails in an explicitly disabled resolved declaration.
s=base.Data; s.power_and_rf_frontend.tx_linear_reference.model='unsupported';
localReject(@()sixgr.lls6g.config.validateScenarioConfig(s));
end

function localInheritance(fixture,work)
original=fileread(fixture);
on=localWrite(work,'enabled_child',fixture,struct('enabled',true));
scenario=sixgr.lls6g.config.loadScenarioConfig(on);
expected=localDefault(); expected.enabled=true;
assert(isequaln(scenario.Data.power_and_rf_frontend.tx_linear_reference,expected));
cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(work,'inherited_enabled'));
localAssertRuntime(cfg,true);
off=localWrite(work,'disabled_grandchild',on,struct('enabled',false));
scenario=sixgr.lls6g.config.loadScenarioConfig(off);
assert(isequaln(scenario.Data.power_and_rf_frontend.tx_linear_reference,localDefault()));
bad=localWrite(work,'invalid_disabled_child',off,struct('model','unsupported'));
localReject(@()sixgr.lls6g.config.loadScenarioConfig(bad));
assert(strcmp(original,fileread(fixture)),'Never rewrite the original scenario.');
end

function localExistingN40(repo,work)
path=fullfile(repo,'simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
original=fileread(path);
scenario=sixgr.lls6g.config.loadScenarioConfig(path);
assert(isequaln(scenario.Data.power_and_rf_frontend.tx_linear_reference,localDefault()));
cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(work,'original_n40'));
localAssertRuntime(cfg,false);
assert(cfg.rf.modeledRadiatedPower.Enabled&&cfg.rf.txSpatialPowerEnabled, ...
    'Existing independently enabled instrumentation must not opt in the new model.');
assert(strcmp(original,fileread(path)),'Never enable the original full scenario implicitly.');
end

function p=localDefault()
p=struct('enabled',false,'model','fixed_first_order_pa_identity_dac', ...
    'classification','optional_research_experiment');
end
function localAssertRuntime(cfg,enabled)
p=cfg.rf.txLinearReference;
assert(isequal(sort(string(fieldnames(p))), ...
    sort(["Enabled";"Model";"Classification";"RequirementClass"]))&& ...
    isequal(p.Enabled,enabled)&&p.Model=="fixed_first_order_pa_identity_dac"&& ...
    p.Classification=="optional_research_experiment"&&p.RequirementClass=="IMPLEMENTATION_POLICY");
end
function localValidatePartial(policy)
sixgr.lls6g.config.validateScenarioConfig(struct('power_and_rf_frontend', ...
    struct('tx_linear_reference',policy)),'AllowPartial',true);
end
function path=localWrite(work,name,parent,policy)
path=fullfile(work,string(name)+".json");
s=struct('inherits',string(parent),'power_and_rf_frontend',struct('tx_linear_reference',policy));
sixgr.util.jsonWrite(path,s);
end
function localReject(action)
try
    action();
catch cause
    assert(strcmp(cause.identifier,'sixgr:lls6g:config:TXLinearReferencePolicy'), ...
        'Unexpected rejection %s: %s',cause.identifier,cause.message);
    assert(contains(string(cause.message),'power_and_rf_frontend.tx_linear_reference'), ...
        'The rejection must identify the original policy field.');
    return;
end
error('test:MissingTXLinearReferencePolicyRejection','Invalid reference policy was accepted.');
end
