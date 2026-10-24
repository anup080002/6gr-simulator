function ok=testLDPCWaveformPolicy()
% Actual small-grid TX/RX policy propagation, not BLER/RF qualification.
% Decoder algorithms are implementation choices, not NR-mandated policies.
% Reuse each encoded TB/waveform across policies; never supply expected bits
% to a receiver or substitute a synthetic decoder outcome.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
assert(exist('nrLDPCDecode','file')==2 && exist('nrPDSCHDecode','file')==2 && ...
    exist('nrPUSCHDecode','file')==2,'test:Missing5GToolbox', ...
    'This actual TX/RX regression requires 5G Toolbox; missing execution is not a pass.');
savedRNG=rng; cleanup=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
rng(20261024,'twister');
cfg=localConfig();
[dl,ul]=localTransmissions(cfg);
dlWaveform=dl.Waveform; ulWaveform=ul.Waveform;
dlTB=dl.TransportBlock; ulTB=ul.TransportBlock; ulCodeword=ul.Codeword;
algorithms=["Belief propagation","Layered belief propagation", ...
    "Normalized min-sum","Offset min-sum"];
terminations=["early","max"];
waveformCases=0; candidateCases=0; attemptedCandidates=0;
[report,context]=localCSIObligation();
assert(all(ismember(ulCodeword,[0 1]),'all') && ...
    any(ulTB==0) && any(ulTB==1), ...
    'The CSI candidate fixture must use actual nonconstant encoded TX data.');
% This second group is a codec boundary, not a second RF observation:
% ideal LLRs come from the actual PUSCH transmitter's unscripted coded TB.
% A nominal receiver CSI obligation must consider absent/present candidates.
llr=20*(1-2*double(ulCodeword(:)));
for algorithm=algorithms
    for termination=terminations
        cfg.phy.ldpc.algorithm=char(algorithm);
        cfg.phy.ldpc.termination=char(termination);
        policy=cfg.phy.ldpc;
        [rxDL,~]=sixgr.phy.dl.PDSCH_Rx(dlWaveform,cfg, ...
            'Carrier',dl.Carrier,'PDSCH',dl.PDSCH, ...
            'PDSCHIndices',dl.PDSCHIndices,'TransportBlockSize',dl.TransportBlockSize, ...
            'TargetCodeRate',dl.TargetCodeRate,'RV',dl.RV,'CodingPlan',dl.CodingPlans, ...
            'NoiseVar',1e-12,'NoiseVarDomain','time','CompactOutput',true, ...
            'FastAWGNPath',true,'SkipTimingEstimate',true);
        localAssertWaveform(dlTB,rxDL,policy,"DL");
        waveformCases=waveformCases+1;
        [rxUL,~]=sixgr.phy.ul.PUSCH_Rx(ulWaveform,cfg, ...
            'Carrier',ul.Carrier,'PUSCH',ul.PUSCH, ...
            'PUSCHIndices',ul.PUSCHIndices,'TransportBlockSize',ul.TransportBlockSize, ...
            'TargetCodeRate',ul.TargetCodeRate,'RV',ul.RV, ...
            'NoiseVar',1e-12,'NoiseVarDomain','time','CompactOutput',true, ...
            'FastAWGNPath',true,'SkipTimingEstimate',true);
        localAssertWaveform(ulTB,rxUL,policy,"UL");
        waveformCases=waveformCases+1;
        coding=struct('RV',ul.RV,'MaxIterations',policy.maxIterations, ...
            'Algorithm',policy.algorithm,'LDPCPolicy',policy,'Nref',{{[]}}, ...
            'PresenceDecisionAlgorithm',cfg.phy.pusch.csiPresenceDecisionAlgorithm);
        candidate=sixgr.phy.ul.pusch.receiveWithCSIPresence(ul.PUSCH, ...
            ul.TargetCodeRate,ul.TransportBlockSize,llr,context, ...
            cfg.phy.pusch.mcs,report,cfg.phy.pusch.shortUCIDecision,coding);
        evidence=candidate.CSIPresenceEvidence;
        assert(~evidence.TransmitterMetadataUsed && ~evidence.PriorHARQSoftBufferUsed);
        assert(evidence.CandidateTBDecodeAttempted(1,1) && ...
            evidence.CandidateTBCRCPass(1,1)==1, ...
            'The physically encoded CSI-absent interpretation must decode its original TB.');
        absent=evidence.CandidateDataEvidence{1};
        assert(isequal(int8(absent.TransportBlocks{1}(:)),int8(ulTB(:))));
        for k=1:2
            data=evidence.CandidateDataEvidence{k};
            if evidence.CandidateTBDecodeAttempted(k,1)
                localAssertReceipt(data.CodewordEvidence{1}.LDPCPolicyReceipt, ...
                    policy,k==1);
                attemptedCandidates=attemptedCandidates+1;
            else
                assert(~data.DecodeAttempted(1) && isnan(data.CRCPass(1)), ...
                    'An unresolved candidate cannot manufacture a decoder outcome.');
            end
        end
        candidateCases=candidateCases+1;
        fprintf('LDPC_WAVEFORM_POLICY_CASE_PASS algorithm="%s" termination=%s DL=1 UL=1 CSI_absent_encoded_TB=1\n', ...
            algorithm,termination);
    end
