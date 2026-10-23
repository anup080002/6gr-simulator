function [ok,checks]=testSharedDLSCHOutcomeBinding()
% Actual native single-CW codec outcomes plus declared accounting fixtures.
% No shared waveform/control/owner is authored; positive production-owner
% coverage belongs to the existing received-CSI -> PDSCH continuation.
setup6GRSimToolkit('Verbose',false);
rows=repmat(struct('Case',"",'Passed',false,'FailureID',"",'Detail',""),0,1);
[pass,passHARQ]=localDecodedRow(false);
[fail,failHARQ]=localDecodedRow(true);
record("actual_native_CRC_positive_and_negative_capsules",@decoders);
record("unavailable_is_not_missing_completed_capsule",@availability);
record("original_decoder_token_payload_and_identity_guards",@decoderGuards);
record("actual_credit_first_repeated_failed_and_unavailable",@credits);
record("credit_transplant_and_extra_ledger_mutation_guards",@creditGuards);
record("original_owner_required_and_canonical_call_order",@ownerBoundary);
checks=struct2table(rows);
for k=find(~checks.Passed).'
    fprintf(2,'SHARED_DLSCH_BIND %s FAIL %s %s\n',checks.Case(k),checks.FailureID(k),checks.Detail(k));
end
fprintf('SHARED_DLSCH_BIND cases=%d failures=%d native_codec=1 declared_accounting=1 shared_physical_owner=0\n', ...
    height(checks),nnz(~checks.Passed));
assert(all(checks.Passed),'test:SharedDLSCHOutcomeBinding:Failed', ...
    '%d/%d bridge boundary cases failed.',nnz(~checks.Passed),height(checks));
