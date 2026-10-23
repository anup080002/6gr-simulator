function [ok,evidence]=testFlatEstimatorScenarioCompatibility()
%TESTFLATESTIMATORSCENARIOCOMPATIBILITY Resolved-config boundary, no PHY.
% These are declared scenario compatibility checks, not receiver-performance
% or static-channel qualification. The executed-observation guard is unchanged.
root=fileparts(fileparts(mfilename('fullpath')));
source=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
originalSource=fileread(source);
loaded=sixgr.lls6g.config.loadScenarioConfig(source);
base=loaded.toStruct();
assert(isequal(base.channels.awgn_beam_failure_recovery_enabled,true), ...
    'test:FlatEstimatorScenarioCompatibility:FixtureEpisode', ...
    'The original fixture must retain its enabled piecewise AWGN episode.');
signals=["srs","trs","csi_rs"];
for signal=signals
    assert(string(sixgr.util.structGet(base,localEstimatorPath(signal),''))== ...
        "nr_channel_estimate", ...
        'test:FlatEstimatorScenarioCompatibility:FixtureEstimator', ...
        'The original episode fixture must use native per-resource estimators.');
end
scratch=tempname;
mkdir(scratch);
cleanup=onCleanup(@()rmdir(scratch,'s')); %#ok<NASGU>
records=struct('Name',{},'Passed',{},'ErrorID',{},'Message',{});
runCase("native_episode",@()localAcceptUnchanged(base));
for signal=signals
    flat=localSetEstimator(base,signal,'flat_static_awgn_ls');
    path=localEstimatorPath(signal);
    runCase(signal+"_flat_episode",@()localRejectStatic(flat,path));

    future=flat;
    future.channels.awgn_beam_failure_start_slot=1000000;
    future.channels.awgn_beam_failure_end_slot_exclusive=1000001;
    runCase(signal+"_future_episode",@()localRejectStatic(future,path));

    equalMatrices=flat;
    equalMatrices.channels.awgn_beam_failure_matrix_dl_real= ...
        equalMatrices.channels.awgn_spatial_matrix_dl_real;
    runCase(signal+"_equal_episode_matrix", ...
        @()localRejectStatic(equalMatrices,path));

    disabled=flat;
    disabled.channels.awgn_beam_failure_recovery_enabled=false;
    runCase(signal+"_static_explicit_false",@()localAcceptUnchanged(disabled));
    absent=disabled;
    absent.channels=rmfield(absent.channels,'awgn_beam_failure_recovery_enabled');
    runCase(signal+"_static_absent_flag",@()localAcceptUnchanged(absent));

    implicit=flat;
    fields={'awgn_spatial_matrix_dl_real','awgn_spatial_matrix_dl_imag', ...
        'awgn_spatial_matrix_policy'};
    for k=1:numel(fields)
        if isfield(implicit.channels,fields{k})
            implicit.channels=rmfield(implicit.channels,fields{k});
        end
    end
    implicit.channels.shared_identity_awgn_enabled=false;
    runCase(signal+"_original_explicit_operator_guard", ...
        @()localRejectUnchanged(implicit, ...
        'sixgr:lls6g:config:FlatEstimatorRequiresExplicitAWGN',strings(0,1)));

    raw=localSetEstimator(struct(),signal,'flat_static_awgn_ls');
    raw.channels=struct('awgn_beam_failure_recovery_enabled',true);
    runCase(signal+"_partial_document",@()localAcceptPartialUnchanged(raw));
    runCase(signal+"_inherited_conflict_and_child_disable", ...
        @()localInherited(source,scratch,signal));
end
allFlat=base;
for signal=signals
    allFlat=localSetEstimator(allFlat,signal,'flat_static_awgn_ls');
end
allFlat.channels.awgn_beam_failure_recovery_enabled=false;
runCase("all_flat_static",@()localAcceptUnchanged(allFlat));
defaults=base;
defaults.reference_signals=rmfield(defaults.reference_signals, ...
    'csi_rs_runtime_channel_estimator');
for signal=["srs","trs"]
    defaults.reference_signals.(signal)=rmfield( ...
        defaults.reference_signals.(signal),'runtime_channel_estimator');
end
runCase("missing_selectors_native_default",@()localAcceptUnchanged(defaults));
assert(isequal(fileread(source),originalSource), ...
    'test:FlatEstimatorScenarioCompatibility:SourceChanged', ...
    'Config validation must not rewrite the original YAML.');
evidence=struct('Scope',"declared_config_compatibility_no_waveform", ...
    'Source',string(source),'SourceConfigHash',string(loaded.ConfigHash), ...
    'PhysicalExecution',false,'Checks',struct2table(records));
ok=all([records.Passed]);
assert(ok,'test:FlatEstimatorScenarioCompatibility:Failed', ...
    '%d of %d config boundary checks failed.',sum(~[records.Passed]),numel(records));
