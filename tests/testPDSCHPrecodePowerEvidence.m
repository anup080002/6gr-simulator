function [ok,checks]=testPDSCHPrecodePowerEvidence()
% Actual calibration TX and declared mapping diagnostics, not received-DCI,
% receiver performance, physical feed power, or radiation qualification.
% Native Type-I matrices are selected/frozen by production code, not scaled
% in this test. Explicit-matrix cases retain their separately declared rule.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; restoreRNG=onCleanup(@() rng(savedRNG)); %#ok<NASGU>
rng(84611,'twister');
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_four_port_received_rank_transition_fixture.yaml');
nativeCfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
[nativeCfg,~]=sixgr.phy.grid.applyRuntimeCarrierTimeline(nativeCfg,16,2);
rows=repmat(struct('Case',"",'Passed',false,'FailureID',"",'Detail',""),0,1);
for layers=[1 2 4]
    record("actual_native_frozen_rank"+layers,@() localNative(nativeCfg,layers));
end
record("actual_explicit_semi_unitary",@() localExplicit(eye(4,2),"semi_unitary"));
record("actual_explicit_trace_one",@() localExplicit(eye(4,2)/sqrt(2),"unit_frobenius"));
record("actual_explicit_nonorthogonal_trace_one", ...
    @() localExplicit([1 1;0 1;0 0;0 0]/sqrt(3),"unit_frobenius"));
record("actual_explicit_unnormalized", ...
    @() localExplicit([2 1;0 1;0 0;0 0],"explicit_no_normalization"));
record("actual_frequency_selective_pages",@localActualPRG);
record("actual_siso_identity_bypass",@localIdentity);
record("symbol_group_pages_and_source_guards",@localSymbolGroups);
record("single_page_precision_and_mapping_poison",@localSinglePage);
checks=struct2table(rows);
failed=checks(~checks.Passed,:);
for k=1:height(failed)
    fprintf(2,'PDSCH_POWER %s FAIL %s %s\n', ...
        failed.Case(k),failed.FailureID(k),failed.Detail(k));
end
fprintf('PDSCH_PRECODE_POWER cases=%d failures=%d receiver_execution=0\n',height(checks),height(failed));
assert(isempty(failed),'test:PDSCHPrecodePowerEvidence', ...
    '%d/%d precoder-power evidence cases failed.',height(failed),height(checks));
ok=true;
    function record(name,fn)
        row=struct('Case',name,'Passed',false,'FailureID',"",'Detail',"");
        try
            fn(); row.Passed=true;
        catch failure
            row.FailureID=string(failure.identifier); row.Detail=string(failure.message);
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
end

function localNative(cfg,layers)
[candidates,info]=sixgr.phy.dl.pmiCodebookCandidates(cfg,layers,4);
candidate=candidates(find([candidates.PMI]==0,1));
assert(string(info.NormalizationConvention)=="unit_frobenius");
p=cfg.phy.pdsch;
grant=struct('Direction','DL','Frame',2,'Slot',16, ...
    'UEIndex',1,'RNTI',double(p.RNTI),'ServingCell',1, ...
    'PRBSet',double(p.prbSet(:).'),'SymbolAllocation',double(p.symbolAllocation(:).'), ...
    'Modulation',p.modulation,'TargetCodeRate',double(p.codeRate), ...
    'MCSIndex',double(p.mcsIndex),'MCS',double(p.mcsIndex), ...
    'NumLayers',layers,'Layers',layers,'NumLogicalPorts',4, ...
    'PMI',0,'AppliedPrecoderPMI',0,'CRI',0, ...
    'PrecodingMatrix',[],'PrecodingActive',true,'K0',0, ...
    'GrantContextId',"declared_power_native_rank_"+layers, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
grant=withAuthoredPDSCHDCI(cfg,grant); % TX-only packed control, not reception.
frozen=sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant);
assert(isequaln(frozen.PrecodingState.PMICodebookMatrixCSIPorts,candidate.W));
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'PHYGrant',frozen, ...
    'ExecutionProfile','phy_calibration','CompactOutput',false);
assert(isequaln(tx.PHYGrant,frozen) && ...
    isequaln(tx.PrecodeInfo.MatrixPorts,frozen.PrecodingState.MatrixPhysicalPorts));
localCheckTX(tx,info,"unit_frobenius");
e=tx.PrecodePowerInfo;
assert(e.NormalizationTraceMaxError<1e-12 && ...
    e.EqualPowerOrthogonalReferenceGramMaxDeviation<1e-12 && ...
    e.EqualPowerOrthogonalReferenceColumnMaxDeviation<1e-12);
