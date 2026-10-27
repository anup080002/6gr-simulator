function [grid,alignedHash]=applyCSIRSOriginalOperator(x,c,r,hz)
id='sixgr:truth:CSIRSLinearModelOperator'; f=r.FFTSupport; t=r.Timing;
assert(isa(x,'double')&&~isa(x,'gpuArray')&&strcmp(class(x),string(r.InputClass))&& ...
    size(x,2)==r.NumReceiveChannels&&all(isfinite(x),'all'),id, ...
    'Preserve the original sample class and receive columns.');
offset=t.AppliedTimingCorrectionSamples; n=t.DemodulatedSampleCount;
assert(isnumeric(offset)&&isreal(offset)&&isscalar(offset)&&isfinite(offset)&&offset>=0&&offset==fix(offset)&& ...
    isnumeric(n)&&isreal(n)&&isscalar(n)&&isfinite(n)&&n>0&&n==fix(n)&&offset+n<=size(x,1),id, ...
    'Do not pad or retime the original measured crop.');
if r.Frequency.CFOCorrectionApplied
    rotation=exp(-1i*2*pi*hz*(0:size(x,1)-1).'/double(f.SampleRateHz));
    x=x.*cast(rotation,'like',x);
end
aligned=x(offset+(1:n),:); alignedHash=numericHash(aligned);
grid=nrOFDMDemodulate(c,aligned,'Nfft',double(f.Nfft),'SampleRate',double(f.SampleRateHz), ...
    'CyclicPrefixFraction',double(f.CyclicPrefixFraction));
assert(size(grid,1)==12*c.NSizeGrid&&size(grid,2)==c.SymbolsPerSlot&& ...
    size(grid,3)==r.NumReceiveChannels,id,'Native operator output dimensions differ.');
end

function value=numericHash(x), value=sixgr.phy.waveform.WaveformHash.numeric(x); end
