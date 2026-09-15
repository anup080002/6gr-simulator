function ok=testPUSCHHARQDecisionAudit()
% Codec/CSV and declared-observation fixtures, not physical detector evidence.
setup6GRSimToolkit('Verbose',false);
audit=table(); prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(92421,'twister');
for k=1:4
    count=1; if k>=3, count=20; end
    [context,observation]=fixture(count,10*k);
    if k<=3
        bits=ones(count,1,'int8'); code=nrUCIEncode(bits,192,'QPSK');
        y=find(code==-2); code(y)=code(y-1); code(code==-1)=1;
        scale=10; if k==2, scale=1e-4; end
        [bits,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(scale*(1-2*double(code)),count,'QPSK');
    else
        failed=false;
        for attempt=1:16
            [bits,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(randn(192,1),count,'QPSK');
            if e.CRCPass==0, failed=true; break; end
        end
        assert(failed,'The authored noise codec fixture must expose an actual CRC failure.');
    end
    rx=struct('DecodedHARQACKBits',bits,'UCIReceiverEvidence',struct( ...
        'ReceiverContextDigest',context.Digest,'HARQACK',e));
    audit=sixgr.truth.appendPUSCHHARQDecisionAudit(audit,rx,context,observation,observation.EndSampleExclusive);
    assert(height(audit)==k && audit.ReceiverUsable(k)==e.DecodeUsable && ...
        audit.ReceiverErasure(k)==~e.DecodeUsable && audit.DecoderWordUsable(k)==e.DecoderWordUsable && ...
        isequal(jsondecode(audit.DecodedBitsJSON(k)),double(bits(:))) && ...
        audit.AvailableAtSample(k)==observation.EndSampleExclusive);
    reject(@()sixgr.truth.appendPUSCHHARQDecisionAudit(audit,rx,context,observation,observation.EndSampleExclusive), ...
        'sixgr:truth:DuplicatePUSCHHARQDecisionAudit');
    [~,other]=fixture(count,100+k);
    reject(@()sixgr.truth.appendPUSCHHARQDecisionAudit(table(),rx,context,other,other.EndSampleExclusive), ...
        'sixgr:truth:PUSCHHARQAuditObservationMismatch');
end
assert(audit.ReceiverUsable(1) && ~audit.ReceiverUsable(2) && ...
    audit.DecoderWordUsable(2)==1 && audit.ConfidenceAccepted(2)==0 && ...
    audit.DecisionReason(2)=="insufficient_conditional_codeword_confidence");
assert(all(isnan(audit.CRCPass(1:2))) && audit.CRCPass(3)==1 && audit.CRCPass(4)==0 && ...
    all(isnan(audit.SelectedPosterior(3:4))) && ~any(audit.ShortConfidenceAttempted(3:4)));
[context,observation]=fixture(1,50);
unattempted=struct('NoiseVarStrictFailure',true,'DecodeAttempted',false, ...
    'ULSCHDecodeAttempted',false,'ReceiverUsable',false);
audit=sixgr.truth.appendPUSCHHARQDecisionAudit(audit,unattempted,context,observation,observation.EndSampleExclusive);
assert(~audit.DecodeAttempted(end) && isnan(audit.DecoderWordUsable(end)) && ...
    ~audit.ShortConfidenceAttempted(end) && isnan(audit.CRCPass(end)) && ...
    audit.ReceiverErasure(end) && audit.DecisionReason(end)=="not_decoded_strict_noise_gate");
[emptyContext,emptyObservation]=fixture(0,60);
[bits,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence([],0,'QPSK');
rx=struct('DecodedHARQACKBits',bits,'UCIReceiverEvidence',struct( ...
    'ReceiverContextDigest',emptyContext.Digest,'HARQACK',e));
empty=sixgr.truth.appendPUSCHHARQDecisionAudit(table(),rx,emptyContext,emptyObservation,emptyObservation.EndSampleExclusive);
assert(isempty(empty),'No fabricated HARQ row for a zero-bit occasion.');
root=tempname(fullfile(pwd,'logs')); mkdir(root);
path=fullfile(root,'pusch_harq_receiver_decisions.csv');
sixgr.util.csvWriteTable(path,audit,'PreserveSchema',true,'RoundTripNumericText',true);
loaded=sixgr.util.csvReadTable(path,'TextType','string');
save(fullfile(root,'declared_codec_audit.mat'),'audit','loaded');
assert(isequal(audit.Properties.VariableNames,loaded.Properties.VariableNames) && height(audit)==height(loaded));
% CSV has no MATLAB type metadata. Restore the declared schema only after
% checking logical values and blank strings; numeric evidence remains exact.
for name=string(audit.Properties.VariableNames)
    expected=audit.(name); actual=loaded.(name);
    if islogical(expected)
        assert(all(actual==0 | actual==1),'Nonbinary logical evidence in %s.',name);
        loaded.(name)=logical(actual);
    elseif isstring(expected)
        assert(isstring(actual),'Text evidence lost in %s.',name);
        blanks=ismissing(actual);
        assert(all(expected(blanks)==""),'Nonblank text evidence lost in %s.',name);
        actual(blanks)=""; loaded.(name)=actual;
    end
end
assert(isequaln(audit,loaded),'CSV must preserve actual evidence, including NaN for unavailable/not-applicable metrics.');
% Values immediately either side of a gate must not be rounded onto it.
boundary=table([0.99-eps(0.99);0.99;0.99+eps(0.99);NaN;Inf;-Inf], ...
    ["0";"1";"[]";"[0,1]";"0";"1"],'VariableNames',{'Posterior','DecodedBitsJSON'});
boundaryPath=fullfile(root,'boundary.csv');
sixgr.util.csvWriteTable(boundaryPath,boundary,'PreserveSchema',true,'RoundTripNumericText',true);
back=sixgr.util.csvReadTable(boundaryPath,'TextType','string');
assert(isequaln(boundary,back),'Decision-boundary doubles and scalar bit JSON must round-trip exactly.');
fprintf('PUSCH_HARQ_DECISION_AUDIT_PASS rows=%d csv_roundtrip=1 physical_qualification=0 root=%s\n',height(audit),root);
ok=true;
end

function [context,observation]=fixture(count,start)
observation=sixgr.phy.waveform.WaveformObservationBuffer(start,start+8,1000,1);
observation.append(sixgr.phy.waveform.WaveformChunk(complex(ones(8,1)),start),1000);
assignment="declared_codec_assignment";
window=struct('AssignmentDigest',assignment,'StartSample',observation.StartSample, ...
    'EndSampleExclusive',observation.EndSampleExclusive,'SampleRateHz',observation.SampleRateHz, ...
    'NumReceiveAntennas',observation.NumReceiveAntennas);
mapping=""; if count>0, mapping="declared_harq_mapping"; end
context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
    'ObservationID',"PUSCH-UCI-"+sixgr.phy.pucch.PUCCHUtil.hash(window), ...
    'ConfigurationEpoch',0,'AssignmentDigest',assignment,'HARQMappingDigest',mapping, ...
    'HARQACKBitCount',count,'ConfiguredGrantUCIBitCount',0, ...
    'CSIReportConfigID',"",'CSIConfigurationEpoch',NaN));
end

function reject(action,id)
try, action(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