% This fixture's actual physical basis is orthonormal. The native trace-1
% codebook therefore divides this particular data energy by rank, not by1.
assert(abs(e.PortTotalEnergy-e.LayerTotalEnergy/layers)<1e-9);
if layers>1
    assert(e.TotalEnergyDelta<0 && isnan(e.ColumnNormMaxError) && ...
        isnan(e.OrthonormalColumnMaxError) && ~e.GramConstraintApplicable);
end
end

function localExplicit(W,convention)
[cfg,carrier,pdsch]=localCalibration(size(W,1),size(W,2),convention);
% This declared calibration request is the matrix-selection owner. Seal its
% original operands before TX; never fabricate a received-DCI authority.
cfg.phy.pdsch.selectedPrecoderSHA256=sixgr.phy.mimo.MatrixContract.digest(W);
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'Carrier',carrier,'PDSCH',pdsch, ...
    'PrecodingMatrix',W,'TargetCodeRate',0.30,'RV',0,'CompactOutput',false);
assert(isequaln(tx.PrecodeInfo.MatrixPorts,W),'Explicit matrix must not be renormalized.');
assert(tx.PrecodeInfo.SelectedMatrixSHA256==cfg.phy.pdsch.selectedPrecoderSHA256 && ...
    tx.PrecodeInfo.AppliedMatrixSHA256==cfg.phy.pdsch.selectedPrecoderSHA256);
localCheckTX(tx,info,convention);
e=tx.PrecodePowerInfo;
if convention=="semi_unitary"
    assert(e.GramConstraintApplicable && e.ColumnNormConstraintApplicable && ...
        isequal(e.ExpectedGram,eye(size(W,2))) && e.OrthonormalColumnMaxError<1e-12);
elseif convention=="unit_frobenius"
    assert(~e.GramConstraintApplicable && ~e.EqualPowerOrthogonalReferenceRequired && ...
        all(isnan(e.ExpectedGram),'all') && e.NormalizationTraceMaxError<1e-12);
    if abs(W(:,1)'*W(:,2))>1e-3
        assert(e.EqualPowerOrthogonalReferenceGramMaxDeviation>0.1 && ...
            isnan(e.OrthonormalColumnMaxError) && e.TotalPowerRelativeError<1e-12);
    end
else
    assert(isnan(e.ExpectedFrobeniusPower) && isnan(e.NormalizationTraceMaxError) && ...
        ~e.GramConstraintApplicable && e.TotalPowerRelativeError<1e-12);
end
end

function localActualPRG()
[cfg,carrier,pdsch]=localCalibration(2,1,"explicit_no_normalization");
prg=nrPRGInfo(carrier,2); W=complex(zeros(2,1,prg.NPRG));
W(1,1,1:2:end)=1; W(2,1,2:2:end)=2i;
% The selected identity covers every original page, not only W(:,:,1).
cfg.phy.pdsch.selectedPrecoderSHA256=sixgr.phy.mimo.MatrixContract.digest(W);
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'Carrier',carrier,'PDSCH',pdsch, ...
    'PrecodingMatrix',W,'TargetCodeRate',0.30,'RV',0,'CompactOutput',false);
assert(isequaln(tx.PrecodeInfo.MatrixPortsPerPRG,W));
assert(tx.PrecodeInfo.SelectedMatrixSHA256==cfg.phy.pdsch.selectedPrecoderSHA256 && ...
    tx.PrecodeInfo.AppliedMatrixSHA256==cfg.phy.pdsch.selectedPrecoderSHA256);
e=tx.PrecodePowerInfo;
assert(isequaln(info.PrecodePowerInfo,e) && numel(e.FrobeniusPowerPerPage)==prg.NPRG && ...
    all(e.MappedResourceCountPerPage>0) && e.TotalPowerRelativeError<1e-12 && ...
    e.MappedSymbolMaxAbsError<1e-12);
assert(isequal(e.FrobeniusPowerPerPage(1:2:end),ones(ceil(prg.NPRG/2),1)) && ...
    isequal(e.FrobeniusPowerPerPage(2:2:end),4*ones(floor(prg.NPRG/2),1)));
wrongFirstPage=double(tx.PDSCHLayerSymbols)*W(:,:,1).';
assert(abs(sum(abs(wrongFirstPage).^2,'all')-e.PortTotalEnergy)>1, ...
    'Changing page powers must expose the old first-page-only energy oracle.');
localRawEnergy(tx,e);
end

function localIdentity()
[cfg,carrier,pdsch]=localCalibration(1,1,"semi_unitary");
% Exercise the supported legacy SISO no-bundle route explicitly, rather
% than depending on mutable catalog defaults for strict-MIMO selection.
cfg.mimo.strict=false; cfg.phy.mimo.strict=false;
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'Carrier',carrier,'PDSCH',pdsch, ...
    'TargetCodeRate',0.30,'RV',0,'CompactOutput',false);
