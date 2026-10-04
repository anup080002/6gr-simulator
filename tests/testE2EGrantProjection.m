function ok=testE2EGrantProjection()
% Explicit test fixtures, not measured PHY or primary performance evidence.
r=struct('TTI',2,'UE',1,'RNTI',4660,'CellID',1,'Direction',"DL", ...
    'PRBSet',"[1,3,7]",'PRBCount',3,'PRBStart',1,'SymbolStart',2, ...
    'NumSymbols',10,'TBSBits',240,'NumLayers',2,'CQIUsed',5,'MCSIndex',7, ...
    'TargetCodeRate',0.5,'HeadOfLineDelay_ms',2,'BufferBytesBefore',80, ...
    'BufferBytesAfter',50,'SearchSpaceID',1,'CORESETID',1,'BWPId',0, ...
    'DAI',1,'K1',4,'K2',0,'GrantReason',"test_fixture", ...
    'HarqID',3,'RV',0,'NDI',1,'IsRetransmission',false, ...
    'Ack',true,'BLER',0,'SINR_dB',20);
t=struct2table(r); t=[t;t]; t.Direction(2)="UL"; t.UE(2)=2; t.RNTI(2)=4661;
[dl,ul]=sixgr.truth.projectSystemGrantTraceForE2E(t,4,12);
assert(isempty(dl{1})&&isempty(dl{3})&&isempty(ul{4}));
assert(dl{2}.RNTI==4660&&dl{2}.UEIndex==1&&ul{2}.RNTI==4661&&ul{2}.UEIndex==2);
assert(isequal(dl{2}.PRBSet,[1 3 7])&&isequal(ul{2}.PRBSet,[1 3 7]));
assert(dl{2}.TBSBits==240&&dl{2}.TBSBytes==30&&dl{2}.NumLayers==2);
assert(isequal(dl{2}.SymbolAllocation,[2 10])&&dl{2}.HARQ.HarqID==3);
bad=t; bad.RNTI(1)=NaN; reject(bad,'InvalidGrantIdentity');
bad=t; bad.UE(1)=1.4; reject(bad,'InvalidGrantIdentity');
bad=removevars(t,'RNTI'); reject(bad,'MissingGrantEvidence');
bad=t; bad.TTI(1)=0; reject(bad,'InvalidGrantSlot');
bad=t; bad.TTI(1)=5; reject(bad,'InvalidGrantSlot');
bad=t; bad.TTI(1)=2.5; reject(bad,'InvalidGrantSlot');
bad=t; bad.PRBSet(1)="[1,1,7]"; reject(bad,'InvalidGrantAllocation');
bad=t; bad.PRBSet(1)="[1,3,12]"; reject(bad,'InvalidGrantAllocation');
bad=t; bad.PRBSet(1)="[1,3]"; reject(bad,'InvalidGrantAllocation');
bad=t; bad.PRBStart(1)=0; reject(bad,'InvalidGrantAllocation');
bad=t; bad.TBSBits(1)=239; reject(bad,'InvalidGrantAllocation');
bad=t; bad.Direction(1)="unknown"; reject(bad,'InvalidGrantDirection');
[dl,ul]=sixgr.truth.projectSystemGrantTraceForE2E(t([],:),4,12);
assert(all(cellfun(@isempty,dl))&&all(cellfun(@isempty,ul)));
fprintf('E2E_GRANT_PROJECTION_PASS exact_PRBs=1 RNTI_UE_separated=1 negative_guards=12\n');
ok=true;
end
function reject(t,suffix)
id=['sixgr:e2e:' suffix];
try
    sixgr.truth.projectSystemGrantTraceForE2E(t,4,12);
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s got %s',id,ME.identifier); return;
end
error('test:MissingRejection','Expected %s',id);
end
