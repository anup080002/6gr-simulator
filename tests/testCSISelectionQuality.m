function [ok,archiveFixture]=testCSISelectionQuality()
% Component arithmetic/provenance tests, not a waveform/conformance campaign.
setup6GRSimToolkit('Verbose',false);
[ref,selected,request,noise,policy]=fixture();
archiveFixture=struct('Reference',ref,'Selection',selected,'Request',request,'Disturbance',noise,'Policy',policy);
before=selected;
[s,T]=sixgr.truth.scoreCSISelectionQuality(ref,selected,request,noise,policy);
assert(isequaln(before,selected) && s.ScoringAvailable && height(T)==6 && ...
    ~s.ReferenceUsedByReceiver && ~s.ActualPDSCHPerformanceQualified && ...
    ~s.CQIBLERQualified && ~s.CRISelectionQualified && s.NoiseIndependentFromReceiverEstimate);
assert(abs(s.SelectedObjective_bpsHz-log2(11))<1e-12 && ...
    abs(s.BestJointObjective_bpsHz-2*log2(6))<1e-12 && ...
    s.ConditionalPMIRegret_bpsHz<1e-12 && s.RankRegret_bpsHz>0 && ...
    abs(s.JointRegret_bpsHz-s.ConditionalPMIRegret_bpsHz-s.RankRegret_bpsHz)<1e-12 && ...
    s.JointTieCount==2 && s.ReportedRankTieCount==4 && ~s.SelectedWithinJointTie);
assert(all(abs(T.LogicalFrobeniusPower-1)<1e-12) && ...
    all(abs(T.ScoredPhysicalFrobeniusPower-1)<1e-12));
