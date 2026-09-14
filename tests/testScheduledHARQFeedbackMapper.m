function ok=testScheduledHARQFeedbackMapper()
% Isolated candidate test: declared receiver vectors, NOT actual UCI decode.
setup6GRSimToolkit('Verbose',false);
caseCount=0; guardCount=0;
for transport=["PUCCH","PUSCH"]
    for received={2,[1 3],[1 5]}
        ordinals=received{1}; n=max(ordinals);
        mapping=localDeclaredMapping(n);
        events=repmat(struct('DAI',1,'EventIndex',1,'PDSCHID',"", ...
            'Priority',0,'ServingCell',1,'State',"ACK",'ConfigurationEpoch',2),numel(ordinals),1);
        for k=1:numel(ordinals)
            events(k).DAI=mod(ordinals(k)-1,4)+1;
            events(k).EventIndex=ordinals(k); events(k).PDSCHID="declared-"+ordinals(k);
        end
        book=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',events,2);
        observed=localObserved(mapping,book.Bits,transport);
        original=mapping;
        rows=sixgr.truth.mapScheduledHARQFeedback(mapping,observed);
        assert(isequal(mapping,original));
        assert(numel(rows)==n && all([rows.ReceiverUsable]) && ...
            isequal(find([rows.ObservedAck]),ordinals));
        assert(all(string({rows(setdiff(1:n,ordinals)).FeedbackOutcome})=="NACK"));
        assert(isequal([rows.SourceSlot],1:n) && isequal([rows.HARQProcess],0:n-1));
        assert(~any(isfield(rows,{'ExpectedAck','FalseAck','DecodedDLCRC','PHYExecutionQualified'})));
        poisoned=observed; poisoned.ExpectedAck=false; poisoned.ExpectedBits=ones(n,1);
        poisoned.UECodebook="contradictory observer data"; poisoned.PendingFeedbackRows=table();
        assert(isequaln(rows,sixgr.truth.mapScheduledHARQFeedback(mapping,poisoned)));
        % Actual entity transitions from the association, still declared MAC.
        cfg=sixgr.config.defaultConfig(); h=sixgr.l2.mac.HARQEntity(cfg,'Direction','DL');
        layout=sixgr.phy.phycode.resolveCodingLayout('Direction','DL', ...
            'TransportBlockSize',800,'TargetCodeRate',.3,'RV',0, ...
            'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',2748);
        grant=struct('TBSBits',800,'Direction',"DL",'Modulation',"QPSK", ...
            'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout);
        for k=1:n
            allocation=h.allocate(mapping.RNTI,k,100,'NewData',true);
            assert(allocation.HARQ.HarqID==rows(k).HARQProcess);
            h.onTx(mapping.RNTI,rows(k).HARQProcess,ones(800,1,'uint8'),grant,k);
        end
        for row=rows
            assert(h.onFeedback(row.RNTI,row.HARQProcess,row.FeedbackOutcome, ...
                'SourceSlot',row.SourceSlot,'FeedbackSlot',row.TargetSlot));
        end
        assert(h.Stats.Ack==numel(ordinals) && h.Stats.Nack==n-numel(ordinals) && ...
            h.Stats.Dtx==0 && h.Stats.StaleFeedbackIgnored==0);
        caseCount=caseCount+1;
    end
end
% Associate declared bits with a retained actually transmitted DL mapping.
% This reuses scheduling evidence ONLY; it is not a new receive experiment.
saved=load('docs/lls/evidence_20260913/scheduled_harq_mapping_03/scheduled_mapping_4.mat','mapping');
mapping=saved.mapping; observed=localObserved(mapping,int8([0;1]),"PUCCH");
rows=sixgr.truth.mapScheduledHARQFeedback(mapping,observed);
assert(isequal(string({rows.TransmissionID}),string({mapping.Records.TransmissionID})) && ...
    isequal([rows.ObservedAck],[false true]));
for bits={int8([]),int8(1),int8([1;0;1])}
    bad=observed; bad.DecodedBits=bits{1};
    rows=sixgr.truth.mapScheduledHARQFeedback(mapping,bad);
    assert(all(string({rows.FeedbackOutcome})=="DTX") && ~any([rows.ReceiverUsable]) && ...
        all(string({rows.FeedbackOutcomeReason})=="receiver_vector_length_mismatch"));
    caseCount=caseCount+1;
end
for flags={[false,false],[true,true],[false,true]}
    pair=flags{1}; bad=observed; bad.DecodeOk=pair(1); bad.DTXFlag=pair(2);
    rows=sixgr.truth.mapScheduledHARQFeedback(mapping,bad);
    assert(all(string({rows.FeedbackOutcome})=="DTX") && ~any([rows.ReceiverUsable]));
    caseCount=caseCount+1;
end
for badBits={NaN,Inf,.5,2,-1,1i,"01",[1 0;0 1]}
    bad=observed; bad.DecodedBits=badBits{1};
    localReject(@()sixgr.truth.mapScheduledHARQFeedback(mapping,bad),'sixgr:truth:InvalidReceivedHARQBit');
    guardCount=guardCount+1;
end
for field=["DecodeOk","DTXFlag"]
    for badValue={NaN,Inf,2,[true false],"true",1i}
        bad=observed; bad.(field)=badValue{1};
        localReject(@()sixgr.truth.mapScheduledHARQFeedback(mapping,bad),'sixgr:truth:InvalidScheduledFeedbackFlag');
        guardCount=guardCount+1;
    end
end
for field=["RNTI","UEIndex","TargetSlot"]
    bad=observed; bad.(field)=bad.(field)+1;
    localReject(@()sixgr.truth.mapScheduledHARQFeedback(mapping,bad),'sixgr:truth:ScheduledFeedbackContextMismatch');
    guardCount=guardCount+1;
end
bad=observed; bad.MappingDigest="changed";
localReject(@()sixgr.truth.mapScheduledHARQFeedback(mapping,bad),'sixgr:truth:ScheduledFeedbackContextMismatch');
guardCount=guardCount+1;
bad=mapping; bad.Records(2).BitIndex=1;
localReject(@()sixgr.truth.mapScheduledHARQFeedback(bad,observed),'sixgr:truth:ChangedScheduledFeedbackMapping');
guardCount=guardCount+1;
bad.Digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(bad,{'LastGrant','Digest'}));
localReject(@()sixgr.truth.mapScheduledHARQFeedback(bad,observed),'sixgr:truth:InvalidScheduledFeedbackMapping');
guardCount=guardCount+1;
bad=rmfield(observed,'MappingDigest');
localReject(@()sixgr.truth.mapScheduledHARQFeedback(mapping,bad),'sixgr:truth:MissingScheduledFeedbackBinding');
guardCount=guardCount+1;
bad=observed; bad.Transport="unknown";
localReject(@()sixgr.truth.mapScheduledHARQFeedback(mapping,bad),'sixgr:truth:InvalidScheduledFeedbackTransport');
guardCount=guardCount+1;
fprintf('SCHEDULED_HARQ_MAPPER_PASS cases=%d guards=%d declared_receiver_vectors=1 live_runtime_integration=0 actual_UCI_reception=0\n',caseCount+1,guardCount);
ok=true;
end

