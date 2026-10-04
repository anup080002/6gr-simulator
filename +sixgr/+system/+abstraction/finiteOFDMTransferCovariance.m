function [covariance,otherResourceCovariance,sameResourceEffectiveChannel,explicitResponse]=finiteOFDMTransferCovariance( ...
    carrier,sourceCoordinates,precoder,powerPerRE,receiveCoordinates,realization,sampling,explicitSymbols)
%FINITEOFDMTRANSFERCOVARIANCE Exact frequency transfer of finite sample FIRs.
% Internal numerical kernel: inputs have the same validation contract as
% sampledOFDMInterferenceCovariance. No tap/time/frequency truncation, cyclic
% channel approximation, gain interpolation or statistical approximation.
%
% For an FFT sample q and delay d, the source sample is fftStart+q-d.
% Multiply each time-varying tap by the indicator that this source sample
% belongs to the declared source OFDM symbol (INCLUDING its actual CP).
% Its FFT evaluated at kReceive-kSource is the cross-subcarrier transfer.
% The source and receive phase factors account for the two FFT origins.
% This is the same linear operator as individual independent-symbol probes.
% Optional explicitSymbols retain the phase of an actually generated pilot or
% control population. Sum their complex responses BEFORE forming a second
% moment; the independent-symbol covariance above is not their interference.
if nargin<8, explicitSymbols=[]; end

N=realization.Nfft; nsym=realization.NumberOfSymbols;
filters=realization.PathFilters; gains=realization.PathGains;
nr=size(gains,4); layers=size(precoder,2); nt=size(precoder,1);
cpCycle=sampling.CyclicPrefixLengths;
cp=cpCycle(mod(carrier.NSlot*carrier.SymbolsPerSlot+(0:nsym-1),numel(cpCycle))+1);
starts=[0 cumsum(N+cp(1:end-1))];
nReceivers=size(receiveCoordinates,1);
covariance=complex(zeros(nr,nr,nReceivers));
otherResourceCovariance=complex(zeros(nr,nr,nReceivers));
sameResourceEffectiveChannel=complex(zeros(nr,layers,nReceivers));
explicitResponse=complex(zeros(nr,nReceivers));
% Removing IDENTICALLY zero FIR coefficients changes no operator support.
tapIndices=find(any(filters~=0,2)); delays=reshape(tapIndices-1,1,[]);
% An exactly zero channel is a valid linear operator (e.g. complete
% attenuation), not missing evidence. Preserve the native FIR's zero output;
% the downstream receiver, not this kernel, determines rank/detection failure.
if isempty(tapIndices), return; end
filters=filters(tapIndices,:);
sourceSymbols=unique(sourceCoordinates(:,2)).';
receiveSymbols=unique(receiveCoordinates(:,2)).';
for receiveSymbol=receiveSymbols
    targetRows=find(receiveCoordinates(:,2)==receiveSymbol);
    targetFrequencies=receiveCoordinates(targetRows,1)-6*carrier.NSizeGrid;
    cpRemoved=fix(realization.CyclicPrefixFraction*cp(receiveSymbol+1));
    fftStart=starts(receiveSymbol+1)+cpRemoved+realization.TrimSamples;
    sampleRows=fftStart+(1:N);
    assert(sampleRows(end)<=size(gains,1), ...
        'sixgr:abstraction:FiniteOFDMWindow','Channel gains do not cover the receive FFT.');
    % Apply the actual layer-to-port matrix before forming effective taps.
    % Native channel gains multiply the delayed TX sample (no conjugation).
    taps=complex(zeros(N,numel(delays),nr,layers));
    for r=1:nr
        pathByTX=reshape(gains(sampleRows,:,:,r),N*size(filters,2),nt);
        pathByLayer=reshape(pathByTX*precoder,N,size(filters,2),layers);
        for layer=1:layers
            taps(:,:,r,layer)=pathByLayer(:,:,layer)*filters.';
        end
    end
    sourceSample=fftStart+(0:N-1)'-delays;
    for sourceSymbol=sourceSymbols
        symbolStart=starts(sourceSymbol+1);
        symbolEnd=symbolStart+cp(sourceSymbol+1)+N;
        mask=sourceSample>=symbolStart & sourceSample<symbolEnd;
        if ~any(mask,'all'), continue; end % exactly no finite-filter overlap
        sourceRows=find(sourceCoordinates(:,2)==sourceSymbol);
        frequencies=reshape(sourceCoordinates(sourceRows,1)-6*carrier.NSizeGrid,1,[]);
        spectra=fft(taps.*mask,[],1);
        sourcePhase=exp(1i*2*pi/N*mod((fftStart-symbolStart-cp(sourceSymbol+1)-delays.')*frequencies,N));
        sourceAmplitude=reshape(sqrt(powerPerRE(sourceRows)),1,[])/N;
        % A bounded working set, not a change to the modeled population.
        % Each output row is accumulated over ALL declared source REs.
        blockRows=max(1,min(numel(targetRows),floor(2^18/(numel(sourceRows)*nr*layers))));
        for first=1:blockRows:numel(targetRows)
            rows=first:min(first+blockRows-1,numel(targetRows));
            target=targetFrequencies(rows);
            difference=mod(target-frequencies,N)+1;
            response=complex(zeros(numel(rows),numel(sourceRows),nr,layers));
            receivePhase=exp(1i*2*pi/N*mod(target*(cp(receiveSymbol+1)-cpRemoved),N));
            for r=1:nr
                for layer=1:layers
                    values=complex(zeros(size(difference)));
                    coefficients=spectra(:,:,r,layer);
                    for tap=1:numel(delays)
                        values=values+coefficients(difference+N*(tap-1)).*sourcePhase(tap,:);
                    end
                    response(:,:,r,layer)=values.*receivePhase.*sourceAmplitude;
                end
            end
            same=false(size(difference));
            if sourceSymbol==receiveSymbol, same=target==frequencies; end
            for j=1:numel(rows)
                output=targetRows(rows(j));
                % Summation is over source RE and independent layer, not TX
                % ports: ports contain correlated precoded layer symbols.
                matrix=reshape(permute(response(j,:,:,:),[3 2 4 1]),nr,[]);
                covariance(:,:,output)=covariance(:,:,output)+matrix*matrix';
                if ~isempty(explicitSymbols)
                    symbols=explicitSymbols(sourceRows,:);
                    explicitResponse(:,output)=explicitResponse(:,output)+matrix*symbols(:);
                end
                matched=find(same(j,:));
                if ~isempty(matched)
                    sameResourceEffectiveChannel(:,:,output)=reshape(response(j,matched,:,:),nr,layers);
                    response(j,matched,:,:)=0;
                end
                other=reshape(permute(response(j,:,:,:),[3 2 4 1]),nr,[]);
                otherResourceCovariance(:,:,output)=otherResourceCovariance(:,:,output)+other*other';
            end
        end
    end
end
end
