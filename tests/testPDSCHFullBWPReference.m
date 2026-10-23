function [ok,evidence]=testPDSCHFullBWPReference(retainedDiagnostic)
%TESTPDSCHFULLBWPREFERENCE Actual bounded TX plus declared-reference checks.
% No RX, RF, received control, connected partial-BWP or hardware claim.
% Q=I defines an expected no-RS reference, not realized finite-data covariance.
% Optional v122 input is read-only original TX replay, never new PHY evidence.
setup6GRSimToolkit('Verbose',false);
oldRNG=rng; cleanup=onCleanup(@()rng(oldRNG)); %#ok<NASGU>
rows=repmat(struct('Case',"",'Passed',false,'FailureID',"",'Detail',""),0,1);
observations=cell(0,1);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_four_port_received_rank_transition_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
for r=[1 2 4]
    [candidates,~]=sixgr.phy.dl.pmiCodebookCandidates(cfg,r,4);
    selected=find([candidates.PMI]==0); assert(isscalar(selected));
    record("fresh_native_rank"+r,@()one(r,candidates(selected).W,"unit_frobenius",0:5));
end
record("fresh_explicit_rank2_full_sparse",@()pair(2,eye(4,2),"semi_unitary"));
record("fresh_explicit_rank4_full_sparse",@()pair(4,eye(4),"semi_unitary"));
record("fresh_unit_total_rank4_full_sparse",@()pair(4,eye(4)/2,"unit_frobenius"));
record("actual_64_output_columns_no_extra_port_multiplier", ...
    @()one(2,kron(eye(4),ones(16,1)/4)*eye(4,2)/sqrt(2),"unit_frobenius",0:1));
record("fresh_compatibility_facade_nonzero_carrier_CRB",@legacy);
record("partial_offset_BWP_component",@partial);
record("full_selective_and_incomplete_reference",@selective);
record("original_binding_and_malformed_negatives",@negative);
record("fixed_SNR_and_active_total_unchanged",@unchanged);
record("windowed_reference_unavailable_not_TX_rejection",@windowed);
record("common_signal_scope_unchanged",@common);
record("n40_config_native_OFDM_reference_domain",@n40);
if nargin>0
    record("original_v122_TX_value_replay",@()retained(retainedDiagnostic));
end
checks=struct2table(rows);
evidence=struct('Checks',checks,'Observations',{observations}, ...
    'Scope',"actual_small_PDSCH_TX_and_declared_simulation_power_reference", ...
    'ReceiverExecuted',false,'RFExecuted',false,'ConnectedPartialBWPQualified',false, ...
    'ReferenceIsMeasured',false,'NormativeEquation',false,'HardwareQualified',false);
for k=find(~checks.Passed).'
    fprintf(2,'PDSCH_FULL_BWP_REFERENCE %s FAIL %s\n',checks.Case(k),checks.Detail(k));
end
assert(all(checks.Passed),'test:PDSCHFullBWPReference:Failed', ...
    '%d/%d bounded reference cases failed.',nnz(~checks.Passed),height(checks));
