function ok=testChannelCyclicPrefixSupport()
% Exact CP support contract, including tiny tails and variable CP lengths.
filters=zeros(17,2); filters([1 8 17],1)=[1e-14 1 1e-14];
a=sixgr.phy.waveform.channelCyclicPrefixSupport(filters,7,[11 9],.5);
assert(a.EarliestRelativeFilterTap_samples==-7 && a.LatestRelativeFilterTap_samples==9);
assert(~a.CircularConvolutionSupported && ~any(a.CircularConvolutionSupportedPerSymbol));
assert(~a.ResidualISIICIIncluded && ~a.StatisticalCalibrationQualified);
assert(isequal(a.RequiredPreviousSymbolSamples,[4 5]) && ...
    isequal(a.RequiredFollowingSymbolSamples,[1 2]), ...
    'Exact support must expose both preceding and following symbol dependencies.');
b=sixgr.phy.waveform.channelCyclicPrefixSupport(filters,7,[18 36],.5);
assert(b.CircularConvolutionSupported && all(b.CircularConvolutionSupportedPerSymbol));
assert(all(b.RequiredPreviousSymbolSamples==0) && all(b.RequiredFollowingSymbolSamples==0));
c=sixgr.phy.waveform.channelCyclicPrefixSupport(filters,7,[18 9],.5);
assert(isequal(c.CircularConvolutionSupportedPerSymbol,[true false]));
d=sixgr.phy.waveform.channelCyclicPrefixSupport(filters,7,36,.25);
assert(d.CircularConvolutionSupported);
filters(18,2)=realmin; % Even the smallest representable tail remains physical.
e=sixgr.phy.waveform.channelCyclicPrefixSupport(filters,7,18,.5);
assert(~e.CircularConvolutionSupported && e.LatestRelativeFilterTap_samples==10);
f=sixgr.phy.waveform.channelCyclicPrefixSupport(1,0,[9 11],.5);
assert(f.CircularConvolutionSupported);
fprintf('CHANNEL_CP_SUPPORT_PASS no_tail_truncation=1 no_qualification_claim=1\n');
ok=true;
end
