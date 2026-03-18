function lut = BLER_LUT(varargin)
%BLER_LUT Build or normalize SINR->BLER lookup table.
%
% Usage:
%   lut = sixgr.system.BLER_LUT()
%   lut = sixgr.system.BLER_LUT('SNR_dB', -8:2:24, 'BLER', myBler)
%   lut = sixgr.system.BLER_LUT(existingStruct)

if nargin == 1 && isstruct(varargin{1})
    lut = localNormalize(varargin{1});
    return;
end

p = inputParser;
p.addParameter("SNR_dB", (-8:2:24).', @(x) isnumeric(x) && isvector(x));
p.addParameter("BLER", [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
p.addParameter("StrictMode", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});

snr = double(p.Results.SNR_dB(:));
bler = p.Results.BLER;
strictMode = logical(p.Results.StrictMode);

if isempty(bler)
    if strictMode
        error("sixgr:system:BLER_LUT:StrictFallbackForbidden", ...
            "Strict mode forbids synthetic BLER LUT fallback.");
    end
    % Smooth baseline mapping used when no calibrated LUT is provided.
    bler = 0.5 .* erfc((snr - 3) ./ 5);
else
    bler = double(bler(:));
end

if numel(bler) ~= numel(snr)
    error("sixgr:system:BLER_LUT:SizeMismatch","SNR_dB and BLER vectors must have equal length.");
end

lut = struct();
lut.SNR_dB = snr;
lut.BLER = max(1e-4, min(0.9999, bler));
lut.Source = "default";
lut = localNormalize(lut);
end

function lut = localNormalize(lut)
if ~isfield(lut, "SNR_dB") || ~isfield(lut, "BLER")
    error("sixgr:system:BLER_LUT:MissingFields","LUT requires SNR_dB and BLER.");
end
snr = double(lut.SNR_dB(:));
bler = double(lut.BLER(:));
if numel(snr) ~= numel(bler)
    error("sixgr:system:BLER_LUT:SizeMismatch","SNR_dB and BLER vectors must match.");
end
[snr, idx] = sort(snr, "ascend");
bler = bler(idx);
bler = max(1e-4, min(0.9999, bler));

lut.SNR_dB = snr;
lut.BLER = bler;
if ~isfield(lut, "Source")
    lut.Source = "custom";
end
end
