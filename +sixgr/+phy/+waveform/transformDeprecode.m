function [symbols,info]=transformDeprecode(input,mrb)
%TRANSFORMDEPRECODE Compatibility facade for canonical inverse unitary DFT.
if nargin<2 || ~isscalar(mrb) || ~isfinite(mrb) || mrb<1 || mrb~=fix(mrb)
    error("sixgr:phy:transformDeprecode:BadMRB","MRB must be a positive integer.");
end
m=12*double(mrb);
symbols=sixgr.phy.waveform.UnitaryDFTDespreader.apply(input,m);
info=struct("EngineUsed","canonical_inverse_unitary_dft","mrb",double(mrb), ...
    "nSC",m,"Normalization","unitary");
end
