function ok = testPDCCHPreparationReception()
% Actual coded PDCCH samples; separate TX planning and received-buffer decode.
setup6GRSimToolkit('Verbose',false);
assert(nargin('sixgr.truth.runWaveformLinkBundle')==3);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.pdcch.listLength==s.get('control.blind_decode_list_length'));
cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,11);
cfg = sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSlotStartTime_s',0.010);
% An explicit deterministic codec payload, not a fabricated scheduler grant.
bits = int8(mod((0:cfg.phy.pdcch.configuredPayloadBits-1).',2));
profile clear; profile on;
cleanup = onCleanup(@()profile('off')); %#ok<NASGU>
p = sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits,'RNTI',1);
profile off; stats=profile('info');
names = string({stats.FunctionTable.FunctionName});
for forbidden = ["applyPowerContext","applyRFImpairmentChain", ...
        "applyRuntimeFadingChannel","initWaveformTruthChannelState","PDCCH_Rx"]
    assert(~any(contains(names,forbidden)),'Preparation executed %s.',forbidden);
end
assert(p.RFExecutionDeferred && p.ChannelExecutionDeferred && p.PowerExecutionDeferred);
assert(p.SampleDomain=="toolbox_normalized_logical_ports");
assert(isequal(p.TransmitSamples,p.Tx.Waveform));
assert(~isempty(p.TxInfo.AllocatedRECoordinates) && ...
    size(p.TxInfo.AllocatedRECoordinates,1)==numel(p.Tx.PDCCHInd)+numel(p.Tx.DMRSInd), ...
    'Actual control RE occupancy must be exported even without ReservedRECoordinates.');
assert(p.TxInfo.OFDM.EngineUsed=="canonical_nrOFDMModulate");
assert(p.TxInfo.OFDM.WaveformSHA256==sixgr.phy.waveform.WaveformHash.numeric(p.Tx.Waveform));
assert(p.RuntimeStartSample==round(0.010*p.SampleRateHz));
[expectedTX,expectedInfo] = sixgr.phy.dl.PDCCH_Tx(cfg,'DCIBits',bits,'RNTI',1);
assert(isequaln(p.Tx,expectedTX) && isequaln(p.TxInfo,expectedInfo));
% Canonical unit-channel receiver check. No fading/impairment claim is made
% for this part; subsequent integration checks exercise those separately.
x = p.TransmitSamples;
origin = p.RuntimeStartSample;
buffer = sixgr.phy.waveform.WaveformObservationBuffer(origin,origin+size(x,1),p.SampleRateHz,size(x,2));
split = floor(size(x,1)/2);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(1:split,:),origin),p.SampleRateHz);
localError(@()sixgr.link.completePDCCHReception(p,buffer), ...
    'WAVEFORM:IncompleteObservation');
buffer.append(sixgr.phy.waveform.WaveformChunk(x(split+1:end,:),origin+split),p.SampleRateHz);
profile clear; profile on;
[rx,info] = sixgr.link.completePDCCHReception(p,buffer);
profile off; stats=profile('info');
names = string({stats.FunctionTable.FunctionName});
assert(rx.Ok && isequal(rx.DCIBits,bits));
assert(info.ListLength==cfg.phy.pdcch.listLength);
assert(info.ObservationStartSample==origin && info.ObservationEndSampleExclusive==origin+p.NumSamples);
for forbidden = ["PDCCH_Tx","preparePDCCHTransmission","applyPowerContext", ...
        "applyRFImpairmentChain","applyRuntimeFadingChannel","initWaveformTruthChannelState"]
    assert(~any(contains(names,forbidden)),'Completion executed %s.',forbidden);
end
[direct,directInfo] = sixgr.phy.dl.PDCCH_Rx(x,cfg, ...
    'Carrier',p.Tx.Carrier,'PDCCH',p.Tx.PDCCH,'K',numel(bits), ...
    'RNTI',p.TxInfo.RNTI,'PDCCHScramblingRNTI',p.TxInfo.PDCCHScramblingRNTI, ...
    'ExpectedDCIBits',bits,'SampleRate_Hz',p.SampleRateHz,'ListLength',cfg.phy.pdcch.listLength);
assert(isequaln(rx,direct));
assert(isequaln(info.CandidateResults,directInfo.CandidateResults));
bad = p; bad.RuntimeStartSample = origin+1;
localError(@()sixgr.link.completePDCCHReception(bad,buffer), ...
    'sixgr:link:PDCCHObservationOriginMismatch');
bad = p; bad.NumSamples = p.NumSamples+1;
localError(@()sixgr.link.completePDCCHReception(bad,buffer), ...
    'sixgr:link:PDCCHObservationLayoutMismatch');
localError(@()sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits,'OFDMModulate',false), ...
    'sixgr:link:PDCCHWaveformRequired');
% Changing the decoder's configured effort must reach the receiver; it is
% not overwritten by the runtime adapter's former fixed list length 16.
cfg.phy.pdcch.listLength = 8;
p8 = sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits,'RNTI',1);
[rx8,info8] = sixgr.link.completePDCCHReception(p8,buffer);
assert(rx8.Ok && info8.ListLength==8 && isequal(rx8.DCIBits,bits));
ok = true;
disp('PDCCH_PREPARATION_RECEPTION_PASS');
end

function localError(f,identifier)
try
    f();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s', ...
        identifier,cause.identifier,cause.message);
    return;
end
error('TEST:MissingError','Expected %s.',identifier);
end
