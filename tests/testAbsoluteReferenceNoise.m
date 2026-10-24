function ok=testAbsoluteReferenceNoise()
% Declared absolute-reference noise/config arithmetic, not measured SINR,
% calibrated thermal noise, fading/array gain or a full waveform campaign.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
groups={@localNativeReference,@localPointAndSampleRate,@localFrozenAuthority, ...
    @localMalformed,@localDFTAndNoiseStream,@localScenario};
names=["native_reference","point_and_sample_rate","immutable_no_received_operands", ...
    "malformed_and_overflow","fft_units_and_noise_stream","resolved_absolute_n40_sweep"];
failures=strings(0,1);
for k=1:numel(groups)
    try
        groups{k}(); fprintf('ABSOLUTE_REFERENCE_NOISE %s PASS\n',names(k));
    catch cause
        failures(end+1)=names(k)+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'ABSOLUTE_REFERENCE_NOISE %s FAIL %s\n',names(k),getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(isempty(failures),'test:AbsoluteReferenceNoise', ...
    '%d/%d groups failed:\n%s',numel(failures),numel(groups),strjoin(failures,newline));
fprintf('ABSOLUTE_REFERENCE_NOISE_PASS groups=%d channel_executions=0 receiver_executions=0 measured_SINR_target=0\n',numel(groups));
ok=true;
end

function localNativeReference()
cfg=localConfig(); original=cfg; before=rng;
[v,r,c]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true);
p=cfg.run.absoluteReferenceNoisePolicy;
loss=nrPathLoss(nrPathLossConfig('Scenario','UMa'),2350e6,false,[0;0;25],[85;0;1.5]);
epre=10^(p.nominal_dl_tx_power_dbm/10)/(12*51)*10^(-loss/10);
psd=epre/(30e3*10^(cfg.channel.snr_dB/10));
localNear(v,psd*30.72e6); localNear(r.ReferenceEPRE_mW,epre);
assert(isequaln(cfg,original)&&isequal(before,rng)&&r.ReferencePathlossEvaluatedThisCall);
assert(r.ReferenceIsMeasured==false&&r.ThermalNoiseApplied==false&& ...
    r.NoiseFigureApplied==false&&r.WaveformAmplitudeUnit=="sqrt_mW"&& ...
    c.NativePathlossEvaluationCount==1&&~c.ArrayGainIncluded&&~c.FadingGainIncluded);
cfg.run.absoluteReferenceNoise=c;
[again,receipt,same]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6);
assert(isequal(v,again)&&isequal(c,same)&&~receipt.ReferencePathlossEvaluatedThisCall);
[ul,u]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"UL",30.72e6);
localNear(ul/v,10^((23-30)/10));
assert(u.Direction=="UL"&&u.ReferenceContractSHA256==r.ReferenceContractSHA256);
end

function localPointAndSampleRate()
targets=[30 20 10 0 -10 -20]; values=zeros(size(targets));
for k=1:numel(targets)
    cfg=localConfig(); cfg.channel.snr_dB=targets(k);
    [values(k),r,c]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true);
    cfg.run.absoluteReferenceNoise=c;
    [twice,r2]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",61.44e6);
    assert(twice==2*values(k)&&r2.NoisePSD_mWPerHz==r.NoisePSD_mWPerHz);
    assert(r.RequestedReferenceEsN0_dB==targets(k));
end
for k=2:numel(targets), localNear(values(k)/values(k-1),10^(-(targets(k)-targets(k-1))/10)); end
% Reference BWP width/SCS are installed operands, not scheduled PRB count.
cfg=localConfig(); [v,~,~]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true);
cfg.phy.bwp.dl.NSizeBWP=24;
[narrow,~,~]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true);
localNear(narrow/v,51/24);
cfg.phy.bwp.dl.SubcarrierSpacing_kHz=15;
[lowerSCS,~,~]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true);
localNear(lowerSCS/narrow,2);
end

