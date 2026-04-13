files = {
'+sixgr/+link/applyWaveformImpairments.m'
'+sixgr/+link/runDLPDSCHThroughput.m'
'+sixgr/+link/runULPUSCHThroughput.m'
'+sixgr/+truth/CoupledTruthRuntime.m'
'+sixgr/+truth/runWaveformLinkBundle.m'
'+sixgr/+truth/buildGrantPHYJob.m'
'+sixgr/+truth/executeGrantPHYJob.m'
'+sixgr/+truth/exportLLSLiveDerivedTables.m'
'+sixgr/+truth/exportLLSLiveSignalChainTables.m'
'+sixgr/+lls6g/buildInternalConfig.m'
};
for i = 1:numel(files)
    f = files{i};
    fprintf('CHECKCODE %s\n', f);
    try
        issues = checkcode(f, '-id');
        if isempty(issues)
            fprintf('OK %s\n', f);
        else
            for k = 1:numel(issues)
                fprintf('%s:%d:%d %s %s\n', f, issues(k).line, issues(k).column, issues(k).id, issues(k).message);
            end
        end
    catch ME
        fprintf('CHECKCODE_ERROR %s :: %s\n', f, ME.message);
    end
end