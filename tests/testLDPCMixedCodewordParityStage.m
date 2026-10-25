function [ok,checks] = testLDPCMixedCodewordParityStage()
% Actual encoded-LLR decoder provenance, not waveform or MAC qualification.
% Reporting never decodes again. Each retained matrix/stage belongs to its
% original indexed codeword; a missing prior must not inherit another CW's
% combined stage. V1 history remains aggregate-only and is not reconstructed.
setup6GRSimToolkit('Verbose',false);
originalRNG=rng; cleanup=onCleanup(@()rng(originalRNG)); %#ok<NASGU>
f=fixture();
rows=repmat(struct('Case',"",'Passed',false,'ErrorID',"",'Detail',""),0,1);
record("DL_actual_indexed_partial_prior",@dl);
record("UL_actual_indexed_partial_prior",@ul);
record("UL_unresolved_codeword_and_no_decode",@unresolved);
record("HARQ_diagnostic_actual_partial_prior",@diagnostic);
record("legacy_v1_original_schema_preserved",@legacy);
record("v2_projection_CSV_and_typed_guards",@projection);
record("stage_population_guards",@stageGuards);
checks=struct2table(rows);
for k=find(~checks.Passed).'
    fprintf(2,'LDPC_MIXED_STAGE %s FAIL %s %s\n',checks.Case(k),checks.ErrorID(k),checks.Detail(k));
end
assert(all(checks.Passed),'test:LDPCMixedCodewordParityStage', ...
    '%d/%d bounded decoder-stage groups failed.',nnz(~checks.Passed),height(checks));