function localFrozenAuthority()
cfg=localConfig(); [v,r,c]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true);
cfg.run.absoluteReferenceNoise=c; original=cfg;
% These values deliberately change the actual link, but are not inputs to
% the declared fixed reference. No current received sample enters this API.
cfg.phy.nTxAnt=64; cfg.phy.nRxAnt=4; cfg.phy.pdsch.NumLayers=4;
cfg.phy.pdsch.PRBSet=7:10; cfg.phy.pdsch.selectedPMI=9;
cfg.phy.pusch.powerControl.closedLoopAccumulation_dB=17;
cfg.channel.pathloss_dB=190; cfg.channel.currentFadingGain=0.001;
cfg.rf.noiseFigure_dB=40;
[actual,receipt]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6);
assert(isequal(v,actual)&&receipt.ReferenceContractSHA256==r.ReferenceContractSHA256);
cfg=original; cfg.channel.snr_dB=cfg.channel.snr_dB+1; localReject(@()localResolve(cfg));
cfg=original; cfg.phy.fc_Hz=2.4e9; localReject(@()localResolve(cfg));
cfg=original; cfg.phy.bwp.dl.NSizeBWP=24; localReject(@()localResolve(cfg));
cfg=original; cfg.run.absoluteReferenceNoisePolicy.nominal_ul_tx_power_dbm=20; localReject(@()localResolve(cfg));
cfg=original; cfg.run.absoluteReferenceNoise.DL.NoisePSD_mWPerHz=2*c.DL.NoisePSD_mWPerHz;
localReject(@()localResolve(cfg));
% Even a resealed numerical capsule must close all original operands.
cfg.run.absoluteReferenceNoise.SHA256=localHash(rmfield(cfg.run.absoluteReferenceNoise,'SHA256'));
localReject(@()localResolve(cfg));
cfg=original; cfg.run.absoluteReferenceNoise.ReferenceIsMeasured=true;
cfg.run.absoluteReferenceNoise.SHA256=localHash(rmfield(cfg.run.absoluteReferenceNoise,'SHA256'));
localReject(@()localResolve(cfg));
for field=["ReferenceIsMeasured","ThermalNoiseApplied","ArrayGainIncluded", ...
        "FadingGainIncluded","ScheduledPowerIncluded","StandardizedAccuracyQualified","HardwareQualified"]
    for value={0,false(0,1),[false false],true}
        cfg=original; cfg.run.absoluteReferenceNoise.(field)=value{1};
        cfg.run.absoluteReferenceNoise.SHA256=localHash(rmfield(cfg.run.absoluteReferenceNoise,'SHA256'));
        localReject(@()localResolve(cfg));
    end
end
cfg=original; cfg.run.absoluteReferenceNoise.NativePathlossEvaluationCount=true;
cfg.run.absoluteReferenceNoise.SHA256=localHash(rmfield(cfg.run.absoluteReferenceNoise,'SHA256'));
localReject(@()localResolve(cfg));
localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(original,"DL",30.72e6,'Freeze',true));
end

function localMalformed()
base=localConfig(); id='sixgr:link:AbsoluteReferenceNoise';
localReject(@()localResolve(base));
for target=[-1e8 1e8 NaN Inf]
    cfg=base; cfg.channel.snr_dB=target;
    localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true));
end
for value={[],NaN,Inf,true,[1 2],"30"}
    cfg=base; cfg.run.absoluteReferenceNoisePolicy.nominal_dl_tx_power_dbm=value{1};
    localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true));
end
for value={[],[0 0 NaN],[0 0 0],[0 0 1.5],[9 0 1.5],[5001 0 1.5], ...
        [85 0 1.4],[85 0 22.6],"85,0,1.5",[85;0;1.5;2]}
    cfg=base; cfg.run.absoluteReferenceNoisePolicy.reference_ue_position_m=value{1};
    localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true));
end
for frequency=[0.49e9 100.01e9]
    cfg=base; cfg.phy.fc_Hz=frequency;
    localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true));
end
cfg=base; cfg.run.absoluteReferenceNoisePolicy.reference_bs_position_m=[0 0 24];
localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true));
cfg=base; cfg.integration.power_reference_mode='normalized_unit_es';
localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true),id);
cfg=base; cfg.integration.configured_snr_is_link_authority=0;
localReject(@()sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true),id);
policy=base.run.absoluteReferenceNoisePolicy;
partial=struct('simulation',struct('noise_operating_mode','absolute_reference_esn0', ...
    'absolute_reference_esn0',struct('reference_los',false)));
sixgr.lls6g.config.validateScenarioConfig(partial,'AllowPartial',true);
for value={[],false,struct('reference_los',0),struct('nominal_dl_tx_power_dbm',true), ...
        struct('reference_bs_position_m',[0 0 NaN]),struct('unknown',1)}
    partial.simulation.absolute_reference_esn0=value{1};
    localReject(@()sixgr.lls6g.config.validateScenarioConfig(partial,'AllowPartial',true), ...
        'sixgr:lls6g:config:AbsoluteReferenceNoisePolicy');
end
partial.simulation.absolute_reference_esn0=policy;
sixgr.lls6g.config.validateScenarioConfig(partial,'AllowPartial',true);
end

