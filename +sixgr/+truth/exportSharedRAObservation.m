function exportSharedRAObservation(runFolder,cfg,continuation,prepared,planes,received)
% Actual received control captures for offline receiver diagnosis. These
% are stage observations, NOT complete continuous VSG playback waveforms.
if ~sixgr.util.persistenceEnabled() || ...
        ~logical(sixgr.util.structGet(cfg,'outputs.rawIQCaptureEnabled',false)) || ...
        ~logical(sixgr.util.structGet(cfg,'outputs.saveRawWaveforms',false))
    return;
end
[post,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(planes);
layout=sixgr.report.resultLayout(runFolder);
folder=fullfile(layout.AirInterfaceMATDir,'ra_received_observations');
sixgr.util.ensureFolder(folder);
name=string(matlab.lang.makeValidName(char(received.RunId+"_"+prepared.StageName)))+"_"+post.StartSample;
target=fullfile(folder,name+".mat");
if isfile(target)
    error('sixgr:truth:DuplicateRAObservationCapture','A received stage capture already exists: %s',target);
end
capture=struct('Source',"actual_shared_physical_RA_stage_observation", ...
    'Scope',"received_stage_not_continuous_instrument_playback", ...
    'SampleRateHz',post.SampleRateHz,'StartSample',post.StartSample, ...
    'EndSampleExclusive',post.EndSampleExclusive,'Prepared',prepared, ...
    'TXAfterRF',tx.readComplete(),'RXBeforeRF',pre.readComplete(), ...
    'RXAfterRF',post.readComplete(),'RXAfterDigitalGainCompensation',receiver.readComplete(), ...
    'ExecutionReplay',replay,'ReceiverContinuation',continuation, ...
    'ReceivedResult',received,'WaveformAmplitudeUnit',"sqrt_mW");
temporary=string(tempname(folder))+".mat";
save(temporary,'capture','-v7.3');
[ok,message]=movefile(temporary,target);
if ~ok, error('sixgr:truth:RAObservationPublishFailed','%s',message); end
end
