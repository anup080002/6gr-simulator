function ok=testCSIRSChannelReferenceOperators()
% Independent OFDM basis experiments, not a statistical/scenario pass.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30,'NSlot',3);
info=nrOFDMInfo(carrier,'Windowing',0); fs=info.SampleRate;
K=72; L=14; T=4; R=2; origin=17; amplitude=.37;
cases=0;
for model=["AWGN","TDL-C","CDL-C"]
 for P=[1 2 4]
  W=exp(-2i*pi*(0:T-1)'*(0:P-1)/T)/sqrt(T);
  for timing=[0 5]
   for fraction=[.5 1]
    for port=1:P
     bin=25; symbol=9;
     grid=complex(zeros(K,L,P)); grid(bin,symbol,port)=1;
     wave=nrOFDMModulate(carrier,grid,'Windowing',0)*W.'*amplitude;
     input=[complex(zeros(origin,T));wave;complex(zeros(64,T))];
     cut=floor(size(input,1)/2); loss=[.83 .61];
     if model~="AWGN"
      if model=="TDL-C"
       channel=nrTDLChannel('DelayProfile','TDL-C','DelaySpread',100e-9, ...
        'MaximumDopplerShift',71,'SampleRate',fs,'NumTransmitAntennas',T, ...
        'NumReceiveAntennas',R,'NormalizeChannelOutputs',true,'Seed',809);
      else
       channel=nrCDLChannel('DelayProfile','CDL-C','DelaySpread',100e-9, ...
        'MaximumDopplerShift',71,'SampleRate',fs,'CarrierFrequency',4e9, ...
        'NormalizeChannelOutputs',true,'Seed',809,'SampleDensity',Inf);
       channel.TransmitAntennaArray.Size=[1 2 2 1 1];
       channel.ReceiveAntennaArray.Size=[1 1 2 1 1];
      end
      objectWarmup=256;
      channel(complex(zeros(objectWarmup,T)));
      [a,ga,ta]=channel(input(1:cut,:));
      [b,gb,tb]=channel(input(cut+1:end,:));
      filters=getPathFilters(channel); normalization=true;
      referenceSource="same_executed_NR_channel_path_gains_and_filters";
     else
      H=[.8 .1i .6 0; .05 -.6i .03 .8];
      a=input(1:cut,:)*H.'; b=input(cut+1:end,:)*H.';
      ga=repmat(reshape(H.',1,1,T,R),cut,1,1,1);
      gb=repmat(reshape(H.',1,1,T,R),size(b,1),1,1,1);
      ta=(0:cut-1).'/fs; tb=(cut:size(input,1)-1).'/fs;
      filters=1; normalization=false; objectWarmup=0;
      referenceSource="executed_fixed_matrix_AWGN_operator";
     end
     ra=struct('Source',referenceSource,'PathGains',ga,'PathFilters',filters, ...
      'SampleTimes_s',ta,'StartSample',0,'EndSampleExclusive',cut, ...
      'SampleRateHz',fs,'StateKey',"independent_basis", ...
      'NumTransmitAntennas',T,'NumReceiveAntennas',R, ...
      'NormalizeChannelOutputs',normalization,'NormalizePathGains',false, ...
      'ReceiverEstimatorInput',false,'AdditionalChannelExecutions',0, ...
      'ObjectTimeOffsetSamples',objectWarmup);
     if model=="AWGN", ra.SpatialMatrix=H; end
     rb=ra; rb.PathGains=gb; rb.SampleTimes_s=tb;
     rb.StartSample=cut; rb.EndSampleExclusive=size(input,1);
     captures={struct('Reference',ra,'LinkID',"basis",'TX',"gnb",'RX',"ue", ...
       'AppliedLargeScaleAmplitudeGain',loss(1)), ...
       struct('Reference',rb,'LinkID',"basis",'TX',"gnb",'RX',"ue", ...
       'AppliedLargeScaleAmplitudeGain',loss(2))};
     delay=3; hz=1133; correction=219;
     received=[a*loss(1);b*loss(2)];
     received=[complex(zeros(delay,R));received(1:end-delay,:)];
     received=received.*exp(2i*pi*hz*(0:size(received,1)-1).'/fs);
     received=received(origin+1:end,:);
     received=received.*exp(-2i*pi*correction*(0:size(received,1)-1).'/fs);
     [actual,ofdm]=sixgr.phy.waveform.ofdmDemodulate( ...
       carrier,received(timing+1:timing+size(wave,1),:),'CyclicPrefixFraction',fraction);
     if port==1, estimate=complex(zeros(K,L,R,P)); end
     estimate(bin,symbol,:,port)=actual(bin,symbol,:);
     % Each column is an independently transmitted OFDM basis through
     % the same deterministic NR realization. Complete all ports before
     % the scorer's all-port evidence guard; never relax that guard.
     cases=cases+1;
     if port<P, continue; end
     idx=sub2ind([K L P],repmat(bin,P,1),repmat(symbol,P,1),(1:P).');
     resource=struct('ResourceID',7,'Indices',idx,'Symbols',ones(P,1));
     event=struct('ResourceID',7,'WaveformPrecoderMatrix',W, ...
       'WaveformPrecoderDigest',sixgr.phy.mimo.MatrixContract.digest(W));
     prepared=struct('ExecutionStage',"csirs_waveform_prepared_not_received", ...
       'SampleRateHz',fs,'Carrier',carrier,'NumPhysicalTransmitAntennas',T, ...
       'RuntimeSlot',4,'RequestedSNR_dB',40,'ReceiveStartSample',origin, ...
       'TransmitStartSample',origin,'ReceiverConfig',struct(), ...
       'PowerContext',struct('AmplitudeScale',amplitude), ...
       'Tx',struct('CSIRSRuntimeEvent',struct('ResourceEvents',event)));
     rx=struct('ReceiverOFDMInfo',ofdm,'RxGrid',actual, ...
       'ReceiverTrackingCorrection',struct('CFOCorrectionApplied',true,'CFOCorrectionApplied_Hz',correction), ...
       'ReceiveTiming',struct('AppliedTimingCorrectionSamples',timing), ...
       'CSIRSInfo',struct('Resources',resource),'CSIRSChannelEstimate',estimate, ...
       'CSIChannelEstimateSource',"independent_transmitted_OFDM_basis_observation", ...
       'CSIRSChannelEstimation',struct('Available',true));
     clock=struct('InjectedTimingOffset_samples',delay,'CFOApplied',true, ...
       'InjectedCFO_Hz',hz,'RFStageOrder',"rx_timing>rx_lo_cfo");
     source=struct('Source',"actual_executed_link_contribution",'LinkID',"basis", ...
       'TransmitterID',"gnb",'ReceiverID',"ue",'ReceiverEstimatorInput',false, ...
       'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0, ...
       'ChannelReferenceCoverageComplete',true, ...
       'ReceiverClockExecution',struct('ReceiveStreamExecutionSegments', ...
       {{struct('Execution',struct('RX',struct('ID',"ue",'Replay',clock)))}}));
     [metric,rows,evidence]=sixgr.truth.scoreSharedCSIRSChannel(prepared,rx,source,captures);
     assert(max(abs(complex(rows.HReal,rows.HImag)-complex(rows.ReferenceHReal,rows.ReferenceHImag)))<1e-10 && ...
       metric.ChannelNMSEComparedComplexValues==P*R && metric.NMSE_dB < -160 && ...
       ~evidence.GainOrPhaseFitted && ~evidence.ReceiverEstimatorInput, ...
       'test:CSIRSReferenceOperatorMismatch', ...
       'Actual %s basis/port=%d timing=%d CP=%g must match the independent channel diagonal: NMSE=%g H=%s reference=%s.', ...
       model,port,timing,fraction,metric.NMSE_dB,mat2str(complex(rows.HReal,rows.HImag),12), ...
       mat2str(complex(rows.ReferenceHReal,rows.ReferenceHImag),12));
     bad=prepared; bad.Tx.CSIRSRuntimeEvent.ResourceEvents.WaveformPrecoderMatrix(1,1)=2;
     expect(@()sixgr.truth.scoreSharedCSIRSChannel(bad,rx,source,captures),'sixgr:truth:CSIRSReferenceSpatialMap');
     badCapture=captures; badCapture{2}.Reference.StartSample=cut+1;
     expect(@()sixgr.truth.scoreSharedCSIRSChannel(prepared,rx,source,badCapture),'sixgr:truth:IncompleteCSIRSChannelReference');
     if objectWarmup>0
      badCapture=captures;
      for k=1:numel(badCapture), badCapture{k}.Reference.ObjectTimeOffsetSamples=0; end
      expect(@()sixgr.truth.scoreSharedCSIRSChannel(prepared,rx,source,badCapture),'sixgr:truth:CSIRSReferenceClock');
     end
    end
   end
  end
 end
end
fprintf('CSIRS_CHANNEL_REFERENCE_OPERATORS_PASS cases=%d actual_NR_TDL_and_AWGN_basis_waveforms=1\n',cases);
ok=true;
end
function expect(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s',id,ex.identifier); return; end
error('test:CSIRSNegativeGuard','Expected %s.',id);
end
