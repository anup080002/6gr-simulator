function ok=testULReceiverOwnedHARQDecode()
% Exact coding boundaries, independent receiver layout, no transmitter API.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(90213,'twister');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cases=[1160 .3;3824 .5;3840 .5;10000 .6];
for k=1:size(cases,1)
    A=cases(k,1); rate=cases(k,2);
    own=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
        'TransportBlockSize',A,'TargetCodeRate',rate,'RV',2, ...
        'Modulation','64QAM','NumLayers',1,'RateMatchedBitCount',6*ceil(A/rate/6));
    % Separate standard encoder as the oracle, never a retained TX object.
    info=nrULSCHInfo(A,rate); bits=int8(randi([0 1],A,1));
    coded=nrLDPCEncode(nrCodeBlockSegmentLDPC(nrCRCEncode(bits,info.CRC),info.BGN),info.BGN);
    llr=20*(1-2*double(coded)); llr(coded<0)=Inf;
    [pass,it,actual]=sixgr.phy.harq.decodeCombinedULSCH(own,llr,cfg);
    assert(pass && isfinite(it) && isequal(actual,bits));
    % Use the real decoder verdict with contradictory reference metadata.
    % This is a coding-boundary test, not an RF/CRC-collision rate claim.
    current=struct('Ok',false,'TransportBlock',1-actual);
    combined=struct('CRCPass',pass,'TransportBlock',actual);
    decision=sixgr.link.resolveULHARQReceiverOutcome(current,combined);
    assert(~decision.CurrentDecodeOK && decision.CombinedDecodeOK && ...
        decision.SelectedCombinedDecode && isequal(decision.DecodedTransportBlockBits,bits));
    current.ExpectedBits=1-bits; combined.ExpectedBits=1-bits;
    combined.ReferenceContentMatch=false;
    assert(isequaln(decision,sixgr.link.resolveULHARQReceiverOutcome(current,combined)), ...
        'TX-reference disagreement cannot override the actual combined receiver CRC.');
    if info.C>1
        % Corrupt only a CB CRC bit, then re-encode the LDPC codeword.
        % Canonical MATLAB TB acceptance is TB-CRC based; the separate CB
        % failure must remain visible without overriding that TB verdict.
        cb=nrCodeBlockSegmentLDPC(nrCRCEncode(bits,info.CRC),info.BGN);
        lastBinary=find(cb(:,1)>=0,1,'last');
        cb(lastBinary,1)=1-cb(lastBinary,1);
        badCode=nrLDPCEncode(cb,info.BGN);
        badLLR=20*(1-2*double(badCode)); badLLR(badCode<0)=Inf;
        [badPass,~,badBits,badDiagnostics]=sixgr.phy.harq.decodeCombinedULSCH(own,badLLR,cfg);
        [publicBits,publicError,publicInfo]=localPublicDecode(badCode,A,rate,info,2);
        assert(badPass==~publicError && ~publicError && isequal(badBits,bits) && ...
            isequal(publicBits,bits) && any(publicInfo.CodeBlockError{1}) && ...
            badDiagnostics.TransportBlockCRCPass && any(badDiagnostics.CodeBlockCRCError));
        accepted=sixgr.link.resolveULHARQReceiverOutcome(current, ...
            struct('CRCPass',badPass,'TransportBlock',badBits,'ExpectedBits',1-bits));
        assert(accepted.CombinedDecodeOK && accepted.SelectedCombinedDecode && ...
            isequal(accepted.DecodedTransportBlockBits,bits));
    end
    % Keep the no-reference-rescue negative, now with an actually failing
    % TB CRC and recomputed valid CB CRCs. Payload bits themselves are intact.
    badTB=nrCRCEncode(bits,info.CRC); badTB(end)=1-badTB(end);
    badTBCode=nrLDPCEncode(nrCodeBlockSegmentLDPC(badTB,info.BGN),info.BGN);
    badTBLLR=20*(1-2*double(badTBCode)); badTBLLR(badTBCode<0)=Inf;
    [tbPass,~,tbBits,tbDiagnostics]=sixgr.phy.harq.decodeCombinedULSCH(own,badTBLLR,cfg);
    [publicTBBits,publicTBError]=localPublicDecode(badTBCode,A,rate,info,2);
    assert(~tbPass && publicTBError && isequal(tbBits,bits) && isequal(publicTBBits,bits) && ...
        ~tbDiagnostics.TransportBlockCRCPass && tbDiagnostics.TransportBlockCRCError && ...
        ~any(tbDiagnostics.CodeBlockCRCError));
    rejected=sixgr.link.resolveULHARQReceiverOutcome(current, ...
        struct('CRCPass',tbPass,'TransportBlock',tbBits,'ExpectedBits',bits));
    assert(~rejected.CombinedDecodeOK && ~rejected.SelectedCombinedDecode, ...
        'Exact reference content cannot rescue a genuinely failed combined TB CRC.');
    localReject(@()sixgr.phy.harq.decodeCombinedULSCH(own,llr(1:end-1,:),cfg), ...
        'sixgr:phy:harq:ULCombinedLLRShapeMismatch');
    invalid=own; invalid.TBCRCType='24B';
    localReject(@()sixgr.phy.harq.decodeCombinedULSCH(invalid,llr,cfg), ...
        'sixgr:phy:harq:ULReceiverCodingLayoutMismatch');
    fprintf('UL_RECEIVER_OWNED_HARQ_DECODE_PASS: A=%d CRC=%s BGN=%d C=%d\n',A,info.CRC,info.BGN,info.C);
end
localReject(@()sixgr.phy.harq.decodeCombinedULSCH(struct('TransportBlock',bits),llr,cfg), ...
    'sixgr:phy:harq:ULReceiverCodingLayoutRequired');
ok=true;
end

function [bits,err,diagnostics]=localPublicDecode(coded,A,rate,sch,rv)
G=6*ceil(2*sch.N*sch.C/6);
matched=nrRateMatchLDPC(coded,G,rv,'64QAM',1);
decoder=nrULSCHDecoder('MultipleHARQProcesses',false,'TargetCodeRate',rate, ...
    'TransportBlockLength',A,'LDPCDecodingAlgorithm','Normalized min-sum', ...
    'MaximumLDPCIterationCount',25);
[bits,err]=decoder(20*(1-2*double(matched)),'64QAM',1,rv);
diagnostics=info(decoder);
end

function localReject(fn,id)
try, fn(); catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
