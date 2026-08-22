function ok = testLLSLinkAdaptationCSVPlot()
%TESTLLSLINKADAPTATIONCSVPLOT Ensure the raster is derived from persisted CSV.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@()localCleanup(tmp)); %#ok<NASGU>

T = table((1:4).',[-5.1;-4.8;-5.4;-4.9],[NaN;-5.7;-5.2;-4.8], ...
    [NaN;0;1;2],[4;0;0;0],logical([1;0;0;0]),[0;-0.9;-0.8;-0.7], ...
    logical([0;1;0;0]), ...
    'VariableNames',["TrialIndex","PostEqSINRdB", ...
    "LinkAdaptationEffectiveSINRdB","LinkAdaptationSelectedCQI", ...
    "MCSIndex","CRCError","OLLAOffsetDbApplied", ...
    "LinkAdaptationForcedWaveformProbe"]);
T.OLLAFeedbackACK = [NaN;0;1;1];
csvPath = fullfile(tmp,"transport_block_trials.csv");
writetable(T,csvPath);
pngPath = sixgr.lls.plots.plotLinkAdaptationTimeline(csvPath,tmp,"PDSCH");
info = imfinfo(pngPath);
assert(exist(pngPath,"file") == 2 && info.Width >= 1000 && info.Height >= 700, ...
    "Link-adaptation evidence must be a readable report-grade PNG.");
assert(isempty(dir(fullfile(tmp,"*.svg"))), ...
    "Link-adaptation plotting must remain raster-only.");

ok = true;
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
