function ok=testMaterializedCSIHybridHARQ()
% Declared CSI and NACK boundaries; actual PF/RR scheduling, no RX claim.
setup6GRSimToolkit('Verbose',false);
for kind=["PF","RR"]
    cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
    cfg.antenna.bs.numElements=4; cfg.scenario.bs.nTxAnt=4;
    cfg.phy.nTxAnt=4; cfg.channel.nTxAnt=4;
    cfg.antenna.bs.numRFChains=4; cfg.rf.bs.numRFChains=4;
    cfg.rf.bs.hybridBeamformingEnabled=true;
    cfg.phy.pdsch.numPorts=2; cfg.phy.pdsch.nPorts=2;
    cfg.phy.pdsch.numLayers=1; cfg.phy.pdsch.nLayers=1;
    cfg.phy.pdsch.precoding.matrix=[]; cfg.phy.pdsch.precodingMatrix=[]; cfg.phy.pdsch.W=[];
    cfg.phy.pdsch.symbolAllocation=[2 12];
    cfg.phy.pdsch.timeDomainAllocations=[0 2 12 1];
    basis=fft(eye(4))/2;
    cfg.phy.csirs.precoderMatrices=cat(3,basis(:,1:2),basis(:,3:4));
    cfg.phy.csi.pmiCodebookMode='type1_su_mimo';
    cfg.mac.scheduler.maxUEPerSlot=1; cfg.mac.scheduler.maxUEPerSlotDL=1;
    cfg.mac.scheduler.muMimoEnabled=false; cfg.mac.harq.enable=true;
    harq=sixgr.l2.mac.HARQEntity(cfg,'Direction','DL', ...
        'NumProcesses',4,'MaxRetx',3,'StoreTB',true);
    if kind=="PF"
        scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL','HARQ',harq);
    else
        scheduler=sixgr.l2.mac.SchedulerRR(cfg,'Direction','DL','HARQ',harq);
    end
    [candidates,~]=sixgr.phy.dl.pmiCodebookCandidates(cfg,1,2,'Mode','type1_su_mimo');
    ue=struct('RNTI',4101,'UEIndex',1,'ServingCell',1, ...
        'DLBufferBytes',20000,'ULBufferBytes',0,'CQI',8,'RI',1, ...
        'PMI',double(candidates(1).PMI),'CRI',1, ...
        'HeadOfLineDelay_ms',1,'ControlEligible',true,'GrantControlState','ok');
    budget=struct('PRBSet',0:23,'ControlSymbolAllocation',[0 2], ...
        'SymbolAllocation',[2 12]);
    first=scheduler.schedule(0,ue,budget);
    assert(numel(first)==1 && first.PHYGrant.PrecodingState.CSIRSPortBasisApplied);
    prec=first.PHYGrant.PrecodingState;
    assert(first.PHYGrant.AntennaArchitecture.NumRFChains==4 && ...
        first.PHYGrant.AntennaArchitecture.NumTxRUs==4 && ...
        first.PHYGrant.AntennaArchitecture.NumLogicalPorts==2);
    % The production waveform materializes these aliases before HARQ storage.
    first.PrecodingMatrixLogicalPorts=prec.MatrixLogicalPorts;
    first.PrecodingMatrix=prec.MatrixPhysicalPorts;
    first.HybridElementToPortMatrix=prec.HybridElementToPortMatrix;
    first.AppliedPrecoderPMI=prec.PMI;
    first.AppliedPrecoderCodebookMode=prec.CodebookMode;
    first.PrecoderNormalizationConvention=prec.NormalizationConvention;
    % Incidental numeric PMI/CRI do not authorize relabeling a custom matrix.
    custom=first;
    custom=rmfield(custom,{'PHYGrant','AppliedPrecoderCodebookMode'});
    custom.PrecoderSource='declared_custom_matrix';
    custom.AppliedPrecoderCodebookMode='runtime_precoder_mode';
    if isfield(custom,'PMICodebookMode'), custom=rmfield(custom,'PMICodebookMode'); end
    arch=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,'bs', ...
        'Signal','PDSCH','NumElements',4,'NumPorts',2,'MinimumPorts',1);
    custom.PrecodingMatrixLogicalPorts=[1;0];
    custom.HybridElementToPortMatrix=arch.HybridElementToPortMatrix;
    custom.PrecodingMatrix=arch.HybridElementToPortMatrix*[1;0];
    customFrozen=sixgr.phy.grant.freezePHYGrant(cfg,'DL',custom);
    assert(~customFrozen.PrecodingState.CSIRSPortBasisApplied && ...
        isequal(customFrozen.PrecodingState.MatrixLogicalPorts,[1;0]));
    payload=zeros(first.TBSBits,1,'uint8');
    harq.onTx(ue.RNTI,first.HARQ.HarqID,payload,first,0);
    harq.onFeedback(ue.RNTI,first.HARQ.HarqID,'NACK','SourceSlot',0,'FeedbackSlot',4);
    retry=scheduler.schedule(5,ue,budget);
    assert(numel(retry)==1 && retry.HARQ.IsRetransmission);
    actual=retry.PHYGrant.PrecodingState;
    assert(actual.CSIRSPortBasisApplied && actual.CSIResourceIndex==1 && ...
        isequal(actual.MatrixPhysicalPorts,prec.MatrixPhysicalPorts) && ...
        isequal(actual.MatrixLogicalPorts,prec.MatrixLogicalPorts) && ...
        string(actual.CSIRSPortToElementMatrixSHA256)==string(prec.CSIRSPortToElementMatrixSHA256));
    assert(retry.HARQ.NDI==first.HARQ.NDI && retry.HARQ.HarqID==first.HARQ.HarqID && ...
        retry.TBSBits==first.TBSBits && retry.PHYGrant.CodingLayout.NumLayers==1);
