function ok = testParallelPBCHArtifactIsolation()
%TESTPARALLELPBCHARTIFACTISOLATION Parallel UE trials never share writers.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
sourcePath = fullfile(pwd, "+sixgr", "+truth", ...
    "runWaveformLinkBundle.m");
source = string(fileread(sourcePath));
startToken = "function T = localCollectPBCHTrials";
endToken = "function tf = localStructLogical";
startIndex = strfind(source, startToken);
endIndex = strfind(source, endToken);
assert(numel(startIndex) == 1 && ~isempty(endIndex) && ...
    endIndex(1) > startIndex(1), ...
    "Unable to isolate the production PBCH trial collector.");
collector = extractBetween(source, startIndex(1), endIndex(1) - 1);
assert(contains(collector, '"WriteArtifacts", false'), ...
    "Coupled PBCH trials must explicitly disable shared artifact writes.");
assert(~contains(collector, '"WriteArtifacts", true'), ...
    "Parallel/coupled PBCH trials must never write shared SIB1 artifacts.");

anchorStart = strfind(source, "function cres = localRunBundleAnchorCase");
anchorEnd = strfind(source, "function row = localMakeBundleAnchorKpiRow");
assert(numel(anchorStart) == 1 && ~isempty(anchorEnd) && ...
    anchorEnd(1) > anchorStart(1), ...
    "Unable to isolate the serial bundle-anchor publisher.");
anchor = extractBetween(source, anchorStart(1), anchorEnd(1) - 1);
assert(contains(anchor, '"RunId", "sib1_anchor_waveform", "WriteArtifacts", true'), ...
    "The serial normalized bundle anchor must remain the SIB1 artifact owner.");
ok = true;
fprintf("PASS testParallelPBCHArtifactIsolation: coupled UE trials are in-memory; serial anchor owns SIB1 publication.\n");
end
