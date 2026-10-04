function ok=testSampledFadingChannelOperator()
% Independent native waveform oracle, including finite-CP leakage and memory.
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30);
ofdm=nrOFDMInfo(carrier);
folder=tempname(fullfile(pwd,'logs')); mkdir(folder); audit=table();
for profile=["TDL-A","CDL-C"]
    for doppler=[0 70]
        for direction=["DL","UL"]
            if profile=="TDL-A"
                channel=nrTDLChannel('DelayProfile','TDL-A','DelaySpread',30e-9, ...
                    'NumTransmitAntennas',4,'NumReceiveAntennas',2, ...
                    'SampleRate',ofdm.SampleRate,'MaximumDopplerShift',doppler, ...
                    'NormalizeChannelOutputs',false,'Seed',1401,'PathGainSampleRate','signal');
            else
                channel=nrCDLChannel('DelayProfile','CDL-C','DelaySpread',100e-9, ...
                    'SampleRate',ofdm.SampleRate,'MaximumDopplerShift',doppler, ...
                    'NormalizeChannelOutputs',false,'Seed',1401,'SampleDensity',Inf);
                channel.TransmitAntennaArray.Size=[1 2 2 1 1];
                channel.ReceiveAntennaArray.Size=[1 1 2 1 1];
            end
            if direction=="UL", swapTransmitAndReceive(channel); end
            native=info(channel); nt=native.NumTransmitAntennas;
            stream=RandStream('mt19937ar','Seed',2401);
            grid=complex(zeros(72,14,nt));
            grid(13:48,2:3,:)=(2*randi(stream,[0 1],36,2,nt)-1 + ...
                1i*(2*randi(stream,[0 1],36,2,nt)-1))/sqrt(2*nt);
            waveform=nrOFDMModulate(carrier,grid,'Windowing',0);
            trim=double(native.ChannelFilterDelay);
            pad=trim+ceil(max(double(native.PathDelays))*ofdm.SampleRate);
            transmitted=[waveform;zeros(pad,nt)];
            [actual,gains,times]=channel(transmitted);
            filters=getPathFilters(channel);
            initial=complex(zeros(size(filters,1)-1,nt,size(filters,2)));
            [predicted,finalState]=sixgr.phy.waveform.applySampledFadingChannel( ...
                transmitted,filters,gains,initial);
            relative=norm(predicted-actual,'fro')/norm(actual,'fro');
            cut=200; % Inside the transmitted burst, not in an idle tail.
            [first,state]=sixgr.phy.waveform.applySampledFadingChannel( ...
                transmitted(1:cut,:),filters,gains(1:cut,:,:,:),initial);
            [second,ending]=sixgr.phy.waveform.applySampledFadingChannel( ...
                transmitted(cut+1:end,:),filters,gains(cut+1:end,:,:,:),state);
            resetSecond=sixgr.phy.waveform.applySampledFadingChannel( ...
                transmitted(cut+1:end,:),filters,gains(cut+1:end,:,:,:),initial);
            assert(norm(resetSecond-second,'fro')>1e-8*norm(second,'fro'), ...
                'This streaming case must expose an incorrect channel-memory reset.');
            if doppler==0
                constant=sixgr.phy.waveform.applySampledFadingChannel( ...
                    transmitted,filters,gains(1,:,:,:),initial);
                assert(norm(constant-predicted,'fro')<1e-12*norm(predicted,'fro'));
            end
            streamError=norm([first;second]-predicted,'fro')/norm(predicted,'fro');
            actualGrid=nrOFDMDemodulate(carrier,actual(trim+(1:size(waveform,1)),:),'CyclicPrefixFraction',.5);
            predictedGrid=nrOFDMDemodulate(carrier,predicted(trim+(1:size(waveform,1)),:),'CyclicPrefixFraction',.5);
            gridError=norm(actualGrid(:)-predictedGrid(:))/norm(actualGrid(:));
            evidence=fullfile(folder,char(lower(profile)+"_"+lower(direction)+"_"+doppler+".mat"));
            save(evidence,'transmitted','filters','gains','times','actual','predicted', ...
                'actualGrid','predictedGrid','relative','streamError','gridError','-v7.3');
            fprintf('SAMPLED_FADING_OPERATOR profile=%s direction=%s doppler=%g samples=%g grid=%g stream=%g\n', ...
                profile,direction,doppler,relative,gridError,streamError);
            assert(relative<1e-11 && gridError<1e-11 && streamError<1e-13 && ...
                isequaln(ending,finalState),'Finite channel operator mismatch; evidence %s',evidence);
            covarianceError=localCovarianceCheck(carrier,ofdm,channel,filters,gains,times,trim,folder,profile,direction,doppler);
            row=table(profile,direction,doppler,relative,gridError,streamError,covarianceError,string(evidence), ...
                'VariableNames',{'Profile','Direction','DopplerHz','RelativeSampleError', ...
                'RelativeGridError','StreamingError','RelativeCovarianceError','EvidenceMAT'});
            audit=[audit;row]; %#ok<AGROW>
        end
    end
