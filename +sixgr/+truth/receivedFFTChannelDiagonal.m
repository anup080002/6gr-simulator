function h=receivedFFTChannelDiagonal(gains,filters,nfft,cpLengths,K,offset,cpFraction)
% Same-symbol OFDM channel diagonal from executed sample-rate path gains.
% Scoring only, not a channel estimator. Average the time-varying operator
% over each actual FFT window, including finite-symbol/CP support. Other
% subcarriers/symbols contribute ICI/ISI, not this diagonal coefficient.
validateattributes(gains,{'single','double'},{'nonempty','finite'});
validateattributes(filters,{'single','double'},{'2d','nonempty','finite'});
validateattributes(nfft,{'numeric'},{'scalar','integer','positive'});
validateattributes(K,{'numeric'},{'scalar','integer','positive','<=',nfft});
validateattributes(cpLengths,{'numeric'},{'vector','integer','nonnegative'});
validateattributes(offset,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(cpFraction,{'numeric'},{'scalar','>=',0,'<=',1,'finite'});
assert(mod(K,2)==0 && size(gains,2)==size(filters,2), ...
    'sixgr:truth:FFTReferenceShape','Require centered NR subcarriers and matching actual paths.');
L=numel(cpLengths); T=size(gains,3); R=size(gains,4);
h=complex(zeros(K,L,R,T,'like',gains));
bins=(-K/2:K/2-1).'; taps=(0:size(filters,1)-1);
phase=exp(-2i*pi/nfft*(bins*(taps-offset)));
symbolStart=0;
for l=1:L
    cp=double(cpLengths(l));
    out=double(symbolStart+offset+floor(cp*cpFraction))+(0:nfft-1).';
    assert(out(end)<size(gains,1),'sixgr:truth:IncompleteFFTChannelReference', ...
        'Every FFT sample must have an actually executed channel snapshot.');
    % Each path filter acts before multiplication by its time-varying gain.
    % Only samples belonging to this TX OFDM symbol contribute to its diagonal.
    input=out-taps;
    support=input>=symbolStart & input<symbolStart+cp+nfft;
    g=reshape(gains(out+1,:,:,:),nfft,[]);
    averages=reshape((double(support).'*g)/nfft,size(filters,1),size(filters,2),T,R);
    impulse=reshape(sum(averages.*reshape(filters,size(filters,1),size(filters,2),1,1),2), ...
        size(filters,1),T,R);
    diagonal=reshape(phase*reshape(impulse,size(filters,1),[]),K,T,R);
    h(:,l,:,:)=reshape(permute(diagonal,[1 3 2]),K,1,R,T);
    symbolStart=symbolStart+cp+nfft;
end
end
