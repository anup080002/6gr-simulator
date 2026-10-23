function ok=testPUSCHTwoCodewordHARQFacade(outputRoot)
% Direct waveform/codec boundary, NOT a scheduled HARQ retransmission test.
% The same two actual TBs are deliberately invoked at RV0 and RV2, even if
% RV0 passed. This tests caller-retained soft state; it does not authorize a
% retransmission after ACK or qualify connected rank>4 scheduling/performance.
setup6GRSimToolkit('Verbose',false);
previous=rng; cleanup=onCleanup(@()rng(previous)); %#ok<NASGU>
rng(95082,'twister');
if nargin<1, outputRoot=tempname(fullfile(pwd,'logs')); end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve earlier PHY boundary evidence.');
mkdir(outputRoot);
scope="direct_PHY_retained_same_TB_RV_boundary_not_MAC_retransmission";
for rank=5:8
    [cfg,carrier,p,rate]=localFixture(rank);
    tx0=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',carrier,'PUSCH',p, ...
        'TargetCodeRate',rate,'RV',[0 0],'NumTxAnt',8,'CompactOutput',false);
    rx0=localReceive(tx0,cfg,p,rate,[0 0],[],[]);
    tx2=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',carrier,'PUSCH',p, ...
        'TargetCodeRate',rate,'RV',[2 2],'NumTxAnt',8,'CompactOutput',false, ...
        'TransportBlockBits',tx0.TransportBlocks, ...
        'TransportBlockSizeOverride',tx0.TransportBlockSize);
    current=localReceive(tx2,cfg,p,rate,[2 2],[],[]);
    combined=localReceive(tx2,cfg,p,rate,[2 2],rx0.HARQSoftBufferCell,rx0.CodingLayouts);
    reference0=localReference(rx0,p,rate,[0 0],[],[]);
    referenceCurrent=localReference(current,p,rate,[2 2],[],[]);
    referenceCombined=localReference(current,p,rate,[2 2],rx0,[0 0]);
    % Retain actual current-only decisions as well as combined decisions.
    % RV2-only failure is a measured decode outcome, never a fixture defect
    % to conceal by changing G, rate, RV, iterations or the CRC decision.
    save(fullfile(outputRoot,sprintf('pusch_two_cw_rank_%d.mat',rank)), ...
        'scope','rank','rate','tx0','tx2','rx0','current','combined', ...
        'reference0','referenceCurrent','referenceCombined');
    assert(isequal(tx0.TransportBlocks,tx2.TransportBlocks));
    localAssertReference(rx0,reference0);
    localAssertReference(current,referenceCurrent);
    localAssertReference(combined,referenceCombined);
    assert(all(rx0.CRCPass) && all(combined.CRCPass) && ...
        isequal(rx0.TransportBlocks,tx0.TransportBlocks) && ...
        isequal(combined.TransportBlocks,tx0.TransportBlocks));
    assert(~rx0.HARQSoftCombiningApplied && ~current.HARQSoftCombiningApplied && ...
        all(combined.HARQSoftCombiningAppliedPerCodeword) && ...
        combined.HARQSoftCombiningApplied && combined.HARQSoftCombiningPositionAware);
    assert(isequal(current.ULSCHCodewordLLRCell,combined.ULSCHCodewordLLRCell));
    assert(~isfield(combined,'RateRecoveredLLR') && ~isfield(combined,'RecLLR'), ...
        'A combined CW1 scalar must not masquerade as current two-codeword LLRs.');
    for cw=1:2
        assert(rx0.HARQSoftBufferCell{cw}.CodewordIndex==cw && ...
            combined.HARQSoftBufferCell{cw}.CodewordIndex==cw && ...
            combined.CodewordDecodeEvidence{cw}.CodewordIndex==cw-1);
        assert(isequaln(combined.HARQSoftBufferCell{cw}.LLRSum, ...
            rx0.HARQSoftBufferCell{cw}.LLRSum+current.HARQSoftBufferCell{cw}.LLRSum));
        assert(isequal(combined.HARQSoftBufferCell{cw}.ObservationWeight, ...
            rx0.HARQSoftBufferCell{cw}.ObservationWeight+current.HARQSoftBufferCell{cw}.ObservationWeight));
    end
    if rank==6
        localNegativeAndPartialPriors(tx2,cfg,p,rate,rx0,current);
    end
    fprintf('PUSCH_TWO_CW_PHY_BOUNDARY rank=%d RV0crc=%s RV2currentcrc=%s RV2combinedcrc=%s evidence=%s\n', ...
        rank,mat2str(rx0.CRCPass),mat2str(current.CRCPass),mat2str(combined.CRCPass),outputRoot);