end
writetable(audit,fullfile(folder,'finite_channel_operator.csv'));
localAdjacentSlotCheck(folder);
fprintf('SAMPLED_FADING_OPERATOR_PASS cases=%d statistical_qualification=0 evidence=%s\n',height(audit),folder);
ok=true;
end

function localAdjacentSlotCheck(folder)
% Two consecutive slots on a nonzero native slot clock. The preceding
% slot's independent symbols must contribute to the next slot's covariance.
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30,'NSlot',1);
ofdm=nrOFDMInfo(carrier);
channel=nrTDLChannel('DelayProfile','TDL-A','DelaySpread',300e-9, ...
    'NumTransmitAntennas',2,'NumReceiveAntennas',2, ...
    'SampleRate',ofdm.SampleRate,'MaximumDopplerShift',70, ...
    'NormalizeChannelOutputs',false,'Seed',3401,'PathGainSampleRate','signal');
native=info(channel); trim=double(native.ChannelFilterDelay);
source=[12 13;13 14]; power=[.3;.7]; W=[1;1i]/sqrt(2);
[sc,sym]=ndgrid(0:71,13:15); coords=[sc(:),sym(:)];
blank=nrOFDMModulate(carrier,complex(zeros(72,28,2)),'Windowing',0);
pad=trim+ceil(max(double(native.PathDelays))*ofdm.SampleRate);
[~,gains,times]=channel([blank;zeros(pad,2)]);
filters=getPathFilters(channel);
precedingSupport=sixgr.phy.waveform.receiveSlotSupport(filters,trim,double(ofdm.Nfft), ...
    double(ofdm.CyclicPrefixLengths),double(carrier.SymbolsPerSlot),1,13,.5);
followingSupport=sixgr.phy.waveform.receiveSlotSupport(filters,trim,double(ofdm.Nfft), ...
    double(ofdm.CyclicPrefixLengths),double(carrier.SymbolsPerSlot),2,[0 1],.5);
assert(precedingSupport.RequiredFollowingSlots>=1 && followingSupport.RequiredPreviousSlots>=1, ...
    'Native adjacent-slot leakage must have matching committed-population dependencies.');
realization=struct('PathFilters',filters,'PathGains',gains,'SampleTimes',times, ...
    'SampleRateHz',ofdm.SampleRate,'TrimSamples',trim,'NumberOfSymbols',28, ...
    'Nfft',ofdm.Nfft,'CyclicPrefixFraction',.5);
model=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
    carrier,source,W,power,coords,realization);
omitted=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
    carrier,source(2,:),W,power(2),coords,realization);
omittedFollowing=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
    carrier,source(1,:),W,power(1),coords,realization);
phases=fft(eye(2)); measured=complex(zeros(2,2,size(coords,1)));
for probe=1:2
    grid=complex(zeros(72,28,2));
    for s=1:2
        grid(source(s,1)+1,source(s,2)+1,:)= ...
            reshape(sqrt(power(s))*W*phases(s,probe),1,1,2);
    end
    waveform=nrOFDMModulate(carrier,grid,'Windowing',0);
    independent=clone(channel); reset(independent);
    [rx,g]=independent([waveform;zeros(pad,2)]);
    assert(isequaln(g,gains),'The physical probes must use the same sampled channel.');
    demod=nrOFDMDemodulate(carrier,rx(trim+(1:size(waveform,1)),:), ...
        'CyclicPrefixFraction',.5);
    for k=1:size(coords,1)
        value=reshape(demod(coords(k,1)+1,coords(k,2)+1,:),2,1);
        measured(:,:,k)=measured(:,:,k)+value*value'/2;
    end
