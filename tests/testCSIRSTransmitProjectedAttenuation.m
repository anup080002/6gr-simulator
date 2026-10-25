function ok=testCSIRSTransmitProjectedAttenuation()
% Native OFDM + actual practical power operator on declared component grids.
% No shared channel/RF execution, UCI, standardized pathloss or accuracy claim.
setup6GRSimToolkit('Verbose',false);
c=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30,'NSlot',1);
rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',3, ...
    'Density','one','SymbolLocations',2,'SubcarrierLocations',0,'NumRB',24);
reference=nrResourceGrid(c,rs.NumCSIRSPorts);
reference(nrCSIRSIndices(c,rs))=nrCSIRS(c,rs);
cfg.phy.csiim=struct('enabled',true,'resource_id',0,'pattern',1, ...
    'subcarrier',4,'symbol',13,'starting_rb',0,'num_rbs',24,'period_slots',5,'offset_slots',1);
native=nrOFDMInfo(c); scale=double(native.Nfft)*sqrt(1000);
K=size(reference,1); L=size(reference,2);
power=1e-3; loss=40;
logical=reshape(reference,K*L,2)*sqrt(power);
B=zeros(2,64); B(1,1)=1; B(2,64)=1;
tx=reshape(logical*B,K,L,64)*scale;
rx=cat(3,reference(:,:,1)*sqrt(power*10^(-loss/10)), ...
    reference(:,:,1)*sqrt(power*10^(-(loss+6)/10)))*scale;
% These are actual native modulations/demodulations, not a shared RF model.
txWave=nrOFDMModulate(c,tx,'Windowing',0);
rxWave=nrOFDMModulate(c,rx,'Windowing',0);
actualTX=nrOFDMDemodulate(c,txWave,'CyclicPrefixFraction',.5);
actualRX=nrOFDMDemodulate(c,rxWave,'CyclicPrefixFraction',.5);
m=sixgr.phy.refsig.measureCSIRSPhysicalResource(c,rs,actualRX/scale,cfg,struct(),'W_resource_grid');
saved=m;
a=call(actualTX,m);
assert(a.Available&&a.SelectedReceiveColumn1==1&&numel(a.PhysicalTransmitColumnIndices0)==64);
near(a.TransmitProjectedPower_W,power); near(a.EffectiveAttenuation_dB,loss);
assert(~a.UniqueNonlinearPortAttributionQualified&&~a.IndependentAccuracyQualified&& ...
    ~a.StandardizedPathlossQualified&&~a.ReceiverUsesReference&&isequaln(m,saved));

% Physical power-preserving remapping changes coordinates, not total power.
C=zeros(2,64); C(1,1:2)=[1 1i]/sqrt(2); C(2,63:64)=[1 -1i]/sqrt(2);
mapped=reshape(logical*C,K,L,64)*scale;
mappedWave=nrOFDMModulate(c,mapped,'Windowing',0);
b=call(nrOFDMDemodulate(c,mappedWave,'CyclicPrefixFraction',.5),m);
near(a.TransmitProjectedPower_W,b.TransmitProjectedPower_W);

% Explicit component counterexample: post-RF-like leakage in a column
% whose ORIGINAL pre-RF grid is entirely zero MUST contribute to projection.
leaking=actualTX; leaking(:,:,2)=reference(:,:,1)*sqrt(power)*scale/2;
d=call(leaking,m); near(d.TransmitProjectedPower_W,1.25*power);
assert(d.TransmitProjectedPower_W>a.TransmitProjectedPower_W);
fprintf('CSI_TX_PROJECTED_ATTENUATION native_OFDM=3 TX_columns=64 attenuation_mapping_and_zero_support PASS\n');
singleTX=nrOFDMDemodulate(c,single(txWave),'CyclicPrefixFraction',.5);
singleRX=nrOFDMDemodulate(c,single(rxWave),'CyclicPrefixFraction',.5);
singleMeasurement=sixgr.phy.refsig.measureCSIRSPhysicalResource( ...
    c,rs,singleRX./cast(scale,'like',singleRX),cfg,struct(),'W_resource_grid');
singleResult=call(singleTX,singleMeasurement);
assert(singleResult.Available&&abs(singleResult.EffectiveAttenuation_dB-loss)<1e-4);
fprintf('CSI_TX_PROJECTED_ATTENUATION original_single_precision_measurement PASS\n');

% The actual legacy pairing facade's optional output retains the whole grid
% and does not change its existing occupied-preRF EVM population.
prepared=struct('Carrier',c,'TransmitSamples',txWave,'TransmitStartSample',0, ...
    'NumSamples',size(txWave,1),'SampleRateHz',native.SampleRate,'Tx',struct('Grid',tx));