function localDFTAndNoiseStream()
cfg=localConfig(); [variance,~,~]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6,'Freeze',true);
% An orthogonal deterministic noise ensemble has covariance variance*I.
% Its exact DFT proves the physical RE conversion, without estimating a
% finite random realization's variance or using an SNR-measured normalizer.
for nfft=[256 512]
    ensemble=sqrt(nfft*variance)*eye(nfft);
    physicalRE=fft(ensemble,[],1)/nfft;
    perRE=mean(abs(physicalRE).^2,2);
    assert(all(abs(perRE-variance/nfft)<=64*eps*variance/nfft));
end
before=rng; x=complex(zeros(257,4));
[whole,state]=sixgr.link.addRuntimeComplexNoise(x,variance,31,37,struct());
[a,sa]=sixgr.link.addRuntimeComplexNoise(x(1:81,:),variance,31,37,struct());
[b,sb]=sixgr.link.addRuntimeComplexNoise(x(82:end,:),variance,31,118,sa);
assert(isequal(whole,[a;b])&&isequal(state,sb)&&isequal(before,rng));
end

function localScenario()
repo=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(repo,'simulator','configs','scenarios');
parent=fullfile(folder,'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
path=fullfile(folder,'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
original=fileread(parent);
old=sixgr.lls6g.config.loadScenarioConfig(parent);
s=sixgr.lls6g.config.loadScenarioConfig(path);
work=tempname; mkdir(work); cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU>
baseline=sixgr.lls6g.buildInternalConfig(old,fullfile(work,'original_thermal'));
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(work,'reference_parent'));
[parentProfile,parentAuthority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg);
assert(parentProfile=="generic_sweep"&&~parentAuthority.SharedWaveformOwner&& ...
    ~parentAuthority.Promoted,'A sweep wrapper is not an executed physical owner.');
assert(string(baseline.run.noiseOperatingMode)=="receiver_noise_figure_thermal_noise"&& ...
    ~isfield(baseline.run,'absoluteReferenceNoise')&&strcmp(original,fileread(parent)));
assert(string(cfg.run.noiseOperatingMode)=="absolute_reference_esn0"&& ...
    ~sixgr.rf.isFixedSNRLinkAuthority(cfg)&& ...
    sixgr.rf.fixedSNRPowerReferenceMode(cfg)=="absolute_calibrated_sqrt_mw");
% Physical model/installed power policy remains the original absolute UMa
% scenario. The declared normalization is separate from these actual gains.
assert(isequaln(cfg.rf,baseline.rf)&&isequaln(cfg.antenna,baseline.antenna)&& ...
    isequaln(cfg.phy.pusch.powerControl,baseline.phy.pusch.powerControl));
assert(cfg.channel.pathlossEnabled&&cfg.channel.normalizePathGains&& ...
    ~cfg.channel.normalizeChannelOutputs&&cfg.rf.modeledRadiatedPower.Enabled&& ...
    cfg.phy.pusch.powerControl.enabled&&cfg.phy.pusch.powerControl.phrReportEnabled);
rank=sixgr.mimo.resolveRankPolicy(cfg);
assert(rank.AdaptiveRank&&rank.Policy=="measured_ri"&& ...
    cfg.phy.pdsch.maxRankDefault==4&&cfg.phy.pusch.maxRankDefault==4&& ...
    cfg.phy.linkAdaptation.innerLoopFlag&&cfg.phy.linkAdaptation.outerLoopFlag);
assert(cfg.run.totalSlots==60&&cfg.run.totalTime_ms==30&& ...
    ~s.get('run_control.runtime_checkpoint_enable'));
assert(isequaln(s.Data.channels,old.Data.channels)&& ...
    isequaln(s.Data.rf_frontend,old.Data.rf_frontend));
assert(s.get('scenario.sweep.execution_error_policy')=="retain_failure_and_continue");
overrides=s.get('scenario.sweep.overrides'); targets=[30 20 10 0 -10 -20];
assert(numel(overrides)==numel(targets));
for k=1:numel(targets)
    % Exactly the generic runner's merge/normalization/validation boundary.
    d=sixgr.util.mergeStruct(s.Data,overrides(k).config);
    d=sixgr.lls6g.config.normalizeScenarioAliases(d,'SourceFiles',s.SourceFiles, ...
        'ConfigPath',s.ConfigPath,'Authority',overrides(k).config);
    d.scenario.runner_profile=char(s.get('scenario.sweep.base_profile'));
    sixgr.lls6g.config.validateScenarioConfig(d);
    [profile,authority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(d);
    assert(profile=="waveform_bundle"&&authority.SharedWaveformOwner&& ...
        d.kpi_spec.csi_selection_quality.enabled);
    assert(d.simulation.snr_db==targets(k)&&d.simulation.n_slots==60&& ...
        ~d.integration.configured_snr_is_link_authority);
    one=localConfig(); one.channel.snr_dB=d.simulation.snr_db;
    one.run.absoluteReferenceNoisePolicy=d.simulation.absolute_reference_esn0;
    [~,receipt]=sixgr.link.resolveAbsoluteReferenceNoise(one,"DL",30.72e6,'Freeze',true);
    assert(receipt.RequestedReferenceEsN0_dB==targets(k));
end
bad=s.Data; bad.simulation=rmfield(bad.simulation,'absolute_reference_esn0');
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad), ...
    'sixgr:lls6g:config:AbsoluteReferenceNoisePolicy');
