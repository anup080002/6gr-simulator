function ok=testUplinkTruthImpairmentDirection()
% Actual SRS samples and retained CDL propagation, using a TDD configuration.
% The analytic pathloss below is explicitly a fixture, not measured access.
% No claim is made about main-scheduler integration or complete RX RF here.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),1);
runtime.CurrentSlot=5;
runtime.CurrentServingIdx(:)=1;
[cfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5,1);
cfg.lls6g.userContext.RuntimeSlotStartTime_s=4e-3;
cfg.lls6g.userContext.RuntimeServingPathloss_dB=77;
cfg.lls6g.userContext.RuntimeServingPathlossSource='unit_fixture_analytic_reference_not_field_measurement';
cfg.lls6g.userContext.RuntimeServingPathlossReferenceRS='SSB-0';
cfg.lls6g.userContext.RuntimeServingPathlossMeasurementId='unit_fixture_not_measured_access';
cfg.lls6g.userContext.RuntimeServingPathlossMeasurementSlot=1;
cfg.lls6g.userContext.RuntimeServingPathlossReferenceSignalType='SSB';
cfg.lls6g.userContext.RuntimeServingPathlossReferenceSignalId=0;
pending=sixgr.link.runSRSChannelEstimation(cfg,'SlotIndex',5, ...
    'TimingAdvanceSamples',0,'PrepareOnly',true);
p=pending.PreparedTransmission;
cfg=p.ReceiverConfig;
assert(string(cfg.lls6g.userContext.RuntimeCurrentDirection)=="UL");
% Rebuild the receiver context from its declared direction, as a shared
% owner must do independently of any one contributor's power-control state.
cfg.lls6g=rmfield(cfg.lls6g,'runtimePowerContext');
truth=sixgr.link.initWaveformTruthChannelState(cfg,p.Tx,p.TxInfo);
assert(truth.Direction=="UL" && string(truth.RuntimeChannelState.Direction)=="UL");
assert(truth.SampleRate_Hz==p.SampleRateHz && ...
    truth.RuntimeChannelState.SampleRate_Hz==p.SampleRateHz && ...
    truth.RuntimeChannelState.CurrentSampleIndex==p.StartSample, ...
    'The OFDMInfo producer rate must reach the materialized channel without a default-clock substitution.');
conflicting=p.TxInfo;
conflicting.OFDM.SampleRate=2*p.SampleRateHz;
localReject(@()sixgr.link.initWaveformTruthChannelState(cfg,p.Tx,conflicting), ...
    'sixgr:link:WaveformSampleRateConflict');
localReject(@()sixgr.link.initWaveformTruthChannelState(cfg,struct('Waveform',p.Tx.Waveform),struct()), ...
    'sixgr:link:WaveformSampleRateUnavailable');
staleRate=truth.RuntimeChannelState;
staleRate.SampleRate_Hz=2*p.SampleRateHz;
localReject(@()sixgr.link.initWaveformTruthChannelState(cfg,p.Tx,p.TxInfo, ...
    'InitialRuntimeChannelState',staleRate),'sixgr:link:WaveformSampleRateConflict');
[x,~]=sixgr.channel.projectRuntimeTransmitSamples(truth.RuntimeChannelState,p.Tx.Waveform);
% Independent clone ONLY for the unit whole-vs-chunk comparison. The tested
% stream below retains one physical fading object and never rewinds it.
wholeState=truth;
wholeState.RuntimeChannelState=sixgr.channel.ChannelFactory.forkRuntimeChannelState(truth.RuntimeChannelState);
[whole,expected,wholeState]=sixgr.link.applyWaveformTruthImpairments( ...
    x,12,wholeState,cfg,p.Tx,p.TxInfo,'InputSampleDomain','materialized_channel_ports');
assert(string(expected.PowerContextDirection)=="UL" && expected.WaveformLinkDirection=="UL");
assert(expected.NoiseFigure_dB==p.Tx.PowerContext.NoiseFigure_dB);
assert(string(expected.NoiseOperatingMode)=="receiver_noise_figure_thermal_noise");
assert(abs(10*log10(expected.InjectedNoiseVariance)-expected.ThermalNoisePower_dBm)<1e-10);
assert(expected.ChannelFadingApplied && expected.RuntimeChannelTransmitAndReceiveSwapped);
assert(~expected.RuntimeChannelAlignmentLookaheadExecutedOnFork);
assert(expected.RuntimeChannelStartSample==p.StartSample && ...
    expected.RuntimeChannelEndSample==p.EndSampleExclusive, ...
    'UL interval mismatch: channel=[%.0f,%.0f), prepared=[%.0f,%.0f), configured start=%.9g s.', ...
    expected.RuntimeChannelStartSample,expected.RuntimeChannelEndSample, ...
    p.StartSample,p.EndSampleExclusive,cfg.lls6g.userContext.RuntimeSlotStartTime_s);

wrong=cfg; wrong.lls6g.userContext.RuntimeCurrentDirection='DL';
localReject(@()sixgr.link.applyWaveformTruthImpairments(x,12,truth,wrong,p.Tx,p.TxInfo), ...
    'sixgr:link:WaveformLinkDirectionMismatch');
wrong=cfg; wrong.lls6g.runtimePowerContext=sixgr.rf.PowerContext(cfg,'DL');
localReject(@()sixgr.link.applyWaveformTruthImpairments(x,12,truth,wrong,p.Tx,p.TxInfo), ...
    'sixgr:link:WaveformLinkDirectionMismatch');
wrong=cfg; wrong.lls6g.userContext.RuntimeCurrentDirection='invalid';
localReject(@()sixgr.link.initWaveformTruthChannelState(wrong,p.Tx,p.TxInfo), ...
    'sixgr:link:InvalidWaveformLinkDirection');

actual=zeros(size(whole),'like',whole);
first=0;
for stop=unique([1 13 517 size(x,1)])
    [y,replay,truth]=sixgr.link.applyWaveformTruthImpairments( ...
        x(first+1:stop,:),12,truth,cfg,p.Tx,p.TxInfo, ...
        'InputSampleDomain','materialized_channel_ports');
    assert(replay.RuntimeChannelStartSample==p.StartSample+first);
    assert(replay.RuntimeChannelEndSample==p.StartSample+stop);
    assert(replay.InjectedNoiseVariance==expected.InjectedNoiseVariance);
    actual(first+1:stop,:)=y;
    first=stop;
end
assert(norm(actual-whole,'fro')<1e-12*max(norm(whole,'fro'),realmin), ...
    'Direction validation must not mutate the channel, and receiver noise must retain its stream.');
assert(isequaln(truth.ReceiverNoiseState,wholeState.ReceiverNoiseState));
disp('UPLINK_TRUTH_IMPAIRMENT_DIRECTION_PASS');
ok=true;
end

function localReject(f,id)
caught=false;
try, f(); catch cause, caught=strcmp(cause.identifier,id); end
assert(caught,'Expected rejection %s.',id);
end
