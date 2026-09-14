function ok=testPUSCHScheduledHARQMapping()
% Declared identity/bit-association fixtures only. No RF or scheduler claim.
setup6GRSimToolkit('Verbose',false);
cases=0;
for n=1:12
 for raw=0:3
    base=localBase(n);
    total=raw+1;
    width=n+mod(total-mod(n-1,4)-1,4); % Independent modulo-distance form.
    m=struct('BaseMapping',base,'BaseMappingDigest',base.Digest, ...
        'UEIndex',1,'RNTI',1,'TargetSlot',20,'ConfigurationEpoch',1, ...
        'BitCount',width,'PhysicalAssignmentCount',n, ...
        'ProtocolPaddingBitIndices',(n+1:width).','ULTotalDAIRaw',raw, ...
        'Source',"gnb_actual_dl_mapping_and_scheduled_ul_total_dai");
    m.Digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(m,'BaseMapping'));
    bits=int8(mod((1:width).',2));
    o=struct('MappingDigest',m.Digest,'UEIndex',1,'RNTI',1,'TargetSlot',20, ...
        'DecodedBits',bits,'DecodeOk',true,'DTXFlag',false,'Transport',"PUSCH");
    before=m;
    rows=sixgr.truth.mapScheduledPUSCHHARQFeedback(m,o);
    assert(isequaln(m,before) && numel(rows)==n && ...
        isequal([rows.ObservedAck].',logical(bits(1:n))) && ...
        all([rows.ReceiverUsable]) && all([rows.ReceiverExpectedHARQBitCount]==width));
    assert(isequal(string({rows.TransmissionID}),string({base.Records.TransmissionID})), ...
        'No protocol padding position may acquire a synthetic physical transmission row.');
    bad=o; bad.DecodedBits=[bits;int8(1)];
    failed=sixgr.truth.mapScheduledPUSCHHARQFeedback(m,bad);
    assert(numel(failed)==n && all(string({failed.FeedbackOutcome})=="DTX") && ...
        ~any([failed.ReceiverVectorLengthMatches]));
    bad=o; bad.DecodedBits=bits(1:end-1);
    failed=sixgr.truth.mapScheduledPUSCHHARQFeedback(m,bad);
    assert(~any([failed.ObservedAck]) && ~any([failed.ReceiverUsable]));
    for field=["DecodeOk","DTXFlag"]
        bad=o; bad.(field)=field=="DTXFlag";
        failed=sixgr.truth.mapScheduledPUSCHHARQFeedback(m,bad);
        assert(~any([failed.ObservedAck]) && all(string({failed.FeedbackOutcome})=="DTX"));
    end
    if width>n
        bad=o; bad.DecodedBits(n+1:end)=1-bits(n+1:end);
        same=sixgr.truth.mapScheduledPUSCHHARQFeedback(m,bad);
        assert(isequaln(rows,same),'Padding cannot update a physical HARQ process.');
        bad=o; bad.DecodedBits=double(bits); bad.DecodedBits(end)=.5;
        localReject(@()sixgr.truth.mapScheduledPUSCHHARQFeedback(m,bad),'sixgr:truth:InvalidReceivedHARQBit');
    end
    bad=o; bad.MappingDigest="other_receive_occasion";
    localReject(@()sixgr.truth.mapScheduledPUSCHHARQFeedback(m,bad),'sixgr:truth:ScheduledPUSCHHARQObservationMismatch');
    bad=o; bad.UEIndex=2;
    localReject(@()sixgr.truth.mapScheduledPUSCHHARQFeedback(m,bad),'sixgr:truth:ScheduledFeedbackContextMismatch');
    bad=m; bad.BaseMapping.Records(1).NDI=0;
    localReject(@()sixgr.truth.mapScheduledPUSCHHARQFeedback(bad,o),'sixgr:truth:ChangedScheduledFeedbackMapping');
    cases=cases+1;
 end
end
fprintf('PUSCH_SCHEDULED_HARQ_MAPPING_PASS declared_cases=%d no_RF_execution\n',cases);
ok=true;
end

function base=localBase(n)
rows=repmat(struct('BitIndex',0,'TransmissionID',"",'PHYGrantContextId',"", ...
    'UEIndex',1,'RNTI',1,'HARQProcess',0,'NDI',1,'SourceSlot',1, ...
    'TargetSlot',20,'ConfigurationEpoch',1),1,n);
for k=1:n
    rows(k).BitIndex=k; rows(k).TransmissionID="declared_tx_"+k;
    rows(k).PHYGrantContextId="declared_grant_"+k;
    rows(k).HARQProcess=k-1; rows(k).SourceSlot=k;
end
base=struct('Records',rows,'BitCount',n,'UEIndex',1,'RNTI',1,'TargetSlot',20, ...
    'ConfigurationEpoch',1,'ContextDigest',"declared_context",'LastGrant',struct(), ...
    'Source',"declared_association_fixture_not_PHY_evidence");
base.Digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(base,'LastGrant'));
end

function localReject(action,id)
try
    action();
catch err
    assert(strcmp(err.identifier,id),'Expected %s; received %s: %s',id,err.identifier,err.message);
    return;
end
error('test:ExpectedRejection','Expected %s',id);
end