ok=true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'FailureID',"",'Detail',"");
        try, fn(); row.Passed=true;
        catch cause
            row.FailureID=string(cause.identifier); row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
    function decoders()
        assert(sixgr.truth.SharedDLSCHOutcomeBinding.requiresBinding(pass)&& ...
            sixgr.truth.SharedDLSCHOutcomeBinding.requiresBinding(fail));
        [p,a]=sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(pass,passHARQ);
        [f,b]=sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(fail,failHARQ);
        assert(a.CRCPass&&~b.CRCPass&&a.NumCodewords==1&&b.NumCodewords==1&& ...
            a.Codewords{1}.CodewordIndex==0&&a.CodewordIndexBase==0&& ...
            a.SuccessfulDecodedBits==512&&b.SuccessfulDecodedBits==0&& ...
            ~a.MACDeliveryQualified&&~b.MACDeliveryQualified&& ...
            p.DLSCHFinalOutcomeJSON==pass.DLSCHFinalOutcomeJSON&& ...
            f.DLSCHFinalOutcomeSHA256==fail.DLSCHFinalOutcomeSHA256);
    end
    function availability()
        absent=localNoReceipt(pass); absent.DecodeAttempted=false; absent.DLSCHDecodeAttempted=false;
        absent.CRCApplicable=false; absent.CRCPass=NaN;
        assert(~sixgr.truth.SharedDLSCHOutcomeBinding.requiresBinding(absent));
        anchor=sixgr.truth.SharedDLSCHOutcomeBinding.capture(struct(),struct(),struct(),struct(),absent,[],struct());
        assert(isstruct(anchor)&&isempty(fieldnames(anchor)));
        crashed=localNoReceipt(pass); crashed.Crash=true; crashed.CRCPass=NaN;
        assert(~sixgr.truth.SharedDLSCHOutcomeBinding.requiresBinding(crashed));
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.requiresBinding(localNoReceipt(pass)), ...
            'sixgr:truth:SharedDLSCHDecoderBinding');
        bad=absent; bad.DLSCHFinalOutcomeAvailable=true;
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.requiresBinding(bad),'sixgr:truth:SharedDLSCHDecoderBinding');
        bad=absent; bad.DLSCHFinalOutcomeJSON="populated_without_decoder";
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.requiresBinding(bad),'sixgr:truth:SharedDLSCHDecoderBinding');
    end
    function decoderGuards()
        id='sixgr:truth:SharedDLSCHDecoderBinding';
        bad=pass; bad.DLSCHFinalOutcomeSHA256="changed";
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(bad,passHARQ),id);
        bad=pass; payload=jsondecode(char(bad.DLSCHFinalOutcomeJSON)); payload.SourceRow.Slot=99;
        bad.DLSCHFinalOutcomeJSON=string(jsonencode(payload));
        bad.DLSCHFinalOutcomeSHA256=string(sixgr.util.sha256Hex(char(bad.DLSCHFinalOutcomeJSON)));
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(bad,passHARQ),id);
        bad=passHARQ; bad.FinalDecodedTransportBlocks{1}(1)=1-bad.FinalDecodedTransportBlocks{1}(1);
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(pass,bad),id);
        bad=passHARQ; bad.CombinedDecodeOK=false;
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(pass,bad),id);
        for value=[NaN 2 Inf -1]
            bad=passHARQ; bad.CombinedDecodeOK=value;
            reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(pass,bad),id);
        end
        bad=pass; bad.CRCPass=false;
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateDecoderRow(bad,passHARQ), ...
            'sixgr:link:DLSCHFinalOutcomeBinding');
        sixgr.truth.SharedDLSCHOutcomeBinding.validateFinalCRC(pass,true);
        sixgr.truth.SharedDLSCHOutcomeBinding.validateFinalCRC(fail,false);
        for value=[NaN 2 Inf -1]
            bad=pass; bad.CRCPass=value;
            reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateFinalCRC(bad,true), ...
                'sixgr:truth:SharedDLSCHFinalRowBinding');
        end
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateFinalCRC(fail,true), ...
            'sixgr:truth:SharedDLSCHFinalRowBinding');
    end
    function credits()
        first=sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot([]);
        [t,L]=localCredit(pass,[]);
        c=sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(t,first,L);
        assert(c.Available&&c.UniqueDeliveredTBBits==512&&c.FirstSuccessfulTBDelivery&& ...
            c.TargetEntryDelta==1&&~c.ExecutionProof&&c.AccountingOnly);
        before=sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot(L);
        [repeat,L2]=localCredit(pass,L);
        c=sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(repeat,before,L2);
        assert(c.Available&&c.UniqueDeliveredTBBits==0&&~c.FirstSuccessfulTBDelivery&& ...
            c.TargetEntryDelta==0&&repeat.DLSCHSuccessfulDecodedBits==512&&repeat.DecodedAttemptBits==512&& ...
            isequaln(L,L2)&&repeat.DLSCHFinalOutcomeJSON==pass.DLSCHFinalOutcomeJSON);
        [failed,L2]=localCredit(fail,L);
        c=sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(failed,before,L2);
        assert(c.Available&&c.UniqueDeliveredTBBits==0&&c.Status=="crc_failure_no_delivery"&&isequaln(L,L2));
        unknown=removevars(pass,'TBId');
        [unknown,L2]=localCredit(unknown,L);
        c=sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(unknown,before,L2);
        assert(~c.Available&&isnan(c.UniqueDeliveredTBBits)&&unknown.DLSCHSuccessfulDecodedBits==512&&isequaln(L,L2));
    end
    function creditGuards()
        before=sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot([]); [t,L]=localCredit(pass,[]);
        for field=["UniqueDeliveredTBBits","FirstSuccessfulTBDelivery","TransportGoodputKey", ...
                "TransportGoodputStatus","TransportGoodputDefinition","TransportGoodputContract", ...
                "UniqueTransportGoodput_Mbps"]
            bad=removevars(t,field);
            reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(bad,before,L), ...
                'sixgr:truth:SharedDLSCHTransportCredit');
        end
        for value=[NaN 2 Inf -1]
            bad=t; bad.FirstSuccessfulTBDelivery=value;
            reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(bad,before,L), ...
                'sixgr:truth:SharedDLSCHTransportCredit');
        end
        bad=L; bad.Key(end+1,1)="unrelated_extra_entry"; bad.PayloadBits(end+1,1)=8;
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(t,before,bad),'sixgr:truth:SharedDLSCHTransportCredit');
        bad=L; bad.PayloadBits(1)=504;
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(t,before,bad),'sixgr:truth:SharedDLSCHTransportCredit');
        bad=t; bad.UniqueDeliveredTBBits=256; bad.GoodBits=256;
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(bad,before,L),'sixgr:kpi:InvalidTransportGoodputCredit');
        bad=t; bad.GoodBits=0;
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.validateCredit(bad,before,L),'sixgr:truth:SharedDLSCHTransportCredit');
        bad=L; bad.Key(end+1,1)=bad.Key(1); bad.PayloadBits(end+1,1)=bad.PayloadBits(1);
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.ledgerSnapshot(bad),'sixgr:truth:SharedDLSCHTransportCredit');
    end
    function ownerBoundary()
        reject(@()sixgr.truth.SharedDLSCHOutcomeBinding.capture(struct(),struct(),struct(),struct(),pass,[],struct()), ...
            'sixgr:truth:SharedDLSCHOwnerRequired');
        source=fileread(which('sixgr.truth.SharedDataCompletionRuntime'));
        markers={'decoderTrial=res.TrialTable;','SharedDLSCHOutcomeBinding.capture(', ...
            '[state,trial]=sixgr.truth.CoupledTruthRuntime.completeSlot(', ...
            'plan.TrialTable=sixgr.link.applyScheduledOperatingPointEvidence(trial);', ...
            'SharedDLSCHOutcomeBinding.bind('};
        positions=zeros(1,numel(markers));
        for k=1:numel(markers)
            hits=strfind(source,markers{k}); assert(isscalar(hits)); positions(k)=hits;
        end
        assert(all(diff(positions)>0),'Keep original capture before MAC credit and final binding after annotation.');
    end
