function [nVarGrid, info] = convertNoiseVarianceToGridDomain(nVarIn, ofdmInfo, varargin)
%CONVERTNOISEVARIANCETOGRIDDOMAIN Convert noise variance with calibrated OFDM gain.
%
%   NGRID = sixgr.phy.waveform.convertNoiseVarianceToGridDomain(NTIME, INFO)
%   uses INFO.SampleToGridNoiseVarianceGain, produced by the OFDM wrappers,
%   to convert sample-domain complex noise variance into occupied-RE
%   resource-grid variance. Grid/frequency-domain inputs are passed through.

ip = inputParser;
ip.addParameter("InputDomain", "auto", @(x) ischar(x) || isstring(x));
ip.addParameter("Source", "runtime_metadata", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

domain = lower(strtrim(string(opt.InputDomain)));
if strlength(domain) == 0
    domain = "auto";
end

if any(domain == ["grid", "frequency", "resource_grid", "re", "occupied_re"])
    gain = 1;
    outputDomain = "resource_grid_pre_equalization";
    transformSource = "identity_grid_domain_noise_variance";
elseif any(domain == ["time", "sample", "waveform", "sample_domain", "auto"])
    gain = localSampleToGridGain(ofdmInfo);
    outputDomain = "resource_grid_pre_equalization";
    transformSource = "calibrated_ofdm_sample_to_grid_noise_transform";
else
    error("sixgr:phy:waveform:UnsupportedNoiseVarianceDomain", ...
        "Unsupported noise variance domain '%s'.", char(domain));
end

nVarGrid = double(nVarIn) .* gain;
info = struct( ...
    "InputDomain", char(domain), ...
    "OutputDomain", char(outputDomain), ...
    "InputSource", char(string(opt.Source)), ...
    "TransformSource", char(transformSource), ...
    "SampleToGridNoiseVarianceGain", double(gain), ...
    "SampleToGridNoiseVarianceGainSource", char(string(localStructGet(ofdmInfo, "NoiseTransform.SampleToGridNoiseVarianceGainSource", ""))), ...
    "Equation", "sigma_grid2 = SampleToGridNoiseVarianceGain * sigma_input2", ...
    "OFDMNoiseTransformVersion", char(string(localStructGet(ofdmInfo, "NoiseTransform.Version", ""))));
end

function gain = localSampleToGridGain(ofdmInfo)
gain = double(localStructGet(ofdmInfo, "SampleToGridNoiseVarianceGain", NaN));
if ~(isscalar(gain) && isfinite(gain) && gain > 0)
    gain = double(localStructGet(ofdmInfo, "NoiseTransform.SampleToGridNoiseVarianceGain", NaN));
end
if ~(isscalar(gain) && isfinite(gain) && gain > 0)
    error("sixgr:phy:waveform:NoiseTransformUnavailable", ...
        "Sample-domain noise variance conversion requires calibrated OFDM noise-transform metadata.");
end
end

function value = localStructGet(s, dottedName, defaultValue)
value = defaultValue;
if ~(isstruct(s) && ~isempty(fieldnames(s)))
    return;
end
parts = split(string(dottedName), ".");
cur = s;
for ii = 1:numel(parts)
    name = char(parts(ii));
    if isstruct(cur) && isfield(cur, name)
        cur = cur.(name);
    else
        value = defaultValue;
        return;
    end
end
value = cur;
end
