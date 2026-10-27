function state=retainRetiredInitialAccessObservation(state,item)
% Preserve original physical captures without running retired UE RX.
id='sixgr:truth:NRRRCInitialReset';
assert(item.Kind=="RetiredInitialAccess"&&isscalar(item),id,'Original retired callback required.');
state.SharedWaveformStream.validateRetiredInitialAccessCompletion(item);
archives=state.RetiredInitialNRRAAttempts;
hit=find(cellfun(@(a)a.UEIndex==item.UE && ...
    a.ResetReceipt.PhysicalRetirement.SHA256==item.Context.RetirementSHA256,archives));
assert(isscalar(hit),id,'Bind to the original completed target-UE reset.');
done=string(sixgr.util.structGet(state,'RetiredInitialAccessObservationIDs',strings(0,1)));
assert(~any(done==string(item.ID)),id,'A retired observation is retained once.');
archive=archives{hit};clock=archive.ResetReceipt.PhysicalRetirement;
planes=struct('ReceiverID',{},'StartSample',{},'EndSampleExclusive',{},'SampleRateHz',{},'SHA256',{});
for p=item.Planes
    o=p.Observation;
    assert(o.isComplete()&&o.SampleRateHz==clock.SampleRateHz&& ...
        o.EndSampleExclusive>=clock.ResetSample,id,'Keep exact completed original clock/planes.');
    planes(end+1)=struct('ReceiverID',string(p.ReceiverID),'StartSample',o.StartSample, ...
        'EndSampleExclusive',o.EndSampleExclusive,'SampleRateHz',o.SampleRateHz, ...
        'SHA256',o.sampleHash()); %#ok<AGROW>
end
receipt=struct('ObservationID',string(item.ID),'UEIndex',item.UE, ...
    'OriginalKind',item.Context.OriginalKind,'RetirementSHA256',item.Context.RetirementSHA256, ...
    'PlaneReceipts',planes,'ComponentCancelled',item.Context.ComponentCancelled, ...
    'ReceiverExecutedAfterReset',false,'MACStateUpdated',false,'RetryTriggered',false, ...
    'ActualMsg1TXCompletion',item.Context.ActualMsg1TXCompletion, ...
    'ActualAccessTXCompletion',sixgr.util.structGet(item.Context,'ActualAccessTXCompletion',struct()), ...
    'Source',"original_capture_after_initial_T300_reset_not_a_new_receive_trial");
root=state.CfgMobility.run.rootRunFolder;
folder=fullfile(root,'control','retired_initial_access');sixgr.util.ensureFolder(folder);
% Save original completed buffers/segments separately from compact metadata.
save(fullfile(folder,string(item.ID)+'.mat'),'item','receipt','-v7.3');
sixgr.util.jsonWrite(fullfile(folder,string(item.ID)+'.json'),receipt);
state.RetiredInitialAccessObservationIDs=[done(:);string(item.ID)];
end
