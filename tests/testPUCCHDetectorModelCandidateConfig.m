function ok=testPUCCHDetectorModelCandidateConfig()
% Configuration-only guard; no physical trials or qualification claim.
base=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pucch_baseline_signal_fixture.yaml');
candidate=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pucch_detector_model_candidate.yaml');
design=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/pucch_format0_noise_design_bound.yaml');
assert(string(candidate.Data.meta.research_class)=="optional_research_experiment");
comparisons=design.symbol_count*design.receive_branch_count*design.maximum_hypothesis_count;
raw=sqrt(-expm1(log(design.target_model_false_detection_bound/comparisons)/ ...
    (design.resource_elements_per_block-1)));
scale=10^design.threshold_decimal_places;
threshold=ceil(raw*scale)/scale;
assert(candidate.Data.pucch.detection_threshold_format0_two_symbols==threshold);
assert(base.Data.pucch.detection_threshold_format0_two_symbols==0.42, ...
    'The historical baseline and its failed threshold must remain preserved.');
% Compare the complete resolved scenario, not a selected list of PHY knobs.
a=base.Data; b=candidate.Data;
b.pucch.detection_threshold_format0_two_symbols=a.pucch.detection_threshold_format0_two_symbols;
metadata={'meta','identity','config_inheritance'};
for k=1:numel(metadata)
    if isfield(a,metadata{k}), a=rmfield(a,metadata{k}); end
    if isfield(b,metadata{k}), b=rmfield(b,metadata{k}); end
end
assert(isequaln(a,b),'test:DetectorCandidatePHYDrift', ...
    'Development candidate may change only metadata and the declared detection threshold.');
cfg=sixgr.lls6g.buildInternalConfig(candidate,tempname);
policy=cfg.phy.pucch.receiverDetectionThresholds;
assert(policy.detection_threshold_format0_two_symbols==threshold);
pilot=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/pucch_tdd_detector_model_candidate_pilot.yaml');
original=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/pucch_tdd_detector_pilot.yaml');
validatePUCCHDetectorPilotPolicy(pilot);
assert(endsWith(string(pilot.scenario_path),'lls_pucch_detector_model_candidate.yaml'));
pilot=rmfield(pilot,{'profile_id','scenario_path'});
original=rmfield(original,{'profile_id','scenario_path'});
assert(isequaln(pilot,original),'test:DetectorCandidatePilotDrift', ...
    'Paired development pilot must retain the original seed, cases and gates.');

% Qualification population for the target 5 MHz / 20 dB AWGN execution is
% explicit.  Do not represent its result as qualification for CDL fading.
awgn=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pucch_detector_awgn_20db_candidate.yaml');
awgnCfg=sixgr.lls6g.buildInternalConfig(awgn,tempname);
assert(string(sixgr.channel.resolveConcreteProfile(awgnCfg))=="AWGN" && ...
    awgnCfg.channel.awgnOnly && awgnCfg.channel.snr_dB==20 && ...
    awgn.Data.pucch.detection_threshold_format0_two_symbols==threshold, ...
    'test:DetectorQualificationPopulation', ...
    'Target qualification must retain the frozen threshold on explicit 20 dB AWGN.');
awgnPilot=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/pucch_tdd_detector_awgn_20db_development.yaml');
awgnCampaign=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/pucch_tdd_detector_awgn_20db_held_out_v2.yaml');
validatePUCCHDetectorPilotPolicy(awgnPilot);
awgnSeeds=validatePUCCHDetectorCampaignPolicy(awgnCampaign,awgnPilot);
assert(isempty(intersect(awgnSeeds,awgnCampaign.development_seeds)) && ...
    contains(string(awgn.Data.meta.description),"does not claim CDL"));
ok=true;
disp('PUCCH_MODEL_CANDIDATE_CONFIG_PASS: frozen threshold; explicit AWGN qualification population; no CDL claim.');
end
