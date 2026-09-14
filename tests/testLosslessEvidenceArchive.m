function ok=testLosslessEvidenceArchive()
% Declared byte fixtures only; neither an RF trial nor qualification.
runtime=sixgr.lls6g.config.ensureYAMLRuntime('RequireYAML',true,'ConfigurePyEnv',true);
script=fullfile(pwd,'scripts','tests','test_lossless_evidence_archive.py');
[status,output]=system(sprintf('"%s" "%s"',runtime.PythonExecutable,script));
fprintf('%s\n',output);
assert(status==0,'test:LosslessEvidenceArchive', ...
    'Archive tests failed. The selected Python must have PyYAML and zstandard installed; no fallback is permitted.');
ok=true;
disp('LOSSLESS_EVIDENCE_ARCHIVE_PASS: declared fixtures, exact bytes and fail-closed restoration; RF episodes=0.');
end