assert(~tx.PrecodeInfo.Active && ...
    tx.PrecodePowerInfo.MappingEvidenceSource=="original_canonical_identity_mapping_trace");
localCheckTX(tx,info,"semi_unitary");
end

function localCheckTX(tx,info,convention)
S=double(tx.PDSCHLayerSymbols); X=double(tx.PDSCHPortSymbols); W=tx.PrecodeInfo.MatrixPorts;
e=tx.PrecodePowerInfo;
assert(isequaln(e,info.PrecodePowerInfo) && e.ContractVersion=="PDSCHPrecodePower/v2" && ...
    e.NormalizationConvention==convention && ~e.MatrixRescaled && ~e.WaveformPowerQualification);
assert(~isempty(tx.Waveform) && size(tx.Waveform,2)==size(W,1));
assert(max(abs(X-S*W.'),[],'all')<1e-12 && e.MappedSymbolMaxAbsError<1e-12 && ...
    e.TotalPowerRelativeError<1e-12 && abs(e.ExpectedMappedPortEnergy-sum(abs(S*W.').^2,'all'))<1e-9);
assert(e.MatrixSHA256PerPage(1)==sixgr.phy.mimo.MatrixContract.digest(W));
localRawEnergy(tx,e);
end

function localRawEnergy(tx,e)
Es=sum(abs(tx.PDSCHLayerSymbols(:)).^2); Ex=sum(abs(tx.PDSCHPortSymbols(:)).^2);
assert(isequaln(e.LayerTotalEnergy,double(Es)) && isequaln(e.PortTotalEnergy,double(Ex)) && ...
    isequaln(e.TotalEnergyDelta,double(Ex-Es)));
end

function [cfg,carrier,pdsch]=localCalibration(ports,layers,convention)
cfg=sixgr.config.defaultConfig();
cfg.run.shortRun=true; cfg.run.strictMode=true; cfg.run.useMex=false;
cfg.phy.pdsch.executionProfile='phy_calibration';
cfg.phy.pdsch.modulation='QPSK'; cfg.phy.pdsch.codeRate=0.30;
cfg.phy.pdsch.mcsTable='calibration_explicit'; cfg.phy.pdsch.mcsIndex=0;
cfg.phy.pdsch.mcsContext=struct('UECapability1024QAM',false, ...
    'RRCEnabled1024QAM',false,'DCIEnabled1024QAM',false, ...
    'DeploymentAllows1024QAM',false,'FrequencyRangeAllows1024QAM',false, ...
    'BandAllows1024QAM',false,'FrequencyRange','FR1','OperatingBand','n78', ...
    'DeploymentClass','controlled_test');
cfg.mimo.strict=true; cfg.phy.mimo.strict=true;
cfg.phy.nTxAnt=ports; cfg.channel.nTxAnt=ports;
cfg.scenario.bs.nTxAnt=ports; cfg.antenna.bs.numElements=ports;
cfg.phy.pdsch.numPorts=ports; cfg.phy.pdsch.nPorts=ports;
cfg.phy.pdsch.numLayers=layers; cfg.phy.pdsch.nLayers=layers;
cfg.phy.pdsch.normalizePrecodingMatrix=false;
cfg.phy.pdsch.precoding.normalizationConvention=char(convention);
cfg.phy.pdsch.precoderNormalizationConvention=char(convention);
cfg.phy.pdsch.precoding.matrix=[]; cfg.phy.pdsch.precodingMatrix=[]; cfg.phy.pdsch.W=[];
cfg.phy.pdsch.tpmi=[]; cfg.phy.pdsch.TPMI=[]; cfg.phy.pdsch.pmi=[]; cfg.phy.pdsch.PMI=[];
cfg.phy.csirs.enable=false; cfg.phy.pdsch.enablePTRS=false;
carrier=nrCarrierConfig; carrier.NSizeGrid=12; carrier.SubcarrierSpacing=30;
pdsch=nrPDSCHConfig; pdsch.NID=0; pdsch.RNTI=1;
pdsch.PRBSet=0:11; pdsch.SymbolAllocation=[2 12]; pdsch.MappingType='A';
pdsch.Modulation='QPSK'; pdsch.NumLayers=layers;
pdsch.DMRS.DMRSConfigurationType=1; pdsch.DMRS.DMRSTypeAPosition=2;
pdsch.DMRS.DMRSAdditionalPosition=1; pdsch.DMRS.DMRSLength=1;
pdsch.DMRS.DMRSPortSet=0:layers-1;
pdsch.DMRS.NumCDMGroupsWithoutData=1+(layers>2);
end

function localSymbolGroups()
W=complex(zeros(4,2,2,2));
W(:,:,1,1)=eye(4,2)/sqrt(2);
W(:,:,2,1)=[1 1;0 1;0 0;0 0]/sqrt(3);
W(:,:,1,2)=1i*[0 0;0 0;1 1;0 1]/sqrt(3);
W(:,:,2,2)=[0 0;0 0;1 0;0 1]/sqrt(2);
spec=struct('Mode',"prg_symbol_selective",'NPorts',4,'NLayers',2, ...
    'NPRG',2,'NSymbolGroups',2,'PRGSize',2,'PRBSet',0:3, ...
    'ScheduledSymbols',[2 3],'SymbolGroupMap',[0 1],'W',W, ...
    'MatrixSource',"declared_mapping_component",'CodebookIdentifier',"", ...
    'NormalizationConvention',"unit_frobenius");
bundle=sixgr.pdsch.PDSCHPrecoderBundle(spec);
prbs=repmat((0:3).',2,1); symbols=repelem([2;3],4);
S=complex(reshape(1:16,8,2),reshape(17:32,8,2))/11;
[ports,trace]=bundle.apply(S.',prbs,symbols,'Domain','data'); X=ports.';
prec=localPrec(W(:,:,1,1),"unit_frobenius"); prec.NumPRG=2;
prec.MatrixPortsPerPRG=reshape(W,4,2,4);
e=sixgr.phy.dl.measurePDSCHPrecodePower(S,X,prec,trace,bundle);
assert(all(e.MappedResourceCountPerPage==2) && e.TotalPowerRelativeError<1e-12 && ...
    e.MappedSymbolMaxAbsError<1e-12 && e.NormalizationTraceMaxError<1e-12 && ...
    isnan(e.OrthonormalColumnMaxError));
manual=0;
for row=1:size(S,1)
    [page,~,~]=bundle.slice(prbs(row),symbols(row));
    manual=manual+sum(abs(S(row,:)*page.').^2);
end
assert(abs(e.ExpectedMappedPortEnergy-manual)<1e-11);
bad=trace; bad.PRG(1)=1; reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,prec,bad,bundle));
bad=trace; bad.AppliedMatrixDigest(1)="different"; reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,prec,bad,bundle));
bad=trace; bad.ResourceIndex(1)=1; reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,prec,bad,bundle));
badPrec=prec; badPrec.NormalizationConvention="semi_unitary";
reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,badPrec,trace,bundle));
badPrec=prec; badPrec.MatrixPortsPerPRG(:,:,4)=2*badPrec.MatrixPortsPerPRG(:,:,4);
reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,badPrec,trace,bundle));
badPrec=prec; badPrec.MatrixPorts=2*prec.MatrixPorts;
reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,badPrec,trace,bundle));
badPrec=prec; badPrec.NumPRG=3;
reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,badPrec,trace,bundle));
end