end
assert(isequaln(dl.Waveform,dlWaveform) && isequaln(ul.Waveform,ulWaveform) && ...
    isequal(dl.TransportBlock,dlTB) && isequal(ul.TransportBlock,ulTB) && ...
    isequal(ul.Codeword,ulCodeword),'TX input arrays must remain unchanged across policies.');
assert(waveformCases==16 && candidateCases==8 && attemptedCandidates>=8);
fprintf(['LDPC_WAVEFORM_POLICY_PASS actual_TX_waveforms=2 actual_RX_cases=%d ' ...
    'encoded_LLR_CSI_cases=%d actual_candidate_decodes=%d ' ...
    'scope=single_layer_small_grid_clean_aligned_AWGN_not_BLER_or_full_scenario\n'], ...
    waveformCases,candidateCases,attemptedCandidates);
ok=true;
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig();
cfg.run.strictMode=true; cfg.run.noProxyTruthContract=true;
cfg.channel.model="AWGN"; cfg.channel.awgnOnly=true; cfg.channel.snr_dB=45;
cfg.channel.nTxAnt=1; cfg.channel.nRxAnt=1;
cfg.phy.nTxAnt=1; cfg.phy.nRxAnt=1;
cfg.antenna.ue.numElements=1; cfg.antenna.bs.numElements=1;
cfg.scenario.bs.nTxAnt=1; cfg.scenario.bs.nRxAnt=1;
cfg.scenario.ue.nTxAnt=1; cfg.scenario.ue.nRxAnt=1;
cfg.phy.carrier.NSizeGrid=12; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.rx.useIdealTimingSync=true;
cfg.phy.channelEstimation.method="LS";
% Dedicated decoder fixture, not access/control scheduling: the 12-PRB
% carrier cannot contain a 20-PRB SS/PBCH block. Explicitly declare absent
% common signals instead of relying on an explicit allocation to bypass
% their production reservation guards. DM-RS remains transmitted/received.
cfg.phy.pdsch.executionProfile="phy_calibration";
cfg.run.pdschExecutionProfile="phy_calibration";
cfg.phy.ssb.enable=false; cfg.phy.pbch.enable=false;
cfg.phy.mib.enable=false; cfg.phy.sib1.enable=false;
cfg.phy.pdcch.enable=false; cfg.phy.prach.enable=false;
cfg.phy.csirs.enable=false; cfg.phy.csirs.nPorts=1;
cfg.phy.trs.enable=false; cfg.phy.srs.enable=false;
profile=sixgr.link.resolveMCSProfile("qam64_table1",1);
assert(profile.Valid && profile.Modulation=="QPSK" && profile.TargetCodeRate==157/1024);
for channel=["pdsch","pusch"]
    for field=["nLayers","numLayers","numPorts","nPorts"]
        cfg.phy.(channel).(field)=1;
    end
    cfg.phy.(channel).dmrs.nPorts=1;
    cfg.phy.(channel).dmrs.portSet=0;
    cfg.phy.(channel).modulation="QPSK";
    cfg.phy.(channel).mcs=1;
    cfg.phy.(channel).mcsIndex=1;
    cfg.phy.(channel).mcsTable="qam64_table1";
    cfg.phy.(channel).codeRate=profile.TargetCodeRate;
    cfg.phy.(channel).prbSet=0:5;
    cfg.phy.(channel).symbolAllocation=[0 10];
    cfg.phy.(channel).mappingType="A";
    cfg.phy.(channel).enablePTRS=false;
end
cfg.phy.pusch.transformPrecoding=false;
cfg.phy.ldpc.maxIterations=8;
cfg.phy.ldpc.scalingFactor=.61;
cfg.phy.ldpc.minSumOffset=.31;
cfg.phy.ldpc.useMexBatchDecode=false;
end

