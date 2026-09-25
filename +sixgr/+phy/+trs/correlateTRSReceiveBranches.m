function [metric, phase] = correlateTRSReceiveBranches(received, reference)
%CORRELATETRSRECEIVEBRANCHES Noncoherent pooling of actual RX correlations.
% Reference-port indices identify RE locations, not receive antennas. Keep
% every RX column and sum correlation powers, not complex branch amplitudes:
% unknown opposite channel phases must not cancel a valid reference signal.
% Preserve the existing whole/chunk statistic and configured decision gate.
reference = reference(:);
assert(ismatrix(received) && size(received,1)==numel(reference) && ...
    size(received,2)>=1, 'sixgr:phy:trs:ReferenceReceiveShape', ...
    'TRS samples must contain one row per reference RE and all RX columns.');
metric=NaN; phase=nan(1,size(received,2));
if isempty(reference) || any(~isfinite(reference)) || any(~isfinite(received),'all')
    return;
end
correlation=sum(received.*conj(reference),1);
branchEnergy=sum(abs(received).^2,1);
usablePhase=branchEnergy>0 & abs(correlation)>0;
phase(usablePhase)=angle(correlation(usablePhase));
whole=localPooledMetric(received,reference);
n=numel(reference);
chunkSize=min(max(12,round(sqrt(double(n)))),n);
chunkMetric=nan(ceil(n/chunkSize),1);
for k=1:numel(chunkMetric)
    idx=(k-1)*chunkSize+1:min(n,k*chunkSize);
    if numel(idx)>=4
        chunkMetric(k)=localPooledMetric(received(idx,:),reference(idx));
    end
end
% A zero-energy chunk is observed and contributes zero, not an omitted
% sample. Nonfinite samples above invalidate the entire receive result.
chunkMetric=chunkMetric(isfinite(chunkMetric));
if isempty(chunkMetric)
    metric=whole;
else
    metric=max(whole,median(chunkMetric));
end
end

function value=localPooledMetric(received,reference)
energy=sum(abs(received).^2,'all')*sum(abs(reference).^2);
if energy==0
    value=0;
else
    value=sqrt(sum(abs(sum(received.*conj(reference),1)).^2)/energy);
end
end
