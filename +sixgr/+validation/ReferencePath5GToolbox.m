function out = ReferencePath5GToolbox(kind, varargin)
%REFERENCEPATH5GTOOLBOX Trusted 5G Toolbox-backed reference calculations.

if nargin < 1
    error("sixgr:validation:MissingToolboxReferenceKind", ...
        "ReferencePath5GToolbox requires a reference kind.");
end

kind = lower(strtrim(string(kind)));
out = struct("Available", false, "Value", NaN, "FunctionName", "", "FailureReason", "");

switch kind
    case "tbs_bits"
        out.FunctionName = "nrTBS";
        if exist("nrTBS", "file") ~= 2
            out.FailureReason = "nrTBS_unavailable";
            return;
        end
        try
            [modulation, nLayers, nPrb, nRePerPrb, targetCodeRate, xOverhead, tbScaling] = localTBSArgs(varargin);
            if isnan(double(tbScaling))
                out.Value = nrTBS(char(string(modulation)), double(nLayers), double(nPrb), double(nRePerPrb), double(targetCodeRate), double(xOverhead));
            else
                out.Value = nrTBS(char(string(modulation)), double(nLayers), double(nPrb), double(nRePerPrb), double(targetCodeRate), double(xOverhead), double(tbScaling));
            end
            out.Available = true;
        catch ME
            out.FailureReason = string(ME.identifier);
        end
    otherwise
        error("sixgr:validation:UnknownToolboxReference", ...
            "Unsupported 5G Toolbox reference '%s'.", kind);
end
end

function [modulation, nLayers, nPrb, nRePerPrb, targetCodeRate, xOverhead, tbScaling] = localTBSArgs(args)
defaults = {"QPSK", 1, NaN, NaN, NaN, 0, NaN};
vals = defaults;
for i = 1:min(numel(args), numel(vals))
    vals{i} = args{i};
end
modulation = vals{1};
nLayers = vals{2};
nPrb = vals{3};
nRePerPrb = vals{4};
targetCodeRate = vals{5};
xOverhead = vals{6};
tbScaling = vals{7};
end
