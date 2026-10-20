function weighted=applyMMSECSIWeighting(codeword,csi)
% Preserve nrEqualizeMMSE's absolute per-symbol reliability for QPSK LLRs.
% nrPDCCHDecode uses the estimated pre-equalization noise variance; native
% MMSE CSI converts those soft bits to the equalized observation reliability.
% Dividing CSI by its mean destroys common signal/noise gain invariance.
% Each QPSK symbol owns exactly two consecutive soft bits. Do not normalize,
% clip, replicate a short vector, drop invalid REs, or silently skip weighting.
id='sixgr:phy:pdcch:InvalidMMSECSIWeighting';
assert(isfloat(codeword)&&isreal(codeword)&&isvector(codeword)&&~isempty(codeword)&& ...
    all(isfinite(codeword(:))) && isfloat(csi)&&isreal(csi)&&isvector(csi)&& ...
    ~isempty(csi)&&all(isfinite(csi(:)))&&all(csi(:)>=0)&&numel(codeword)==2*numel(csi), ...
    id,'Require finite real QPSK LLRs and one nonnegative native MMSE CSI weight per symbol.');
weights=cast(repelem(csi(:),2),'like',codeword);
weighted=reshape(codeword(:).*weights(:),size(codeword));
assert(all(isfinite(weighted(:))),id,'CSI weighting overflowed; do not publish or decode invalid LLRs.');
end
