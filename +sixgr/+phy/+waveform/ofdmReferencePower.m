function [refPower, info] = ofdmReferencePower(x, ofdmInfo, varargin)
%OFDMREFERENCEPOWER Measure signal power against an explicit OFDM reference.
%
%   The time-domain reference excludes cyclic-prefix samples and averages
%   over useful OFDM samples. The grid-domain reference averages over the
%   occupied resource-grid RE returned by nrOFDMDemodulate.

ip = inputParser;
ip.addParameter("Domain", "active_samples", @(v) ischar(v) || isstring(v));
ip.parse(varargin{:});
domain = lower(strtrim(string(ip.Results.Domain)));

if any(domain == ["grid", "occupied_re", "resource_grid"])
    refPower = mean(abs(double(x(:))).^2, "omitnan");
    info = struct( ...
        "ReferenceDomain", "occupied_resource_grid_RE", ...
        "SampleCount", double(numel(x)), ...
        "CyclicPrefixExcluded", false, ...
        "UnusedSubcarriersExcluded", true);
    return;
end

if ~(any(domain == ["active_samples", "time", "useful_samples"]))
    error("sixgr:phy:waveform:UnsupportedReferencePowerDomain", ...
        "Unsupported OFDM reference-power domain '%s'.", char(domain));
end

idx = localUsefulSampleIndices(size(x, 1), ofdmInfo);
if isempty(idx)
    refPower = mean(abs(double(x(:))).^2, "omitnan");
    referenceDomain = "all_waveform_samples_metadata_unavailable";
    cpExcluded = false;
else
    refPower = mean(abs(double(x(idx, :))).^2, "all", "omitnan");
    referenceDomain = "active_samples_excluding_cp";
    cpExcluded = true;
end
info = struct( ...
    "ReferenceDomain", char(referenceDomain), ...
    "SampleCount", double(numel(idx) * max(1, size(x, 2))), ...
    "CyclicPrefixExcluded", logical(cpExcluded), ...
    "UnusedSubcarriersExcluded", false);
end

function idx = localUsefulSampleIndices(nSamples, ofdmInfo)
idx = [];
if nargin < 2 || ~isstruct(ofdmInfo)
    return;
end
nfft = round(double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN)));
cpLens = round(double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", [])));
if ~(isfinite(nfft) && nfft > 0 && ~isempty(cpLens))
    return;
end
offset = 0;
while offset < nSamples
    for s = 1:numel(cpLens)
        cp = max(0, cpLens(s));
        useful = offset + cp + (1:nfft);
        useful = useful(useful <= nSamples);
        idx = [idx, useful]; %#ok<AGROW>
        offset = offset + cp + nfft;
        if offset >= nSamples
            break;
        end
    end
end
idx = idx(:);
end