end
relative=norm(measured(:)-model.Covariance(:))/norm(measured(:));
current=coords(:,2)>=14; preceding=coords(:,2)==13;
actualCurrent=measured(:,:,current); predictedCurrent=omitted.Covariance(:,:,current);
actualPreceding=measured(:,:,preceding); predictedPreceding=omittedFollowing.Covariance(:,:,preceding);
missingHistory=norm(actualCurrent(:)-predictedCurrent(:))/norm(actualCurrent(:));
missingFollowing=norm(actualPreceding(:)-predictedPreceding(:))/norm(actualPreceding(:));
path=fullfile(folder,'adjacent_slots_native_covariance.mat');
save(path,'model','omitted','measured','relative','missingHistory','source', ...
    'coords','realization','omittedFollowing','missingFollowing', ...
    'precedingSupport','followingSupport','-v7.3');
assert(relative<1e-11 && missingHistory>1e-10 && missingFollowing>1e-12 && ...
    any(model.CyclicPrefixSupport.RequiredFollowingSymbolSamples>0), ...
    'Adjacent-slot history must recover native leakage without a CP reset; evidence %s',path);
fprintf('FINITE_OFDM_ADJACENT_SLOTS_PASS relative=%g omitted_history_error=%g omitted_following_error=%g evidence=%s\n', ...
    relative,missingHistory,missingFollowing,path);
end

function relative=localCovarianceCheck(carrier,ofdm,channel,filters,gains,times,trim,folder,profile,direction,doppler)
% Complete orthogonal ensemble across RE AND layer, not a coherent tone
% repeated across REs. E[s*s']=I exactly, with no Monte Carlo tolerance.
nt=size(gains,3); nr=size(gains,4); rank=2;
W=fft(eye(nt)); W=W(:,1:rank)/sqrt(nt*rank);
source=[12 1;13 2]; power=[.3;.7];
[sc,sym]=ndgrid(0:71,0:3); coords=[sc(:),sym(:)];
realization=struct('PathFilters',filters,'PathGains',gains,'SampleTimes',times,'SampleRateHz',ofdm.SampleRate, ...
    'TrimSamples',trim,'NumberOfSymbols',14,'Nfft',ofdm.Nfft,'CyclicPrefixFraction',.5);
model=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
    carrier,source,W,power,coords,realization);
bad=realization; bad.SampleTimes(2)=bad.SampleTimes(2)+1/ofdm.SampleRate;
rejected=false;
try
    sixgr.system.abstraction.sampledOFDMInterferenceCovariance(carrier,source,W,power,coords,bad);
catch cause
    assert(strcmp(cause.identifier,'sixgr:abstraction:FiniteOFDMSampleClock'),'%s',cause.message);
    rejected=true;
end
assert(rejected,'A nonuniform gain clock must not be silently interpolated.');
count=size(source,1)*rank; phases=fft(eye(count));
measured=complex(zeros(nr,nr,size(coords,1)));
coefficients=complex(zeros(nr,count,size(coords,1)));
for probe=1:count
    grid=complex(zeros(72,14,nt)); index=0;
    for s=1:size(source,1)
        value=zeros(nt,1);
        for layer=1:rank
            index=index+1;
            value=value+sqrt(power(s))*W(:,layer)*phases(index,probe);
        end
        grid(source(s,1)+1,source(s,2)+1,:)=reshape(value,1,1,nt);
    end
    waveform=nrOFDMModulate(carrier,grid,'Windowing',0);
    native=clone(channel); reset(native);
    [received,independentGains]=native([waveform;zeros(size(gains,1)-size(waveform,1),nt)]);
    assert(isequaln(independentGains,gains),'Each orthogonal probe requires the same channel realization.');
    rx=nrOFDMDemodulate(carrier,received(trim+(1:size(waveform,1)),:),'CyclicPrefixFraction',.5);
    for k=1:size(coords,1)
        value=reshape(rx(coords(k,1)+1,coords(k,2)+1,:),nr,1);
        measured(:,:,k)=measured(:,:,k)+value*value'/count;
        coefficients(:,:,k)=coefficients(:,:,k)+value*conj(phases(:,probe)).'/count;
    end
