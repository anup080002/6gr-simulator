function ok=testCSISelectionQualityPolicy()
% Authoring/resolution contracts only; no PHY execution or scoring claim.
setup6GRSimToolkit('Verbose',false);
defaults=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','defaults', ...
    'top_level_required_sections_03.yaml'));
block=defaults.kpi_spec.csi_selection_quality;
off=sixgr.lls6g.config.resolveCSISelectionQualityPolicy(block);
assert(~off.Enabled && off.PolicySource=="kpi_spec.csi_selection_quality" && ...
    off.Objective=="mean_support_sum_log2_one_plus_linear_mmse_sinr" && ...
    off.Receiver=="linear_mmse" && ...
    off.PowerNormalization=="unit_physical_chain_grid_coefficient_power" && ...
    off.PowerFactor==1 && off.Support=="selected_resource_pilot_union" && ...
    off.ResearchClass=="optional_research_experiment" && ...
    off.Classification=="IMPLEMENTATION_POLICY" && ...
    off.TieAbsoluteTolerance==1e-10 && off.PhysicalPowerTolerance==1e-10);
legacy=sixgr.lls6g.config.resolveCSISelectionQualityPolicy();
assert(~legacy.Enabled && legacy.PolicySource=="absent_disabled_legacy" && ...
    ~isfield(legacy,'Objective') && ~isfield(legacy,'PowerFactor'));
catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
rule=catalog.sections.kpi_spec.parameters.csi_selection_quality;
assert(~rule.required && string(rule.nested_rule)=="kpi_csi_selection_quality");
assert(isequal(sort(string(fieldnames(block))),sort(string(fieldnames( ...
    catalog.nested_sections.kpi_csi_selection_quality.parameters)))));
enabled=block; enabled.enabled=true; enabled.tie_absolute_tolerance=0;
enabled.physical_power_tolerance=1e-8;
p=sixgr.lls6g.config.resolveCSISelectionQualityPolicy(enabled);
assert(p.Enabled && p.TieAbsoluteTolerance==0 && p.PhysicalPowerTolerance==1e-8);
% Even disabled policies are complete and cannot hide unknown fields/units.
for field=string(fieldnames(block)).'
    mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(rmfield(block,field)));
end
mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy([]));
mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(struct()));
bad=block; bad.enabled="true";
mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(bad));
for value=[0 2 NaN Inf]
    bad=block; bad.power_factor=value;
    mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(bad));
end
bad=block; bad.power_normalization="unit_physical_total_power";
mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(bad));
bad=block; bad.support="all_carrier_subcarriers";
mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(bad));
bad=block; bad.classification="NR_NORMATIVE";
mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(bad));
bad=block; bad.physical_power_unit="mW";
mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(bad));
for value=[-1 NaN Inf]
    bad=block; bad.tie_absolute_tolerance=value;
    mustFail(@()sixgr.lls6g.config.resolveCSISelectionQualityPolicy(bad));
end
% A leaf may override enabled through ordinary inheritance, but the final
% resolved mapping must still contain every field from the YAML defaults.
partial=struct('kpi_spec',struct('csi_selection_quality',struct('enabled',true)));
sixgr.lls6g.config.validateScenarioConfig(partial,'AllowPartial',true);
merged=sixgr.util.mergeStruct(block,partial.kpi_spec.csi_selection_quality);
mergedPolicy=sixgr.lls6g.config.resolveCSISelectionQualityPolicy(merged);
assert(mergedPolicy.Enabled);
baseline=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
baselinePolicy=sixgr.lls6g.config.resolveCSISelectionQualityPolicy( ...
    baseline.get('kpi_spec.csi_selection_quality'));
