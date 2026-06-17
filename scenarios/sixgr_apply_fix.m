function [ok, note] = sixgr_apply_fix(fixId, runFolder, inputConfigPath, requestedWorkers)
%SIXGR_APPLY_FIX Apply one safe artifact/reporting fix without altering simulation truth.

ok = false;
note = "unsupported_fix";

switch lower(string(fixId))
    case "materialize_support_artifacts"
        sixgr.trace.TraceArtifactWriter.materializeSupportArtifacts(runFolder, inputConfigPath, requestedWorkers);
        ok = true;
        note = "support artifacts refreshed from existing run outputs";
    otherwise
        ok = false;
        note = "fix_id_not_allowed";
end
end
