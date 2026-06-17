function summary = run_full_study(configPath, outputRoot, runTag, varargin)
%RUN_FULL_STUDY Front-door wrapper for the actual mobile-2UE study.

summary = run_mobile_2ue_study(configPath, outputRoot, runTag, varargin{:});
pointerPath = char(summary.PointerPath);
sixgr.util.ensureDir(pointerPath);
fid = fopen(pointerPath, "w");
if fid >= 0
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, "%s\n", char(string(summary.RunFolder)));
end
disp(jsonencode(summary));
end
