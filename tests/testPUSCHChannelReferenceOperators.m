function ok=testPUSCHChannelReferenceOperators()
% Independent basis-waveform validation; not a decoder/scenario pass claim.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.channel.pathlossEnabled=false; cfg.channel.shadowFadingEnabled=false;
cfg.channel.sharedIdentityAWGNEnabled=false;
cfg.channel.awgnSpatialMatrixDL=[.8 0 .6 0;0 .6 0 .8];
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30,'NSlot',3);
info=nrOFDMInfo(carrier,'Windowing',0); fs=info.SampleRate;
K=72; L=14; origin=17; amplitude=.37;
projection=diag(exp(1i*[.2 -.7]));
B=exp(-2i*pi*(0:3)'*(0:1)/4)/2;
cases=0;
for layers=[1 2]
  W=exp(-2i*pi*(0:1)'*(0:layers-1)/2)/sqrt(2);
  for fraction=[0 .5 1]
    for ports=1:layers
      % A single nonzero OFDM basis coefficient isolates the diagonal,
      % even with receiver CFO correction and a time-varying link gain.
      bin=25; symbol=9;
      grid=complex(zeros(K,L,layers)); grid(bin,symbol,ports)=1;
      logical=nrOFDMModulate(carrier,grid,'Windowing',0)*W.';
      physical=amplitude*logical*projection.';
      input=[complex(zeros(origin,2));physical];
      initial=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'UL','UEIndex',1,'ServingCell',1);
      initial=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(initial,cfg,input, ...
          struct('OFDM',info),'NumTxAnt',2,'NumRxAnt',4);
      cut=floor(size(input,1)/2);
      [a,~,state,ra]=sixgr.channel.ChannelFactory.applyRuntimeChannelState(initial,input(1:cut,:), ...
          'CaptureChannelReference',true,'InputSampleDomain','materialized_channel_ports', ...
          'OutputSampleAlignment','continuous_raw_samples');
      [b,~,~,rb]=sixgr.channel.ChannelFactory.applyRuntimeChannelState(state,input(cut+1:end,:), ...
          'CaptureChannelReference',true,'InputSampleDomain','materialized_channel_ports', ...
          'OutputSampleAlignment','continuous_raw_samples');
      losses=[-.8 -2.1];
      received=[a*10^(losses(1)/20);b*10^(losses(2)/20)]*conj(B);
      pre=233; post=-87;
      received=received.*exp(-2i*pi*pre*(0:size(received,1)-1)'/fs);
      received=received(origin+1:end,:);
      received=received.*exp(-2i*pi*post*(0:size(received,1)-1)'/fs);
      [actual,ofdm]=sixgr.phy.waveform.ofdmDemodulate(carrier,received,'CyclicPrefixFraction',fraction);
      op=struct('ReceiveCombiningMatrix',B,'CaptureOriginCFOCorrection_Hz',pre, ...
          'AlignedOriginCFOCorrection_Hz',post,'AppliedTimingCorrection_samples',origin,'SampleRateHz',fs);
      snapshot=struct('Contract',"PUSCH_pilot_channel_capture/v1", ...
          'GridShape',[K L 2 layers],'Carrier',carrier, ...
          'ReceiverOFDMInfo',ofdm,'ReceiverChannelOperator',op);
      tx=struct('Carrier',carrier,'Waveform',logical,'PrecodeInfo',struct('MatrixPorts',W), ...
          'PowerContext',struct('AmplitudeScale',amplitude));
      prepared=struct('Direction',"UL",'Tx',tx,'SampleRateHz',fs,'StartSample',origin,'ReceiveStartSample',0);
      captures={struct('Reference',ra,'LinkID',"basis",'TX',"UE",'RX',"gNB"), ...
          struct('Reference',rb,'LinkID',"basis",'TX',"UE",'RX',"gNB")};
      replays={struct('AppliedLargeScaleGain_dB',losses(1)),struct('AppliedLargeScaleGain_dB',losses(2))};
      [reference,evidence]=sixgr.truth.sharedPUSCHChannelReference(snapshot,prepared,captures,replays,projection);
      expected=reshape(reference(bin,symbol,:,ports),1,[]);
      measured=reshape(actual(bin,symbol,:),1,[]);
      assert(max(abs(measured-expected))<1e-11 && ~evidence.GainOrPhaseFitted && ...
          ~evidence.ReceiverEstimatorInput && evidence.AdditionalChannelExecutions==0, ...
          'Reference must reproduce actual basis transmission with separate CFO clocks, mapping and segment losses.');
      bad=captures; bad{2}.Reference.StartSample=bad{2}.Reference.StartSample+1;
      caught=false;
      try, sixgr.truth.sharedPUSCHChannelReference(snapshot,prepared,bad,replays,projection);
      catch ex, caught=strcmp(ex.identifier,'sixgr:truth:IncompletePUSCHChannelReference'); end
      assert(caught,'Missing executed samples must not be bridged.');
      cases=cases+1;
    end
  end
end
fprintf('PUSCH_CHANNEL_REFERENCE_OPERATORS_PASS cases=%d actual_waveforms=1 fitted_gain_or_phase=0\n',cases);
ok=true;
end
