function ok=testDLReceiverOwnedHARQDecode(configPath)
% Receiver-owned combined decoding, canonical TB acceptance, separate CB CRC.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(90214,'twister');
if nargin<1
    configPath='simulator/configs/scenarios/lls_received_ul_shared_queue_fixture.yaml';
end
s=sixgr.lls6g.config.loadScenarioConfig(configPath);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cases=[1160 .3;3824 .5;3840 .5;10000 .6];
for k=1:size(cases,1)
    A=cases(k,1); rate=cases(k,2);
    info=nrDLSCHInfo(A,rate);
    % Repeat enough coded bits to cover the mother code at all tested RVs.
    G=6*ceil(2*info.N*info.C/6);
    for rv=[0 2 3 1]
        plan=sixgr.pdsch.DLSCHCodingPlan.resolve( ...
            'TransportBlockSize',A,'TargetCodeRate',rate,'RV',rv, ...
            'Modulation','64QAM','NumLayers',1,'RateMatchedBitCount',G,'CodewordIndex',0);
        layout=plan.toCodingLayout(); bits=int8(randi([0 1],A,1));
        cb=nrCodeBlockSegmentLDPC(nrCRCEncode(bits,info.CRC),info.BGN);
        coded=nrLDPCEncode(cb,info.BGN);
        llr=20*(1-2*double(coded)); llr(coded<0)=Inf;
        [pass,it,actual]=sixgr.phy.harq.decodeCombinedDLSCH(layout,llr,cfg);
        assert(pass && isfinite(it) && isequal(actual,bits));
        matched=nrRateMatchLDPC(coded,G,rv,'64QAM',1);
        canonical=sixgr.pdsch.DLSCHDecoder(20*(1-2*double(matched)),'CodingPlan',plan);
        assert(canonical.CRCPass && canonical.TransportBlockCRCPass && ...
            all(canonical.CodeBlockCRCPass) && isequal(canonical.TransportBlock,bits));
        assert(numel(canonical.CodeBlockCRCError)==info.C*double(info.C>1), ...
            'The absent single-block CRC must not appear as one passed check.');
        if info.C>1
            % Corrupt CB CRC only; preserve payload, TB CRC, and LDPC parity.
            lastBinary=find(cb(:,1)>=0,1,'last'); cb(lastBinary,1)=1-cb(lastBinary,1);
            badCode=nrLDPCEncode(cb,info.BGN);
            badLLR=20*(1-2*double(badCode)); badLLR(badCode<0)=Inf;
            [badPass,~,badBits,badDiagnostics]=sixgr.phy.harq.decodeCombinedDLSCH(layout,badLLR,cfg);
            badMatched=nrRateMatchLDPC(badCode,G,rv,'64QAM',1);
            [publicBits,publicError,publicInfo]=localPublicDecode( ...
                20*(1-2*double(badMatched)),A,rate,rv);
            % Canonical MATLAB TB acceptance uses TB CRC, not an extra CB
            % veto. This corrects the former stricter implementation policy
            % while preserving the actual failed CB checksum observation.
            assert(badPass==~publicError && ~publicError && isequal(badBits,bits) && ...
                isequal(publicBits,bits) && any(publicInfo.CodeBlockError{1}) && ...
                badDiagnostics.TransportBlockCRCPass && ...
                any(badDiagnostics.CodeBlockCRCError));
            bad=sixgr.pdsch.DLSCHDecoder(20*(1-2*double(badMatched)),'CodingPlan',plan);
            assert(bad.TransportBlockCRCPass && ~bad.TransportBlockCRCError && ...
                any(bad.CodeBlockCRCError) && bad.CRCPass && ~bad.CRCError && ...
                bad.CRCPassPerCodeword && ~bad.CRCErrorPerCodeword && ...
                isequal(bad.TransportBlock,bits), ...
                'TB acceptance must match canonical decoding without erasing the failed CB CRC.');
            if rv==0
                plan1=sixgr.pdsch.DLSCHCodingPlan.resolve( ...
                    'TransportBlockSize',A,'TargetCodeRate',rate,'RV',rv, ...
                    'Modulation','64QAM','NumLayers',1,'RateMatchedBitCount',G,'CodewordIndex',1);
                pair=sixgr.pdsch.DLSCHDecoder( ...
                    {20*(1-2*double(matched)),20*(1-2*double(badMatched))}, ...
                    'CodingPlan',{plan,plan1});
                assert(pair.CRCPass && ~pair.CRCError && ...
                    isequal(pair.CRCPassPerCodeword,[true true]) && ...
                    isequal(pair.CRCErrorPerCodeword,[false false]) && ...
                    pair.Codewords{1}.TransportBlockCRCPass && pair.Codewords{2}.TransportBlockCRCPass && ...
                    ~any(pair.Codewords{1}.CodeBlockCRCError) && any(pair.Codewords{2}.CodeBlockCRCError), ...
                    'Aggregate TB acceptance and per-codeword CB diagnostics must remain distinct.');
                fprintf('DL_TWO_CODEWORD_CB_CRC_SEPARATE_DIAGNOSTIC_PASS\n');
            end
        end
        % A genuinely invalid TB CRC must fail even when every CB CRC is
        % valid and the decoded payload equals the known original bits.
        badTB=nrCRCEncode(bits,info.CRC); badTB(end)=1-badTB(end);
        badTBCode=nrLDPCEncode(nrCodeBlockSegmentLDPC(badTB,info.BGN),info.BGN);
        badTBLLR=20*(1-2*double(badTBCode)); badTBLLR(badTBCode<0)=Inf;
        [tbPass,~,tbBits,tbDiagnostics]=sixgr.phy.harq.decodeCombinedDLSCH(layout,badTBLLR,cfg);
        badTBMatched=nrRateMatchLDPC(badTBCode,G,rv,'64QAM',1);
        [publicTBBits,publicTBError]=localPublicDecode(20*(1-2*double(badTBMatched)),A,rate,rv);
        tbDecoded=sixgr.pdsch.DLSCHDecoder(20*(1-2*double(badTBMatched)),'CodingPlan',plan);
        assert(~tbPass && publicTBError && ~tbDecoded.CRCPass && tbDecoded.CRCError && ...
            ~tbDiagnostics.TransportBlockCRCPass && tbDiagnostics.TransportBlockCRCError && ...
            ~any(tbDiagnostics.CodeBlockCRCError) && ~any(tbDecoded.CodeBlockCRCError) && ...
            isequal(tbBits,bits) && isequal(publicTBBits,bits) && isequal(tbDecoded.TransportBlock,bits));
        if info.C>1 && rv==0
            failedPair=sixgr.pdsch.DLSCHDecoder( ...
                {20*(1-2*double(matched)),20*(1-2*double(badTBMatched))}, ...
                'CodingPlan',{plan,plan1});
            assert(~failedPair.CRCPass && failedPair.CRCError && ...
                isequal(failedPair.CRCPassPerCodeword,[true false]) && ...
                isequal(failedPair.CRCErrorPerCodeword,[false true]) && ...
                ~any(failedPair.Codewords{2}.CodeBlockCRCError) && ...
                ~failedPair.Codewords{2}.TransportBlockCRCPass);
        end
        localReject(@()sixgr.phy.harq.decodeCombinedDLSCH(layout,llr(1:end-1,:),cfg), ...
            'sixgr:phy:harq:DLCombinedLLRShapeMismatch');
        invalid=layout; invalid.TBCRCType='24B';
        localReject(@()sixgr.phy.harq.decodeCombinedDLSCH(invalid,llr,cfg), ...
            'sixgr:phy:harq:DLReceiverCodingLayoutMismatch');
        fprintf('DL_RECEIVER_OWNED_HARQ_DECODE_PASS: A=%d CRC=%s BGN=%d C=%d RV=%d\n', ...
            A,info.CRC,info.BGN,info.C,rv);
    end
end
localReject(@()sixgr.phy.harq.decodeCombinedDLSCH(struct('TransportBlock',bits),llr,cfg), ...
    'sixgr:phy:harq:DLReceiverCodingLayoutRequired');
ok=true;
end

function [bits,err,diagnostics]=localPublicDecode(llr,A,rate,rv)
decoder=nrDLSCHDecoder('MultipleHARQProcesses',false,'TargetCodeRate',rate, ...
    'TransportBlockLength',A,'LDPCDecodingAlgorithm','Normalized min-sum', ...
    'MaximumLDPCIterationCount',12);
[bits,err]=decoder(llr,'64QAM',1,rv);
diagnostics=info(decoder);
end

function localReject(fn,id)
try, fn(); catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
