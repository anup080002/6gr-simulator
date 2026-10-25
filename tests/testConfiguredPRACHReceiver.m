function [ok,result]=testConfiguredPRACHReceiver()
% One native Msg1 waveform and actual receiver calls on unit/silent samples.
% No shared RF/channel, cell monitor arming, decoded SI or RA acceptance.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
parent=fullfile(pwd,'results','validation','configured_prach_receiver');
sixgr.util.ensureFolder(parent);
folder=tempname(parent); sixgr.util.ensureFolder(folder);
fprintf('CONFIGURED_PRACH_RECEIVER_EVIDENCE %s\n',folder);
cfg=raStrictAnchorConfig();
ra=sixgr.mac.ra.RAConfig(cfg,'RunId',"configured_receiver_native_fixture");
[tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(cfg,ra);
prachCfg=sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg,ra);
originalWaveform=tx.Waveform;
originalSHA=sixgr.phy.waveform.WaveformHash.runtimeArray(originalWaveform);
save(fullfile(folder,'original_native_input.mat'),'cfg','ra','prachCfg','tx','occasion','originalSHA');

% Existing production entry delegates to the new source-independent receiver.
actual=sixgr.phy.ra.detectConfiguredPRACH(originalWaveform,cfg,prachCfg,occasion);
legacy=sixgr.phy.ra.detectMsg1PRACH(originalWaveform,cfg,ra,occasion);
wrong=ra; wrong.PreambleIndex=mod(ra.PreambleIndex+1,64);
mismatch=sixgr.phy.ra.detectMsg1PRACH(originalWaveform,cfg,wrong,occasion);
save(fullfile(folder,'actual_receiver_results.mat'),'actual','legacy','mismatch','wrong');
assert(actual.Detected&&actual.DetectedPreambleIndex==ra.PreambleIndex);
assert(~isfield(actual,'RAPIDMatchesTx')&&legacy.RAPIDMatchesTx&&~mismatch.RAPIDMatchesTx);
assert(isequaln(actual,rmfield(legacy,'RAPIDMatchesTx'))&& ...
    isequaln(actual,rmfield(mismatch,'RAPIDMatchesTx')), ...
    'UE TX-identity mismatch must change only the downstream diagnostic, not reception.');
assert(isequal(actual.CandidatePreambles,(0:63).')&&actual.CandidateCount==64&& ...
    actual.Threshold==cfg.random_access.detection_threshold&& ...
    contains(actual.DetectorBackend,"nrPRACHDetect"));

% Remove the UE preamble/beam inputs entirely. Native receiver hypotheses
% still carry their public template, but every candidate is independently
% searched; no known transmitted preamble is supplied to this API.
blindCfg=cfg;
remove=intersect(fieldnames(blindCfg.random_access), ...
    {'preamble_index','associated_ssb_index','associated_ssb_selection_source'});
blindCfg.random_access=rmfield(blindCfg.random_access,remove);
blindPRACH=rmfield(prachCfg,'PreambleIndex');
blind=sixgr.phy.ra.detectConfiguredPRACH(originalWaveform,blindCfg,blindPRACH,occasion);
assert(isequaln(actual,blind),'Receiver may not require the UE transmitted-preamble operand.');

% Actual zero-valued samples traverse the same native detector, not a
% synthesized DTX/miss row or an early outcome bypass.
silent=zeros(size(originalWaveform),'like',originalWaveform);
silentActual=sixgr.phy.ra.detectConfiguredPRACH(silent,blindCfg,blindPRACH,occasion);
silentLegacy=sixgr.phy.ra.detectMsg1PRACH(silent,cfg,ra,occasion);
save(fullfile(folder,'silent_receiver_results.mat'),'silent','silentActual','silentLegacy');
assert(~silentActual.Detected&&isnan(silentActual.DetectedPreambleIndex)&& ...
    ~silentActual.PropagationTimingEstimateValid&& ...
    isnan(silentActual.PropagationTimingOffsetSamples)&& ...
    ~isfield(silentActual,'RAPIDMatchesTx')&&~silentLegacy.RAPIDMatchesTx);
assert(isequaln(silentActual,rmfield(silentLegacy,'RAPIDMatchesTx'))&& ...
    isequal(silentActual.CandidatePreambles,(0:63).'));

% Declared capture pre-guard changes the input origin, not the actual
% correlation samples or measured propagation relative to the known RO.
guard=37;
guardedCfg=blindCfg;
guardedCfg.lls6g.receiverSync.ReceivedWaveformTimingPlane="untrimmed_shared_physical_receive_stream";
guardedCfg.lls6g.receiverSync.ChannelFilterDelay_samples=0;
guardedCfg.lls6g.receiverSync.ULObservationSearchGuard_samples=guard;
guardedInput=[zeros(guard,size(originalWaveform,2),'like',originalWaveform);originalWaveform];
guarded=sixgr.phy.ra.detectConfiguredPRACH(guardedInput,guardedCfg,blindPRACH,occasion);
save(fullfile(folder,'guarded_receiver_result.mat'),'guardedInput','guardedCfg','guarded');
assert(guarded.Detected&&guarded.DetectedPreambleIndex==actual.DetectedPreambleIndex&& ...
    isequaln(guarded.CorrelationPeaks,actual.CorrelationPeaks)&& ...
    guarded.RawTimingOffsetSamples==actual.RawTimingOffsetSamples+guard&& ...
    guarded.PropagationTimingOffsetSamples==actual.PropagationTimingOffsetSamples&& ...
    guarded.DetectorInputStartOffsetSamples==guard&& ...
    guarded.PropagationTimingEstimateSource== ...
        "nrPRACHDetect_measured_round_trip_relative_gnb_common_offset_window");
reject(@()sixgr.phy.ra.detectConfiguredPRACH(guardedInput(1:guard,:), ...
    guardedCfg,blindPRACH,occasion),'sixgr:phy:ra:IncompletePRACHReceiveWindow');
reject(@()sixgr.phy.ra.detectConfiguredPRACH(originalWaveform,cfg,ra,occasion), ...
    'sixgr:phy:ra:ConfiguredPRACHReceiverRequired');
reject(@()sixgr.phy.ra.detectConfiguredPRACH(originalWaveform,cfg,prachCfg,struct()), ...
    'sixgr:phy:ra:ConfiguredPRACHOccasionRequired');
assert(isequaln(tx.Waveform,originalWaveform)&& ...
    string(originalSHA)==string(sixgr.phy.waveform.WaveformHash.runtimeArray(tx.Waveform)));
result=struct('Scope',"native_PRACH_unit_and_silent_receiver_not_cell_monitor_or_RA", ...
    'NativeTXCount',1,'ReceiverCalls',7,'EvidenceFolder',string(folder), ...
    'OriginalWaveformSHA256',string(originalSHA));
ok=true;
fprintf('PASS testConfiguredPRACHReceiver: nativeTX=1 receiverCalls=7; sharedRF=0 cellMonitor=0 RA=0\n');
end

function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s.',id,cause.identifier);
    return;
end
error('sixgr:test:ConfiguredPRACHGuardMissing','Expected %s.',id);
end
