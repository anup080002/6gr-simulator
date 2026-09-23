function ok = testExecutedHARQPayloadAuthority()
% Constructed contract negatives, not simulated PHY measurement evidence.
setup6GRSimToolkit('Verbose',false);
row = table(1,16,false,'VariableNames',{'Slot','TBSize_bits','CRCPass'});
for direction = ["DL","UL"]
    h = struct('TransportBlockBits',int8(mod((1:16)',2)), ...
        'DecodedTransportBlockBits',int8([]), ...
        'CurrentDecodeOK',false,'CombinedDecodeOK',false, ...
        'GrantSnapshot',struct('Direction',direction,'TBSBits',16, ...
            'TransportBlockSize',16,'TBSBytes',2, ...
            'ScheduledTransportBlockSize',24));
    [bits,decoded,grant] = sixgr.truth.validateExecutedHARQPayload(h,row,direction);
    assert(isequal(bits,h.TransportBlockBits) && isempty(decoded) && ...
        isequaln(grant,h.GrantSnapshot),'Preflight must not rewrite retained evidence.');
    zero = h; zero.TransportBlockBits(:)=0;
    assert(all(sixgr.truth.validateExecutedHARQPayload(zero,row,direction)==0), ...
        'An actual all-zero transmitted payload must remain valid.');
    contextOnly = rmfield(h,'GrantSnapshot');
    contextOnly.Context.GrantSnapshot = h.GrantSnapshot;
    [~,~,g] = sixgr.truth.validateExecutedHARQPayload(contextOnly,row,direction);
    assert(isequaln(g,h.GrantSnapshot));
    crcCollision = h;
    crcCollision.CombinedDecodeOK = true;
    crcCollision.DecodedTransportBlockBits = 1-h.TransportBlockBits;
    [~,decoded] = sixgr.truth.validateExecutedHARQPayload(crcCollision,row,direction);
    assert(isequal(decoded,crcCollision.DecodedTransportBlockBits), ...
        'A CRC pass must not substitute transmitted bits for actual decoder content.');

    % Rejection is checked through the real completion entry point so a
    % helper-only guard cannot hide allocate()/onTx() side effects.
    state = struct('MultiUser',struct('RNTIStart',1),'CurrentSlot',1, ...
        'DLHarq',sixgr.l2.mac.HARQEntity(struct(),'Direction','DL'), ...
        'ULHarq',sixgr.l2.mac.HARQEntity(struct(),'Direction','UL'), ...
        'DLCombinedLLR',{cell(1,16)},'ULCombinedLLR',{cell(1,16)});
    bad = rmfield(h,'TransportBlockBits');
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:MissingExecutedTransportBlock');
    bad = h; bad.TransportBlockBits=int8([]);
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:MissingExecutedTransportBlock');
    for invalid = {[0.2;zeros(15,1)], [NaN;zeros(15,1)], ...
            [2;zeros(15,1)], ones(4), complex(zeros(16,1),ones(16,1)), '0101'}
        bad = h; bad.TransportBlockBits=invalid{1};
        localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQInvalidBits');
    end
    bad = h; bad.TransportBlockBits=bad.TransportBlockBits(1:15);
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQNonByteAlignedTB');
    badRow = row; badRow.TBSize_bits=15.9;
    localRejectUnchanged(state,badRow,h,direction,'sixgr:truth:ExecutedHARQSizeMismatch');
    bad = rmfield(h,'GrantSnapshot');
    localRejectUnchanged(state,row,bad,direction, ...
        "sixgr:truth:CoupledTruthRuntime:MissingExecuted"+direction+"GrantSnapshot");
    for field = ["TBSBits","TransportBlockSize","TBSBytes"]
        bad = h; bad.GrantSnapshot.(field)=3;
        localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQSizeMismatch');
    end
    bad = h; bad.GrantSnapshot.PHYGrant.CodingLayout.TBSBits=24;
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQSizeMismatch');
    bad = h; bad.Context.GrantSnapshot=h.GrantSnapshot;
    bad.Context.GrantSnapshot.TBSBits=24;
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQSizeMismatch');
    bad = h; bad.Context.TransportBlockContext.TBSBits=24;
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQSizeMismatch');
    bad = h; bad.Context.GrantSnapshot=[];
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQInvalidGrant');
    bad = h; bad.Context.TransportBlockContext="not_a_layout";
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQInvalidContext');
    bad = h; bad.HARQTBContext.TBSBits=NaN;
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQSizeMismatch');
    bad = h; bad.GrantSnapshot.Direction="opposite";
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQGrantDirectionMismatch');
    bad = h; bad.CombinedDecodeOK=true;
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:MissingDecodedTransportBlock');
    bad = h; bad.CombinedDecodeOK=NaN;
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQInvalidDecodeFlag');
    bad = h; bad.DecodedTransportBlockBits=[0.5;zeros(15,1)];
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQInvalidBits');
    bad = h; bad.DecodedTransportBlockBits=zeros(8,1,'int8');
    localRejectUnchanged(state,row,bad,direction,'sixgr:truth:ExecutedHARQSizeMismatch');
    planning = state; planning.RuntimeViewMode="future_ul_grant_planning";
    localRejectUnchanged(planning,row,h,direction,'sixgr:truth:ExecutionFromPlanningView');
    sweepState = state; sweepState.CurrentSweepPointIndex = 3;
    staleRow = row; staleRow.SweepPointIndex = 2;
    localRejectUnchanged(sweepState,staleRow,h,direction, ...
        'sixgr:truth:ExecutedSweepPointMismatch');
end
ok = true;
disp('PASS testExecutedHARQPayloadAuthority: no fabricated payload or grant, no mutation on rejection.');
end

function localRejectUnchanged(state,row,h,direction,id)
beforeDL = localSnapshot(state.DLHarq);
beforeUL = localSnapshot(state.ULHarq);
beforeRNG = rng;
caught = false;
try
    sixgr.truth.CoupledTruthRuntime.completeSlot(state,struct(),1,direction,row,struct('HARQ',h));
catch ex
    assert(string(ex.identifier)==string(id),'Expected %s; got %s: %s',id,ex.identifier,ex.message);
    caught = true;
end
assert(caught,'Expected %s.',id);
assert(isequaln(beforeDL,localSnapshot(state.DLHarq)) && ...
    isequaln(beforeUL,localSnapshot(state.ULHarq)) && isequaln(beforeRNG,rng), ...
    'A rejected completion mutated the shared HARQ handle or RNG.');
end

function s = localSnapshot(harq)
s = struct('Stats',harq.Stats,'UEList',harq.UEList, ...
    'UEProcs',{harq.UEProcs},'DeliveryLedger',harq.DeliveryLedger);
end