assert(isequaln(rng,originalRNG),'Decoder/projection fixture changed global RNG.');
fprintf('LDPC_MIXED_STAGE_PASS groups=%d native_encoded_LLR=1 waveform=0 MAC_retry=0\n',height(checks));
ok=true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'ErrorID',"",'Detail',"");
        try, fn(); row.Passed=true;
        catch cause
            row.ErrorID=string(cause.identifier);
            row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
    function dl()
        initial=decodeDL(f,1,[]);
        for index=1:2
            prior=cell(1,2); prior{index}=initial.Codewords{index}.SoftBuffer;
            actual=decodeDL(f,2,prior);
            stages=repmat("initial_decode",1,2); stages(index)="harq_combined_decode";
            matrices=cellfun(@(x)x.FinalParityChecks,actual.Codewords,'UniformOutput',false);
            assertSummary(actual.LDPCParityEvidence,matrices,stages,"mixed_codeword_decode");
            for cw=1:2
                word=actual.Codewords{cw};
                assert(word.HARQCombineInfo.Applied==(cw==index) && ...
                    word.LDPCParityEvidence.Stage==stages(cw));
                expected=word.RateRecoveredLLR;
                if cw==index, expected=expected+initial.Codewords{cw}.RateRecoveredLLR; end
                assert(isequaln(word.HARQCombinedLLR,expected));
                nativeCompare(expected,word.CodingLayout,word.FinalParityChecks,word.TransportBlock,word.CRCPass);
            end
            before=actual;
            [final,state]=sixgr.link.finalizeDLSCHCodewordOutcomes(actual,f.Config);
            assert(isequaln(actual,before) && final.AdditionalDecoderInvocationCount==0);
            for cw=1:2
                assert(final.Codewords{cw}.LDPCParityStage==stages(cw) && ...
                    isequaln(state.LDPCParityEvidencePerCodeword{cw},actual.Codewords{cw}.LDPCParityEvidence));
            end
        end
        swapped={initial.Codewords{2}.SoftBuffer,[]};
        reject(@()decodeDL(f,2,swapped),'sixgr:phy:harq:SoftBufferCodewordMismatch');
    end
    function ul()
        initial=decodeUL(f,1,[true true],[]);
        for index=1:2
            prior=cell(1,2); prior{index}=initial.CodewordEvidence{index}.HARQCombining.SoftBuffer;
            actual=decodeUL(f,2,[true true],prior);
            stages=repmat("initial_decode",1,2); stages(index)="harq_combined_decode";
            matrices=cellfun(@(x)x.FinalParityChecks,actual.CodewordEvidence,'UniformOutput',false);
            assertSummary(actual.LDPCParityEvidence,matrices,stages,"mixed_codeword_decode");
            for cw=1:2
                word=actual.CodewordEvidence{cw};
                assert(word.HARQCombining.Applied==(cw==index) && ...
                    word.LDPCParityEvidence.Stage==stages(cw));
                expected=word.HARQCombining.SoftBuffer.LLR;
                nativeCompare(expected,word.CodingLayout,word.FinalParityChecks, ...
                    actual.TransportBlocks{cw},logical(actual.CRCPass(cw)));
            end
        end
        swapped={initial.CodewordEvidence{2}.HARQCombining.SoftBuffer,[]};
        reject(@()decodeUL(f,2,[true true],swapped),'sixgr:phy:harq:SoftBufferCodewordMismatch');
    end
    function unresolved()
        initial=decodeUL(f,1,[true true],[]);
        prior={initial.CodewordEvidence{1}.HARQCombining.SoftBuffer,[]};
        actual=decodeUL(f,2,[true false],prior);
        assertSummary(actual.LDPCParityEvidence,{actual.CodewordEvidence{1}.FinalParityChecks,[]}, ...
            ["harq_combined_decode",""],"harq_combined_decode");
        assert(isequal(actual.DecodeAttempted,[true false]) && isnan(actual.CRCPass(2)) && ...
            ~actual.LDPCParityEvidence.Available && isnan(actual.LDPCParityEvidence.CheckCount));
        none=decodeUL(f,2,[false false],[]);
        assertSummary(none.LDPCParityEvidence,{[],[]},["",""],"");
        assert(~any(none.DecodeAttempted) && ~none.LDPCParityEvidence.HasObservedCodewords);
        p=project(none.LDPCParityEvidence);
        assert(isequaln(sixgr.link.deriveMeasuredPHYEvidence(p),p) && ...
            p.MeasuredLDPCParityStage=="" && p.MeasuredLDPCParityAvailable==0);
    end
    function diagnostic()
        initial=decodeUL(f,1,[true true],[]);
        current=decodeUL(f,2,[true true],[]);
        layouts=cellfun(@(x)x.CodingLayout,current.CodewordEvidence,'UniformOutput',false);
        recovered=cellfun(@(x)x.HARQCombining.SoftBuffer.LLR,current.CodewordEvidence,'UniformOutput',false);
        rx=struct('RecLLRCell',{recovered},'CodingLayouts',{layouts}, ...
            'TransportBlock',vertcat(current.TransportBlocks{:}),'Ok',current.AllTransportBlocksPassed);
        tx=struct('TransportBlock',vertcat(f.Bits{:}),'CodingLayouts',{layouts});
        beforeRX=rx; beforeTX=tx;
        for index=1:2
            prior=cell(1,2); prior{index}=initial.CodewordEvidence{index}.HARQCombining.SoftBuffer;
            d=sixgr.link.evaluateHARQDecode(tx,rx,f.Config,prior);
            stages=repmat("initial_decode",1,2); stages(index)="harq_combined_decode";
            assertSummary(d.CombinedLDPCParityEvidence,d.CombinedFinalParityChecks,stages,"mixed_codeword_decode");
            assert(isequal(d.HARQSoftCombiningInfo.AppliedPerCodeword,(1:2)==index) && ...
                isequaln(rx,beforeRX) && isequaln(tx,beforeTX));
            for cw=1:2
                [~,~,parity]=nrLDPCDecode(d.CombinedLLR{cw},double(layouts{cw}.BaseGraph),4, ...
                    'Algorithm','Normalized min-sum','ScalingFactor',.61,'Termination','max');
                assert(isequal(parity,d.CombinedFinalParityChecks{cw}));
            end
        end
    end
    function legacy()
        matrices={logical([0;1]),int8([0 0;1 0])};
        original=sixgr.phy.phycode.summarizeLDPCParity(matrices,"harq_combined_decode", ...
            "sixgr.phy.LDPCParitySummary/v1");
        assert(~isfield(original,'CodewordStages'));
        before=original; p=project(original);
        assert(isequaln(original,before) && p.MeasuredLDPCParityContractVersion==original.ContractVersion && ...
            p.MeasuredLDPCParityStage==original.Stage && ...
            ~isfield(jsondecode(p.MeasuredLDPCParityEvidenceJSON),'CodewordStages') && ...
            isequaln(sixgr.link.deriveMeasuredPHYEvidence(p),p));
        bad=original; bad.CodewordStages=["initial_decode","harq_combined_decode"];
        reject(@()project(bad),'sixgr:link:InvalidLDPCParityEvidence');
    end
    function projection()
        mixed=sixgr.phy.phycode.summarizeLDPCParity({logical([0;1]),int8([0 0;1 0])}, ...
            ["initial_decode","harq_combined_decode"]);
        partial=sixgr.phy.phycode.summarizeLDPCParity({[],logical([0;1])}, ...
            ["","harq_combined_decode"]);
        p=project(mixed); q=project(partial);
        assert(isequaln(sixgr.link.deriveMeasuredPHYEvidence(p),p));
        saved=jsondecode(p.MeasuredLDPCParityEvidenceJSON);
        assert(isequal(reshape(string(saved.CodewordStages),1,[]),mixed.CodewordStages));
        T=sixgr.link.appendMeasuredPHYEvidenceColumns(table([1;2],'VariableNames',{'TrialId'}),{p;q});
        folder=tempname; mkdir(folder); cleaner=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
        file=fullfile(folder,'parity_stages.csv');
        sixgr.util.csvWriteTable(file,T,'PreserveSchema',true);
        readback=readtable(file,'TextType','string','VariableNamingRule','preserve');
        assert(isequal(readback.MeasuredLDPCParityStage,T.MeasuredLDPCParityStage) && ...
            isequal(readback.MeasuredLDPCParityEvidenceJSON,T.MeasuredLDPCParityEvidenceJSON));
        bad=mixed; bad.Stage="harq_combined_decode"; reject(@()project(bad),'sixgr:link:InvalidLDPCParityEvidence');
        bad=mixed; bad.CodewordStages={"initial_decode","harq_combined_decode"};
        reject(@()project(bad),'sixgr:link:InvalidLDPCParityEvidence');
        bad=p; bad.MeasuredLDPCParityStage="harq_combined_decode";
        reject(@()sixgr.link.deriveMeasuredPHYEvidence(bad),'sixgr:link:InvalidLDPCParityEvidence');
        for field=["Stage","CodewordStages","CompatibilityVectorIsCompleteEvidence","TransportBlockAcceptanceDetermined"]
            altered=saved; altered.(field)=0;
            reject(@()replay(p,altered),'sixgr:link:InvalidLDPCParityEvidence');
        end
        altered=saved; altered.CodewordStages=["initial_decode","initial_decode"];
        reject(@()replay(p,altered),'sixgr:link:InvalidLDPCParityEvidence');
        altered=saved; altered.Available=double(altered.Available);
        reject(@()replay(p,altered),'sixgr:link:InvalidLDPCParityEvidence');
        altered=saved; altered.CodewordAvailable=double(altered.CodewordAvailable);
        reject(@()replay(p,altered),'sixgr:link:InvalidLDPCParityEvidence');
        altered=jsondecode(q.MeasuredLDPCParityEvidenceJSON);
        altered.CodewordStages=flipud(altered.CodewordStages);
        reject(@()replay(q,altered),'sixgr:link:InvalidLDPCParityEvidence');
        altered=rmfield(saved,'CodewordStages');
        reject(@()replay(p,altered),'sixgr:link:InvalidLDPCParityEvidence');
    end
    function stageGuards()
        reject(@()sixgr.phy.phycode.summarizeLDPCParity({0,[]}, ...
            ["initial_decode","harq_combined_decode"]),'sixgr:phy:ldpc:ParityStage');
        reject(@()sixgr.phy.phycode.summarizeLDPCParity({0,0}, ...
            ["initial_decode",""]),'sixgr:phy:ldpc:ParityStage');
        reject(@()sixgr.phy.phycode.summarizeLDPCParity({0,0},"mixed_codeword_decode"), ...
            'sixgr:phy:ldpc:ParityStage');
        empty=sixgr.phy.phycode.summarizeLDPCParity({},strings(1,0));
        % The producer canonicalizes every cell population to a row, even
        % zero codewords: literal {} is 0-by-0, not the returned 1-by-0.
        assertSummary(empty,cell(1,0),strings(1,0),"");
        p=project(empty); assert(isequaln(sixgr.link.deriveMeasuredPHYEvidence(p),p));
    end