assert(~baselinePolicy.Enabled);
path=fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
scenario=sixgr.lls6g.config.loadScenarioConfig(path);
s=scenario.toStruct();
assert(s.kpi_spec.csi_selection_quality.enabled);
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
[profile,runnerAuthority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(scenario,cfg);
assert(profile=="waveform_bundle" && ~runnerAuthority.Promoted && runnerAuthority.SharedWaveformOwner);
assert(isequal(cfg.measurements.csiSelectionQuality, ...
    sixgr.lls6g.config.resolveCSISelectionQualityPolicy(s.kpi_spec.csi_selection_quality)));
assert(~isfield(cfg.measurements.csiSelectionQuality,'PowerUnit') && ...
    ~isfield(cfg.measurements.csiSelectionQuality,'PhysicalReferencePlane'));
request=cfg.phy.csi.reportConfiguration;
assert(request.ProfileID==string(cfg.phy.mimo.profileID) && ...
    request.Direction==string(cfg.phy.mimo.direction) && ...
    isequal(request.AllowedRanks,cfg.phy.csi.rankDomain) && ...
    isequal(request.RankDomain,request.AllowedRanks));
% Enumeration metadata must not change a single transmitted report bit.
disabled=s; disabled.kpi_spec.csi_selection_quality.enabled=false;
ordinary=sixgr.lls6g.buildInternalConfig(disabled,tempname);
assert(isequaln(rmfield(request,{'ProfileID','Direction','RankDomain'}), ...
    ordinary.phy.csi.reportConfiguration));
for rank=request.AllowedRanks
    before=ordinary.phy.csi.reportConfiguration; before.Rank=rank;
    after=request; after.Rank=rank;
    oldSchema=sixgr.phy.mimo.CSIReportConfiguration(before,before.Epoch);
    newSchema=sixgr.phy.mimo.CSIReportConfiguration(after,after.Epoch);
    value=struct('RI',rank,'PMI',0,'CRI',0,'CQI_CW0',10,'LI',0, ...
        'PMI_I11',0,'PMI_I12',0,'PMI_I13',0,'PMI_I2',0);
    oldBits=oldSchema.build(value); newBits=newSchema.build(value);
    assert(isequal(oldBits.Part1Bits,newBits.Part1Bits) && ...
        isequal(oldBits.Part2Bits,newBits.Part2Bits));
end
% This is the exact supported source used by the bounded shared-RX test.
small=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml'));
small=small.toStruct(); small.kpi_spec.csi_selection_quality.enabled=true;
sixgr.lls6g.config.validateScenarioConfig(small);
smallCfg=sixgr.lls6g.buildInternalConfig(small,tempname);
[profile,runnerAuthority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(small,smallCfg);
assert(string(small.scenario.runner_profile)=="system_level_lls" && ...
    profile=="waveform_bundle" && runnerAuthority.Promoted && runnerAuthority.SharedWaveformOwner);
assert(smallCfg.phy.mimo.strict && ...
    smallCfg.phy.csi.reportConfiguration.ProfileID=="fr1_typeI_single_panel_strict" && ...
    smallCfg.phy.csi.reportConfiguration.Direction=="DL" && ...
    isequal(smallCfg.phy.csi.reportConfiguration.AllowedRanks,[1 2]) && ...
    smallCfg.antenna.ue.numRxRFChains==2);
% Reject genuine nonshared paths, not the legacy profile name by itself.
unpromoted=small;
for gate=["pbch_required","prach_required","pdcch_required","srs_required","trs_required"]
    unpromoted.control_gating.(gate)=false;
end
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(unpromoted));
mustRejectAudit(@()sixgr.lls6g.buildInternalConfig(unpromoted,tempname));
wrongModel=small; wrongModel.users.execution_model="independent_link_sweep";
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(wrongModel));
mustRejectAudit(@()sixgr.lls6g.buildInternalConfig(wrongModel,tempname));
noOwner=s; noOwner.users.enabled=false; noOwner.users.n_users=1;
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(noOwner));
mustRejectAudit(@()sixgr.lls6g.buildInternalConfig(noOwner,tempname));
% Known unsupported combinations reject during configuration, not RX.
bad=s; bad.reference_signals.csi_rs_enabled=false;
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(bad));
bad=s; bad.reference_signals.csi_reporting_enabled=false;
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(bad));
bad=s; bad.mimo.phase07_strict.enabled=false;
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(bad));
bad=s; bad.mimo.phase07_strict.codebook_type="typeII";
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(bad));
bad=s; bad.mimo.phase07_strict.csi_report.frequency_granularity="subband";
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(bad));
bad=s; bad.mimo.phase07_strict.ports=2;
bad.mimo.codebook_subset_restriction="restricted";
mustRejectAudit(@()sixgr.lls6g.config.validateScenarioConfig(bad));
bad=s; bad.link_adaptation.rank_adaptation_policy="fixed";
bad.mimo.rank_adaptation_policy="fixed";
mustRejectAudit(@()sixgr.lls6g.buildInternalConfig(bad,tempname));
% Non-strict CSI remains supported with the audit disabled. It is not
% silently switched to another receiver merely to provide audit fields.
generic=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'dl_4ghz_baseline.yaml'));
generic=generic.toStruct();
if isfield(generic.mimo,'phase07_strict'), generic.mimo=rmfield(generic.mimo,'phase07_strict'); end
generic.reference_signals.csi_reporting_enabled=true;
generic.reference_signals.csi_rs_enabled=true;
generic.reference_signals.csi_rs_ports=1;
generic.reference_signals.csi_rs_num_resources=1;
generic.pdsch.layer_count=1; generic.pdsch.rank=1;
generic.mimo.n_layers=1; generic.mimo.codebook_type="type1";
generic.kpi_spec.csi_selection_quality.enabled=false;
genericCfg=sixgr.lls6g.buildInternalConfig(generic,tempname);
assert(~genericCfg.phy.mimo.strict && ...
    isequal(genericCfg.phy.csi.reportConfiguration.AllowedRanks,1) && ...
    isequal(genericCfg.phy.csi.rankDomain,1));
