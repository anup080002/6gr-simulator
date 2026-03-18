function [tpSym, info] = transformPrecode(modSym, mrb)
%TRANSFORMPRECODE DFT-s-OFDM transform precoding wrapper.
%
%   [TPSYM,INFO] = sixgr.phy.waveform.transformPrecode(MODSYM, MRB)
%   applies NR transform precoding (DFT) across each column of MODSYM, where
%   MRB is the number of allocated resource blocks for the transmission.
%
%   This wrapper calls nrTransformPrecode (5G Toolbox).
%
%   Requirements:
%     size(MODSYM,1) must be a multiple of (MRB*12).

if nargin < 2
    error("sixgr:phy:transformPrecode:MissingArgs", "Provide MODSYM and MRB.");
end
if ~(isscalar(mrb) && isnumeric(mrb) && isfinite(mrb) && mrb >= 1)
    error("sixgr:phy:transformPrecode:BadMRB", "MRB must be a positive scalar.");
end
mrb = double(mrb);

if exist("nrTransformPrecode","file") ~= 2
    error("sixgr:phy:transformPrecode:Missing5G", "nrTransformPrecode not found (5G Toolbox required).");
end

nSC = mrb*12;
if rem(size(modSym,1), nSC) ~= 0
    error("sixgr:phy:transformPrecode:LenMismatch", ...
        "Number of input symbols per layer (%d) must be a multiple of MRB*12=%d.", size(modSym,1), nSC);
end

tpSym = nrTransformPrecode(modSym, mrb);

info = struct();
info.EngineUsed = "nrTransformPrecode";
info.mrb = mrb;
info.nSC = nSC;

end