% Independent error-covariance expression verifies the direct-filter scorer.
for k=1:height(T)
    W=sixgr.phy.mimo.TypeI2PortCodebook.matrix(T.Rank(k),T.PMI(k));
    A=ref.H*W*T.AppliedAmplitudeFactor(k);
    E=(eye(T.Rank(k))+A'*(noise.Covariance\A))\eye(T.Rank(k));
    expected=(1./real(diag(E))-1).';
    assert(max(abs(T.LayerSINR{k}-expected),[],'all')<1e-11);
end
% Rank-2 actual selection is legal and tied-best; no matrix-rank heuristic.
rank2=withSelection(selected,request,2,0);
[best,~]=sixgr.truth.scoreCSISelectionQuality(ref,rank2,request,noise,policy);
assert(best.SelectedWithinJointTie && best.JointRegret_bpsHz==0);
% Common channel/noise amplitude scaling must not change the objective.
scaled=ref; scaled.H=3i*ref.H;
scaledNoise=noise; scaledNoise.SampleNoiseVariance=9*noise.SampleNoiseVariance;
scaledNoise.Covariance=9*noise.Covariance;
[scaledSummary,scaledTable]=sixgr.truth.scoreCSISelectionQuality(scaled,selected,request,scaledNoise,policy);
assert(max(abs(scaledTable.Objective_bpsHz-T.Objective_bpsHz))<1e-11 && ...
    abs(scaledSummary.JointRegret_bpsHz-s.JointRegret_bpsHz)<1e-11);
% Equal column norms are insufficient: correlated physical beams have
% different candidate physical-chain excitation powers. Retain each one.
nonorthogonal=ref; nonorthogonal.PortToPhysicalMatrix=[1 .6;0 .8];
nonorthogonal.PortToPhysicalMatrixSHA256= ...
    sixgr.phy.mimo.MatrixContract.digest(nonorthogonal.PortToPhysicalMatrix);
nonorthogonal.H=ref.H*nonorthogonal.PortToPhysicalMatrix;
[p,P]=sixgr.truth.scoreCSISelectionQuality(nonorthogonal,selected,request,noise,policy);
assert(~p.UnscaledPhysicalCandidatePowerEqual && ...
    max(P.UnscaledPhysicalFrobeniusPower)-min(P.UnscaledPhysicalFrobeniusPower)>1 && ...
    all(abs(P.ScoredPhysicalFrobeniusPower-1)<1e-12));
% A retained transmit amplitude belongs in BOTH H and the actual port basis.
% At fixed physical-chain power and fixed noise, the per-candidate factor
% cancels its magnitude; a common complex phase cannot change the objective.
txAmplitude=3+4i;
amplitude=nonorthogonal;
amplitude.H=txAmplitude*nonorthogonal.H;
amplitude.PortToPhysicalMatrix=txAmplitude*nonorthogonal.PortToPhysicalMatrix;
amplitude.PortToPhysicalMatrixSHA256= ...
    sixgr.phy.mimo.MatrixContract.digest(amplitude.PortToPhysicalMatrix);
[a,A]=sixgr.truth.scoreCSISelectionQuality(amplitude,selected,request,noise,policy);
assert(max(abs(A.Objective_bpsHz-P.Objective_bpsHz))<1e-11 && ...
    abs(a.SelectedObjective_bpsHz-p.SelectedObjective_bpsHz)<1e-11 && ...
    abs(a.JointRegret_bpsHz-p.JointRegret_bpsHz)<1e-11 && ...
    max(abs(A.UnscaledPhysicalFrobeniusPower-abs(txAmplitude)^2* ...
        P.UnscaledPhysicalFrobeniusPower))<1e-11 && ...
    max(abs(A.AppliedAmplitudeFactor-P.AppliedAmplitudeFactor/abs(txAmplitude)))<1e-12 && ...
    all(abs(A.ScoredPhysicalFrobeniusPower-policy.PowerFactor)<1e-12));
% Frequency/time samples are scored separately; complex averaging would
% cancel these channels and manufacture a zero objective.
frequency=ref; frequency.H=cat(3,ref.H,-ref.H); frequency.Support=[0 3;1 3];
[f,~]=sixgr.truth.scoreCSISelectionQuality(frequency,selected,request,noise,policy);
assert(f.SupportCount==2 && abs(f.SelectedObjective_bpsHz-s.SelectedObjective_bpsHz)<1e-12);
zero=ref; zero.H=zeros(size(ref.H));
[z,Z]=sixgr.truth.scoreCSISelectionQuality(zero,selected,request,noise,policy);
assert(z.JointTieCount==6 && z.JointRegret_bpsHz==0 && all(Z.Objective_bpsHz==0));
% A changed actual selection is scored, never overwritten by the reference.
directional=ref; directional.H=[1 1;0 0];
wrong=withSelection(selected,request,1,2);
[w,~]=sixgr.truth.scoreCSISelectionQuality(directional,wrong,request,noise,policy);
assert(w.SelectedObjective_bpsHz==0 && w.ConditionalPMIRegret_bpsHz>1 && w.SelectedPMI==2);
% Poison unrelated numerical-rank/beam proxies: they have no authority.
poison=selected; poison.NumericalRank=99; poison.BestBeamIndex=99;
[same,~]=sixgr.truth.scoreCSISelectionQuality(ref,poison,request,noise,policy);
assert(isequaln(s,same));
bad=selected; bad.Identity.MeasurementID="another-measurement";
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,bad,request,noise,policy), ...
    'sixgr:truth:CSISelectionIdentity');
badNoise=noise; badNoise.Identity.RandomSeed=2;
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,selected,request,badNoise,policy), ...
    'sixgr:truth:CSISelectionIdentity');
badNoise=noise; badNoise.ReferencePlane="post_AGC_receiver_grid";
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,selected,request,badNoise,policy), ...
    'sixgr:truth:CSISelectionPlane');
badNoise=noise; badNoise.Source="receiver_estimated_covariance";
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,selected,request,badNoise,policy), ...
    'sixgr:truth:CSISelectionNoise');