genericSchema=sixgr.phy.mimo.CSIReportConfiguration( ...
    genericCfg.phy.csi.reportConfiguration,genericCfg.phy.csi.reportConfigurationEpoch);
assert(genericSchema.part1BitCount()==4 && genericSchema.part2BitCount()==0);
generic.kpi_spec.csi_selection_quality.enabled=true;
mustRejectAudit(@()sixgr.lls6g.buildInternalConfig(generic,tempname));
absent=s; absent.kpi_spec=rmfield(absent.kpi_spec,'csi_selection_quality');
cfg=sixgr.lls6g.buildInternalConfig(absent,tempname);
assert(~cfg.measurements.csiSelectionQuality.Enabled && ...
    cfg.measurements.csiSelectionQuality.PolicySource=="absent_disabled_legacy");
% Resolved validation catches explicit empty policy and invalid study policy.
bad=s; bad.kpi_spec.csi_selection_quality=[];
mustFail(@()sixgr.lls6g.config.validateScenarioConfig(bad));
bad=s; bad.kpi_spec.csi_selection_quality=rmfield(block,'objective');
mustRejectConfig(@()sixgr.lls6g.config.validateScenarioConfig(bad),'objective');
changed=s; changed.kpi_spec.csi_selection_quality.tie_absolute_tolerance=2e-10;
assert(sixgr.lls6g.config.hashResolvedScenario(changed)~=sixgr.lls6g.config.hashResolvedScenario(s));
ok=true;
fprintf('testCSISelectionQualityPolicy: PASS (configuration-only policy binding)\n');
end

function mustFail(action)
try, action(); catch cause
    assert(strcmp(cause.identifier,'sixgr:lls6g:config:CSISelectionQualityPolicy'), ...
        'Unexpected policy failure %s: %s',cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected invalid CSI selection-quality policy to fail.');
end

function mustRejectConfig(action,field)
try, action(); catch cause
    assert(startsWith(string(cause.identifier),'sixgr:lls6g:config:') && ...
        contains(string(cause.message),field),'Unexpected configuration failure %s: %s',cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected incomplete resolved policy to fail.');
end

function mustRejectAudit(action)
try, action(); catch cause
    assert(strcmp(cause.identifier,'sixgr:lls6g:config:CSISelectionQualityCompatibility') && ...
        contains(cause.message,'kpi_spec.csi_selection_quality'), ...
        'Unexpected audit preflight failure %s: %s',cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected unsupported selection audit to fail before waveform execution.');
end
