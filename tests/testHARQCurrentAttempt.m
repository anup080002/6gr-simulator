function ok=testHARQCurrentAttempt()
% Production frozen grants + HARQ entity and native coding-layout operands.
% NACK/CSI/TCI/resources are declared control-boundary inputs. No waveform,
% received DCI/feedback, channel or successful decoding claim is made.
setup6GRSimToolkit('Verbose',false);
for direction=["DL","UL"]
    cfg=sixgr.config.defaultConfig();
    cfg.phy.pdsch.numPorts=2; cfg.phy.pdsch.nPorts=2;
    cfg.phy.pdsch.hybridBeamformingEnabled=false;
    cfg.phy.pdsch.enablePTRS=false;
    cfg.phy.pusch.NumAntennaPorts=2;
    cfg.phy.pusch.TransmissionScheme='nonCodebook';
    cfg.phy.pusch.transformPrecoding=false;
    cfg.phy.pusch.hybridBeamformingEnabled=false;
    cfg.phy.pusch.enablePTRS=false;
    owner=sixgr.l2.mac.HARQEntity(cfg,'Direction',direction);
    tbs=256; bits=uint8(mod((0:tbs-1).',2));
    allocated=owner.allocate(101,1,tbs/8,'NewData',true);
    grant=struct('Direction',char(direction),'Frame',1,'Slot',1,'RNTI',101, ...
        'UEIndex',1,'ServingCell',1,'PRBSet',0:5,'SymbolAllocation',[2 10], ...
        'Modulation','QPSK','MCSIndex',0,'TargetCodeRate',120/1024, ...
        'TBSBits',tbs,'TBSBytes',tbs/8,'TransportBlockSize',tbs, ...
        'TransportBlockId','declared_original_tb','TBId','declared_original_tb', ...
        'NumLayers',1,'Layers',1,'NumLogicalPorts',2,'NumRFChains',2, ...
        'NumElements',2,'NumRxAntennas',2,'DMRSPortSet',0, ...
        'PTRSEnabled',false,'PTRSPortSet',[],'PMI',0,'AppliedPrecoderPMI',0, ...
        'PrecodingMatrixLogicalPorts',[1;0],'PrecodingMatrix',[1;0], ...
        'TransmissionScheme','nonCodebook','IsRetransmission',false,'HARQ',allocated.HARQ);
    grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,grant,'Slot',1,'Frame',1);
    firstLayout=layout(direction,tbs,0,4096);
    grant.HARQTBContext=sixgr.harq.createTBContext(struct('Grant',grant, ...
        'PHYGrant',grant.PHYGrant,'CodingLayout',firstLayout,'Direction',direction,'TBSBits',tbs));
    owner.onTx(101,allocated.HARQ.HarqID,bits,grant,1);
    owner.onFeedback(101,allocated.HARQ.HarqID,'NACK','SourceSlot',1,'FeedbackSlot',3);
    original=owner.peekRetx(101,3);
    assert(~isempty(original) && isequal(original.TB,bits));
    current=original.LastGrant; current=rmfield(current,'PHYGrant');
    current.Slot=3; current.HARQ=original.HARQ; current.IsRetransmission=true;
    current.GrantContextId='declared_new_attempt';
    % A different current spatial operator is legal at this validation
    % boundary. The helper must not restore the original [1;0] coefficient.
    current.PrecodingMatrixLogicalPorts=[0;1]; current.PrecodingMatrix=[0;1];
    current.PMI=1; current.AppliedPrecoderPMI=1;
    current.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,current,'Slot',3,'Frame',1);
    nextLayout=layout(direction,tbs,original.HARQ.RV,3072);
    assert(string(firstLayout.CombineSignature)==string(nextLayout.CombineSignature) && ...
        string(firstLayout.RateMatchSignature)~=string(nextLayout.RateMatchSignature));
    beforeOriginal=original; beforeCurrent=current; beforeRNG=rng;
    beforeCalls=sixgr.runtime.RuntimeCallLedger.snapshot();
    prepared=sixgr.phy.grant.validateHARQCurrentAttempt(original,current,bits);
    full=sixgr.phy.grant.validateHARQCurrentAttempt(original,current,bits, ...
        'CurrentCodingLayout',nextLayout);
    assert(prepared.OriginalPayloadAndProcessValidated && ...
        prepared.FixedRankImplementationPolicyApplied && ~prepared.NativeCodingOperandsValidated && ...
        full.NativeCodingOperandsValidated && ~full.OriginalSpatialStateSubstituted && ...
        ~full.IndependentExecutionAttested && full.CurrentRV==original.HARQ.RV && ...
        isequal(current.PHYGrant.PrecodingState.MatrixPhysicalPorts,[0;1]));
    % Match original producer semantics: the context can precede native
    % encoding. Missing native operands must not become a segmentation pass.
    limited=original;
    limited.TBContext.LDPCBaseGraph=NaN; limited.TBContext.LiftingSizeZc=NaN;
    limited.TBContext.CodeBlockSizes=NaN; limited.TBContext.NcbPerCodeBlock=NaN;
    limitedCurrent=current; limitedCurrent.HARQTBContext=limited.TBContext;
    limitedReceipt=sixgr.phy.grant.validateHARQCurrentAttempt(limited,limitedCurrent,bits);
    assert(~limitedReceipt.NativeCodingOperandsValidated);
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(limited,limitedCurrent,bits, ...
        'CurrentCodingLayout',nextLayout),'sixgr:phy:grant:HARQCurrentAttemptScalar');
    badBits=bits; badBits(17)=1-badBits(17); % Not just a first-bit sentinel.
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,current,badBits), ...
        'sixgr:phy:grant:HARQCurrentAttemptTransportBlock');
    for field=["RNTI","UEIndex","ServingCell"]
        bad=current; bad.(field)=bad.(field)+1;
        reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
            'sixgr:phy:grant:HARQCurrentAttemptIdentity');
    end
    for field=["HarqID","NDIEpoch","RV"]
        bad=current; bad.HARQ.(field)=bad.HARQ.(field)+1;
        reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
            'sixgr:phy:grant:HARQCurrentAttemptIdentity');
    end
    bad=current; bad.HARQ.NDI=~bad.HARQ.NDI;
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
        'sixgr:phy:grant:HARQCurrentAttemptIdentity');
    bad=current; bad.TransportBlockId='another_original_tb';
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
        'sixgr:phy:grant:HARQCurrentAttemptIdentity');
    bad=current; bad.TransportBlockSize=tbs+8;
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
        'sixgr:phy:grant:HARQCurrentAttemptTransportBlock');
    bad=current; bad.NumLayers=2;
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
        'sixgr:phy:grant:HARQCurrentAttemptFixedRankPolicy');
    bad=current; bad.HARQTBContext.CodeBlockLayoutHash='changed_original_context';
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
        'sixgr:phy:grant:HARQCurrentAttemptOriginalContext');
    for field=["PrecodingMatrix","PrecodingMatrixLogicalPorts"]
        bad=current; bad.(field)=[1;0];
        reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
            'sixgr:phy:grant:HARQCurrentAttemptSpatialAlias');
    end
    for field=["NumElements","NumLogicalPorts","NumRFChains","NumRxAntennas"]
        bad=current; bad.(field)=NaN;
        reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
            'sixgr:phy:grant:HARQCurrentAttemptSpatialAlias');
        bad=current; bad.(field)=current.(field)+1;
        reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
            'sixgr:phy:grant:HARQCurrentAttemptSpatialAlias');
    end
    bad=current; bad.AppliedPrecoderPMI=0;
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
        'sixgr:phy:grant:HARQCurrentAttemptSpatialAlias');
    for field=["CombineSignature","CodingLayoutHash"]
        badLayout=nextLayout; badLayout.(field)='invalid_signature';
        reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,current,bits, ...
            'CurrentCodingLayout',badLayout),'sixgr:phy:grant:HARQCurrentAttemptNativeCoding');
    end
    badLayout=nextLayout; badLayout.BaseGraph=uint8(3-double(nextLayout.BaseGraph));
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,current,bits, ...
        'CurrentCodingLayout',badLayout),'sixgr:phy:grant:HARQCurrentAttemptNativeCoding');
    bad=current; bad.PHYGrant.IsFrozen=1;
    reject(@()sixgr.phy.grant.validateHARQCurrentAttempt(original,bad,bits), ...
        'sixgr:phy:grant:HARQCurrentAttemptSchema');
    assert(isequaln(original,beforeOriginal) && isequaln(current,beforeCurrent) && ...
        isequaln(owner.peekRetx(101,3),original) && isequal(rng,beforeRNG) && ...
        isequaln(sixgr.runtime.RuntimeCallLedger.snapshot(),beforeCalls));
    fprintf('HARQ_CURRENT_ATTEMPT_PASS direction=%s native_layout_producers=2 waveform_RX=0\n',direction);
end
ok=true;
end

function value=layout(direction,tbs,rv,E)
value=sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',tbs,'TargetCodeRate',120/1024,'RV',rv, ...
    'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',E);
end
function reject(fn,id)
try, fn(); catch ex
    assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); return;
end
error('test:ExpectedHARQCurrentAttemptRejection','Expected %s.',id);
end
