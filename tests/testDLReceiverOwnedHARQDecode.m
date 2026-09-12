function ok=testDLReceiverOwnedHARQDecode()
% Receiver-owned combined decoding and canonical CB/TB CRC decision gates.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(90214,'twister');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_shared_queue_fixture.yaml');
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
        if info.C>1
            % Corrupt CB CRC only; preserve payload, TB CRC, and LDPC parity.
            lastBinary=find(cb(:,1)>=0,1,'last'); cb(lastBinary,1)=1-cb(lastBinary,1);
            badCode=nrLDPCEncode(cb,info.BGN);
            badLLR=20*(1-2*double(badCode)); badLLR(badCode<0)=Inf;
            [badPass,~,badBits]=sixgr.phy.harq.decodeCombinedDLSCH(layout,badLLR,cfg);
            assert(~badPass && isequal(badBits,bits));
            badMatched=nrRateMatchLDPC(badCode,G,rv,'64QAM',1);
            bad=sixgr.pdsch.DLSCHDecoder(20*(1-2*double(badMatched)),'CodingPlan',plan);
            assert(bad.TransportBlockCRCPass && ~bad.TransportBlockCRCError && ...
                any(bad.CodeBlockCRCError) && ~bad.CRCPass && bad.CRCError && ...
                ~bad.CRCPassPerCodeword && bad.CRCErrorPerCodeword && ...
                isequal(bad.TransportBlock,bits), ...
                'A valid TB CRC cannot hide a failed CB CRC in the overall decode verdict.');
            if rv==0
                plan1=sixgr.pdsch.DLSCHCodingPlan.resolve( ...
                    'TransportBlockSize',A,'TargetCodeRate',rate,'RV',rv, ...
                    'Modulation','64QAM','NumLayers',1,'RateMatchedBitCount',G,'CodewordIndex',1);
                pair=sixgr.pdsch.DLSCHDecoder( ...
                    {20*(1-2*double(matched)),20*(1-2*double(badMatched))}, ...
                    'CodingPlan',{plan,plan1});
                assert(~pair.CRCPass && pair.CRCError && ...
                    isequal(pair.CRCPassPerCodeword,[true false]) && ...
                    isequal(pair.CRCErrorPerCodeword,[false true]) && ...
                    pair.Codewords{1}.TransportBlockCRCPass && pair.Codewords{2}.TransportBlockCRCPass, ...
                    'Aggregate decoding must retain the failed codeword CB CRC verdict.');
                fprintf('DL_TWO_CODEWORD_CB_CRC_NEGATIVE_PASS\n');
            end
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

function localReject(fn,id)
try, fn(); catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
