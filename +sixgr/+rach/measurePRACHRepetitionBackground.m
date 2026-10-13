function out=measurePRACHRepetitionBackground(received,reference,repetitions,normalization)
%MEASUREPRACHREPETITIONBACKGROUND Independent pre-SIC correlation background.
% Columns are useful-symbol repetitions within each RX branch. Adjacent,
% disjoint pairs cancel a time-invariant repeated signal. This measures noise
% PLUS inter-repetition variation (CFO/phase noise/time-varying interference),
% not pure thermal noise. No detection threshold, TX payload or noise oracle
% is used. Scale to the sum over all repetitions in the detector's metric.
validateattributes(received,{'numeric'},{'2d','finite','nonempty'});
validateattributes(reference,{'numeric'},{'column','finite','nonempty'});
validateattributes(repetitions,{'numeric'},{'scalar','integer','positive'});
validateattributes(normalization,{'numeric'},{'scalar','real','finite','positive'});
nfft=size(received,1); nrx=size(received,2)/repetitions;
assert(numel(reference)==nfft && mod(nrx,1)==0, ...
    'sixgr:rach:RepetitionBackgroundShape','PRACH repetition/RX dimensions disagree.');
out=struct('NoiseFloor',NaN,'Estimator',"disjoint_received_repetition_differences", ...
    'Definition',"original_energy_normalized_correlation_noise_plus_inter_repetition_variation", ...
    'Status',"unavailable_fewer_than_two_repetitions", ...
    'PairCount',floor(repetitions/2),'RxAntennaCount',nrx, ...
    'Normalization',double(normalization),'SampleEquivalentVariance',NaN);
if out.PairCount==0, return; end
y=reshape(received,nfft,repetitions,nrx);
delta=(y(:,2:2:2*out.PairCount,:)-y(:,1:2:2*out.PairCount,:))/sqrt(2);
df=fft(delta,[],1); rf=fft(reference);
occupied=abs(rf)>max(abs(rf))*1e-8;
assert(any(occupied),'sixgr:rach:EmptyRepetitionReference','Empty PRACH reference spectrum.');
out.SampleEquivalentVariance=mean(abs(df(occupied,:,:)).^2,'all')/nfft;
% Parseval: mean-lag |ifft(D .* conj(R))|^2 = sum |D .* R|^2/Nfft^2.
out.NoiseFloor=double(sum(abs(df.*conj(rf)).^2,'all')/nfft^2 * ...
    (repetitions/out.PairCount)/normalization);
out.Status="measured_noise_plus_inter_repetition_variation";
end
