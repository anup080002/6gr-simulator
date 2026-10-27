function ok=testPortableTypeICSIReportEngine(compareNative)
if nargin<1,compareNative=false;end
% Authored measured-operand policy regression; no waveform/BLER qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
request=cfg.phy.csi.reportConfiguration;
% Authored capability fixture explicitly admits rank3; selected n40 remains [1 2 4].
request.AllowedRanks=1:4;request.RankDomain=1:4;request.MaxRank=4;
cfg.phy.csi.reportConfiguration=request;cfg.phy.csi.rankDomain=1:4;
carrier=nrCarrierConfig; carrier.NSizeGrid=1; carrier.SubcarrierSpacing=30;
csirs=nrCSIRSConfig; csirs.RowNumber=4; csirs.NumRB=carrier.NSizeGrid;
model=struct('ModelID',"authored_threshold_fixture_not_calibrated", ...
    'Source',"authored_component_test_only",'ThresholdsDB',[-6.7 -4.7 -2.3 .2 2.4 4.3 5.9 8.1 10.3 11.7 14.1 16.3 18.7 21 22.7], ...
    'ComparisonToleranceDB',0,'CQITable',"table1");
runtime=struct('ReportConfiguration',request,'RankDomain',1:4,'Receiver',"MMSE", ...
    'Strict',true,'CurrentSlot',1,'CQITable',"table1",'PortableCQIModel',model);
