function [symbols,info]=transformPrecode(input,mrb)
%TRANSFORMPRECODE Compatibility facade for the canonical unitary DFT.
if nargin<2 || ~isscalar(mrb) || ~isfinite(mrb) || mrb<1 || mrb~=fix(mrb)
    error("sixgr:phy:transformPrecode:BadMRB","MRB must be a positive integer.");
end
m=12*double(mrb);
symbols=sixgr.phy.waveform.UnitaryDFTSpreader.apply(input,m);
info=struct("EngineUsed","canonical_unitary_dft","mrb",double(mrb), ...
    "nSC",m,"Normalization","unitary");
end