fprintf('PDSCH_FULL_BWP_REFERENCE_PASS cases=%d receiver=0 reference_QI_is_model_not_measurement=1\n',height(checks));
ok=true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'FailureID',"",'Detail',"");
        try, fn(); row.Passed=true;
        catch cause
            row.FailureID=string(cause.identifier);
            row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
    function one(r,W,convention,prbs)
        [tx,info]=localTX(r,W,convention,prbs,0,6,false,0);
        observations{end+1,1}=localObserve(tx,info,6,W);
    end
    function legacy()
        W=eye(4,2);
        [tx,info]=localLegacyTX(W);
        o=localObserve(tx,info,6,W); observations{end+1,1}=o;
        assert(tx.PDSCHPowerReference.SourceBinding.CarrierStartCRB==5 && ...
            tx.PDSCHPowerReference.Receipt.BWPStartCarrierRelative==0 && ...
            tx.PDSCHPowerReference.Receipt.BWPAuthority=="original_native_nrPDSCHConfig_resolved_BWP");
    end
    function pair(r,W,convention)
        [full,fi]=localTX(r,W,convention,0:5,0,6,false,0);
        [sparse,si]=localTX(r,W,convention,0:1,0,6,false,0);
        a=localObserve(full,fi,6,W); b=localObserve(sparse,si,6,W);
        close(a.AmplitudeScale,b.AmplitudeScale);
        assert(isequaln(full.PrecoderBundle.W,W) || ...
            isequaln(full.PrecoderBundle.W,reshape(W,size(W,1),r,1,1)));
        observations{end+1,1}=a; observations{end+1,1}=b;
        % The model reference is identical across occupancy. Real pilot,
        % reserved-CDM and QAM energies determine the different numerator.
        close(a.ExpectedReferencePower,b.ExpectedReferencePower);
    end
    function partial()
        W=eye(4,2);
        [tx,info]=localTX(2,W,"semi_unitary",2:4,2,3,false,0);
        o=localObserve(tx,info,3,W); observations{end+1,1}=o;
        assert(tx.PDSCHPowerReference.Receipt.BWPStartCarrierRelative==2 && ...
            tx.PDSCHPowerReference.Receipt.BWPNumPRB==3 && size(tx.Grid,1)==72);
        reject(@()sixgr.phy.dl.PDSCHFullBWPReference.build(tx, ...
            struct('StartCarrierRelative',0,'NumPRB',3,'Authority',"declared_component_BWP")),"sixgr:rf:PDSCHPowerReferenceBWP");
        reject(@()sixgr.phy.dl.PDSCHFullBWPReference.build(tx, ...
            struct('StartCarrierRelative',2,'NumPRB',2,'Authority',"declared_component_BWP")),"sixgr:rf:PDSCHPowerReferenceBWP");
    end
    function selective()
        W=cat(3,eye(4,2),2*eye(4,2),3*eye(4,2));
        [tx,info]=localTX(2,W,"explicit_no_normalization",0:5,0,6,true,0);
        [~,ctx]=sixgr.rf.applyPowerContext(tx.Waveform,localPowerCfg(),'DL',info,'ApplyPA',false);
        expectedPerSymbol=12*2*(2+8+18); % Three original two-PRB pages.
        close(ctx.PowerReferenceContract.ExpectedGridEnergyPerSymbol, ...
            repmat(expectedPerSymbol,size(ctx.PowerReferenceContract.ReferenceActiveSymbolsZeroBased)));
        [partialTX,partialInfo]=localTX(2,W(:,:,1:2),"explicit_no_normalization",0:3,0,6,true,0);
        assert(~partialTX.PDSCHPowerReference.Receipt.Available);
        reject(@()sixgr.rf.applyPowerContext(partialTX.Waveform,localPowerCfg(),'DL',partialInfo,'ApplyPA',false), ...
            "sixgr:rf:PDSCHPowerReferenceUnsupported");
    end
    function negative()
        [tx,info]=localTX(2,eye(4,2),"semi_unitary",0:1,0,6,false,0);
        power=localPowerCfg();
        for name=["BWPNumPRB","ConfigurationEpoch","AssignmentId","GridSHA256"]
            bad=info;
            if isnumeric(bad.PDSCHPowerReferenceBinding.(name))
                bad.PDSCHPowerReferenceBinding.(name)=bad.PDSCHPowerReferenceBinding.(name)+1;
            else
                bad.PDSCHPowerReferenceBinding.(name)="forged";
            end
            reject(@()sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',bad,'ApplyPA',false), ...
                "sixgr:rf:PDSCHPowerReferenceAuthority");
        end
        bad=rmfield(info,'PDSCHPowerReference');
        reject(@()sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',bad,'ApplyPA',false),"sixgr:rf:PDSCHPowerReferenceAuthority");
        bad=info; bad.PDSCHPowerReference=tx.PDSCHPowerReference.Receipt;
        reject(@()sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',bad,'ApplyPA',false),"sixgr:rf:PDSCHPowerReferenceAuthority");
        bad=info; bad.OFDM.SampleRate=2*bad.OFDM.SampleRate;
        reject(@()sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',bad,'ApplyPA',false),"sixgr:rf:PDSCHPowerReferenceAuthority");
        bad=info; bad.PortGrid(1)=bad.PortGrid(1)+1;
        reject(@()sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',bad,'ApplyPA',false),"sixgr:rf:PDSCHPowerReferenceAuthority");
        x=tx.Waveform; x(1)=x(1)+1;
        reject(@()sixgr.rf.applyPowerContext(x,power,'DL',info,'ApplyPA',false),"sixgr:rf:PDSCHPowerReferenceAuthority");
        badTX=tx; badTX.DataPrecoderTrace.AppliedMatrixDigest(1)="forged";
        reject(@()sixgr.phy.dl.PDSCHFullBWPReference.build(badTX, ...
            struct('StartCarrierRelative',0,'NumPRB',6,'Authority',"declared_component_BWP")),"sixgr:rf:PDSCHPowerReferenceAuthority");
        % Scheduled grant target takes precedence; never reapply cell budget.
        power.lls6g.runtimeScheduledPowerContext.GrantTargetTxPower_dBm=20;
        [~,ctx]=sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',info,'ApplyPA',false);
        assert(ctx.TotalTxPower_mW==100 && ...
            string(ctx.TotalTxPowerSource)=="runtime_scheduled_power_context.grant_target_tx_power_dbm");
        close(ctx.AmplitudeScale^2,100/ctx.PowerReferenceContract.ExpectedUsefulSamplePower_native_squared);
    end
    function unchanged()
        [tx,info]=localTX(4,eye(4),"semi_unitary",0:1,0,6,false,0);
        power=localPowerCfg();
        power.integration=struct('run_mode','FIXED_SNR_SWEEP', ...
            'configured_snr_is_link_authority',true,'power_reference_mode','normalized_unit_es');
        prior=rng;
        [y,ctx]=sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',info,'ApplyPA',false);
        assert(isequaln(y,tx.Waveform) && isequaln(rng,prior) && ~ctx.ScaleApplied && ctx.AmplitudeScale==1);
        power=localPowerCfg(); power.powerAndRF.downlinkPowerNormalizationPolicy='active_ofdm_total_power';
        [y,ctx]=sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',info,'ApplyPA',false);
        [pin,~,~]=sixgr.rf.measureActiveOFDMTotalPower(tx.Waveform,info);
        assert(isequaln(y,tx.Waveform*sqrt(1000/pin)) && ~isfield(ctx,'PowerReferenceContract'));
    end
    function windowed()
        [tx,info]=localTX(1,eye(4,1),"semi_unitary",0:1,0,6,false,2);
        assert(~tx.PDSCHPowerReference.Receipt.Available && ...
            tx.PDSCHPowerReference.Receipt.Status=="unsupported_windowed_or_resampled_OFDM_reference");
        reject(@()sixgr.rf.applyPowerContext(tx.Waveform,localPowerCfg(),'DL',info,'ApplyPA',false), ...
            "sixgr:rf:PDSCHPowerReferenceUnsupported");
        power=localPowerCfg(); power.integration=struct('run_mode','FIXED_SNR_SWEEP', ...
            'configured_snr_is_link_authority',true,'power_reference_mode','normalized_unit_es');
        y=sixgr.rf.applyPowerContext(tx.Waveform,power,'DL',info,'ApplyPA',false);
        assert(isequaln(y,tx.Waveform));
    end
    function common()
        % Declared non-PDSCH OFDM component, not an SSB/CSI qualification.
        carrier=nrCarrierConfig; carrier.NSizeGrid=6; carrier.SubcarrierSpacing=30;
        grid=complex(zeros(72,14,1)); grid(1:24,3)=1;
        [x,o]=sixgr.phy.waveform.ofdmModulate(carrier,grid);
        info=struct('OFDM',o,'PortGrid',grid,'PowerNormalizationSignal',"declared_common_component");
        [y,ctx]=sixgr.rf.applyPowerContext(x,localPowerCfg(),'DL',info,'ApplyPA',false);
        close(ctx.FullBWPActivityFactor,24/72);
        assert(isequaln(y,x*ctx.AmplitudeScale) && ...
            ctx.PowerReferenceSource=="legacy_non_PDSCH_unit_total_carrier_RE_reference" && ...
            ~isfield(ctx,'PowerReferenceContract'));
    end
    function n40()
        sc=sixgr.lls6g.config.loadScenarioConfig( ...
            'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
        config=sixgr.lls6g.buildInternalConfig(sc,tempname);
        carrier=sixgr.phy.grid.makeCarrier(config);
        [window,~]=sixgr.phy.waveform.resolveOFDMWindowing(config,carrier);
        ofdm=nrOFDMInfo(carrier);
        assert(window==0 && ofdm.SampleRate==ofdm.Nfft*carrier.SubcarrierSpacing*1000);
    end
    function retained(path)
        before=string(sixgr.util.sha256File(path));
        original=load(path,'cases','checks');
        assert(numel(original.cases)==18 && all([original.checks.Passed]));
        for k=1:numel(original.cases)
            v=original.cases{k}; originalInfo=v.Original.ScalerTxInfo;
            % Reuse the original saved TX's immutable objects, matrices,
            % grid and OFDM. No decoding, modulation or reference grid runs.
            tx=struct('Assignment',originalInfo.CalibrationReceiverBundle.Assignment, ...
                'ResourcePlan',v.Original.ResourcePlan,'Carrier',v.Original.Carrier, ...
                'Grid',v.Original.Grid,'Waveform',v.Original.Waveform, ...
                'OFDMInfo',originalInfo.OFDM,'PrecoderBundle',v.Original.PrecoderBundle, ...
                'DataPrecoderTrace',v.Original.DataPrecoderTrace, ...
                'NumLayers',v.Original.PDSCH.NumLayers);
            if isempty(tx.PrecoderBundle), tx.PrecoderMode="explicit_identity_no_bundle";
            else, tx.PrecoderMode=tx.PrecoderBundle.Mode; end
            reference=sixgr.phy.dl.PDSCHFullBWPReference.build(tx, ...
                struct('StartCarrierRelative',0,'NumPRB',double(tx.Carrier.NSizeGrid), ...
                'Authority',"original_native_nrPDSCHConfig_resolved_BWP_retained_replay"));
            info=originalInfo; info.PowerNormalizationSignal="PDSCH";
            info.PDSCHPowerReference=reference; info.PDSCHPowerReferenceBinding=reference.SourceBinding;
            [y,ctx]=sixgr.rf.applyPowerContext(tx.Waveform,v.PowerConfig,'DL',info,'ApplyPA',false);
            close(ctx.AmplitudeScale,v.PowerContext.AmplitudeScale/sqrt(sum(abs(v.Request.Matrix).^2,'all')));
            assert(isequaln(y,tx.Waveform*ctx.AmplitudeScale));
            observations{end+1,1}=struct('Case',v.Case,'RetainedOriginalReplay',true, ...
                'OldOutputBudgetRatio',v.Measured.OutputToDeclaredBudgetRatio, ...
                'NewOutputBudgetRatio',ctx.OutputTotalPower_mW/ctx.TotalTxPower_mW, ...
                'ReferenceReceipt',reference.Receipt);
        end
        assert(before==string(sixgr.util.sha256File(path)));
    end
end

function [tx,info]=localTX(rankValue,W,convention,prbs,bwpStart,bwpCount,selective,window)
f=StrictPDSCHChainFixture.create(rankValue,'NPRB',6,'OFDMOptions',{'Windowing',window});
d=f.Assignment.toStruct(); d.PRBSetCarrierRelative=prbs; d.PRBSetBWPRelative=prbs-bwpStart;
d.AssignmentId=d.AssignmentId+"_reference_"+string(bwpStart)+"_"+string(bwpCount)+"_"+string(numel(prbs));
a=sixgr.pdsch.PDSCHSchedulingAssignment(d);
rd=f.ReferenceConfig.toStruct(); rd.NPhysicalTxAntennas=size(W,1);
ref=sixgr.pdsch.PDSCHReferenceSignalConfig(rd);
ri=sixgr.pdsch.PDSCHReferenceSignalGenerator.resolveIndices(a,f.Carrier,ref);
[k,l]=ndgrid(reshape(12*prbs+(0:11).',1,[]),0:13);
indices=sort(k(:)+72*l(:)).';
ownership=sixgr.pdsch.PDSCHResourceOwnershipMap(indices,struct());
context=struct('PRBSet',prbs,'SymbolAllocation',[0 14],'GridNumPRB',6,'GridSymbolsPerSlot',14, ...
    'BWPStartPRB',bwpStart,'AbsoluteSlot',0,'UnavailableIndices',zeros(1,0), ...
    'DMRSIndicesPerPort',{ri.DMRSIndicesPerPort},'PTRSIndicesPerPort',{ri.PTRSIndicesPerPort}, ...
    'DMRSLogicalPortSet',ri.DMRSLogicalPortSet,'PTRSLogicalPortSet',ri.PTRSLogicalPortSet, ...
    'LayerCountPerCodeword',rankValue,'QmPerCodeword',2,'CodeBlockCountPerCodeword',1, ...
    'ReferenceConfigurationDigest',ref.ConfigurationDigest);
p=sixgr.pdsch.PDSCHResourcePlan(ownership,context);
mode="wideband_fixed_matrix"; prgSize=0;
if selective, mode="prg_noncodebook"; prgSize=2; end
spec=struct('Mode',mode,'NPorts',size(W,1),'NLayers',rankValue, ...
    'NPRG',size(W,3),'NSymbolGroups',1,'PRGSize',prgSize,'PRBSet',prbs, ...
    'ScheduledSymbols',0:13,'SymbolGroupMap',zeros(1,14),'W',W, ...
    'MatrixSource',"declared_native_or_explicit_component_matrix", ...
    'CodebookIdentifier',"",'NormalizationConvention',convention);
b=sixgr.pdsch.PDSCHPrecoderBundle(spec);
integration=struct('ActiveBWPStartPRB',bwpStart,'ActiveBWPNumPRB',bwpCount);
cfg=struct('run',struct('pdschExecutionProfile','phy_calibration','strictMode',true));
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'Carrier',f.Carrier,'Assignment',a,'ResourcePlan',p, ...
    'ReferenceSignalConfig',ref,'PrecoderBundle',b,'IntegrationContext',integration, ...
    'TransportBlockBits',f.TransportBlocks,'ExecutionProfile','phy_calibration');
assert(isequaln(tx.PrecoderBundle,b) && isequaln(tx.Assignment,a));
end

function [tx,info]=localLegacyTX(W)
% Previously exercised explicit calibration facade, now with nonzero CRB
% origin but a carrier-sized BWP. This does not broaden connected BWP support.
cfg=sixgr.config.defaultConfig();
cfg.run.shortRun=true; cfg.run.strictMode=true; cfg.run.useMex=false;
cfg.run.pdschExecutionProfile='phy_calibration';
cfg.phy.pdsch.mcsTable='calibration_explicit'; cfg.phy.pdsch.mcsIndex=0;
cfg.phy.pdsch.mcsContext=struct('UECapability1024QAM',false, ...
    'RRCEnabled1024QAM',false,'DCIEnabled1024QAM',false, ...
    'DeploymentAllows1024QAM',false,'FrequencyRangeAllows1024QAM',false, ...
    'BandAllows1024QAM',false,'FrequencyRange','FR1','OperatingBand','n78', ...
    'DeploymentClass','controlled_test');
cfg.mimo.strict=true; cfg.phy.mimo.strict=true;
cfg.phy.nTxAnt=4; cfg.channel.nTxAnt=4; cfg.scenario.bs.nTxAnt=4; cfg.antenna.bs.numElements=4;
cfg.phy.pdsch.numPorts=4; cfg.phy.pdsch.nPorts=4;
cfg.phy.pdsch.numLayers=2; cfg.phy.pdsch.nLayers=2;
cfg.phy.pdsch.normalizePrecodingMatrix=false;
cfg.phy.pdsch.precoding.normalizationConvention='semi_unitary';
cfg.phy.pdsch.precoderNormalizationConvention='semi_unitary';
cfg.phy.pdsch.precoding.matrix=[]; cfg.phy.pdsch.precodingMatrix=[]; cfg.phy.pdsch.W=[];
cfg.phy.pdsch.tpmi=[]; cfg.phy.pdsch.TPMI=[]; cfg.phy.pdsch.pmi=[]; cfg.phy.pdsch.PMI=[];
cfg.phy.csirs.enable=false; cfg.phy.pdsch.enablePTRS=false;
cfg.phy.pdsch.selectedPrecoderSHA256=sixgr.phy.mimo.MatrixContract.digest(W);
carrier=nrCarrierConfig; carrier.NSizeGrid=6; carrier.NStartGrid=5; carrier.SubcarrierSpacing=30;
p=nrPDSCHConfig; p.NID=0; p.RNTI=1; p.NSizeBWP=6; p.NStartBWP=5;
p.PRBSet=0:1; p.SymbolAllocation=[2 12]; p.MappingType='A'; p.Modulation='QPSK'; p.NumLayers=2;
p.DMRS.DMRSConfigurationType=1; p.DMRS.DMRSTypeAPosition=2;
p.DMRS.DMRSAdditionalPosition=1; p.DMRS.DMRSLength=1;
p.DMRS.DMRSPortSet=0:1; p.DMRS.NumCDMGroupsWithoutData=1;
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'Carrier',carrier,'PDSCH',p, ...
    'PrecodingMatrix',W,'TargetCodeRate',0.30,'RV',0,'CompactOutput',false);
assert(isequaln(tx.PrecodeInfo.MatrixPorts,W));
end

function observation=localObserve(tx,info,bwpCount,W)
prior=rng; [y,ctx]=sixgr.rf.applyPowerContext(tx.Waveform,localPowerCfg(),'DL',info,'ApplyPA',false);
assert(isequaln(rng,prior) && isequaln(y,tx.Waveform*ctx.AmplitudeScale));
r=ctx.PowerReferenceContract;
assert(r.Available && ~r.MeasuredReference && ~r.NormativeEquation && ~r.RadiatedPowerClaim);
expected=12*bwpCount*sum(abs(W).^2,'all')/double(info.OFDM.Nfft)^2;
close(ctx.ReferenceInputPower_mW,expected);
close(ctx.AmplitudeScale^2,1000/expected);
% Independent native OFDM useful interval sum (not scaler alpha or context).
cp=double(info.OFDM.OFDMSamplingResolution.CyclicPrefixLengthsPerSlot);
N=double(info.OFDM.Nfft); offsets=[0 cumsum(N+cp(1:end-1))];
active=find(reshape(sum(abs(tx.Grid).^2,[1 3]),[],1)>0);
samples=zeros(N*numel(active),1);
for j=1:numel(active), s=active(j); samples((j-1)*N+(1:N))=offsets(s)+cp(s)+(1:N); end
actual=mean(sum(abs(double(y(samples,:))).^2,2));
E=sum(abs(double(tx.Grid(:,active,:))).^2,'all');
close(actual,1000*E/(numel(active)*12*bwpCount*sum(abs(W).^2,'all')));
close(ctx.OutputTotalPower_mW,actual);
observation=struct('Rank',tx.NumLayers,'BWPNumPRB',bwpCount, ...
    'PRBSet',tx.ResourcePlan.PRBSet,'AmplitudeScale',ctx.AmplitudeScale, ...
    'ExpectedReferencePower',expected,'ActualOutputBudgetRatio',actual/1000, ...
    'ActualCompositeGridEnergy',E,'ReferenceReceipt',r);
end

function cfg=localPowerCfg()
cfg=struct('run',struct('noiseOperatingMode','receiver_noise_figure_thermal_noise'), ...
    'powerAndRF',struct('bsTxPower_dBm',30,'bsRFChainCount',4, ...
    'downlinkPowerNormalizationPolicy','fixed_epre_over_configured_bwp'), ...
    'rf',struct('pa',struct('enable',false)));
end
function close(a,b)
assert(isequal(size(a),size(b)) && all(isfinite(a),'all') && all(isfinite(b),'all') && ...
    max(abs(double(a)-double(b)),[],'all')<=2e-10*max(realmin,max(abs(double(b)),[],'all')), ...
    'test:PDSCHFullBWPReference:Arithmetic','Independent arithmetic did not close.');
end
function reject(fn,id)
try, fn(); catch e
    assert(string(e.identifier)==id,'test:PDSCHFullBWPReference:WrongRejection', ...
        'Expected %s, got %s: %s',id,e.identifier,e.message); return;
end
error('test:PDSCHFullBWPReference:MissingRejection','Expected rejection %s.',id);
end