badNoise=noise; badNoise.Covariance=2*noise.Covariance;
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,selected,request,badNoise,policy), ...
    'sixgr:truth:CSISelectionNoise');
badPolicy=policy; badPolicy.PowerFactor=2;
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,selected,request,noise,badPolicy), ...
    'sixgr:truth:CSISelectionPolicy');
bad=ref; bad.Support=[0 3;0 3]; bad.H=cat(3,ref.H,ref.H);
mustFail(@()sixgr.truth.scoreCSISelectionQuality(bad,selected,request,noise,policy), ...
    'sixgr:truth:CSISelectionSupport');
bad=ref; bad.PortToPhysicalMatrix=2*ref.PortToPhysicalMatrix;
mustFail(@()sixgr.truth.scoreCSISelectionQuality(bad,selected,request,noise,policy), ...
    'sixgr:truth:CSISelectionSpatialBasis');
bad=selected; bad.PMI=1; % changed scalar alone is not changed actual W
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,bad,request,noise,policy), ...
    'sixgr:truth:CSISelectionMatrix');
restricted=request; restricted.CodebookSubsetRestriction=ones(1,6);
[r2,s2,n2]=rebind(ref,selected,noise,restricted);
mustFail(@()sixgr.truth.scoreCSISelectionQuality(r2,s2,restricted,n2,policy), ...
    'sixgr:truth:CSISelectionUnsupportedRestriction');
unbound=request; unbound.Epoch=4;
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,selected,unbound,noise,policy), ...
    'sixgr:truth:CSISelectionConfiguration');
testFourPortRestrictions(policy);
% Provenance correction must not suggest a TS-mandated optimization rule.
engine=fileread(which('sixgr.phy.mimo.NRCSIReportEngine'));
assert(~contains(engine,'"RankDecisionReason","ts38214_maximum_spectral_efficiency"') && ...
    contains(engine,'matlab_r2026a_measured_channel_MaxSE_policy'));
ok=true;
fprintf('testCSISelectionQuality: PASS (component-only independent scoring)\n');
end

function testFourPortRestrictions(policy)
[ref,selected,request,noise]=fixture();
request.Ports=4; request.N1=2; request.O1=4; request.CodebookMode=1;
request.CodebookSubsetRestriction=[1 zeros(1,7)];
request.I2Restriction=[1 zeros(1,15)];
ref.H=eye(4); ref.PortToPhysicalMatrix=eye(4);
ref.PortToPhysicalMatrixSHA256=sixgr.phy.mimo.MatrixContract.digest(eye(4));
noise.Covariance=eye(4); [ref,selected,noise]=rebind(ref,selected,noise,request);
selected=withSelection(selected,request,1,0);
[s,T]=sixgr.truth.scoreCSISelectionQuality(ref,selected,request,noise,policy);
assert(s.CandidateCount==3 && all(contains(T.PMIComponentsJSON,'PMI_I11')) && ...
    all(contains(T.CodebookSpecification,'V18.9.0')));
bad=selected; bad.PMI_I11=1;
mustFail(@()sixgr.truth.scoreCSISelectionQuality(ref,bad,request,noise,policy), ...
    'sixgr:truth:CSISelectionPMITuple');
