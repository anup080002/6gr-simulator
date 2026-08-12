function y = applyLinearDelay(x,delaySamples)
%APPLYLINEARDELAY Apply a non-circular time-domain propagation delay.
%
% Integer delays use exact zero-prefix/truncation. Fractional delays use a
% windowed-sinc interpolator with zero extension. The operator is linear,
% so a delay beyond CP transfers preceding-symbol samples into the FFT window.

arguments
    x {mustBeNumeric}
    delaySamples (1,1) double {mustBeFinite,mustBeNonnegative}
end
if isempty(x), y=x; return; end
wasRow=isrow(x); if wasRow, x=x.'; end
nSamples=size(x,1); integerDelay=floor(delaySamples);
fraction=delaySamples-integerDelay;
if integerDelay>=nSamples
    y=zeros(size(x),'like',x);
elseif fraction<=32*eps(max(1,delaySamples))
    y=[zeros(integerDelay,size(x,2),'like',x);x(1:nSamples-integerDelay,:)];
else
    halfLength=64; tapIndex=(-halfLength:halfLength).';
    h=sinc(tapIndex-fraction).*kaiser(2*halfLength+1,10); h=h/sum(h);
    filtered=conv2(x,h,'full');
    fractional=filtered(halfLength+1:halfLength+nSamples,:);
    y=[zeros(integerDelay,size(x,2),'like',x);fractional(1:nSamples-integerDelay,:)];
end
if wasRow, y=y.'; end
end