function [dl,ul]=localTransmissions(cfg)
carrier=sixgr.phy.grid.makeCarrier(cfg);
pdsch=nrPDSCHConfig; pusch=nrPUSCHConfig;
pdsch.PRBSet=0:5; pdsch.SymbolAllocation=[0 10]; pdsch.MappingType="A";
pdsch.Modulation="QPSK"; pdsch.NumLayers=1; pdsch.RNTI=1; pdsch.NID=1;
pdsch.DMRS.DMRSPortSet=0;
pusch.PRBSet=0:5; pusch.SymbolAllocation=[0 10]; pusch.MappingType="A";
pusch.Modulation="QPSK"; pusch.NumLayers=1; pusch.RNTI=1; pusch.NID=1;
pusch.NumAntennaPorts=1; pusch.DMRS.DMRSPortSet=0;
[dl,~]=sixgr.phy.dl.PDSCH_Tx(cfg,'Carrier',carrier,'PDSCH',pdsch, ...
    'NumTxAnt',1,'CompactOutput',true);
% Keep actual encoded bits for the separately labelled candidate-codec test.
[ul,~]=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',carrier,'PUSCH',pusch, ...
    'NumTxAnt',1,'CompactOutput',false);
end

function localAssertWaveform(tb,rx,policy,direction)
assert(rx.Ok && rx.CRCPass && ~rx.CRCError && ...
    rx.StrictReceiverEvidenceOk && rx.DecodeUsable, ...
    '%s actual receiver must retain successful measured TB evidence.',direction);
assert(isequal(int8(tb(:)),int8(rx.TransportBlock(:))), ...
    '%s decoded TB must equal the actual TX TB.',direction);
assert(iscell(rx.LDPCPolicyReceipts) && numel(rx.LDPCPolicyReceipts)==1, ...
    '%s single-codeword receiver must expose its actual decoder receipt.',direction);
localAssertReceipt(rx.LDPCPolicyReceipts{1},policy,true);
end

function localAssertReceipt(r,p,expectParityPass)
assert(r.ContractVersion=="sixgr.phy.LDPCExactPolicy/v1" && ...
    r.RequestedAlgorithm==string(p.algorithm) && r.AppliedAlgorithm==string(p.algorithm));
assert(r.RequestedTermination==string(p.termination) && ...
    r.AppliedTermination==string(p.termination) && r.MaximumIterations==p.maxIterations);
assert(r.ConfiguredScalingFactor==p.scalingFactor && r.ConfiguredOffset==p.minSumOffset);
if string(p.algorithm)=="Normalized min-sum"
    assert(r.AppliedScalingFactor==p.scalingFactor && r.ScalingFactorApplicable);
else
    assert(isnan(r.AppliedScalingFactor) && ~r.ScalingFactorApplicable);
end
if string(p.algorithm)=="Offset min-sum"
    assert(r.AppliedOffset==p.minSumOffset && r.OffsetApplicable);
else
    assert(isnan(r.AppliedOffset) && ~r.OffsetApplicable);
end
assert(r.DecoderEngine=="nrLDPCDecode" && ~r.MEXApplied && ...
    ~r.RetryApplied && ~r.AlgorithmSubstitutionApplied && ~r.TransportBlockAcceptanceDetermined);
assert(r.CodeBlockCount>=1 && numel(r.ActualIterationsPerCodeBlock)==r.CodeBlockCount && ...
    all(r.ActualIterationsPerCodeBlock>=1 & r.ActualIterationsPerCodeBlock<=p.maxIterations));
if string(p.termination)=="max"
    assert(all(r.ActualIterationsPerCodeBlock==p.maxIterations));
end
assert(r.FinalParityCheckShape(1)>1 && r.FinalParityCheckShape(2)==r.CodeBlockCount && ...
    r.FinalParityScope=="complete_native_final_parity_matrix_checks_by_codeblock" && ...
    numel(r.UnsatisfiedParityChecksPerCodeBlock)==r.CodeBlockCount);
if expectParityPass
    assert(all(r.UnsatisfiedParityChecksPerCodeBlock==0) && ...
        all(r.AllParityChecksSatisfiedPerCodeBlock));
end
end

function [report,context]=localCSIObligation()
% Installed nominal receive schema, deliberately independent of TX payload.
request=struct('ReportConfigID',"ldpc_policy_nominal_csi",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',1,'MaxRank',2, ...
    'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',1, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
report=sixgr.phy.mimo.CSIReportConfiguration(request,0);
context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
    'ObservationID',"actual_tx_codeword_codec_fixture",'ConfigurationEpoch',0, ...
    'AssignmentDigest',"declared_small_grid_assignment",'HARQMappingDigest',"", ...
    'HARQACKBitCount',0,'ConfiguredGrantUCIBitCount',0, ...
    'CSIReportConfigID',report.ReportConfigID,'CSIConfigurationEpoch',report.Epoch));
end
