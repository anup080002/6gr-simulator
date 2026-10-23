function ok = testEffectiveRunnerProfileAuthority()
% Pure routing equivalence, not execution or physical qualification.
setup6GRSimToolkit('Verbose',false);
authoredNames=["pbch_required","prach_required","pdcch_required", ...
    "srs_required","trs_required"];
runtimeNames=["pbchRequired","prachRequired","pdcchRequired", ...
    "srsRequired","trsRequired"];
count=0;
for requested=["waveform_bundle","system_level_lls","generic_sweep","ai_benchmark"]
    for model=["slot_coupled_truth","independent_link_sweep"]
        for mask=0:31
            s=struct('scenario',struct('runner_profile',requested), ...
                'users',struct('enabled',true,'n_users',1,'execution_model',model), ...
                'control_gating',struct());
            cfg=struct('lls6g',struct('users',s.users), ...
                'run',struct('controlGating',struct()));
            for k=1:numel(authoredNames)
                active=logical(bitget(mask,k));
                s.control_gating.(authoredNames(k))=active;
                cfg.run.controlGating.(runtimeNames(k))=active;
            end
            expected=requested;
            promoted=requested=="system_level_lls" && ...
                model=="slot_coupled_truth" && mask~=0;
            if promoted, expected="waveform_bundle"; end
            [preflight,preflightAuthority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(s);
            [dispatch,dispatchAuthority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg,requested);
            assert(preflight==expected && dispatch==expected && ...
                isequaln(preflightAuthority,dispatchAuthority) && ...
                dispatchAuthority.Promoted==promoted && ...
                dispatchAuthority.SharedWaveformOwner== ...
                    (expected=="waveform_bundle" && model=="slot_coupled_truth"));
            % Audit policy cannot alter ordinary dispatch, enabled or off.
            s.kpi_spec.csi_selection_quality.enabled=false;
            assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg,requested)==expected);
            s.kpi_spec.csi_selection_quality.enabled=true;
            assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg,requested)==expected);
            count=count+1;
        end
    end
end
% Runtime false/missing gates must not resurrect authored true gates.
s.scenario.runner_profile="system_level_lls";
s.users.execution_model="slot_coupled_truth";
s.control_gating.pbch_required=true;
cfg.lls6g.users=s.users;
for name=runtimeNames, cfg.run.controlGating.(name)=false; end
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s)=="waveform_bundle");
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg,"")=="system_level_lls");
cfg.run=struct();
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg,"")=="system_level_lls");
% The old rule used exactly these five gates, not PUCCH/PUSCH-UCI alone.
for name=authoredNames, s.control_gating.(name)=false; end
s.control_gating.pucch_required=true;
s.control_gating.pusch_uci_required=true;
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s)=="system_level_lls");
cfg.run.controlGating=struct('pucchRequired',true,'puschUCIRequired',true);
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg)=="system_level_lls");
% Explicit caller profile and runtime model retain their prior precedence.
cfg.run.controlGating.pbchRequired=true;
cfg.lls6g.users.execution_model="independent_link_sweep";
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg,"")=="system_level_lls");
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg," WAVEFORM_BUNDLE ")=="waveform_bundle");
cfg.lls6g.users=s.users;
cfg.lls6g.users.enabled=false;
[profile,authority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg);
assert(profile=="waveform_bundle" && authority.Promoted && ~authority.SharedWaveformOwner);
cfg.lls6g.users.n_users=2;
[~,authority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg);
assert(authority.SharedWaveformOwner,'The existing count>1 shared-owner rule must remain intact.');
% Extracting routing must not coerce an ordinary profile or invent one.
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(struct())=="");
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,cfg," AI_BENCHMARK ")=="ai_benchmark");
% buildInternalConfig has mapped the gates before installing lls6g.users.
% That stage must use the same resolved user authority, without mutating it.
buildStage=rmfield(cfg,'lls6g');
before=s;
[profile,authority]=sixgr.lls6g.config.resolveEffectiveRunnerProfile(s,buildStage);
assert(profile=="waveform_bundle" && authority.SharedWaveformOwner && isequaln(s,before));
object=sixgr.lls6g.config.ScenarioConfig(s);
assert(sixgr.lls6g.config.resolveEffectiveRunnerProfile(object,buildStage)==profile);
ok=true;
fprintf('EFFECTIVE_RUNNER_AUTHORITY_PASS equivalent_routes=%d no_waveforms=1\n',count);
end