end

function [t,h]=localDecodedRow(corruptCRC)
A=512; rate=.3; G=1800; bits=int8(mod((1:A).',2));
plan=sixgr.pdsch.DLSCHCodingPlan.resolve('TransportBlockSize',A,'TargetCodeRate',rate, ...
    'RV',0,'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',G,'CodewordIndex',0);
info=nrDLSCHInfo(A,rate); crc=nrCRCEncode(bits,info.CRC);
if corruptCRC, crc(end)=1-crc(end); end
coded=nrLDPCEncode(nrCodeBlockSegmentLDPC(crc,info.BGN),info.BGN);
matched=nrRateMatchLDPC(coded,G,0,'QPSK',1);
d=sixgr.pdsch.DLSCHDecoder(20*(1-2*double(matched)), ...
    'CodingPlan',plan,'MaxIterations',25,'Algorithm','Normalized min-sum');
assert(d.CRCPass==~corruptCRC&&isequal(d.TransportBlock,bits));
cfg=struct('phy',struct('ldpc',struct('maxIterations',25,'algorithm','Normalized min-sum')));
[selection,decoded]=sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg);
t=table("DL",2,17,d.CRCPass,false,true,true,true,A,A*double(d.CRCPass), ...
    A*double(d.CRCPass)/.001/1e6,1,"declared_codec_TB",1, ...
    'VariableNames',{'Direction','Frame','Slot','CRCPass','Crash','CRCApplicable', ...
    'DecodeAttempted','DLSCHDecodeAttempted','TBSize_bits','GoodBits','Goodput_Mbps','UEIndex','TBId','NDIEpoch'});
t.Source="actual_native_codec_declared_accounting_coordinates_no_shared_execution";
t=sixgr.link.bindDLSCHFinalOutcome(t,selection);
h=struct('FinalCodewordOutcome',selection,'FinalDecodedTransportBlocks',{decoded.TransportBlocks}, ...
    'CombinedDecodeOK',selection.CRCPass);
end
function t=localNoReceipt(t)
names=string(t.Properties.VariableNames);
t=removevars(t,cellstr(names(startsWith(names,"DLSCHFinalOutcome")|startsWith(names,"DLSCHSuccessfulDecodedBits")|names=="DLSCHAggregateGoodBitsPolicy")));
end
function [t,L]=localCredit(t,L)
t.DecodedAttemptBits=t.GoodBits; t.DecodedAttemptGoodput_Mbps=t.Goodput_Mbps;
[t,L]=sixgr.kpi.creditTransportGoodput(t,L);
t.UniqueTransportGoodput_Mbps=t.UniqueDeliveredTBBits/.001/1e6;
t.GoodBits=t.UniqueDeliveredTBBits; t.Goodput_Mbps=t.UniqueTransportGoodput_Mbps;
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'test:SharedDLSCHWrongGuard','Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:SharedDLSCHMissingGuard','Expected %s.',id);
end