function observed=localObserved(mapping,bits,transport)
observed=struct('MappingDigest',mapping.Digest,'UEIndex',mapping.UEIndex, ...
    'RNTI',mapping.RNTI,'TargetSlot',mapping.TargetSlot,'DecodedBits',bits, ...
    'DecodeOk',true,'DTXFlag',false,'Transport',transport);
end

function mapping=localDeclaredMapping(n)
records=repmat(struct('BitIndex',1,'TransmissionID',"",'PHYGrantContextId',"", ...
    'UEIndex',1,'RNTI',321,'HARQProcess',0,'NDI',true,'SourceSlot',1, ...
    'TargetSlot',10,'ConfigurationEpoch',2),1,n);
for k=1:n
    records(k).BitIndex=k; records(k).TransmissionID="declared-TX-"+k;
    records(k).PHYGrantContextId="declared-context-"+k;
    records(k).HARQProcess=k-1; records(k).SourceSlot=k;
end
mapping=struct('Records',records,'BitCount',n,'UEIndex',1,'RNTI',321, ...
    'TargetSlot',10,'ConfigurationEpoch',2,'ContextDigest',"declared-context", ...
    'LastGrant',struct(),'Source',"declared_MAC_fixture_not_physical_execution");
mapping.Digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(mapping,'LastGrant'));
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingExpectedError','Expected %s',id);
end
