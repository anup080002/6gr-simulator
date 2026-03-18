function [modSym, info] = transformDeprecode(tpSym, mrb)
%TRANSFORMDEPRECODE Inverse DFT-s-OFDM transform precoding wrapper.
%
%   [MODSYM,INFO] = sixgr.phy.waveform.transformDeprecode(TPSYM, MRB)
%   applies NR transform deprecoding across each column of TPSYM.
%
%   This wrapper calls nrTransformDeprecode (5G Toolbox).

if nargin < 2
    error("sixgr:phy:transformDeprecode:MissingArgs", "Provide TPSYM and MRB.");
end
if ~(isscalar(mrb) && isnumeric(mrb) && isfinite(mrb) && mrb >= 1)
    error("sixgr:phy:transformDeprecode:BadMRB", "MRB must be a positive scalar.");
end
mrb = double(mrb);

if exist("nrTransformDeprecode","file") ~= 2
    error("sixgr:phy:transformDeprecode:Missing5G", "nrTransformDeprecode not found (5G Toolbox required).");
end

nSC = mrb*12;
if rem(size(tpSym,1), nSC) ~= 0
    error("sixgr:phy:transformDeprecode:LenMismatch", ...
        "Number of input symbols per layer (%d) must be a multiple of MRB*12=%d.", size(tpSym,1), nSC);
end

modSym = nrTransformDeprecode(tpSym, mrb);

info = struct();
info.EngineUsed = "nrTransformDeprecode";
info.mrb = mrb;
info.nSC = nSC;

end
