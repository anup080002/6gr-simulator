function ok=testCSISINRPortAndBranchMeasurement()
% Independent received-grid fixtures, not production-run evidence.
setup6GRSimToolkit('Verbose',false); rng(73512,'twister');
carrier=nrCarrierConfig('NSizeGrid',100,'SubcarrierSpacing',30);
csirs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',3, ...
    'Density','one','SymbolLocations',4,'SubcarrierLocations',0,'NumRB',100);
assert(csirs.NumCSIRSPorts==2);
reference=nrResourceGrid(carrier,2);
reference(nrCSIRSIndices(carrier,csirs))=nrCSIRS(carrier,csirs);
H=[1 0.08;0.25 0.05]; noiseVariance=10^(-12/10);
y=complex(zeros(1200,14,2));
for r=1:2
    y(:,:,r)=reference(:,:,1)*H(r,1)+reference(:,:,2)*H(r,2);
end
y=y+sqrt(noiseVariance/2)*complex(randn(size(y)),randn(size(y)));
measured=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,csirs,y);
assert(measured.Available && measured.ReferencePort==3000 && measured.ReceiveBranch1Based==1);
assert(abs(measured.CSI_SINR_dB-12)<1.5, ...
    'Port-3000 SINR must not average the deliberately weak second transmit port or receive branch.');
assert(measured.CSI_SINR_dB==max(measured.CSI_SINRPerReceiveAntenna_dB));
scaled=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,csirs,y*1e-4);
assert(abs(scaled.CSI_SINR_dB-measured.CSI_SINR_dB)<1e-9);
assert(max(abs(scaled.NoiseInterferencePowerPerReceiveAntenna./ ...
    measured.NoiseInterferencePowerPerReceiveAntenna-1e-8))<1e-15);
% A frequency-selective phase rotation has nearly zero coherent wideband
% mean but finite received RE power. It must not disappear in a SINR mean.
response=exp(-1j*2*pi*(0:1199)'/600);
frequencySelective=reference(:,:,1).*response;
frequencySelective=frequencySelective+sqrt(noiseVariance/2)* ...
    complex(randn(size(frequencySelective)),randn(size(frequencySelective)));
selective=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,csirs,frequencySelective);
[nativeH,nativeNoise]=nrChannelEstimate(carrier,frequencySelective,reference,'CDMLengths',[2 1]);
port0=double(nrCSIRSIndices(carrier,csirs)); port0=port0(port0<=1200*14);
nativePort=nativeH(:,:,1,1);
nativePower=mean(abs(nativePort(port0).*reference(port0)).^2);
[~,noiselessNoise]=nrChannelEstimate(carrier,reference(:,:,1).*response,reference,'CDMLengths',[2 1]);
assert(abs(selective.CSI_SINR_dB-10*log10(nativePower/nativeNoise))<1e-12, ...
    'Generic CSI measurement must reproduce the direct Toolbox calculation.');
fprintf('CSI_SELECTIVE_NATIVE_REFERENCE native_noise=%g noiseless_estimated_noise=%g native_power=%g\n', ...
    nativeNoise,noiselessNoise,nativePower);
fprintf('CSI_PORT_BRANCH_MEASUREMENT flat=%g selective=%g selective_signal=%g selective_disturbance=%g configured_noise=%g\n', ...
    measured.CSI_SINR_dB,selective.CSI_SINR_dB, ...
    selective.DesiredPowerPerReceiveAntenna,selective.NoiseInterferencePowerPerReceiveAntenna,noiseVariance);
assert(abs(selective.CSI_SINR_dB-12)<1.5, ...
    'Average linear reference-RE powers, not the coherent frequency mean of H.');
ok=true;
end
