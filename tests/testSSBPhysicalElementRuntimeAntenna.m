function ok = testSSBPhysicalElementRuntimeAntenna()
% An already-precoded SSB must not inherit the data logical-port interface.
setup6GRSimToolkit('Verbose',false);
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    'simulator','configs','scenarios','lls_100mhz_tdlc_bidirectional_truth.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(scenario, ...
    fullfile(tempdir,'sixgr_ssb_element_runtime_antenna'));
cfg = sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,1,1);
cfg.lls6g.userContext.RuntimeSignalFamily = "PBCH";
cfg.lls6g.userContext.RuntimeCurrentDirection = "DL";
original = cfg.lls6g.userContext;
bs = original.RuntimeServingBSAntenna;
assert(bs.NumElements==2 && bs.NumWaveformColumns==1, ...
    'Exercise the retained two-element / one-logical-port scenario.');
[wave,~,producer] = sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',2,'SSBIndex',0);
assert(producer.WaveformDomain=="physical_element_domain" && size(wave,2)==bs.NumElements);
carrier = sixgr.phy.grid.makeCarrier(cfg);
info = struct('OFDM',nrOFDMInfo(carrier));
tx = struct('Waveform',wave,'Carrier',carrier);
state = sixgr.link.initWaveformTruthChannelState(cfg,tx,info);
runtime = state.RuntimeChannelState;
assert(runtime.Materialized && runtime.UseFading && runtime.NumTxAnt==2);
assert(~runtime.ElementExpansionApplied, ...
    'Physical SSB samples must not be precoded a second time.');
assert(runtime.Meta.TransmitAntennaNumElements==bs.NumElements && ...
    runtime.Meta.TransmitAntennaNumPorts==bs.NumPorts && ...
    runtime.Meta.TransmitAntennaNumRFChains==bs.NumRFChains && ...
    runtime.Meta.TransmitAntennaNumWaveformColumns==size(wave,2) && ...
    runtime.Meta.TransmitAntennaWaveformDomain=="element");
assert(contains(runtime.Meta.TDLTransmitCorrelationMatrixSource,'runtime_element_positions_m'), ...
    'The TDL path must retain actual physical element positions.');
assert(isequaln(cfg.lls6g.userContext,original), ...
    'SSB specialization must not mutate subsequent data-channel configuration.');

% Independent explicit element-interface reference, with the same retained
% geometry and seeded fading realization. Compare samples, not only labels.
reference = cfg;
reference.lls6g.userContext.RuntimeServingBSAntenna.NumWaveformColumns = bs.NumElements;
reference.lls6g.userContext.RuntimeServingBSAntenna.WaveformDomain = "element";
reference.lls6g.userContext.RuntimeServingBSAntennaMeta.NumWaveformColumns = bs.NumElements;
reference.lls6g.userContext.RuntimeServingBSAntennaMeta.WaveformDomain = "element";
expected = sixgr.link.initWaveformTruthChannelState(reference,tx,info);
[actualSamples,replay] = sixgr.link.applyRuntimeFadingChannel(wave,state);
[expectedSamples,~] = sixgr.link.applyRuntimeFadingChannel(wave,expected);
assert(isequaln(actualSamples,expectedSamples) && all(isfinite(actualSamples(:))));
assert(~replay.RuntimeChannelElementExpansionApplied && ...
    ~replay.RuntimeChannelInputPaddedToMaterializedPorts);

% Configuration and retained geometry disagreements still fail closed.
wrong = cfg;
wrong.lls6g.userContext.RuntimeServingBSAntenna.NumElements = bs.NumElements+1;
localReject(@()sixgr.link.initWaveformTruthChannelState(wrong,tx,info), ...
    'sixgr:link:SSBRuntimeElementCountMismatch');
wrong = cfg;
wrong.lls6g.userContext.RuntimeServingBSAntennaMeta.NumElements = bs.NumElements+1;
localReject(@()sixgr.link.initWaveformTruthChannelState(wrong,tx,info), ...
    'sixgr:link:SSBRuntimeElementCountMismatch');
wrong = cfg; wrong.phy.ssb.precoderPhysicalElementCount = bs.NumElements+1;
localReject(@()sixgr.link.initWaveformTruthChannelState(wrong,tx,info), ...
    'sixgr:link:SSBPhysicalElementCountMismatch');
ok = true;
end

function localReject(action,identifier)
try
    action();
catch err
    assert(strcmp(err.identifier,identifier),'Expected %s; got %s: %s', ...
        identifier,err.identifier,err.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',identifier);
end
