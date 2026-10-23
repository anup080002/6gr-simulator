function [coherence,evidence]=receivedCPTimingCoherence(carrier,waveform,offsets)
%RECEIVEDCPTIMINGCOHERENCE Independent OFDM-boundary evidence from RX samples.
% For each candidate slot start, compare each actual CP with its Nfft-later
% copy. Squared normalized correlation is invariant to gain and constant CFO.
% A sparse/CDM pilot correlation can have large comb aliases outside the CP;
% these hypotheses do not preserve the received OFDM symbol boundaries.
% No channel, transmitted samples, injected delay or assumed CFO enters this
% receiver calculation. This estimator is not prescribed by 3GPP.
arguments
    carrier (1,1) nrCarrierConfig
    waveform {mustBeNumeric,mustBeFinite,mustBeNonempty}
    offsets {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBeNonnegative}
end
assert(ismatrix(waveform) && isfloat(waveform) && ~issparse(waveform) && ...
    isvector(offsets) && ~isempty(offsets), ...
    'sixgr:phy:sync:InvalidCPTimingObservation','Use actual RX samples and nonempty candidate offsets.');
info=nrOFDMInfo(carrier);
localSlot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
positions=localSlot*double(carrier.SymbolsPerSlot)+(1:double(carrier.SymbolsPerSlot));
prefix=double(info.CyclicPrefixLengths(positions));
nfft=double(info.Nfft); count=sum(prefix+nfft); offsets=double(offsets(:));
assert(size(waveform,1)>=count+max(offsets), ...
    'sixgr:phy:sync:IncompleteCPTimingObservation', ...
    'Every timing hypothesis must contain a complete actual received slot.');
x=double(waveform);
first=x(1:end-nfft,:); second=x(nfft+1:end,:);
% Prefix sums avoid extracting a complete slot for every hypothesis. They
% retain every actual CP/tail pair; there is no decimation or proxy waveform.
cross=[complex(0);cumsum(sum(conj(first).*second,2))];
firstPower=[0;cumsum(sum(abs(first).^2,2))];
secondPower=[0;cumsum(sum(abs(second).^2,2))];
c=complex(zeros(size(offsets))); a=zeros(size(offsets)); b=a; start=0;
for lengthCP=prefix(:).'
    lo=offsets+start+1; hi=lo+lengthCP;
    c=c+cross(hi)-cross(lo);
    a=a+firstPower(hi)-firstPower(lo);
    b=b+secondPower(hi)-secondPower(lo);
    start=start+nfft+lengthCP;
end
coherence=zeros(size(offsets)); valid=a>0 & b>0;
coherence(valid)=min(1,abs(c(valid)./sqrt(a(valid))./sqrt(b(valid))).^2);
evidence=struct('Method',"received_full_slot_cp_tail_normalized_coherence_squared", ...
    'Nfft',nfft,'CyclicPrefixLengths',prefix,'NumSymbols',numel(prefix), ...
    'SamplePairCount',sum(prefix)*size(waveform,2), ...
    'HypothesisCount',numel(offsets),'OracleTimingUsed',false, ...
    'ReceiverZeroPaddingUsed',false,'InputSampleCount',size(waveform,1));
end
