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
    if info.C>1
        % Valid LDPC parity and valid TB CRC cannot rescue a failed CB CRC.
        % Corrupt only a CB CRC bit, then re-encode the LDPC codeword.
        cb=nrCodeBlockSegmentLDPC(nrCRCEncode(bits,info.CRC),info.BGN);
        lastBinary=find(cb(:,1)>=0,1,'last');
        cb(lastBinary,1)=1-cb(lastBinary,1);
        badCode=nrLDPCEncode(cb,info.BGN);
        badLLR=20*(1-2*double(badCode)); badLLR(badCode<0)=Inf;
        [badPass,~,badBits]=sixgr.phy.harq.decodeCombinedULSCH(own,badLLR,cfg);
        assert(~badPass && isequal(badBits,bits), ...
            'Failed code-block CRC must reject the combined TB even when the TB CRC remains valid.');
    end
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

function localReject(fn,id)
try, fn(); catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