fprintf('FLAT_ESTIMATOR_SCENARIO_COMPATIBILITY_PASS checks=%d no_phy=1\n',numel(records));

    function runCase(name,callback)
        record=struct('Name',string(name),'Passed',false,'ErrorID',"",'Message',"");
        try
            callback();
            record.Passed=true;
        catch ex
            record.ErrorID=string(ex.identifier);
            record.Message=string(ex.message);
            fprintf('FLAT_ESTIMATOR_CONFIG_CASE_FAIL %s %s %s\n', ...
                char(name),ex.identifier,ex.message);
        end
        records(end+1)=record; %#ok<AGROW>
    end
end

function path=localEstimatorPath(signal)
if signal=="csi_rs"
    path="reference_signals.csi_rs_runtime_channel_estimator";
else
    path="reference_signals."+signal+".runtime_channel_estimator";
end
end

function cfg=localSetEstimator(cfg,signal,value)
if signal=="csi_rs"
    cfg.reference_signals.csi_rs_runtime_channel_estimator=value;
else
    cfg.reference_signals.(signal).runtime_channel_estimator=value;
end
end

function localAcceptUnchanged(cfg)
before=cfg;
sixgr.lls6g.config.validateScenarioConfig(cfg,'AllowPartial',false);
assert(isequaln(before,cfg),'Validation must not change the selected estimator or episode.');
end

function localAcceptPartialUnchanged(cfg)
before=cfg;
sixgr.lls6g.config.validateScenarioConfig(cfg,'AllowPartial',true);
assert(isequaln(before,cfg),'Partial validation must not rewrite inherited choices.');
end

function localRejectStatic(cfg,path)
localRejectUnchanged(cfg,'sixgr:lls6g:config:FlatEstimatorRequiresStaticAWGN', ...
    [path;"channels.awgn_beam_failure_recovery_enabled=true"]);
end

function localRejectUnchanged(cfg,expected,tokens)
before=cfg;
localExpectError(@()sixgr.lls6g.config.validateScenarioConfig(cfg, ...
    'AllowPartial',false),expected,tokens);
assert(isequaln(before,cfg),'Rejected configuration must remain unchanged.');
end

function localInherited(source,scratch,signal)
% An invalid resolved parent remains a legal partial document: a leaf can
% explicitly disable the episode before the loader performs compatibility.
bad=localSetEstimator(struct(),signal,'flat_static_awgn_ls');
bad.inherits={source};
localAcceptPartialUnchanged(bad);
badPath=fullfile(scratch,char(signal+"_flat_parent.json"));
localWriteConfig(badPath,bad);
originalBad=fileread(badPath);
localExpectError(@()sixgr.lls6g.config.loadScenarioConfig(badPath), ...
    'sixgr:lls6g:config:FlatEstimatorRequiresStaticAWGN', ...
    [localEstimatorPath(signal);"channels.awgn_beam_failure_recovery_enabled=true"]);
good=struct('inherits',{{badPath}}, ...
    'channels',struct('awgn_beam_failure_recovery_enabled',false));
goodPath=fullfile(scratch,char(signal+"_static_child.json"));
localWriteConfig(goodPath,good);
originalGood=fileread(goodPath);
loaded=sixgr.lls6g.config.loadScenarioConfig(goodPath);
actual=loaded.toStruct();
assert(isequal(actual.channels.awgn_beam_failure_recovery_enabled,false));
assert(string(sixgr.util.structGet(actual,localEstimatorPath(signal),''))== ...
    "flat_static_awgn_ls",'The loader must not silently switch the estimator.');
assert(any(string(loaded.SourceFiles)==string(badPath)) && ...
    any(string(loaded.SourceFiles)==string(goodPath)), ...
    'Both original inherited documents must remain in source provenance.');
assert(isequal(fileread(badPath),originalBad) && isequal(fileread(goodPath),originalGood));
end

function localWriteConfig(path,cfg)
fid=fopen(path,'w');
assert(fid>=0,'test:FlatEstimatorScenarioCompatibility:FixtureWrite', ...
    'Cannot create the temporary config fixture.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(cfg));
end

function localExpectError(callback,expected,tokens)
try
    callback();
catch ex
    assert(strcmp(ex.identifier,expected), ...
        'test:FlatEstimatorScenarioCompatibility:WrongError', ...
        'Expected %s, got %s: %s',expected,ex.identifier,ex.message);
    % contains matches any supplied pattern; an empty pattern set is not
    % an optional-context success. Check each requested token individually.
    for k=1:numel(tokens)
        assert(contains(string(ex.message),tokens(k)), ...
            'test:FlatEstimatorScenarioCompatibility:ErrorContext', ...
            'The rejection must identify the actual selector and episode flag.');
    end
    return;
end
error('test:FlatEstimatorScenarioCompatibility:MissingRejection', ...
    'Expected %s.',expected);
end