end
% Configured RF chains and active logical ports are independent on UL too.
cfg=sixgr.config.defaultConfig();
cfg.antenna.ue.numElements=4; cfg.scenario.ue.nTxAnt=4;
cfg.antenna.ue.numRFChains=4; cfg.rf.ue.numRFChains=4;
cfg.rf.ue.hybridBeamformingEnabled=true;
cfg.phy.pusch.numPorts=2; cfg.phy.pusch.nPorts=2;
cfg.phy.pusch.NumAntennaPorts=2;
g=struct('Direction','UL','Frame',0,'Slot',0,'RNTI',101,'UEIndex',1, ...
    'ServingCell',1,'PRBSet',0:5,'SymbolAllocation',[2 10], ...
    'Modulation','QPSK','NumLayers',1,'Layers',1,'NumLogicalPorts',2, ...
    'TargetCodeRate',0.3,'MCSIndex',1,'TransmissionScheme','nonCodebook', ...
    'PrecodingMatrixLogicalPorts',[1;0]);
frozen=sixgr.phy.grant.freezePHYGrant(cfg,'UL',g);
assert(frozen.AntennaArchitecture.NumRFChains==4 && ...
    frozen.AntennaArchitecture.NumTxRUs==4 && ...
    frozen.AntennaArchitecture.NumLogicalPorts==2 && ...
    isequal(size(frozen.PrecodingState.HybridElementToPortMatrix),[4 2]));
g.NumTxRUs=2;
try
    sixgr.phy.grant.freezePHYGrant(cfg,'UL',g);
catch ME
    assert(string(ME.identifier)=="sixgr:phy:grant:FrozenTransmitRUCountMismatch", ...
        'Unexpected alias rejection %s: %s',ME.identifier,ME.message);
    ok=true;
    return;
end
error('testMaterializedCSIHybridHARQ:MissingAliasGuard','Conflicting TXRU alias was accepted.');
end
