function ok=testReceivedAccessBindings()
% Declared ownership fixtures, not claimed physical access observations.
cfg=sixgr.config.defaultConfig();
fs=30.72e6; n=fs*sixgr.time.slotDurationSec(cfg);
items=cell(2,1);
for ue=1:2
    issued=sixgr.mac.ra.buildMsg4ContentionResolution("001122334455",'FinalCRNTI',4660+ue-1);
    msg=sixgr.mac.ra.parseMsg4ContentionResolution(issued.PayloadBits);
    slot=19+20*(ue-1);
    rows=table("RRCSetupComplete",slot,slot*n,(slot+1)*n,fs,(slot+1)*n/fs, ...
        "complete_contiguous_received_sample_buffer",'VariableNames', ...
        {'StageName','StageSlot','ObservationStartSample','ObservationEndSampleExclusive', ...
        'ObservationSampleRateHz','ObservationCompletionTime_s','ObservationCoverageSource'});
    result=struct('RACompleted',true,'StrictOk',true,'RequireRRCSetupComplete',true, ...
        'Msg4ScheduledSlot',slot-2,'SetupCompleteScheduledSlot',slot, ...
        'RRCSetupCompleteCRC',true,'RRCSetupCompleteDecoded',true,'RRCConnected',true, ...
        'RuntimeStageRows',rows,'DecodedMsg4',msg,'Msg4PDCCHCrcPass',true, ...
        'Msg4PDSCHCrcPass',true,'Msg3ContentionIdentity',msg.ContentionIdentity, ...
        'UEId',ue,'CellId',1);
    items{ue}=struct('UEIndex',ue,'ServingCellIndex',1,'Result',result);
end
map=sixgr.system.resolveReceivedAccessBindings(cfg,flipud(items),2);
assert(isequal(map.UEIndex,[1;2]) && isequal(map.RNTI,[4660;4661]) && ...
    isequal(map.BlockedSlotCount,[20;40]));
bad=items; bad{2}.Result.DecodedMsg4.FinalCRNTI=1;
map=sixgr.system.resolveReceivedAccessBindings(cfg,bad,2);
assert(map.RNTI(2)==4661,'Received bytes, not relabelled metadata, own identity.');
reject(@()sixgr.system.resolveReceivedAccessBindings(cfg,items(1),2), ...
    'sixgr:system:MissingUEAccessReceipt');
bad=items; bad{2}=bad{1};
reject(@()sixgr.system.resolveReceivedAccessBindings(cfg,bad,2), ...
    'sixgr:system:DuplicateUEAccessReceipt');
bad=items; bad{2}.Result.DecodedMsg4=bad{1}.Result.DecodedMsg4;
reject(@()sixgr.system.resolveReceivedAccessBindings(cfg,bad,2), ...
    'sixgr:system:DuplicateReceivedCRNTI');
bad{2}.ServingCellIndex=2;
map=sixgr.system.resolveReceivedAccessBindings(cfg,bad,2);
assert(all(map.RNTI==4660),'Equal C-RNTI in different serving cells is not an alias.');
bad=items; bad{2}.Result.UEId=1;
reject(@()sixgr.system.resolveReceivedAccessBindings(cfg,bad,2), ...
    'sixgr:system:UEAccessOwnerMismatch');
bad=items; bad{2}.Result.RRCConnected=false;
reject(@()sixgr.system.resolveReceivedAccessBindings(cfg,bad,2), ...
    'sixgr:truth:IncompleteRRCSetupComplete');
bad=items; bad{2}.Result.Msg4PDCCHCrcPass=false;
reject(@()sixgr.system.resolveReceivedAccessBindings(cfg,bad,2), ...
    'sixgr:mac:ra:UnacceptedMsg4Identity');
ok=true;
end
function reject(fn,id)
try, fn(); catch e, assert(strcmp(e.identifier,id),'Expected %s got %s',id,e.identifier); return; end
error('test:MissingRejection','Expected %s',id);
end