end
localSingleCodewordCellDispatch();
ok=true;
end

function [cfg,carrier,p,rate]=localFixture(rank)
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
p=nrPUSCHConfig;
p.PRBSet=0:23; p.SymbolAllocation=[0 14]; p.MappingType='A';
p.Modulation={'QPSK','16QAM'}; rate=[.30 .45];
if rank==6
    % Same mother-code shape/hash in both CWs defeats a shape-only guard.
    p.Modulation={'QPSK','QPSK'}; rate=[.30 .30];
end
p.NumLayers=rank; p.TransmissionScheme='codebook';
p.NumAntennaPorts=8; p.TPMI=0; p.TransformPrecoding=false;
p.DMRS.DMRSConfigurationType=2; p.DMRS.DMRSLength=2;
p.DMRS.DMRSPortSet=0:(rank-1);
cfg=struct('run',struct('strictMode',false), ...
    'channel',struct('model','AWGN'), ...
    'phy',struct('ueArray',[8 1 1],'pusch',struct('NumAntennaPorts',8), ...
    'channelEstimation',struct('method','LS')));
end

function rx=localReceive(tx,cfg,p,rate,rv,prior,priorLayouts,varargin)
% The direct boundary declares TBS/rate/RV and allocation, not a TX G or a
% transmitter layout. The receiver derives G from actual demapped LLRs.
rx=sixgr.phy.ul.PUSCH_Rx(tx.Waveform,cfg,'Carrier',tx.Carrier, ...
    'PUSCH',p,'TransportBlockSize',tx.TransportBlockSize, ...
    'TargetCodeRate',rate,'RV',rv,'NoiseVar',1e-12,'NoiseVarDomain','time', ...
    'MaxIterations',25,'Algorithm','Normalized min-sum', ...
    'FastAWGNPath',false,'SkipTimingEstimate',true,'CompactOutput',false, ...
    'HARQSoftBufferLLR',prior,'HARQSoftBufferLayout',priorLayouts,varargin{:});
end

function reference=localReference(rx,p,rate,rv,prior,priorRV)
layers=sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(p.NumLayers);
mods=string(p.Modulation); blocks=cell(1,2); errors=zeros(1,2); recovered=cell(1,2);
for cw=1:2
    A=rx.TransportBlockSize(cw); sch=nrULSCHInfo(A,rate(cw));
    value=nrRateRecoverLDPC(rx.ULSCHCodewordLLRCell{cw},A,rate(cw),rv(cw),char(mods(cw)),layers(cw));
    if ~isempty(prior)
        value=value+nrRateRecoverLDPC(prior.ULSCHCodewordLLRCell{cw}, ...
            A,rate(cw),priorRV(cw),char(mods(cw)),layers(cw));
    end
    recovered{cw}=value;
    decoded=nrLDPCDecode(value,sch.BGN,25,'Algorithm','Normalized min-sum');
    withCRC=nrCodeBlockDesegmentLDPC(decoded,sch.BGN,A+sch.L);
    [blocks{cw},errors(cw)]=nrCRCDecode(withCRC,sch.CRC);
    blocks{cw}=int8(blocks{cw}(:));
end
reference=struct('TransportBlocks',{blocks},'CRCError',logical(errors), ...
    'DecoderInput',{recovered});
end

function localAssertReference(rx,reference)
assert(isequal(rx.TransportBlocks,reference.TransportBlocks) && ...
    isequal(rx.CRCError,reference.CRCError));
for cw=1:2
    actual=rx.CombinedRateRecoveredLLRCell{cw}; expected=reference.DecoderInput{cw};
    assert(isequal(size(actual),size(expected)) && isequal(isinf(actual),isinf(expected)));
    finite=isfinite(expected);
    assert(all(isfinite(actual(finite))) && ...
        all(abs(actual(finite)-expected(finite))<=1e-12*max(1,max(abs(expected(finite))))));
end
end