request.CodebookSubsetRestriction=[]; request.I2Restriction=[];
request.RankDomain=1:4; request.AllowedRanks=1:4;
[ref,selected,noise]=rebind(ref,selected,noise,request);
selected.RankDomain=1:4;
[s,T]=sixgr.truth.scoreCSISelectionQuality(ref,selected,request,noise,policy);
assert(isequal(unique(T.Rank).',1:4) && all(abs(T.ScoredPhysicalFrobeniusPower-1)<1e-12));
assert(s.CandidateCount>3);
end

function [ref,selected,request,noise,policy]=fixture()
request=struct('ProfileID',"fr1_typeI_single_panel_strict",'Direction',"DL", ...
    'CodebookType',"typei-singlepanel",'Ports',2,'Panels',1,'Rank',1, ...
    'N1',1,'N2',1,'O1',1,'O2',1,'RankDomain',[1 2],'AllowedRanks',[1 2], ...
    'Epoch',0,'ReportConfigID',"declared_component_report",'FrequencyGranularity',"wideband");
id=struct('ObservationID',"declared_component_observation",'ReceiverID',"UE1", ...
    'MeasurementID',"declared_component_measurement",'MeasurementDigest',repmat("a",1,64), ...
    'ResourceID',"11",'ReceiverClockDomain',"declared_component_sample_clock", ...
    'ReportConfigID',request.ReportConfigID,'RequestSHA256',"pending", ...
    'ConfigurationEpoch',0,'ReceiverClockEpoch',0,'ResourceOrdinal0',0, ...
    'MeasurementSlot',2,'ObservationStartSample',0,'ObservationEndSampleExclusive',100, ...
    'SampleRateHz',1000,'RunFolder',"declared_component_fixture_not_runtime",'RandomSeed',1);
id.MeasurementDigest=strjoin(id.MeasurementDigest,"");
ref=struct('Identity',id,'H',sqrt(10)*eye(2),'Support',[0 3], ...
    'PortToPhysicalMatrix',eye(2), ...
    'PortToPhysicalMatrixSHA256',sixgr.phy.mimo.MatrixContract.digest(eye(2)), ...
    'Source',"same_execution_nominal_linear_CSI_RS_reference", ...
    'ReferencePlane',"nominal_linear_CSI_RS_port_channel_on_actual_RX_FFT_clock", ...
    'ReceiverEstimatorInput',false,'RFImpairmentsIncluded',false, ...
    'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0);
selected=struct('Identity',id,'RankDomain',request.RankDomain,'CRI',0, ...
    'MeasurementID',id.MeasurementID,'MeasurementResourceID',id.ResourceID,'MeasurementSlot',2);
selected=withSelection(selected,request,1,0);
noise=struct('Identity',id,'ReferencePlane',ref.ReferencePlane, ...
    'Source',"executed_pre_rx_rf_noise_with_recorded_ofdm_gain", ...
    'SampleNoiseVariance',.5,'SampleToGridNoiseVarianceGain',2,'NoiseStreamSeed',1,'Covariance',eye(2));
[ref,selected,noise]=rebind(ref,selected,noise,request);
policy=struct('Objective',"mean_support_sum_log2_one_plus_linear_mmse_sinr", ...
    'Receiver',"linear_mmse",'PowerNormalization',"unit_physical_chain_grid_coefficient_power", ...
    'PowerFactor',1,'TieAbsoluteTolerance',1e-10,'PhysicalPowerTolerance',1e-10);
end

function selected=withSelection(selected,request,rankValue,pmi)
request.Rank=rankValue; selected.RI=rankValue; selected.PMI=pmi;
if request.Ports==2
    W=sixgr.phy.mimo.TypeI2PortCodebook.matrix(rankValue,pmi);
else
    [W,c]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,pmi);
    for field=string(fieldnames(c)).', selected.(field)=c.(field); end
end
selected.Precoder_W=W; selected.PrecoderMatrixSHA256=sixgr.phy.mimo.MatrixContract.digest(W);
end

function [ref,selected,noise]=rebind(ref,selected,noise,request)
id=ref.Identity; id.RequestSHA256=sixgr.util.sha256Hex(jsonencode(orderfields(request)));
id.ConfigurationEpoch=request.Epoch; id.ReportConfigID=request.ReportConfigID;
ref.Identity=id; selected.Identity=id; noise.Identity=id;
end

function mustFail(f,expected)
try
    f();
catch e
    assert(strcmp(e.identifier,expected),'Unexpected failure %s: %s',e.identifier,e.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',expected);
end