bad=s.Data; bad.integration.configured_snr_is_link_authority=true;
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad), ...
    'sixgr:lls6g:config:AbsoluteReferenceNoiseAuthority');
localSweepGuards(s.Data,work);
end

function localSweepGuards(parent,work)
id='sixgr:lls6g:config:CSISelectionQualityCompatibility';
original=parent;
bad=parent; bad.scenario.sweep.base_profile='ai_benchmark';
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),id);
bad=parent; bad.scenario.sweep.overrides=struct([]);
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),id);
% Exercise actual canonical override authority, not a stale flat alias that
% the original runner would legitimately replace during normalization.
mutations={struct('users_enabled',false,'num_ues',1), ...
    struct('execution_model','independent_link_sweep')};
for k=1:numel(mutations)
    override=struct('canonical_control',struct('topology',mutations{k}));
    bad=parent; bad.scenario.sweep.overrides=struct('label','bad_child','config',override);
    localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),id);
    % Direct building must not bypass the child dependency guard either.
    localReject(@()sixgr.lls6g.buildInternalConfig(bad,fullfile(work,'bad_child')),id);
end
% Child policy is configurable, not silently forced enabled by its parent.
% Disabling the audit changes neither the dispatched waveform route nor the
% original parent policy, and does not produce measurement evidence.
override=struct('kpi_spec',struct('csi_selection_quality',struct('enabled',false)));
off=parent; off.scenario.sweep.overrides=struct('label','audit_disabled','config',override);
sixgr.lls6g.config.validateScenarioConfig(off);
child=sixgr.util.mergeStruct(off,override);
child=sixgr.lls6g.config.normalizeScenarioAliases(child, ...
    'SourceFiles',parent.config_inheritance.provenance.source_files, ...
    'ConfigPath',parent.config_inheritance.provenance.config_path,'Authority',override);
child.scenario.runner_profile='waveform_bundle';
assert(~child.kpi_spec.csi_selection_quality.enabled&& ...
    parent.kpi_spec.csi_selection_quality.enabled&&isequaln(parent,original));
assert(isequaln(child.config_inheritance.provenance,parent.config_inheritance.provenance));
[profile,authority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(parent);
assert(profile=="generic_sweep"&&~authority.SharedWaveformOwner);
end

function cfg=localConfig()
p=struct('reference_policy','nominal_full_bwp_unity_array', ...
    'reference_pathloss_scenario','UMa','reference_bs_position_m',[0 0 25], ...
    'reference_ue_position_m',[85 0 1.5],'reference_los',false, ...
    'nominal_dl_tx_power_dbm',30,'nominal_ul_tx_power_dbm',23, ...
    'classification','optional_research_experiment');
bwp=struct('NSizeBWP',51,'NStartBWP',0,'SubcarrierSpacing_kHz',30,'BWPID',0);
cfg=struct('run',struct('noiseOperatingMode','absolute_reference_esn0', ...
    'absoluteReferenceNoisePolicy',p),'integration',struct('run_mode','GEOMETRY_NETWORK', ...
    'configured_snr_is_link_authority',false,'power_reference_mode','absolute_calibrated_sqrt_mw'), ...
    'channel',struct('snr_dB',0),'phy',struct('fc_Hz',2350e6,'bwp',struct('dl',bwp,'ul',bwp)));
end
function localResolve(cfg)
sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",30.72e6);
end
function localNear(a,b)
assert(isfinite(a)&&isfinite(b)&&abs(a-b)<=64*eps*max(abs(a),abs(b)));
end
function h=localHash(v)
h=string(sixgr.util.sha256Hex(unicode2native(jsonencode(v),'UTF-8')));
end
function localReject(action,id)
if nargin<2, id='sixgr:link:AbsoluteReferenceNoise'; end
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Unexpected error %s: %s',cause.identifier,cause.message);
    return;
end
error('test:AbsoluteReferenceNoiseMissingRejection','Expected %s.',id);
end
