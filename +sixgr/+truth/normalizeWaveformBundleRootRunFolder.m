function rootRunFolder = normalizeWaveformBundleRootRunFolder(runFolder)
%NORMALIZEWAVEFORMBUNDLEROOTRUNFOLDER Resolve one canonical run root.
%
% Live publishers can be called with the run root, a domain root such as
% air_interface, or a nested publication directory.  Collapse only known
% result-layout suffixes so live_stage_status.csv is always written to
% <run>/reports/csv and never to a nested legacy mirror.

runFolder = string(runFolder);
if ~isscalar(runFolder)
    error("sixgr:truth:InvalidWaveformBundleRunFolder", ...
        "Waveform-bundle publication requires one scalar run-folder path.");
end
rootRunFolder = char(regexprep(runFolder, '[\\/]+$', ''));
if strlength(string(rootRunFolder)) == 0
    return;
end

containerLeaves = ["csv","mat","image","logs","profiling","detailed","reports"];
domainLeaves = ["air_interface","beamforming","control","harq","meta", ...
    "reports","rf","system","packet_flow"];

while true
    [parent, leaf] = fileparts(rootRunFolder);
    if strlength(string(leaf)) == 0 || strcmp(parent, rootRunFolder)
        break;
    end
    leafToken = lower(string(leaf));
    if any(leafToken == containerLeaves)
        rootRunFolder = parent;
        continue;
    end
    if any(leafToken == domainLeaves)
        rootRunFolder = parent;
    end
    break;
end
end
