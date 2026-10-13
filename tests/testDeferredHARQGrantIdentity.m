function ok = testDeferredHARQGrantIdentity()
% Production cancellation and HARQ lifecycle with declared MAC events.
% These are not waveform/CRC outcomes or statistical missing-DCI evidence.
setup6GRSimToolkit('Verbose',false);
for direction = ["DL","UL"]
    for priorTransmission = [false,true]
        h = sixgr.l2.mac.HARQEntity(struct(),'Direction',direction, ...
            'NumProcesses',1,'MaxRetx',2);
        state = struct(); state.(char(direction+"Harq")) = h;
        rnti = 201; bits = uint8(mod((1:800)',2));
        if priorTransmission
            first = h.allocate(rnti,1,100);
            g = localGrant(direction,rnti,first.HARQ);
            h.onTx(rnti,0,bits,g,1);
            assert(h.onFeedback(rnti,0,"ACK",'SourceSlot',1,'FeedbackSlot',2));
        end
        other = h.allocate(202,3,100); %#ok<NASGU>
        otherIndex = find(h.UEList == 202);
        otherBefore = h.UEProcs{otherIndex};
        candidate = h.allocate(rnti,34,100);
        expected = candidate.HARQ;
        stats = h.Stats; ledger = h.getDeliveryLedger();
        for repeat = 1:3
            g = localGrant(direction,rnti,candidate.HARQ);
            state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
                state,g,direction,'DCINotIssued',true);
            assert(h.hasFreeProcess(rnti) && ~h.hasPendingRetx(rnti));
            assert(isequaln(h.Stats,stats) && isequaln(h.getDeliveryLedger(),ledger), ...
                'Deferral must not fabricate transmission, feedback, loss or delivery.');
            assert(isequaln(h.UEProcs{otherIndex},otherBefore),'Do not mutate another UE.');
            candidate = h.allocate(rnti,34+repeat,100);
            assert(isequaln(candidate.HARQ,expected), ...
                'An unissued DCI must not consume NDI or its new-data epoch.');
        end

        % Default cancellation remains distinct: if control was issued but
        % no data TX occurred, do not roll back that command's NDI history.
        g = localGrant(direction,rnti,candidate.HARQ);
        state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state,g,direction);
        next = h.allocate(rnti,40,100);
        assert(next.HARQ.NDI ~= candidate.HARQ.NDI && ...
            next.HARQ.NDIEpoch == candidate.HARQ.NDIEpoch+1);

        % An actual existing TB and position-aware soft buffer survive a
        % deferred retransmission, without RV/attempt/feedback mutation.
        g = localGrant(direction,rnti,next.HARQ);
        h.onTx(rnti,0,bits,g,40);
        assert(h.onFeedback(rnti,0,"NACK",'SourceSlot',40,'FeedbackSlot',41));
        h.storeSoftBuffer(rnti,0,struct('LLRSum',ones(20,1), ...
            'ObservationWeight',ones(20,1),'CodingLayoutHash',"declared_MAC_buffer"));
        retry = h.allocate(rnti,42,100,'NewData',false);
        assert(retry.HARQ.IsRetransmission);
        g = localGrant(direction,rnti,retry.HARQ);
        before = h.UEProcs; stats = h.Stats; ledger = h.getDeliveryLedger();
        state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
            state,g,direction,'DCINotIssued',true);
        assert(isequaln(h.UEProcs,before) && isequaln(h.Stats,stats) && ...
            isequaln(h.getDeliveryLedger(),ledger));
        assert(h.hasPendingRetx(rnti) && isequal(h.getStoredTB(rnti,0),bits));
        again = h.allocate(rnti,43,100,'NewData',false);
        assert(isequaln(again.HARQ,retry.HARQ));

        % A false pre-DCI cancellation claim must not erase transmitted state.
        live = sixgr.l2.mac.HARQEntity(struct(),'Direction',direction,'NumProcesses',1);
        a = live.allocate(rnti,1,100); g = localGrant(direction,rnti,a.HARQ);
        live.onTx(rnti,0,bits,g,1);
        liveState = struct(); liveState.(char(direction+"Harq")) = live;
        before = live.UEProcs;
        localReject(@()sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
            liveState,g,direction,'DCINotIssued',true),'sixgr:truth:UnissuedHARQRollbackFailed');
        assert(isequaln(before,live.UEProcs));
    end
end
fprintf('DEFERRED_HARQ_GRANT_IDENTITY_PASS DL/UL, initial/reused processes, repeated deferral, retained retry; declared_MAC_only=1\n');
ok = true;
end

function g = localGrant(direction,rnti,harq)
layout = sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',harq.RV, ...
    'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',2748);
g = struct('RNTI',rnti,'HARQ',harq,'TBSBits',800,'Direction',direction, ...
    'Modulation','QPSK','NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout, ...
    'TransportBlockId',direction+"-MAC-"+string(harq.NDIEpoch), ...
    'PHYGrantContextId',direction+"-MAC-grant-"+string(harq.NDIEpoch));
end

function localReject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
