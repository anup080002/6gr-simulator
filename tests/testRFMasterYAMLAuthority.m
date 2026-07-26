function tests=testRFMasterYAMLAuthority
%TESTRFMASTERYAMLAUTHORITY Prove both operator masters own Phase-11 RF state.
tests=functiontests(localfunctions);
end

function testBothMasterYAMLsOwnCanonicalRFConfiguration(t)
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
repoRoot=fileparts(fileparts(mfilename("fullpath")));
scenarioRoot=fullfile(repoRoot,"simulator","configs","scenarios");
names=["master_sinr_sweep.yaml","master_geometry_based.yaml"];
raw=cell(1,2);
resolved=cell(1,2);
cfg=cell(1,2);
tmp=tempname; mkdir(tmp);
cleanup=onCleanup(@()localCleanup(tmp)); %#ok<NASGU>
for k=1:2
    path=fullfile(scenarioRoot,names(k));
    raw{k}=sixgr.lls6g.config.readConfigFile(path);
    verifyTrue(t,isfield(raw{k},"rf_frontend"), ...
        names(k)+" must expose rf_frontend.");
    localRequireRFFields(t,raw{k}.rf_frontend,names(k));
    scenario=sixgr.lls6g.config.loadScenarioConfig(path);
    resolved{k}=scenario.toStruct();
    cfg{k}=sixgr.lls6g.buildInternalConfig(scenario, ...
        fullfile(tmp,"mode-"+k));
    verifyEqual(t,string(cfg{k}.rf.specification.resolvedProfile.ProfileID), ...
        string(raw{k}.rf_frontend.profile_id));
    verifyEqual(t,double(cfg{k}.rf.configurationEpoch), ...
        double(raw{k}.rf_frontend.configuration_epoch));
    verifyEqual(t,double(cfg{k}.rf.phaseNoise.maskOffsets_Hz(:)), ...
        double(raw{k}.rf_frontend.phase_noise.mask_offsets_hz(:)));
    verifyEqual(t,double(cfg{k}.rf.phaseNoise.maskLevels_dBcHz(:)), ...
        double(raw{k}.rf_frontend.phase_noise.mask_levels_dbchz(:)));
end
verifyEqual(t,localFieldTree(raw{1}.rf_frontend,""), ...
    localFieldTree(raw{2}.rf_frontend,""), ...
    "Both operator masters must expose the same RF configuration surface.");

probe=resolved{1};
probe.rf_frontend.profile_id="rf_impaired_research";
probe.rf_frontend.claim_class="RESEARCH";
probe.rf_frontend.pa.enabled=true;
probe.rf_frontend.pa.input_backoff_db=9.25;
probe.rf_frontend.phase_noise.enabled=true;
probe.rf_frontend.phase_noise.mask_levels_dbchz= ...
    [-80 -92 -108 -126 -142];
probeCfg=sixgr.lls6g.buildInternalConfig(probe,fullfile(tmp,"probe"));
[paProfile,canonical]=sixgr.rf.runtime.PAProfile. ...
    fromConfiguration(probeCfg);
verifyTrue(t,canonical);
verifyEqual(t,paProfile.InputBackoff_dB,9.25);
verifyEqual(t,double(probeCfg.rf.phaseNoise.maskLevels_dBcHz(:)), ...
    double(probe.rf_frontend.phase_noise.mask_levels_dbchz(:)));
phaseNoise=sixgr.rf.PhaseNoiseModel(probeCfg,30.72e6,11);
verifyEqual(t,phaseNoise.Backend,"sixgr_rf_runtime_phase_noise_process");
end

function localRequireRFFields(t,rf,name)
top=["enabled","profile_id","specification_version","claim_class", ...
    "configuration_epoch","reference_plane","oscillator", ...
    "timing_and_sample_clock","phase_noise","iq_and_lo_leakage","pa", ...
    "cfr","dpd","dac","receiver","blocker","measurements", ...
    "ul_power_control"];
for field=top
    verifyTrue(t,isfield(rf,field),name+" missing rf_frontend."+field);
end
requiredPaths=[ ...
    "reference_plane.impedance_ohm"
    "oscillator.tracking_proportional_gain"
    "oscillator.tracking_integral_gain"
    "timing_and_sample_clock.anti_alias_filter_taps"
    "phase_noise.mask_offsets_hz"
    "phase_noise.mask_levels_dbchz"
    "iq_and_lo_leakage.calibration_source"
    "pa.coefficient_provenance"
    "pa.power_restoration_allowed"
    "dpd.training_samples"
    "dpd.holdout_samples"
    "dac.reconstruction_filter_taps"
    "receiver.selectivity_filter_taps"
    "receiver.lna_p1db_input_dbm"
    "receiver.mixer_iip2_dbm"
    "receiver.mixer_iip3_dbm"
    "receiver.agc.attack_coefficient"
    "receiver.adc.aperture_jitter_seconds"
    "measurements.rbw_hz"
    "ul_power_control.pusch"
    "ul_power_control.pucch"
    "ul_power_control.srs"
    "ul_power_control.prach"];
for path=requiredPaths.'
    verifyTrue(t,localHasPath(rf,path),name+" missing rf_frontend."+path);
end
verifyFalse(t,logical(rf.pa.power_restoration_allowed));
verifyTrue(t,logical(rf.ul_power_control.configured_snr_pathloss_forbidden));
end

function found=localHasPath(value,path)
parts=split(string(path),".");
found=true;
for k=1:numel(parts)
    if ~isstruct(value)||~isfield(value,parts(k))
        found=false;
        return;
    end
    value=value.(parts(k));
end
end

function paths=localFieldTree(value,prefix)
paths=strings(0,1);
names=sort(string(fieldnames(value)));
for k=1:numel(names)
    if strlength(prefix)==0
        path=names(k);
    else
        path=prefix+"."+names(k);
    end
    paths(end+1,1)=path; %#ok<AGROW>
    child=value.(names(k));
    if isstruct(child)&&isscalar(child)
        paths=[paths;localFieldTree(child,path)]; %#ok<AGROW>
    end
end
paths=sort(paths);
end

function localCleanup(folder)
if isfolder(folder)
    rmdir(folder,"s");
end
end
