function out = runQuickPlus20WiringGate(outputRoot, runTag)
%RUNQUICKPLUS20WIRINGGATE Execute the minimal two-UE 2x2 same-chain gate.

if nargin < 1 || strlength(strtrim(string(outputRoot))) == 0
    outputRoot = fullfile(pwd, "results");
end
if nargin < 2 || strlength(strtrim(string(runTag))) == 0
    runTag = "phase26_plus20_2x2_mu_mimo_wiring_gate";
end
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_plus20_2x2_mu_mimo_wiring_gate.yaml");
out = runFullSINRSameChainSweep(outputRoot, runTag, 20, "", scenarioPath);
end