end

function f=fixture()
f.A=256; f.Rate=.3; f.G=1800; f.RV=[0 2];
f.Policy=struct('maxIterations',4,'algorithm','Normalized min-sum', ...
    'scalingFactor',.61,'minSumOffset',.31,'termination','max','useMexBatchDecode',false);
f.Config=struct('phy',struct('ldpc',f.Policy));
f.Bits={int8(mod((1:f.A).',2)),int8(mod(floor((1:f.A).'/3),2))};
f.PUSCH=struct('NumLayers',6,'Modulation','QPSK'); % Declared codec layout, no grant/waveform.
f.Plans=cell(2,2); f.ULLayouts=cell(2,2); f.DLLLR=cell(2,2); f.ULLLR=cell(2,2);
for cw=1:2
    info=nrULSCHInfo(f.A,f.Rate);
    coded=nrLDPCEncode(nrCodeBlockSegmentLDPC(nrCRCEncode(f.Bits{cw},info.CRC),info.BGN),info.BGN);
    for attempt=1:2
        rv=f.RV(attempt);
        plan=sixgr.pdsch.DLSCHCodingPlan.resolve('TransportBlockSize',f.A, ...
            'TargetCodeRate',f.Rate,'RV',rv,'Modulation','QPSK','NumLayers',3, ...
            'RateMatchedBitCount',f.G,'CodewordIndex',cw-1);
        f.Plans{attempt,cw}=plan;
        f.ULLLR{attempt,cw}=12*(1-2*double(nrRateMatchLDPC(coded,f.G,rv,'QPSK',3)));
        f.ULLayouts{attempt,cw}=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
            'TransportBlockSize',f.A,'TargetCodeRate',f.Rate,'RV',rv, ...
            'Modulation','QPSK','NumLayers',3,'RateMatchedBitCount',f.G);
    end