buffer=sixgr.phy.waveform.WaveformObservationBuffer(0,size(txWave,1),native.SampleRate,64);
buffer.append(sixgr.phy.waveform.WaveformChunk(txWave,0),native.SampleRate);
legacy=sixgr.phy.refsig.pairCSIRSTransmitterSymbols(prepared,buffer);
[pairs,full]=sixgr.phy.refsig.pairCSIRSTransmitterSymbols(prepared,buffer);
assert(isequaln(legacy,pairs)&&full.ObservationSHA256==buffer.sampleHash()&& ...
    full.GridSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(full.Grid)&& ...
    size(full.Grid,3)==64&&full.PreRFZeroPositionsRetained&&full.AdditionalOFDMDemodulations==0);
pairedPower=call(full.Grid,m); near(pairedPower.TransmitProjectedPower_W,a.TransmitProjectedPower_W);
leakWave=nrOFDMModulate(c,leaking,'Windowing',0);
leakBuffer=sixgr.phy.waveform.WaveformObservationBuffer(0,size(leakWave,1),native.SampleRate,64);
leakBuffer.append(sixgr.phy.waveform.WaveformChunk(leakWave,0),native.SampleRate);
[sparsePairs,fullLeak]=sixgr.phy.refsig.pairCSIRSTransmitterSymbols(prepared,leakBuffer);
assert(~any([sparsePairs.PortIndex]==1)&&any(abs(fullLeak.Grid(:,:,2))>0,'all'));
leakPower=call(fullLeak.Grid,m); near(leakPower.TransmitProjectedPower_W,d.TransmitProjectedPower_W);

% Original signed estimates are retained, never floored to manufacture a log.
negative=zeros(size(actualRX)); negative(:,14,:)=scale;
nm=sixgr.phy.refsig.measureCSIRSPhysicalResource(c,rs,negative/scale,cfg,struct(),'W_resource_grid');
n=call(actualTX,nm);
assert(~n.Available&&all(n.SignedReceivedPowerPerColumn_W<0)&&isnan(n.EffectiveAttenuation_dB));
z=sixgr.phy.refsig.projectCSIRSTransmitAttenuation(c,actualTX,native.Nfft,reference,m,"normalized_complex_baseband");
assert(~z.Available&&contains(z.Status,"normalized"));
noIM=sixgr.phy.refsig.measureCSIRSPhysicalResource(c,rs,actualRX/scale,struct(),struct(),'W_resource_grid');
unmatched=call(actualTX,noIM); assert(~unmatched.Available);

% Resealing a modified token does not legitimize altered original operands.
for field=["ProjectionWeightsReal","ReferenceEnergyPerTile","TileIndices1Based", ...
        "ProjectedCoefficientsReal","SignedPort3000PowerPerBranch"]
    bad=m; bad.SINR.SignalPowerEstimation.CDMProjectionReceipt.(field)(end)= ...
        bad.SINR.SignalPowerEstimation.CDMProjectionReceipt.(field)(end)+.1;
    bad=reseal(bad); reject(@()call(actualTX,bad));
end
bad=m; bad.SINR.SignalPowerEstimation.CDMProjectionReceipt.TileIndices1Based= ...
    char(bad.SINR.SignalPowerEstimation.CDMProjectionReceipt.TileIndices1Based);
reject(@()call(actualTX,reseal(bad)));
bad=m; bad.SINR.SignalPowerEstimation.CDMProjectionReceipt.ReferenceUsedByReceiver=0;
reject(@()call(actualTX,reseal(bad)));
bad=m; bad.RSRPPerAntenna_dBm(2)=bad.RSRPPerAntenna_dBm(2)+1; reject(@()call(actualTX,bad));
bad=m; bad.SINR.Source="model_power"; reject(@()call(actualTX,bad));
reject(@()sixgr.phy.refsig.projectCSIRSTransmitAttenuation(c,actualTX,"1024",reference,m,"sqrt_mW"));
fprintf('CSI_TX_PROJECTED_ATTENUATION signed_unavailable_and_original_operand_guards PASS\n');
ok=true;
    function out=call(grid,measurement)
        out=sixgr.phy.refsig.projectCSIRSTransmitAttenuation(c,grid,native.Nfft,reference,measurement,"sqrt_mW");
    end
end
function m=reseal(m)
m.SINR.SignalPowerEstimation.CDMProjectionReceiptSHA256=sixgr.util.sha256Hex( ...
    char(jsonencode(m.SINR.SignalPowerEstimation.CDMProjectionReceipt)));
end
function near(a,b), assert(all(abs(a-b)<=1e-10*max(abs(b),1e-12),'all')); end
function reject(f)
try, f(); catch e, assert(startsWith(string(e.identifier),"sixgr:refsig:CSIProjectedAttenuation")); return; end
error('test:MissingRejection','Changed original projection operands accepted.');
end
