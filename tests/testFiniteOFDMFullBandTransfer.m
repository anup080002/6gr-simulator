function ok=testFiniteOFDMFullBandTransfer()
% Full 273-PRB numerical scaling benchmark, NOT decoded performance.
% A constant two-tap MIMO channel whose complete support fits inside CP has
% an independent closed-form frequency response and exactly zero other-RE
% leakage. Time-varying/boundary cases are tested against waveform probes
% separately in testFiniteOFDMTransferCovariance.
carrier=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30,'NSlot',1);
sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
N=sampling.Nfft; fs=sampling.SampleRateHz; ns=sampling.CurrentSlotSamples;
nt=4; nr=2; layers=2;
H0=[1 .2i .1 0;.3 1 0 .1i]; H2=[.1 .2 0 .1;.05i 0 .2 .1];
W=[1 0;0 1;1i 0;0 -1i]/2;
assert(abs(norm(W,'fro')^2-1)<1e-12);
gains=complex(zeros(ns,2,nt,nr));
gains(:,1,:,:)=repmat(reshape(H0.',1,1,nt,nr),ns,1,1,1);
gains(:,2,:,:)=repmat(reshape(H2.',1,1,nt,nr),ns,1,1,1);
filters=[1 0;0 0;0 1];
realization=struct('PathFilters',filters,'PathGains',gains, ...
    'SampleTimes',(0:ns-1)'/fs,'SampleRateHz',fs,'TrimSamples',0, ...
    'NumberOfSymbols',carrier.SymbolsPerSlot,'Nfft',N,'CyclicPrefixFraction',.5);
coordinates=[(0:12*carrier.NSizeGrid-1)' 6*ones(12*carrier.NSizeGrid,1)];
power=(1+.1*cos(coordinates(:,1)))/(12*carrier.NSizeGrid);
timer=tic;
[covariance,other,useful]=sixgr.system.abstraction.finiteOFDMTransferCovariance( ...
    carrier,coordinates,W,power,coordinates,realization,sampling);
elapsed=toc(timer);
expected=complex(zeros(nr,layers,size(coordinates,1)));
expectedCov=complex(zeros(size(covariance)));
for k=1:size(coordinates,1)
    frequency=coordinates(k,1)-6*carrier.NSizeGrid;
    expected(:,:,k)=(H0+exp(-1i*2*pi*frequency*2/N)*H2)*W*sqrt(power(k));
    expectedCov(:,:,k)=expected(:,:,k)*expected(:,:,k)';
end
relativeUseful=norm(useful(:)-expected(:))/norm(expected(:));
relativeCovariance=norm(covariance(:)-expectedCov(:))/norm(expectedCov(:));
relativeLeakage=norm(other(:))/norm(expectedCov(:));
assert(max([relativeUseful relativeCovariance])<2e-11 && relativeLeakage<1e-20, ...
    'test:FullBandFiniteTransfer','The full-band numerical transfer disagrees with the independent FIR frequency response.');
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
T=table(273,N,size(coordinates,1),nt,nr,layers,elapsed,relativeUseful,relativeCovariance,relativeLeakage, ...
    false,false,"constant_two_tap_mimo_closed_form_not_bler_or_rf_qualification", ...
    'VariableNames',{'PRBs','Nfft','SourceRECount','TxPorts','RxPorts','Layers','ElapsedSeconds', ...
    'RelativeUsefulError','RelativeCovarianceError','RelativeOtherRELeakage', ...
    'StatisticalBLERQualified','PrimaryStudyAccepted','EvidenceScope'});
writetable(T,fullfile(folder,'finite_transfer_fullband_benchmark.csv'));
fprintf('FINITE_TRANSFER_FULLBAND_PASS prbs=273 resources=%d elapsed_s=%g useful=%g covariance=%g leakage=%g folder=%s\n', ...
    height(coordinates),elapsed,relativeUseful,relativeCovariance,relativeLeakage,folder);
ok=true;
end