end
% Encode the original ordered population together. A singleton encoder call
% legitimately requires CodewordIndex=0 and cannot stand in for CW1.
for attempt=1:2
    encoded=sixgr.pdsch.DLSCHEncoder(f.Bits,f.Plans(attempt,:));
    for cw=1:2
        assert(double(encoded.Codewords{cw}.CodewordIndex)==cw-1);
        f.DLLLR{attempt,cw}=12*(1-2*double(encoded.RateMatchedBits{cw}));
    end
end
end

function d=decodeDL(f,attempt,prior)
d=sixgr.pdsch.DLSCHDecoder(f.DLLLR(attempt,:),'CodingPlan',f.Plans(attempt,:), ...
    'MaxIterations',4,'Algorithm','Normalized min-sum','ScalingFactor',.61, ...
    'Offset',.31,'Termination','max','PriorRecoveredLLR',prior,'PriorCodingPlan',f.Plans(1,:));
end

function d=decodeUL(f,attempt,resolved,prior)
llr=f.ULLLR(attempt,:);
for cw=1:numel(resolved)
    if ~resolved(cw), llr{cw}=[]; end
end
d=sixgr.phy.ul.pusch.decodeResolvedULSCH(llr,resolved,f.PUSCH,[f.A f.A], ...
    [f.Rate f.Rate],repmat(f.RV(attempt),1,2),f.ULLayouts(attempt,:),4, ...
    'Normalized min-sum',prior,f.ULLayouts(1,:),f.Policy);
end

function nativeCompare(llr,layout,parity,bits,pass)
[decoded,~,nativeParity]=nrLDPCDecode(llr,double(layout.BaseGraph),4, ...
    'Algorithm','Normalized min-sum','ScalingFactor',.61,'Termination','max');
withCRC=nrCodeBlockDesegmentLDPC(decoded,double(layout.BaseGraph),double(layout.TransportBlockLengthWithCRC));
[nativeBits,errorFlag]=nrCRCDecode(withCRC,char(layout.TBCRCType));
assert(isequal(parity,nativeParity) && isequal(int8(bits(:)),int8(nativeBits(:))) && pass==~logical(errorFlag));
end

function assertSummary(s,matrices,stages,aggregate)
assert(s.ContractVersion=="sixgr.phy.LDPCParitySummary/v2" && ...
    isequal(s.CodewordStages,stages) && s.Stage==aggregate && ...
    isequaln(s.FinalParityChecksPerCodeword,matrices) && ...
    isequal(s.CodewordAvailable,~cellfun(@isempty,matrices)));
before=s; p=project(s);
assert(isequaln(s,before) && p.MeasuredLDPCParityStage==aggregate && ...
    isequaln(sixgr.link.deriveMeasuredPHYEvidence(p),p));
end

function p=project(s)
p=sixgr.link.deriveMeasuredPHYEvidence(struct('LDPCParityEvidence',s));
end

function replay(p,compact)
p.MeasuredLDPCParityEvidenceJSON=string(jsonencode(compact));
sixgr.link.deriveMeasuredPHYEvidence(p);
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'test:LDPCMixedCodewordParityStage:WrongRejection', ...
        'Expected %s, received %s: %s',id,cause.identifier,cause.message); return;
end
error('test:LDPCMixedCodewordParityStage:MissingRejection','Expected %s.',id);
end
