function ok = testRepoProxyFileStateIntegrity()
%TESTREPOPROXYFILESTATEINTEGRITY Guard proxy backend removal against Git-state drift.

setup6GRSimToolkit("Verbose", false);
repoRoot = string(fileparts(which("setup6GRSimToolkit")));

removedProxyFiles = [ ...
    "+sixgr/+system/AbstractPHY.m"; ...
    "+sixgr/+system/BLER_DB.m"; ...
    "+sixgr/+system/BLER_LUT.m"; ...
    "+sixgr/+hybrid/CalibrateBLER.m"; ...
    "+sixgr/+hybrid/End2EndOrchestrator.m"; ...
    "+sixgr/+hybrid/ExportCalibrationArtifacts.m"; ...
    "+sixgr/+hybrid/HybridRunner.m" ...
    ];

for i = 1:numel(removedProxyFiles)
    filePath = fullfile(repoRoot, strrep(char(removedProxyFiles(i)), "/", filesep));
    assert(exist(filePath, "file") == 0, ...
        "Removed proxy/hybrid backend source is present in the active repo: %s", removedProxyFiles(i));
end

statusLines = localGitStatus(repoRoot, removedProxyFiles);
for i = 1:numel(removedProxyFiles)
    target = removedProxyFiles(i);
    targetLines = statusLines(endsWith(statusLines, target));
    hasTrackedDeletion = any(startsWith(targetLines, "1 D.") | startsWith(targetLines, "1 .D"));
    hasStagedDeletion = any(startsWith(targetLines, "1 D."));
    hasUnstagedDeletion = any(startsWith(targetLines, "1 .D"));
    hasUntracked = any(startsWith(targetLines, "? "));
    hasUnexpectedState = any(~(startsWith(targetLines, "1 D.") | startsWith(targetLines, "1 .D") | startsWith(targetLines, "? ")));

    assert(~(hasTrackedDeletion && hasUntracked), ...
        "Proxy/hybrid backend file is both deleted and untracked, which is ambiguous: %s", target);
    assert(~hasUntracked, ...
        "Removed proxy/hybrid backend source is present as an untracked file: %s", target);
    assert(~hasUnstagedDeletion, ...
        "Removed proxy/hybrid backend deletion is unstaged, which leaves index/worktree drift: %s", target);
    assert(~hasUnexpectedState, ...
        "Removed proxy/hybrid backend file has an unexpected Git state: %s -> %s", ...
        target, strjoin(cellstr(targetLines), " | "));

    if ~isempty(targetLines)
        assert(hasStagedDeletion, ...
            "Removed proxy/hybrid backend file must be either staged for removal or absent from Git status: %s", target);
    end
end

untrackedFiles = localGitUntrackedFiles(repoRoot);
backendLikeUntracked = untrackedFiles(localContainsAny(lower(untrackedFiles), [ ...
    "abstractphy", "bler_db", "bler_lut", "hybridrunner", "calibratebler", ...
    "exportcalibrationartifacts", "end2endorchestrator"]));
assert(isempty(backendLikeUntracked), ...
    "Proxy/hybrid backend source is present as an untracked file: %s", ...
    strjoin(cellstr(backendLikeUntracked), " | "));

proxyNamedUntracked = untrackedFiles(startsWith(untrackedFiles, "+sixgr/") & ...
    contains(lower(untrackedFiles), "proxy"));
allowedProxyNamed = "+sixgr/+link/deriveDecoderTruthProxySINR.m";
unexpectedProxyNamed = setdiff(proxyNamedUntracked, allowedProxyNamed, "stable");
assert(isempty(unexpectedProxyNamed), ...
    "Unexpected untracked proxy-named source under +sixgr: %s", ...
    strjoin(cellstr(unexpectedProxyNamed), " | "));
if any(proxyNamedUntracked == allowedProxyNamed)
    helperPath = fullfile(repoRoot, strrep(char(allowedProxyNamed), "/", filesep));
    helperText = string(fileread(helperPath));
    assert(contains(helperText, "post_equalization_evm_proxy") && ...
        contains(helperText, "not a") && contains(helperText, "decoder-truth SINR measurement"), ...
        "Allowed proxy-named SINR helper must remain explicitly labeled as a non-truth proxy.");
    assert(~contains(helperText, "BLER_LUT") && ~contains(helperText, "BLER_DB") && ...
        ~contains(helperText, "AbstractPHY") && ~contains(helperText, "PhyFactory.create"), ...
        "Allowed proxy-named SINR helper must not contain backend/proxy PHY implementation hooks.");
end

ok = true;
end

function lines = localGitStatus(repoRoot, targets)
cmd = "git -C " + localCmdQuote(repoRoot) + ...
    " status --porcelain=v2 --untracked-files=all -- " + ...
    strjoin(arrayfun(@localCmdQuote, targets, "UniformOutput", false), " ");
[status, raw] = system(char(cmd));
assert(status == 0, "Unable to inspect Git proxy file state: %s", string(raw));
lines = string(splitlines(string(raw)));
lines = lines(strlength(strtrim(lines)) > 0);
end

function files = localGitUntrackedFiles(repoRoot)
cmd = "git -C " + localCmdQuote(repoRoot) + " ls-files --others --exclude-standard";
[status, raw] = system(char(cmd));
assert(status == 0, "Unable to inspect untracked Git files: %s", string(raw));
files = string(splitlines(string(raw)));
files = files(strlength(strtrim(files)) > 0);
files = strrep(files, "\", "/");
end

function mask = localContainsAny(values, tokens)
values = string(values(:));
tokens = string(tokens(:));
mask = false(size(values));
for i = 1:numel(tokens)
    mask = mask | contains(values, tokens(i));
end
end

function quoted = localCmdQuote(value)
text = char(string(value));
text = strrep(text, '"', '\"');
quoted = ['"' text '"'];
end
