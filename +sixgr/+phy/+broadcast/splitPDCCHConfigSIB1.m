function out = splitPDCCHConfigSIB1(value, varargin)
%SPLITPDCCHCONFIGSIB1 Split MIB pdcch-ConfigSIB1 into Type0 CSS indices.
%
% TS 38.331 carries pdcch-ConfigSIB1 as an 8-bit MIB field. TS 38.213
% section 13 uses the four MSBs as controlResourceSetZero and the four LSBs
% as searchSpaceZero.

p = inputParser;
p.addParameter("Source", "pdcch_ConfigSIB1_value", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});

value = round(double(value));
if ~(isscalar(value) && isfinite(value) && value >= 0 && value <= 255)
    error("sixgr:phy:broadcast:InvalidPDCCHConfigSIB1", ...
        "pdcch-ConfigSIB1 must be an integer in [0,255].");
end

out = struct();
out.PDCCHConfigSIB1 = double(value);
out.CORESET0Index = floor(double(value) / 16);
out.SearchSpaceZero = mod(double(value), 16);
out.Source = string(p.Results.Source);
out.ControlResourceSetZeroBitRange = [1 4];
out.SearchSpaceZeroBitRange = [5 8];
end
