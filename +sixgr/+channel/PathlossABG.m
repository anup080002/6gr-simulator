function pl_dB = PathlossABG(d_m, fc_Hz, coeffs, varargin)
% sixgr.channel.PathlossABG
%
% ABG pathloss model (useful for FR3 studies):
%   PL(dB) = 10*alpha*log10(d/d0) + beta + 10*gamma*log10(fc_GHz) + Xsf
%
% Inputs:
%   d_m     : distance (m), scalar or vector
%   fc_Hz   : carrier frequency (Hz)
%   coeffs  : struct with fields alpha,beta,gamma,shadowSigma_dB,d0_m
%
% Name-value:
%   "Stream" : RandStream for reproducible shadowing
%
% Notes:
%   - This is a generic ABG evaluator. For strict 3GPP compliance you must
%     set coefficients according to the scenario and frequency range.
%   - ASCII-only file.
%
% Example:
%   c = struct("alpha",3.5,"beta",20,"gamma",2,"shadowSigma_dB",4,"d0_m",1);
%   pl = sixgr.channel.PathlossABG(100,3.5e9,c);

opt.Stream = [];
if mod(numel(varargin),2) ~= 0
    error("PathlossABG:BadNV","Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    val  = varargin{i+1};
    switch lower(name)
        case "stream"
            opt.Stream = val;
        otherwise
            error("PathlossABG:UnknownOpt","Unknown option: %s", name);
    end
end

d_m = double(d_m(:));
fc_Hz = double(fc_Hz);

if ~isstruct(coeffs)
    error("PathlossABG:BadCoeffs","coeffs must be a struct.");
end

alpha = localGet(coeffs,"alpha",3.5);
beta  = localGet(coeffs,"beta",20);
gamma = localGet(coeffs,"gamma",2.0);
sigSF = localGet(coeffs,"shadowSigma_dB",0.0);
d0    = localGet(coeffs,"d0_m",1.0);

fc_GHz = fc_Hz/1e9;
d_eff = max(d_m, d0);

pl_det = 10*alpha*log10(d_eff./d0) + beta + 10*gamma*log10(fc_GHz);

% Shadowing
if sigSF > 0
    if isempty(opt.Stream)
        sf = sigSF .* randn(size(d_eff));
    else
        sf = sigSF .* randn(opt.Stream, size(d_eff));
    end
else
    sf = zeros(size(d_eff));
end

pl_dB = pl_det + sf;
pl_dB = reshape(pl_dB, size(d_m));

end

function v = localGet(s, f, d)
if isfield(s,f)
    v = double(s.(f));
else
    v = double(d);
end
end