cfg.runtime.currentSlot=runtime.CurrentSlot; % Original authored receiver/selection clock.
for rank=1:4
    runtime.RankDomain=rank;
    X=eye(4); H=repmat(reshape(X,[1 1 4 4]),12,14,1,1);
    % Exact opposite phases: full snapshots must not collapse by complex averaging.
    H(2:2:end,:,:,:)=-H(2:2:end,:,:,:);
    m=sixgr.phy.mimo.CSIMeasurementState('MeasurementID',"portable_fixture", ...
        'UEID',"1",'ResourceType',"CSI-RS",'ResourceID',"authored_resource_0", ...
        'ResourceOrdinal',0,'Slot',1,'MaxAgeSlots',5,'ChannelEstimate',X, ...
        'NoiseVariance',.01,'Provenance',"measured_authored_component_fixture");
    c=sixgr.phy.mimo.PortableTypeICSIReportEngine.run(carrier,csirs,nrPDSCHDMRSConfig,H,.01,runtime,m);
    packed=sixgr.phy.dl.packCSIFeedbackPayload(c,runtime);
    assert(isequal(packed.Part1Bits,c.CSIPart1Bits)&&isequal(packed.Part2Bits,c.CSIPart2Bits));
    assert(~isfield(c.RankSelectionEvidence.Candidates{1},'CandidateSINRPerRELayer'));
    assert(~isfield(c.RankSelectionEvidence.Candidates{1},'SelectedSINRPerRELayer'));
    if compareNative
        native=sixgr.phy.mimo.NRCSIReportEngine.run(carrier,csirs,nrPDSCHDMRSConfig,H,.01,runtime,m);
        nq=request;nq.Rank=native.RI;
        assert(isequal(native.Precoder_W,sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(nq,native.PMI)));
        np=sixgr.phy.dl.packCSIFeedbackPayload(native,runtime);
        assert(isequal(np.Part1Bits,native.CSIPart1Bits)&&isequal(np.Part2Bits,native.CSIPart2Bits));
        fprintf('Explicit policy comparison rank %g: portable PMI/CQI %g/%g, native %g/%g. No policy equality claimed.\n',rank,c.PMI,c.CQI,native.PMI,native.CQI);
    end
    assert(strlength(string(jsonencode(c.RankSelectionEvidence)))>0);
    assert(c.RankSelectionEvidence.AdditionalRankSearches==0);
    assert(c.RI==rank && c.RankSelectionEvidence.SelectedObjective>0 && ...
        c.SelectionInfo.SelectedMetric>0 && ~c.RankSelectionEvidence.DecodedBLERAvailable);
    assert(isequal(c.Precoder_W,sixgr.phy.mimo.TypeISinglePanelCodebook.matrix( ...
        setfield(request,'Rank',rank),c.PMI))); %#ok<SFLD>
    cfg.phy.csi.selectionBackend="portable_typeI_mmse";
    cfg.phy.csi.portableCQIModel=model; cfg.phy.csi.cqiTable="table1";
    cfg.phy.csi.rankDomain=rank; cfg.phy.rx.detector="MMSE";
    p=struct('ReceiverConfig',cfg,'Carrier',carrier);
    r=struct('CSIMeasurementState',m,'CSIRSChannelEstimate',H,'CSIRSNoiseVar',.01);
    sixgr.truth.validatePortableCSIRankSelectionEvidence(c.RankSelectionEvidence,p,r,c);
    % A legitimately delayed selection uses the original prepared clock;
    % measurement acquisition stays slot1 and remains within its age5 bound.
    delayed=runtime;delayed.CurrentSlot=2;
    delayedCfg=cfg;delayedCfg.runtime.currentSlot=2;
    delayedReport=sixgr.phy.mimo.PortableTypeICSIReportEngine.run( ...
        carrier,csirs,nrPDSCHDMRSConfig,H,.01,delayed,m);
    delayedPrepared=struct('ReceiverConfig',delayedCfg,'Carrier',carrier);
    sixgr.truth.validatePortableCSIRankSelectionEvidence( ...
        delayedReport.RankSelectionEvidence,delayedPrepared,r,delayedReport);
    assert(delayedReport.MeasurementSlot==1&&delayedReport.RankSelectionEvidence.Configuration.CurrentSlot==2);
    noClock=p;
    noClock.ReceiverConfig.runtime=rmfield(noClock.ReceiverConfig.runtime,'currentSlot');
    sixgr.truth.validatePortableCSIRankSelectionEvidence(c.RankSelectionEvidence,noClock,r,c);
    for alteredSlot=[0 2 99]
        badClock=c.RankSelectionEvidence;badClock.Configuration.CurrentSlot=alteredSlot;
        try
            sixgr.truth.validatePortableCSIRankSelectionEvidence(badClock,p,r,c);
            error('test:MissingClockRejection','Foreign selection clock accepted.');
        catch e
            assert(strcmp(e.identifier,'sixgr:truth:CSIRankSelectionEvidenceMismatch'),e.message);
        end
    end
    bad=c.RankSelectionEvidence; bad.RankDomain=mod(rank,4)+1;
    mustReject(@()sixgr.truth.validatePortableCSIRankSelectionEvidence(bad,p,r,c));
    bad=c.RankSelectionEvidence; bad.RankSearchCallCount=2;
    mustReject(@()sixgr.truth.validatePortableCSIRankSelectionEvidence(bad,p,r,c));
    bad=c.RankSelectionEvidence; bad.SelectedObjective=bad.SelectedObjective+1;
    mustReject(@()sixgr.truth.validatePortableCSIRankSelectionEvidence(bad,p,r,c));
    bad=c.RankSelectionEvidence;bad.Candidates{1}.CandidateSumLog2OnePlusSINR(1)=bad.Candidates{1}.CandidateSumLog2OnePlusSINR(1)+1;
    mustReject(@()sixgr.truth.validatePortableCSIRankSelectionEvidence(bad,p,r,c));
    badc=c;badc.CSIPart1Bits(1)=1-badc.CSIPart1Bits(1);
    mustReject(@()sixgr.truth.validatePortableCSIRankSelectionEvidence(c.RankSelectionEvidence,p,r,badc));
    badr=r;badr.CSIRSNoiseVar=.02;
    mustReject(@()sixgr.truth.validatePortableCSIRankSelectionEvidence(c.RankSelectionEvidence,p,badr,c));
    r.CSIRSChannelEstimate=H.*2;
    mustReject(@()sixgr.truth.validatePortableCSIRankSelectionEvidence(c.RankSelectionEvidence,p,r,c));
end
mustReject(@()sixgr.phy.mimo.CodebookEngine.select(eye(4),eye(4),'Objective','native_MaxSE'));
late=runtime;late.CurrentSlot=7;
mustReject(@()sixgr.phy.mimo.PortableTypeICSIReportEngine.run(carrier,csirs,nrPDSCHDMRSConfig,H,.01,late,m));
wrong=runtime;wrong.ReportConfiguration.CodebookType="typeII";
mustReject(@()sixgr.phy.mimo.PortableTypeICSIReportEngine.run(carrier,csirs,nrPDSCHDMRSConfig,H,.01,wrong,m));
% Search the entire admitted rank domain, not only forced single-rank cases.
runtime.RankDomain=1:4; cfg.phy.csi.rankDomain=1:4;
one=request;one.Rank=1;pack=sixgr.phy.mimo.CodebookEngine.enumerate(one);
beam=pack.Matrices(:,:,1); low=[1;0;0;0]*beam';
[lowReport,~,~]=localCase(low,[],1:4,runtime,cfg,carrier,csirs);
[fullReport,~,~]=localCase(eye(4),[],1:4,runtime,cfg,carrier,csirs);
assert(lowReport.RI==1 && fullReport.RI==4, ...
    'Measured rank-one/full-rank operators must drive actual all-rank selection.');