function localSinglePage()
W=[1 1;0 1;0 0;0 0]/sqrt(3); prec=localPrec(W,"unit_frobenius");
S=single(complex(reshape(1:10,5,2),reshape(11:20,5,2)))/7;
X=S*single(W).';
e=sixgr.phy.dl.measurePDSCHPrecodePower(S,X,prec);
assert(e.LayerTotalEnergy==double(sum(abs(S(:)).^2)) && ...
    e.PortTotalEnergy==double(sum(abs(X(:)).^2)) && ...
    e.TotalEnergyDelta==double(sum(abs(X(:)).^2)-sum(abs(S(:)).^2)) && ...
    ~e.GramConstraintApplicable && e.MappedSymbolMaxAbsError<1e-6);
badX=X; badX(1,1)=badX(1,1)+10;
bad=sixgr.phy.dl.measurePDSCHPrecodePower(S,badX,prec);
assert(bad.MappedSymbolMaxAbsError>9 && bad.TotalPowerMaxAbsError>1);
prec.MatrixPortsPerPRG=2*W;
reject(@() sixgr.phy.dl.measurePDSCHPrecodePower(S,X,prec));
end

function prec=localPrec(W,convention)
prec=struct('MatrixPorts',W,'MatrixPortsPerPRG',W,'NormalizationConvention',convention, ...
    'NormalizeW',false,'NumLayers',size(W,2),'NumPorts',size(W,1),'NumPRG',1);
end

function reject(fn)
try
    fn();
catch failure
    assert(string(failure.identifier)=="sixgr:phy:dl:PDSCHPrecodePowerAuthority", ...
        'test:PDSCHPowerWrongRejection','Wrong guard: %s: %s',failure.identifier,failure.message);
    return;
end
error('test:PDSCHPowerMissingRejection','Contradictory mapping source was accepted.');
end
