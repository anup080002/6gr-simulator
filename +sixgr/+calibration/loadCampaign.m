function [p,cases,identity,sources]=loadCampaign(path)
%LOADCAMPAIGN Generic waveform calibration, separate from any agenda item.
p=sixgr.lls6g.config.readConfigFile(path);
assert(string(p.schema)=="sixgr.link_calibration_campaign/v1", ...
    'sixgr:calibration:Schema','Unsupported calibration campaign schema.');
assert(string(p.channel_evolution)=="independent_attempt_realizations" && ...
    string(p.feedback_assumption)=="ideal_error_free_delayed_control" && ...
    string(p.receiver_assumption)=="practical_dmrs_known_noise_ideal_timing" && ...
    string(p.sinr_feature)=="applied_channel_per_data_re_pre_combining", ...
    'sixgr:calibration:Assumptions','Unsupported calibration execution/measurement assumption.');
assert(string(p.reference_channel.model)=="AWGN", ...
    'sixgr:calibration:ReferenceChannel','The reference must be the independently executed AWGN link.');
rv=double(p.rv_sequence(:).');
assert(~isempty(rv) && rv(1)==0 && all(ismember(rv,0:3)), ...
    'sixgr:calibration:History','Declare an increasing SNR axis and an RV sequence beginning at 0.');
sixgr.calibration.historyGrid(p,"reference");
sixgr.calibration.historyGrid(p,"reference_validation");
sixgr.calibration.historyGrid(p,"fit");
if isfield(p,'population_planning')
    planning=p.population_planning;
    validateattributes(planning.minimum_pilot_starts,{'numeric'},{'scalar','integer','positive'});
    validateattributes(planning.maximum_starting_episodes_per_history,{'numeric'},{'scalar','integer','positive'});
    validateattributes(planning.reach_confidence,{'numeric'},{'scalar','>',0,'<',1});
end
for role=["reference","reference_validation","fit","validation"]
    validateattributes(p.populations.(role),{'numeric'},{'scalar','integer','positive','finite'});
end
validateattributes(p.episodes_per_invocation,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(p.seed_base,{'numeric'},{'scalar','integer','positive','finite'});
q=p.qualification;
validateattributes(q.minimum_conditional_trials,{'numeric'},{'scalar','integer','positive'});
validateattributes(q.confidence_level,{'numeric'},{'scalar','>',0,'<',1});
validateattributes(q.maximum_wilson_half_width,{'numeric'},{'scalar','>',0,'<',0.5});
validateattributes(q.maximum_validation_absolute_bler_error,{'numeric'},{'scalar','>',0,'<',1});
validateattributes(q.beta_linear_bounds,{'numeric'},{'numel',2,'positive','finite','increasing'});
validateattributes(q.beta_log_grid_count,{'numeric'},{'scalar','integer','>=',3});
validateattributes(q.minimum_beta_objective_contrast,{'numeric'},{'scalar','positive','finite'});
raw=p.cases; if iscell(raw), raw=vertcat(raw{:}); end
cases=struct([]); sources=string(java.io.File(char(path)).getCanonicalPath());
for k=1:numel(raw)
    configPath=fullfile(fileparts(path),raw(k).config);
    if java.io.File(char(raw(k).config)).isAbsolute(), configPath=raw(k).config; end
    [cfg,provenance]=sixgr.lls.loadConfig(configPath);
    cfg=sixgr.util.mergeStruct(cfg,raw(k).overrides);
    cfg=sixgr.lls.validateConfig(cfg);
    link=lower(string(cfg.simulation.link)); x=cfg.(link);
    % Current applied-channel feature adapter is explicitly SISO. Refuse to
    % manufacture multi-layer SINR by repeating a scalar or reusing this key.
    assert(x.numberLayers==1 && cfg.channel.txAntennas==1 && cfg.channel.rxAntennas==1 && ...
        ~cfg.antenna.enabled && ~cfg.interference.enabled && ...
        ~cfg.synchronizationResidual.enabled && ~cfg.ntn.enabled && ...
        ~cfg.isac.enabled && ~cfg.linkAdaptation.enabled && ...
        string(cfg.receiver.channelEstimation)=="practical" && ~cfg.receiver.useMexLDPC, ...
        'sixgr:calibration:Coverage','This adapter requires a SISO practical-DMRS fixed-MCS baseline, toolbox LDPC, and no additional interference/RF/array branches.');
    profile=sixgr.link.resolveMCSProfile(x.mcsTable,x.mcsIndex);
    assert(link~="pusch" || ~x.transformPrecoding, ...
        'sixgr:calibration:Coverage','The SISO CP-OFDM adapter does not qualify transform-precoded UL.');
    assert(profile.Valid && string(profile.Modulation)==string(x.modulation) && ...
        abs(double(profile.TargetCodeRate)-double(x.targetCodeRate))<1e-12, ...
        'sixgr:calibration:MCS','The selected MCS must match its configured modulation and code rate.');
    cfg.harq.enabled=true; cfg.harq.rvSequence=rv; cfg.harq.maxTransmissions=numel(rv);
    cfg.simulation.studyType='harq_throughput';
    for channel={p.reference_channel,p.target_channel}
        variant=cfg; variant.channel=sixgr.util.mergeStruct(cfg.channel,channel{1});
        sixgr.lls.validateConfig(variant);
    end
    direction="UL"; if link=="pdsch", direction="DL"; end
    cases(k).ID=string(raw(k).id); cases(k).Direction=direction; cases(k).Config=cfg;
    sources=[sources;provenance.SourceFiles(:)]; %#ok<AGROW>
end
assert(numel(unique(string({cases.ID})))==numel(cases), ...
    'sixgr:calibration:Cases','Case IDs must be unique.');
assert(all(ismember(string(q.required_directions),string({cases.Direction}))), ...
    'sixgr:calibration:Coverage','Missing required DL/UL cases.');
sixgr.calibration.startingPopulations(p,cases);
% Freeze the full MATLAB implementation, including dirty/untracked source.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
files=dir(fullfile(root,'+sixgr','**','*.m'));
% Core defaults and allocation/codebook catalogs are executable policy too;
% hashing MATLAB code alone would miss a changed inherited PHY default.
catalogs=[dir(fullfile(root,'simulator','configs','schema','*.yaml')); ...
    dir(fullfile(root,'simulator','configs','schema','*.json'))];
sources=unique([sources;string(fullfile({files.folder},{files.name})).'; ...
    string(fullfile({catalogs.folder},{catalogs.name})).'; ...
    string(fullfile(root,'run_link_calibration.m'))],'stable');
hashes=strings(numel(sources),1);
for k=1:numel(sources), hashes(k)=sixgr.csi.studyFileSHA256(sources(k)); end
science=rmfield(p,'episodes_per_invocation');
software=struct('MATLAB',version,'Toolboxes',ver);
identity=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    string(jsonencode(science))+string(jsonencode(cases))+ ...
    string(jsonencode(software))+join(hashes(2:end),''),'UTF-8'))));
sources=table(sources,hashes,'VariableNames',{'Path','SHA256'});
end