end
relative=norm(measured(:)-model.Covariance(:))/norm(measured(:));
path=fullfile(folder,char(lower(profile)+"_"+lower(direction)+"_"+doppler+"_covariance.mat"));
save(path,'model','measured','relative','source','power','W','coords','-v7.3');
assert(relative<1e-11 && model.WithinWindowISIICIIncluded && ~model.StatisticalBLERQualified, ...
    'Finite OFDM covariance mismatch; evidence %s',path);
% Recover each input's transfer coefficient from the independent native
% orthogonal ensemble. Verify the SAME-RE layer matrix and separately summed
% other-RE leakage, not merely the total covariance (which could hide a
% double-counted or wrongly attributed inter-layer term).
expectedSame=complex(zeros(size(model.SameResourceEffectiveChannel)));
expectedOther=complex(zeros(size(measured)));
reconstructed=complex(zeros(size(measured)));
for k=1:size(coords,1)
    for s=1:size(source,1)
        index=(s-1)*rank+(1:rank);
        if isequal(coords(k,:),source(s,:))
            expectedSame(:,:,k)=coefficients(:,index,k);
        else
            B=coefficients(:,index,k);
            expectedOther(:,:,k)=expectedOther(:,:,k)+B*B';
        end
    end
    B=model.SameResourceEffectiveChannel(:,:,k);
    reconstructed(:,:,k)=B*B'+model.OtherResourceCovariance(:,:,k);
end
sameError=norm(expectedSame(:)-model.SameResourceEffectiveChannel(:))/norm(expectedSame(:));
otherError=norm(expectedOther(:)-model.OtherResourceCovariance(:))/norm(expectedOther(:));
assert(sameError<1e-11 && otherError<1e-10 && ...
    norm(reconstructed(:)-model.Covariance(:))<1e-12*norm(model.Covariance(:)) && ...
    model.SameResourceChannelIncludesTransmitPower, ...
    'Finite channel must retain separate useful-layer and other-resource populations.');
save(path,'expectedSame','expectedOther','sameError','otherError','-append');
% Consume the physically verified split with the SAME spatial detector
% used by SLS. Independent native transfer coefficients determine the
% error-covariance reference; no receiver samples are passed a true H.
noise=.01*eye(nr);
detected=sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR(model,noise);
expectedSINR=zeros(size(coords,1),rank);
for k=1:size(coords,1)
    A=expectedSame(:,:,k); R=noise+expectedOther(:,:,k);
    errorCov=(eye(rank)+A'*(R\A))\eye(rank);
    expectedSINR(k,:)=(1./real(diag(errorCov))-1).';
end
sinrError=norm(detected.SINRLinear(:)-expectedSINR(:))/max(1,norm(expectedSINR(:)));
assert(sinrError<1e-11 && ~detected.WaveformBacked && ~detected.PrimaryStudyAccepted, ...
    'Finite-window spatial SINR must match the independent native channel ensemble.');
save(path,'detected','expectedSINR','sinrError','-append');
outside=~ismember(coords,source,'rows');
powerByRE=zeros(size(coords,1),1);
for k=1:numel(powerByRE), powerByRE(k)=real(trace(measured(:,:,k))); end
leakageFraction=sum(powerByRE(outside))/sum(powerByRE);
assert(leakageFraction>1e-12, ...
    'The native reference must contain measurable leakage, not merely roundoff outside source REs.');
fprintf('FINITE_OFDM_COVARIANCE profile=%s direction=%s doppler=%g relative=%g leakage_power_fraction=%g\n', ...
    profile,direction,doppler,relative,leakageFraction);
end
