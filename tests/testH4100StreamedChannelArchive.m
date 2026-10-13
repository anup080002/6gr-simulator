function ok=testH4100StreamedChannelArchive()
% Exact H4 64-by-4 CDL capture through the production large-archive writer.
% A bounded channel/export test, not an access, decoding or scenario pass.
setup6GRSimToolkit('Verbose',false);
parent=fullfile(pwd,'results','diagnostics','h4_streamed_channel_archive');
if ~isfolder(parent), mkdir(parent); end
root=string(tempname(parent)); mkdir(root);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    'simulator','configs','scenarios', ...
    'h4_100_cdlc100_connected_impaired_40db_gate.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
% This test exercises coefficient storage; do not start an unrelated IQ
% instrument-package export. The production YAML remains unchanged.
cfg=sixgr.util.structSet(cfg,'outputs.continuousRawIQCaptureEnabled',false);
cfg=sixgr.util.structSet(cfg,'run.rootRunFolder',root);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),1);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[~,stream]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
assert(stream.SampleRateHz==122.88e6);
ch=stream.channelState(1,'DL');
assert(ch.NumTxAnt==64 && ch.NumRxAnt==4 && ch.UseFading);

% Drive only the initialized physical owner for 2048 samples. This is not
% a scheduled PDSCH, and the generic export envelope below claims no TRS.
count=2048;
rngStream=RandStream('Threefry','Seed',20261013);
x=0.01*complex(randn(rngStream,count,64),randn(rngStream,count,64));
events=stream.Events;
plane=stream.Physical.registerLinkScoringPlane(events,'link_1_1','ue_1_rx');
stream.Physical.requestLinkChannelReference(events,'link_1_1','ue_1_rx',0,count);
events.enqueue('gnb_1','channel_archive_component', ...
    sixgr.phy.waveform.WaveformChunk(x,0));
events.commitTransmissionsThrough('gnb_1',count);
events.commitTransmissionsThrough('ue_1',count);
% The exporter binds scoring coefficients to the actual TX and RX windows;
% register the same endpoint observations as production preparations do.
for observedPlane=["gnb_1:tx","ue_1_rx:pre_rf","ue_1_rx:post_rf",plane]
    events.observe(observedPlane,'channel_archive_component',0,count);
end
received=events.advanceUntilEvent(count);
assert(events.NextSampleIndex==count && ...
    stream.channelState(1,'DL').CurrentSampleIndex==count);
trace=events.ExecutionTrace{1}.Execution;
assert(~isfield(trace,'ChannelReferences') && ...
    ~isfield(trace.ChannelReferenceMetadata.Reference,'PathGains') && ...
    ~trace.ChannelReferenceMetadata.Reference.CoefficientArraysRetained);
envelope=struct('ExecutionStage',"trs_waveform_prepared_not_received", ...
    'SampleRateHz',stream.SampleRateHz,'TransmitStartSample',0,'NumSamples',count);
[row,~,captures]=sixgr.truth.exportSharedChannelObservation(root, ...
    table(1,'VariableNames',{'Slot'}),received.Completed,envelope,plane);
verified=sixgr.channel.validateSharedChannelObservationArtifact(root,row);
assert(string(verified.Manifest.Contract)=="actual_shared_channel_observation/v2" && ...
    string(verified.Manifest.Source)=="same_executed_NR_channel_path_gains_and_filters" && ...
    ~verified.Manifest.ReceiverEstimatorInput && verified.Manifest.AdditionalChannelExecutions==0);
segments=verified.Manifest.Segments;
assert(all([segments.NumTransmitAntennas]==64) && ...
    all([segments.NumReceiveAntennas]==4) && ...
    sum([segments.SampleTimeCount])==count);
elements=sum(cellfun(@(e)e.ElementCount,verified.PathGainReadEvidence));
peak=max(cellfun(@(e)e.MaxBlockElements,verified.PathGainReadEvidence));
assert(elements>8388608 && peak<=1048576 && ...
    all(cellfun(@(e)~e.FullArrayLoaded && e.AllFinite,verified.PathGainReadEvidence)));
snapshot=sixgr.channel.readChannelObservationSnapshot(root,row,1,17);
assert(isequal(snapshot.PathGains,captures{1}.Reference.PathGains(17,:,:,:)) && ...
    snapshot.AbsoluteSampleIndex==captures{1}.Reference.StartSample+16);
% Preserve the binding and scope with the actual coefficient files so this
% component artifact cannot be confused with a successful full H4 run.
sixgr.util.csvWriteTable(fullfile(root,'channel_observation_binding.csv'),row, ...
    'PreserveSchema',true);
sixgr.util.jsonWrite(fullfile(root,'scope.json'),struct( ...
    'Scope',"executed_H4_CDL_channel_archive_component", ...
    'ScenarioAccepted',false,'Samples',count,'ElementCount',elements, ...
    'PeakCoefficientReadElements',peak,'FullCoefficientHashVerified',true));
ok=true;
fprintf('H4_100_STREAMED_CHANNEL_ARCHIVE_PASS elements=%d peak_read=%d root=%s scenario_accepted=0\n', ...
    elements,peak,root);
end
