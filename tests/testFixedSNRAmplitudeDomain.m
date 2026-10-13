function ok=testFixedSNRAmplitudeDomain()
% Actual OFDM samples must keep distinct normalized and absolute unit labels.
% Unit corrections must not scale samples or change the noise reference.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15);
grid=complex(zeros(300,14,2));
grid(1:48,3:12,1)=.5;
grid(61:108,3:12,2)=.5i;
[wave,ofdm]=sixgr.phy.waveform.ofdmModulate(carrier,grid);
info=struct('OFDM',ofdm,'PortGrid',grid);
cfg=struct('powerAndRF',struct('bsTxPower_dBm',30,'ueTxPower_dBm',23), ...
    'channel',struct('awgnReferenceREEnergy',.25), ...
    'integration',struct('run_mode','FIXED_SNR_SWEEP', ...
        'configured_snr_is_link_authority',true, ...
        'power_reference_mode','normalized_unit_es'));
for direction=["DL","UL"]
    referenceBefore=sixgr.link.resolveAWGNReferenceEnergy(cfg);
    [normalized,context]=sixgr.rf.applyPowerContext(wave,cfg,direction,info,'ApplyPA',false);
    assert(isequal(normalized,wave) && context.AmplitudeScale==1);
    assert(context.FixedSNRNormalizedReference && ~context.PhysicalDevicePowerClaim);
    assert(string(context.WaveformAmplitudeUnit)=="normalized_complex_baseband", ...
        'testFixedSNRAmplitudeDomain:IncorrectNormalizedUnit', ...
        'Unscaled fixed-Es samples must not claim an absolute sqrt(mW) amplitude.');
    configured=sixgr.rf.PowerContext(cfg,direction);
    assert(string(configured.WaveformAmplitudeUnit)=="normalized_complex_baseband", ...
        'Receiver noise registration must retain the same configured sample units before any TX is queued.');
    assert(sixgr.link.resolveAWGNReferenceEnergy(cfg)==referenceBefore);
    row=sixgr.phy.ra.bindStagePowerEvidence(struct(),context);
    assert(row.WaveformAmplitudeUnit=="normalized_complex_baseband" && ...
        isnan(row.AppliedTxPower_dBm) && isnan(row.MeasuredTxPowerBeforeRF_dBm));
    assert(sixgr.rf.appliedWaveformAmplitudeUnit(cfg,context)== ...
        "normalized_complex_baseband");
    wrong=context; wrong.WaveformAmplitudeUnit="sqrt_mW";
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));
    wrong=context; wrong.PhysicalDevicePowerClaim=true;
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));
    wrong=context; wrong.AmplitudeScale=2;
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));
    wrong=context; wrong.ScaleApplied=true;
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));
    wrong=context; wrong.FixedSNRNormalizedReference=[true false];
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));
    wrong=context; wrong.WaveformAmplitudeUnit=missing;
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));
    wrong=context; wrong.WaveformAmplitudeUnit=["sqrt_mW","normalized_complex_baseband"];
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));
    wrong=rmfield(context,'PhysicalDevicePowerClaim');
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,wrong));

    absolute=rmfield(cfg,'integration');
    [physical,physicalContext]=sixgr.rf.applyPowerContext( ...
        wave,absolute,direction,info,'ApplyPA',false);
    assert(string(physicalContext.WaveformAmplitudeUnit)=="sqrt_mW" && ...
        physicalContext.PhysicalDevicePowerClaim && ~physicalContext.FixedSNRNormalizedReference);
    assert(sixgr.rf.appliedWaveformAmplitudeUnit(absolute,physicalContext)=="sqrt_mW");
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(cfg,physicalContext));
    localReject(@()sixgr.rf.appliedWaveformAmplitudeUnit(absolute,context));
    expected=30; if direction=="UL", expected=23; end
    [measured,~,~]=sixgr.rf.measureActiveOFDMTotalPower(physical,info);
    assert(abs(10*log10(measured)-expected)<1e-10);
    physicalRow=sixgr.phy.ra.bindStagePowerEvidence(struct(),physicalContext);
    assert(physicalRow.WaveformAmplitudeUnit=="sqrt_mW" && ...
        abs(physicalRow.MeasuredTxPowerBeforeRF_dBm-expected)<1e-10);
end

thermal=struct('NoiseOperatingMode','receiver_noise_figure_thermal_noise', ...
    'PowerContextAmplitudeUnit','normalized_complex_baseband', ...
    'ThermalNoisePower_dBm',-100,'NoiseBandwidth_Hz',5e6,'SampleRate_Hz',ofdm.SampleRate);
try
    sixgr.link.resolveReceiverThermalNoiseVariance(thermal);
    error('testFixedSNRAmplitudeDomain:MissingThermalRejection', ...
        'Normalized samples cannot supply absolute thermal noise authority.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:link:AbsoluteThermalNoiseAuthorityRequired'));
end
thermal.PowerContextAmplitudeUnit='sqrt_mW';
assert(abs(sixgr.link.resolveReceiverThermalNoiseVariance(thermal)- ...
    10^(-100/10)*ofdm.SampleRate/5e6)<1e-20);
localSharedReceiverUnits();
fprintf('FIXED_SNR_AMPLITUDE_DOMAIN_PASS DL/UL normalized sample identity, absolute scaling and thermal rejection\n');
ok=true;
end

function localSharedReceiverUnits()
% Execute a bounded, silent-TX noise window through the real shared owner.
% This checks registration/replay units, not detector false-alarm statistics.
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    'simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg);
[~,ofdm]=sixgr.phy.waveform.ofdmModulate(carrier, ...
    complex(zeros(12*carrier.NSizeGrid,carrier.SymbolsPerSlot)));
fs=ofdm.SampleRate;
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,1);
owner.addTransmitter('unit_test_tx',cfg,'DL',4,false);
owner.addReceiver('unit_test_rx',cfg,'DL',4,false);
input=struct('ID',"unit_test_tx",'Chunk', ...
    sixgr.phy.waveform.WaveformChunk(complex(zeros(97,4)),0));
before=rng;
[outputs,execution]=owner.process(input,0,97,[]);
assert(isequal(rng,before) && numel(outputs)==3);
replay=execution.RX.Replay;
assert(string(replay.WaveformAmplitudeUnit)=="normalized_complex_baseband");
assert(abs(replay.AppliedAWGNSNR_dB-20)<1e-10 && ...
    replay.SignalEnergyPerOccupiedRE==.25);
% A stale absolute ledger must not silently enter a normalized receiver.
bad=cfg;
bad.lls6g.runtimePowerContext=sixgr.rf.PowerContext(cfg,'DL');
bad.lls6g.runtimePowerContext.WaveformAmplitudeUnit="sqrt_mW";
other=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,1);
localReject(@()other.addReceiver('unit_test_rx',bad,'DL',4,false));
end

function localReject(action)
try
    action();
catch cause
    assert(strcmp(cause.identifier,'sixgr:rf:WaveformAmplitudeAuthorityMismatch'), ...
        'Unexpected rejection: %s',cause.message);
    return;
end
error('testFixedSNRAmplitudeDomain:MissingPowerRejection', ...
    'Mismatched applied waveform units/configuration must not be queued as valid physical IQ.');
end
