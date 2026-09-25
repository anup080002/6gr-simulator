function exportSharedRARObservation(runFolder,cfg,context,planes,result,family)
% Retain real monitoring samples, including silent-gNB windows. This is
% received diagnostic evidence, not a fabricated Msg2 or VSG playback file.
if nargin<6, family="RAR"; end
assert(any(family==["RAR","Contention"]),'sixgr:truth:InvalidRAMonitoringFamily','Unknown physical monitoring family.');
if ~sixgr.util.persistenceEnabled() || ...
        ~logical(sixgr.util.structGet(cfg,'outputs.rawIQCaptureEnabled',false)) || ...
        ~logical(sixgr.util.structGet(cfg,'outputs.saveRawWaveforms',false))
    return;
end
[post,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(planes);
layout=sixgr.report.resultLayout(runFolder);
folder=fullfile(layout.AirInterfaceMATDir,lower(family)+"_monitoring_observations");
sixgr.util.ensureFolder(folder);
name=string(matlab.lang.makeValidName(char(context.RunId)))+"_"+family+"_"+context.AbsoluteSlot;
target=fullfile(folder,name+".mat");
if isfile(target)
    error('sixgr:truth:DuplicateRARObservationCapture','A monitoring observation already exists: %s',target);
end
rows=result.RARMonitoringObservations;
if family=="Contention", rows=result.ContentionMonitoringObservations; end
capture=struct('Source',"actual_shared_physical_"+family+"_monitoring", ...
    'Scope',"received_monitoring_window_not_continuous_instrument_playback", ...
    'SampleRateHz',post.SampleRateHz,'StartSample',post.StartSample, ...
    'EndSampleExclusive',post.EndSampleExclusive,'Context',context, ...
    'TXAfterRF',tx.readComplete(),'RXBeforeRF',pre.readComplete(), ...
    'RXAfterRF',post.readComplete(),'RXAfterDigitalGainCompensation',receiver.readComplete(), ...
    'ExecutionReplay',replay,'ReceiverObservation',rows(end,:), ...
    'WaveformAmplitudeUnit',"sqrt_mW");
% Do not open an HDF5 writer on a deep OneDrive result pathname. Preserve
% every monitoring sample through the validated filesystem publication path.
sixgr.util.matSave(target,struct('capture',capture), ...
    'UseArtifactStore',false,'ForceV73',true);
end