[restricted,~,~]=localCase(eye(4),[],[1 2],runtime,cfg,carrier,csirs);
assert(restricted.RI==2 && isequal(restricted.RankSelectionEvidence.RankDomain,[1 2]));
v=[1;1i;.5;-.25i];correlated=.1*(v*v');
[interfered,~,~]=localCase(eye(4),correlated,1:4,runtime,cfg,carrier,csirs);
assert(interfered.InterferenceCovarianceUsed && ...
    any(abs(interfered.RankCandidateObjective-fullReport.RankCandidateObjective)>1e-6));
assert(isequal(interfered.DisturbanceCovarianceUsed,correlated+.01*eye(4)));
runtime.ConfiguredSNRdB=-40;
[a,~,~]=localCase(eye(4),correlated,1:4,runtime,cfg,carrier,csirs);
runtime.ConfiguredSNRdB=80;
[b,~,~]=localCase(eye(4),correlated,1:4,runtime,cfg,carrier,csirs);
assert(isequal(a.RankCandidateObjective,b.RankCandidateObjective)&& ...
    a.RI==b.RI&&a.PMI==b.PMI&&a.CQI==b.CQI,'Configured SNR cannot replace measured disturbance.');
[outage,m0,H0]=localCase(zeros(4),[],1:4,runtime,cfg,carrier,csirs);
assert(outage.CQI==0&&outage.RI==1&&isinf(outage.WidebandSINR_dB)&& ...
    outage.WidebandSINR_dB<0&&all(outage.RankCandidateObjective==0));
% Exercise the real strict facade's outage contract and original typed pack.
cfg.phy.csi.rankDomain=1:4;
cfg.runtime.currentSlot=runtime.CurrentSlot;
assert(runtime.CurrentSlot==m0.Slot);
[wire,~]=sixgr.phy.dl.CSI_Feedback(m0.ChannelEstimate,.01,cfg, ...
    'MeasurementState',m0,'ReportConfiguration',request,'Carrier',carrier, ...
    'CSIRSConfig',csirs,'PDSCHDMRSConfig',nrPDSCHDMRSConfig,'FullChannelEstimate',H0);
assert(wire.CQI==0&&isinf(wire.SINR_dB)&&wire.SINR_dB<0&& ...
    isequal(wire.CSIPart1Bits,outage.CSIPart1Bits)&&isequal(wire.CSIPart2Bits,outage.CSIPart2Bits));
invalid=eye(4);invalid(1,2)=.2;
mustReject(@()localCase(eye(4),invalid,1:4,runtime,cfg,carrier,csirs));
ok=true;
end
function [c,m,H]=localCase(X,R,ranks,runtime,cfg,carrier,csirs)
runtime.RankDomain=ranks;cfg.phy.csi.rankDomain=ranks;
H=repmat(reshape(X,[1 1 4 4]),12,14,1,1);
m=sixgr.phy.mimo.CSIMeasurementState('MeasurementID',"portable_full_domain", ...
    'UEID',"1",'ResourceType',"CSI-RS",'ResourceID',"authored_resource_0", ...
    'ResourceOrdinal',0,'Slot',1,'MaxAgeSlots',5,'ChannelEstimate',X, ...
    'NoiseVariance',.01,'InterferenceCovariance',R,'InterferenceCovarianceIncludesNoise',false, ...
    'Provenance',"measured_authored_component_fixture");
c=sixgr.phy.mimo.PortableTypeICSIReportEngine.run(carrier,csirs,nrPDSCHDMRSConfig,H,.01,runtime,m);
p=struct('ReceiverConfig',cfg,'Carrier',carrier);
r=struct('CSIMeasurementState',m,'CSIRSChannelEstimate',H,'CSIRSNoiseVar',.01);
sixgr.truth.validatePortableCSIRankSelectionEvidence(c.RankSelectionEvidence,p,r,c);
wire=sixgr.phy.dl.packCSIFeedbackPayload(c,runtime);
assert(isequal(wire.Part1Bits,c.CSIPart1Bits)&&isequal(wire.Part2Bits,c.CSIPart2Bits));
end
function mustReject(f)
failed=false;try,f();catch,failed=true;end
assert(failed,'Expected a strict unsupported/identity rejection.');
end
