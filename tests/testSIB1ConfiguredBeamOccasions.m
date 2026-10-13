function ok=testSIB1ConfiguredBeamOccasions()
% Physical broadcast component on the exact two-UE scenario configuration.
% Four separate AWGN captures qualify each candidate's SI occasion; this
% does not claim simultaneous multi-UE access or statistical BLER coverage.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
root=fullfile(pwd,'results','lls','sib1_configured_beam_occasions', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
save(fullfile(root,'configuration.mat'),'cfg');
carrier=sixgr.phy.grid.makeCarrier(cfg);
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
rows=struct([]);
% Check every beam-associated SI occasion before any expensive waveform.
% The production plan checks CSI-RS/TRS over their joint repetition cycle.
for candidate=0:3
    current=cfg;
    current.phy.ssb.runtimeSSBIndex=candidate;
    common=sixgr.phy.frame.CommonDLResourcePlan(current);
    common.validateSIB1References();
end
localValidateReferenceCalendar(cfg,frame);
% Keep the reproduced resource conflicts observable: restoring the old
% reference placements must still fail, not puncture common SI silently.
collision=cfg;
collision.phy.csirs.symbolLocationsByResource=6;
localRejectReferences(collision,'sixgr:phy:frame:SIB1CSIRSCollision');
collision=cfg;
collision.phy.ssb.runtimeSSBIndex=2;
collision.phy.trs.slotNumbers=[7 8];
localRejectReferences(collision,'sixgr:phy:frame:SIB1TRSCollision');
for candidate=0:3
    current=cfg;
    current.phy.ssb.runtimeSSBIndex=candidate;
    [control,siCfg,siCarrier,~,slot0]=sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,current);
    [pdsch,dci]=sixgr.phy.broadcast.configuredSIB1Allocation(siCarrier,siCfg);
    assert(slot0==5+candidate && frame.IsDLAllocation(slot0,pdsch.SymbolAllocation));
    assert(frame.IsDLAllocation(slot0,[control.SearchSpace.StartSymbolWithinSlot control.CORESET.Duration]));
    assert(dci.TDRAIndex==3 && isequal(pdsch.SymbolAllocation,[2 7]));
    tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(current,'SNRdB',20,'Seed',1700+candidate);
    receiver=current;
    receiver.initial_access.sib1.pdsch=struct('prb_start',1,'num_prb',1, ...
        'symbol_start',2,'num_symbols',12,'mcs',0,'rv',0);
    % Candidate is a receiver search hypothesis, not supplied decoded bits
    % or transmit beam weights. Keep all physical receive branches intact.
    rx=sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform,receiver, ...
        'CandidateSSBIndex',candidate);
    row=struct('SSBIndex',candidate,'ConfiguredSNR_dB',20,'SIB1Slot0',slot0, ...
        'TDRAIndex',dci.TDRAIndex,'SymbolStart',pdsch.SymbolAllocation(1), ...
        'NumSymbols',pdsch.SymbolAllocation(2),'TBSBits',tx.SIB1TransportBlockSize, ...
        'PayloadBits',tx.SIB1PayloadNumBits,'ReceiveBranches',size(tx.Waveform,2), ...
        'PBCHCRC',rx.BCHCrcPass,'DCICRC',rx.DCICrcPass,'PDSCHCRC',rx.DLSCHCrcPass, ...
        'StrictOk',rx.StrictOk,'FailureReason',string(rx.FailureReason));
    save(fullfile(root,sprintf('candidate_%d.mat',candidate)),'row','rx');
    if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    writetable(struct2table(rows),fullfile(root,'broadcast_cases.csv'));
    assert(rx.StrictOk && rx.SSBIndex==candidate && rx.SIB1AbsoluteSlot==slot0, ...
        'test:SIB1ConfiguredBeamDecode','Candidate %d failed: %s',candidate,rx.FailureReason);
    assert(rx.PDSCHSymbolStart==2 && rx.PDSCHNumSymbols==7 && ...
        rx.PDSCHNumRB==24 && isempty(rx.UsedOracleFields));
    assert(tx.SIB1TransportBlockSize>=tx.SIB1PayloadNumBits && tx.SIB1TransportBlockSize<=2976);
end
fprintf('SIB1_CONFIGURED_BEAM_OCCASIONS_PASS %s\n',root);
ok=true;
end

function localValidateReferenceCalendar(cfg,frame)
carrier=sixgr.phy.grid.makeCarrier(cfg);
trs=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
period=lcm(lcm(double(cfg.phy.csirs.period_slots),double(cfg.phy.trs.period_slots)), ...
    double(cfg.phy.ssb.period_ms)*carrier.SlotsPerSubframe);
plane=12*carrier.NSizeGrid*carrier.SymbolsPerSlot;
counts=[0 0];
for slot0=0:2*period-1
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    carrier=sixgr.phy.grid.makeCarrier(current);
    ssb=sixgr.phy.frame.ssbPRBSymbolReservation(current,carrier,slot0);
    csiRE=zeros(0,1); trsRE=zeros(0,1);
    if sixgr.phy.refsig.csirsOccasion(current,slot0)
        indices=sixgr.phy.refsig.csirs(carrier,current);
        csiRE=unique(mod(double(indices(:))-1,plane));
        counts(1)=counts(1)+1;
        assert(~isempty(csiRE) && all(floor(csiRE/(12*carrier.NSizeGrid))==12));
    end
    if sixgr.truth.isActiveTRSOccasion(current,slot0+1)
        for resource=1:numel(trs.ToolboxResources)
            indices=nrCSIRSIndices(carrier,trs.ToolboxResources{resource},'IndexBase','0based');
            trsRE=[trsRE;mod(double(indices(:)),plane)]; %#ok<AGROW>
        end
        trsRE=unique(trsRE);
        counts(2)=counts(2)+1;
        assert(~isempty(trsRE));
    end
    assert(isempty(intersect(csiRE,ssb.ReservedCarrierRE0)) && ...
        isempty(intersect(trsRE,ssb.ReservedCarrierRE0)) && isempty(intersect(csiRE,trsRE)), ...
        'test:SIB1ReferenceCalendarCollision','Reference/SSB collision at absolute slot0 %d.',slot0);
    symbols=unique(floor([csiRE;trsRE]/(12*carrier.NSizeGrid)));
    for symbol=reshape(symbols,1,[])
        assert(frame.IsDLAllocation(slot0,[symbol 1]), ...
            'test:SIB1ReferenceOutsideDL','Reference outside DL symbols at slot0 %d.',slot0);
    end
end
assert(isequal(counts,[2*period/cfg.phy.csirs.period_slots ...
    2*period/cfg.phy.trs.period_slots*2]),'Reference producers must retain their configured cadences.');
end

function localRejectReferences(cfg,identifier)
try
    common=sixgr.phy.frame.CommonDLResourcePlan(cfg);
    common.validateSIB1References();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, observed %s.',identifier,cause.identifier);
    return;
end
error('test:SIB1ReferenceMissingRejection','Expected %s.',identifier);
end