function localNegativeAndPartialPriors(tx,cfg,p,rate,initial,current)
priors=initial.HARQSoftBufferCell; layouts=initial.CodingLayouts;
assert(isequal(size(priors{1}.LLRSum),size(priors{2}.LLRSum)) && ...
    string(priors{1}.CodingLayoutHash)==string(priors{2}.CodingLayoutHash), ...
    'The cross-codeword negative must have identical shape and coding hash.');
localReject(@()localReceive(tx,cfg,p,rate,[2 2],priors([2 1]),layouts), ...
    'sixgr:phy:harq:SoftBufferCodewordMismatch');
localReject(@()localReceive(tx,cfg,p,rate,[2 2],priors{1},layouts), ...
    'sixgr:pusch:MissingPerCodewordCodingAuthority');
localReject(@()localReceive(tx,cfg,p,rate,[2 2],priors(1),layouts), ...
    'sixgr:pusch:MissingPerCodewordCodingAuthority');
localReject(@()localReceive(tx,cfg,p,rate,[2 2],priors,layouts{1}), ...
    'sixgr:pusch:MissingPerCodewordCodingAuthority');
localReject(@()localReceive(tx,cfg,p,rate,[2 2],priors,layouts(1)), ...
    'sixgr:pusch:MissingPerCodewordCodingAuthority');
badLayout=current.CodingLayouts;
badLayout{2}.RateMatchedBitCount=badLayout{2}.RateMatchedBitCount+uint32(1);
localReject(@()localReceive(tx,cfg,p,rate,[2 2],priors,layouts,'CodingLayout',badLayout), ...
    'sixgr:phy:ul:PUSCHCodingLayoutMismatch');
missing=priors; missing{2}=[];
partial=localReceive(tx,cfg,p,rate,[2 2],missing,layouts);
assert(isequal(partial.HARQSoftCombiningAppliedPerCodeword,[true false]) && ...
    isequaln(partial.HARQSoftBufferCell{2},current.HARQSoftBufferCell{2}));
bad=priors; bad{2}.CodingLayoutHash='foreign-layout';
reset=localReceive(tx,cfg,p,rate,[2 2],bad,layouts);
assert(isequal(reset.HARQSoftCombiningAppliedPerCodeword,[true false]) && ...
    reset.HARQSoftCombiningPerCodeword{2}.ResetPrior && ...
    string(reset.HARQSoftCombiningPerCodeword{2}.Reason)=="coding_layout_mismatch_soft_combine_rejected" && ...
    isequaln(reset.HARQSoftBufferCell{2},current.HARQSoftBufferCell{2}));
assert(isequal(initial.HARQSoftBufferCell,priors),'Caller-owned prior buffers must remain unchanged.');
end

function localSingleCodewordCellDispatch()
% Legacy scalar inputs and exact one-cell inputs execute the same single-CW
% boundary. This repeat is not a scheduled retransmission or throughput trial.
[cfg,carrier,p,~]=localFixture(5);
p.NumLayers=1; p.NumAntennaPorts=1; p.Modulation='QPSK'; p.DMRS.DMRSPortSet=0;
cfg.phy.ueArray=[1 1 1]; cfg.phy.pusch.NumAntennaPorts=1; rate=.3;
tx=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',carrier,'PUSCH',p, ...
    'TargetCodeRate',rate,'RV',0,'NumTxAnt',1,'CompactOutput',false);
initial=localReceive(tx,cfg,p,rate,0,[],[]);
scalar=localReceive(tx,cfg,p,rate,0,initial.HARQSoftBuffer,initial.CodingLayout);
cellInput=localReceive(tx,cfg,p,rate,0,{initial.HARQSoftBuffer},{initial.CodingLayout});
assert(isequal(scalar.TransportBlock,cellInput.TransportBlock) && ...
    isequaln(scalar.RateRecoveredLLR,cellInput.RateRecoveredLLR) && ...
    scalar.HARQSoftCombiningApplied && cellInput.HARQSoftCombiningApplied && ...
    cellInput.HARQSoftBuffer.CodewordIndex==1);
localReject(@()localReceive(tx,cfg,p,rate,0,{initial.HARQSoftBuffer,[]},[]), ...
    'sixgr:pusch:MissingPerCodewordCodingAuthority');
end

function localReject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
