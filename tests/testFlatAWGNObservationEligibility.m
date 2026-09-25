function ok=testFlatAWGNObservationEligibility()
% Declared contract fixtures, not physical-channel qualification episodes.
rf=struct('RFConfiguredStageCount',0,'RFAppliedStageCount',0, ...
    'AGCEnabled',false,'AGCApplied',false);
link=struct('TX',"tx",'RX',"rx",'Replay',struct( ...
    'RuntimeChannelTimingTruthSource',"executed_fixed_matrix_operator_zero_delay", ...
    'ChannelFadingApplied',false));
execution=struct('Links',link,'TX',struct('ID',"tx",'Replay',rf), ...
    'RX',struct('ID',"rx",'Replay',rf));
base=struct('NoiseOperatingMode',"standalone_awgn_snr_argument", ...
    'ReceiverID',"rx",'TransmitterID',"tx", ...
    'ReceiveStreamExecutionSegments',{{struct('Execution',execution)}});
expected=sixgr.phy.rx.assertFlatStaticAWGNObservation(base);
assert(~expected.ChannelCoefficientsConsumed && ~expected.InjectedNoiseVarianceConsumed);
poison=base; poison.InjectedNoiseVariance=1e20; poison.AppliedAWGNSNR_dB=Inf;
assert(isequal(expected,sixgr.phy.rx.assertFlatStaticAWGNObservation(poison)));
bad=rmfield(base,'ReceiveStreamExecutionSegments'); localReject(bad);
bad=base; bad.NoiseOperatingMode='thermal'; localReject(bad);
bad=base; bad.ReceiveStreamExecutionSegments{1}.Execution.Links.Replay.ChannelFadingApplied=true;
localReject(bad);
bad=base; bad.ReceiveStreamExecutionSegments{1}.Execution.Links.Replay.RuntimeChannelTimingTruthSource='unknown';
localReject(bad);
bad=base; bad.ReceiveStreamExecutionSegments{1}.Execution.TX.Replay.RFConfiguredStageCount=1;
localReject(bad);
bad=base; bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.RFAppliedStageCount=1;
localReject(bad);
bad=base; bad.ReceiveStreamExecutionSegments{1}.Execution.Links=[link link]; localReject(bad);
bad=rmfield(base,'ReceiverID'); localReject(bad);
bad=base; bad.ReceiveStreamExecutionSegments{1}.Execution.Links.RX="other_rx";
localReject(bad); % No actual channel to the captured receiver.
reversed=base; reversed.ReceiveStreamExecutionSegments{2}=struct('Execution',execution);
reversed.ReceiveStreamExecutionSegments{2}.Execution.Links.RX="other_rx";
e=sixgr.phy.rx.assertFlatStaticAWGNObservation(reversed);
assert(e.ActiveLinkSegmentCount==1 && e.ExecutionSegmentCount==2);
bad=reversed; bad.ReceiveStreamExecutionSegments{2}.Execution.RX.Replay.RFAppliedStageCount=1;
localReject(bad); % Still check captured receiver RF during direction-inactive segments.
agc=base;
agc.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay=struct( ...
    'RFConfiguredStageCount',1,'RFAppliedStageCount',1,'AGCEnabled',true,'AGCApplied',true);
localReject(agc); % Configured AGC is not evidence that its gain was removed.
agc.ReceiverGainCompensation=struct('GainOnlyRFExecuted',true);
sixgr.phy.rx.assertFlatStaticAWGNObservation(agc);
agc.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.RFConfiguredStageCount=2;
localReject(agc); % Inverse AGC cannot undo an ADC or another RF impairment.
fprintf('FLAT_AWGN_OBSERVATION_ELIGIBILITY_PASS metadata_contract_only=1\n');
ok=true;
end

function localReject(replay)
try
    sixgr.phy.rx.assertFlatStaticAWGNObservation(replay);
catch ex
    assert(string(ex.identifier)=="sixgr:phy:rx:FlatAWGNObservationRequired");
    return;
end
error('test:FlatEstimatorAcceptedInvalidModel','Invalid flat/white receiver model was accepted.');
end
