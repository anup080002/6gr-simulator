function out = unavailableArtifactPath(filePath)
%UNAVAILABLEARTIFACTPATH Return the explicit unavailable-card path for a plot.

filePath = string(filePath);
[folder, name] = fileparts(filePath);
if endsWith(name, "_unavailable")
    out = fullfile(folder, name + ".svg");
else
    out = fullfile(folder, name + "_unavailable.svg");
end
out = string(out);
end
