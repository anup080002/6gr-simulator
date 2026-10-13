function ok=testDataScoringTimingOperators()
% Independent sample operations: signed/fractional timing, two CFO clocks.
% This is a scoring-operator test, not statistical receiver qualification.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30);
pdsch=nrPDSCHConfig('PRBSet',0:5,'SymbolAllocation',[2 10]);
indices=nrPDSCHDMRSIndices(carrier,pdsch);
symbols=nrPDSCHDMRS(carrier,pdsch);
grid=nrResourceGrid(carrier,1); grid(indices)=symbols;
wave=sixgr.phy.waveform.ofdmModulate(carrier,grid);
fs=nrOFDMInfo(carrier).SampleRate;
cfg=sixgr.config.defaultConfig(); cfg.channel.model='AWGN';
prepared=struct('Contract',"isolated_executed_data_scoring/v1", ...
    'Direction',"DL",'ReceiveStartSample',0,'SampleRateHz',fs,'InputConfig',cfg);
capture=struct('WaveformSHA256',string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(wave)), ...
    'ReceiverEstimatorInput',false,'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0);
cases=0;
for direction=["DL","UL"]
  prepared.Direction=direction; channel="PDSCH";
  if direction=="UL", channel="PUSCH"; end
  for delay=[0 16 -7 2.5]
   for rxCFO=[0 400]
    capture.RecordedReceiverTimingOffset_samples=delay;
    capture.ReceiverClockExecution=localRXReplay(delay,rxCFO);
    pre=233; post=-87;
    op=struct('ReceiveCombiningMatrix',1,'CaptureOriginCFOCorrection_Hz',pre, ...
        'AlignedOriginCFOCorrection_Hz',post,'AppliedTimingCorrection_samples',delay, ...
        'SampleRateHz',fs,'TimingApplicationPolicy',"signed_waveform_shift_fractional_phase_ramp_supported");
    actual=sixgr.util.applyFractionalSampleDelay(wave,delay);
    actual=actual.*exp(2i*pi*rxCFO*(0:size(actual,1)-1)'/fs);
    actual=actual.*exp(-2i*pi*pre*(0:size(actual,1)-1)'/fs);
    actual=sixgr.util.applyFractionalSampleDelay(actual,-delay);
    actual=actual.*exp(-2i*pi*post*(0:size(actual,1)-1)'/fs);
    received=sixgr.phy.waveform.ofdmDemodulate(carrier,actual);
    expected=sixgr.phy.rx.channelEstimate(carrier,received,indices,symbols, ...
        'UseFastMex',false,'StrictMode',true,'ChannelModel',"AWGN", ...
        'ExpectedTxPorts',1,'Method',"LS");
    snapshot=struct('Contract',channel+"_pilot_channel_capture/v1", ...
        'GridShape',[72 14 1 1],'Carrier',carrier,'ReceiverChannelOperator',op, ...
        'PilotIndices',indices,'PilotSymbols',symbols);
    [reference,evidence,unmatched,unmatchedEvidence]= ...
        sixgr.truth.sharedDataScoringWaveformReference(snapshot,prepared,wave,capture);
    assert(max(abs(reference-expected),[],'all')<1e-12 && ...
        ~evidence.GainOrPhaseFitted && ~evidence.ReceiverEstimatorInput && ...
        evidence.RecordedReceiverTimingOffset_samples==delay && ...
        evidence.ReceiverCFOIncluded && evidence.ExecutedReceiverCFO_Hz==rxCFO && ...
        ~unmatchedEvidence.ReceiverCFOIncluded);
    if rxCFO~=0
        assert(norm(reference(:)-unmatched(:))>1e-3, ...
            'The former untracked reference must remain a distinct diagnostic.');
    end
    % A real gain error must survive clock reconciliation, not be fitted out.
    score=sixgr.phy.srs.pilotChannelNMSE(2*expected,reference,indices);
    assert(abs(score.Linear-1)<1e-12 && ~score.GainOrPhaseFitted);
    cases=cases+1;
   end
  end
end
bad=rmfield(capture,'RecordedReceiverTimingOffset_samples'); caught=false;
try, sixgr.truth.sharedDataScoringWaveformReference(snapshot,prepared,wave,bad);
catch ME, caught=strcmp(ME.identifier,'sixgr:truth:MissingDataScoringTimingReplay'); end
assert(caught,'Absent executed clock evidence cannot be replaced by configuration.');
snapshot.ReceiverChannelOperator=rmfield(op,'TimingApplicationPolicy'); caught=false;
try, sixgr.truth.sharedDataScoringWaveformReference(snapshot,prepared,wave,capture);
catch ME, caught=strcmp(ME.identifier,'sixgr:truth:MissingDataScoringTimingPolicy'); end
assert(caught,'Do not guess the receiver correction operation.');
% Exercise the shared PreparedDataTransmission branch as well. A declared
% 16-sample TX shift is already in the retained reference. Only the actual
% RX endpoint delay is replayed; the flattened TX+RX sum is poisoned.
sharedCases=0;
txWave=[zeros(16,1);wave;zeros(16,1)];
tx=struct('Waveform',txWave,'Carrier',carrier, ...
    'PowerContext',struct('PAApplied',false,'PAEnabled',false));
binding=struct('PHYGrant',struct('AntennaArchitecture',struct('NumElements',1)), ...
    'Grant',struct('TimingDecision',struct('DataDecision', ...
    struct('TimingAdvanceTicks',0,'Valid',true))));
rxCfg=struct('lls6g',struct('runtime',struct('AbsoluteSlotIndex0',8)));
for direction=["DL","UL"]
  shared=sixgr.link.PreparedDataTransmission(direction,cfg,binding,tx,struct(),rxCfg,fs,0,struct(),struct());
  channel="PDSCH"; if direction=="UL", channel="PUSCH"; end
  origin=shared.ReceiveStartSample;
  for delay=[0 1 7]
   for rxCFO=[0 -700]
    ref=sixgr.phy.waveform.WaveformObservationBuffer(origin,origin+size(txWave,1),fs,1);
    ref.append(sixgr.phy.waveform.WaveformChunk(txWave,origin),fs);
    endpoint=struct('ID',"rx",'Replay',localRXReplay(delay,rxCFO));
    segment=struct('StartSample',origin,'EndSampleExclusive',origin+size(txWave,1), ...
        'Execution',struct('RX',endpoint));
    execution=struct('ReceiverID',"rx",'TransmitterID',"tx", ...
        'InjectedTimingOffset_samples',999,'InjectedCFO_Hz',99999, ...
        'ReceiveStreamExecutionSegments',{{segment}});
    source=struct('Source',"actual_executed_link_contribution", ...
        'ReceiverID',"rx",'TransmitterID',"tx",'ReceiverEstimatorInput',false, ...
        'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0, ...
        'ReceiverClockExecution',execution);
    first=16+delay;
    op=struct('ReceiveCombiningMatrix',1,'CaptureOriginCFOCorrection_Hz',233, ...
        'AlignedOriginCFOCorrection_Hz',-87,'AppliedTimingCorrection_samples',first, ...
        'SampleRateHz',fs,'TimingApplicationPolicy',"actual_capture_complete_slot_extraction_no_padding");
    actual=txWave(first-delay+1:end-delay,:);
    actual=actual.*exp(2i*pi*rxCFO*(origin+first:origin+first+size(actual,1)-1)'/fs);
    actual=actual.*exp(-2i*pi*233*(first:first+size(actual,1)-1)'/fs);
    actual=actual.*exp(2i*pi*87*(0:size(actual,1)-1)'/fs);
    received=sixgr.phy.waveform.ofdmDemodulate(carrier,actual);
    expected=sixgr.phy.rx.channelEstimate(carrier,received(:,1:14,:),indices,symbols, ...
        'UseFastMex',false,'StrictMode',true,'ChannelModel',"AWGN", ...
        'ExpectedTxPorts',1,'Method',"LS");
    snapshot=struct('Contract',channel+"_pilot_channel_capture/v1", ...
        'GridShape',[72 14 1 1],'Carrier',carrier,'ReceiverChannelOperator',op, ...
        'PilotIndices',indices,'PilotSymbols',symbols);
    [measured,e]=sixgr.truth.sharedDataScoringWaveformReference(snapshot,shared,ref,source);
    assert(max(abs(measured-expected),[],'all')<1e-12 && ...
        e.RecordedReceiverTimingOffset_samples==delay && e.ReceiverTimingIncluded && ...
        ~e.ReceiverEstimatorInput && ~e.GainOrPhaseFitted);
    sharedCases=sharedCases+1;
   end
  end
end
fprintf('DATA_SCORING_TIMING_OPERATORS_PASS cases=%d gain_error_preserved=1\n',cases);
fprintf('SHARED_DATA_SCORING_OPERATORS_PASS cases=%d TX_delay_not_reapplied=1\n',sharedCases);
ok=true;
end

function replay=localRXReplay(delay,hz)
replay=struct('InjectedTimingOffset_samples',delay,'CFOApplied',hz~=0, ...
    'InjectedCFO_Hz',hz,'RFEndpoint',"rx",'RFStageOrder',"rx_timing>rx_lo_cfo");
end
