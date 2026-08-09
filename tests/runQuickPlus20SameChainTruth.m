function out = runQuickPlus20SameChainTruth(outputRoot, runTag)
%RUNQUICKPLUS20SAMECHAINTRUTH Execute the bounded +20 dB truth gate.
%
% The quick YAML keeps the production PHY/control feature surface enabled.
% It reduces only coupled slots, seeds, profiler/MAT capture, and separate
% high-trial statistical qualification campaigns. Its result is therefore
% a functional same-chain diagnostic, never a publication qualification.

if nargin < 1 || strlength(strtrim(string(outputRoot))) == 0
    outputRoot = fullfile(pwd, "results");
end
if nargin < 2 || strlength(strtrim(string(runTag))) == 0
    runTag = "phase25_plus20_quick_same_chain_truth";
end
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_plus20_64x4_mu_mimo_quick_truth.yaml");
out = runFullSINRSameChainSweep(outputRoot, runTag, 20, "", scenarioPath);
end
