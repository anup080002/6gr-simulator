function spec = resolveMultiUserSpec(cfg)
%RESOLVEMULTIUSERSPEC Resolve the waveform runner's complete user specification.
% Mechanical extraction of runWaveformLinkBundle.localResolveMultiUserSpec.
% Resolved cfg.lls6g.users remains the authority. Existing legacy defaults,
% count normalization and the missing_from_config beam-policy sentinel are
% unchanged; this adapter neither selects a beam nor executes a waveform.
userCfg = sixgr.util.structGet(cfg, "lls6g.users", struct());
hasUsersCfg = isstruct(userCfg) && isscalar(userCfg) && ~isempty(fieldnames(userCfg));
if hasUsersCfg
    numUsers = max(1, round(double(sixgr.util.structGet(userCfg, "n_users", 1))));
    enabled = logical(sixgr.util.structGet(userCfg, "enabled", false)) || numUsers > 1;
else
    numUsers = 1;
    enabled = false;
end
spec = struct();
spec.Enabled = enabled;
spec.NumUsers = numUsers;
spec.RNTIStart = max(1, round(double(sixgr.util.structGet(userCfg, "rnti_start", 1))));
spec.SeedStride = max(1, round(double(sixgr.util.structGet(userCfg, "seed_stride", 101))));
spec.ExecutionModel = string(sixgr.util.structGet(userCfg, "execution_model", "independent_link_sweep"));
spec.BeamSelectionStrategy = lower(string(sixgr.util.structGet(userCfg, "beam_selection_strategy", "")));
if strlength(strtrim(spec.BeamSelectionStrategy)) == 0
    spec.BeamSelectionStrategy = "missing_from_config";
end
spec.SaveUserTables = logical(sixgr.util.structGet(userCfg, "save_user_tables", true));
end
