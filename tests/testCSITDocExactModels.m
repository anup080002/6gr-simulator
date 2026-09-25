function testCSITDocExactModels()
%TESTCSITDOCEXACTMODELS Exact 10.5.3.1 analytical and strict-state gates.
repo=string(fileparts(fileparts(mfilename("fullpath"))));
flow=sixgr.csi.buildTDocStudyExecutionFlowContract(repo);
assert(all(flow.Exists & flow.CanonicalPathSelected));
assert(nnz(flow.Role=="suite_orchestration")==1);
lengths=[8 16 32 64]; phases=[5 15];
for L=lengths
    W=sixgr.phy.refsig.OCCFactory.matrix("walsh",L);
    D=sixgr.phy.refsig.OCCFactory.matrix("dft",L);
    assert(norm(W'*W-eye(L),"fro")<1e-11);
    assert(norm(D'*D-eye(L),"fro")<1e-11);
    for phase=phases
        w=sixgr.phy.refsig.OCCFactory.coupling("walsh",L,phase);
        d=sixgr.phy.refsig.OCCFactory.coupling("dft",L,phase);
        assert(abs(w.TotalOffDiagonalEnergy-d.TotalOffDiagonalEnergy)<1e-10);
    end
end

for M=[2 4 8]
    for phase=[-30 0 15 45]
        direct=abs(mean(exp(1j*deg2rad(phase)*(0:M-1))))^2;
        x=deg2rad(phase)/2;
        if abs(sin(x))<eps, closed=1; else, closed=(sin(M*x)/(M*sin(x)))^2; end
        assert(abs(direct-closed)<1e-12);
    end
end

for M=[2 4 8]
    sigma=deg2rad(15); expected=1/M+(1-1/M)*exp(-sigma^2);
    rng(10531+M,"twister"); phi=sigma*randn(30000,M);
    measured=mean(abs(mean(exp(1j*phi),2)).^2);
    assert(abs(measured-expected)<0.01);
end

idx=(0:7).'; R=besselj(0,2*pi*140*abs(idx-idx.')*.0005);
assert(norm(R-R',"fro")<1e-12);
assert(min(real(eig((R+R')/2)))>-1e-10);

assert(abs(10*log10((1/256)/(1/128))+3.01029995664)<1e-10);
assert(abs(10*log10((1/512)/(1/128))+6.02059991328)<1e-10);

state=sixgr.phy.mimo.CSIMeasurementState(MeasurementID="M1",UEID="1", ...
    ResourceType="CSI-RS",ResourceID="R1",ResourceOrdinal=0,Slot=2, ...
    MaxAgeSlots=4,ChannelEstimate=eye(2),NoiseVariance=.1);
state.validateAt(6);
assertThrows(@()state.validateAt(7),"sixgr:mimo:StaleMeasurementState");
assertThrows(@()state.validateAt(1),"sixgr:mimo:StaleMeasurementState");
for invalidSlot=[NaN Inf -1 .5]
    assertThrows(@()state.validateAt(invalidSlot),"sixgr:mimo:InvalidMeasurementTime");
end

store=sixgr.phy.rsla.MeasurementStateStore();
measurement=struct("Valid",true,"MeasurementID","M1","UEID",1, ...
    "CellID",0,"BWPID",0,"ResourceID","R1","BeamID","B1", ...
    "ConfigurationEpoch",1,"ProducerSlot",2,"AvailableSlot",3);
consumer=struct("UEID",1,"CellID",0,"BWPID",0,"ResourceID","R1", ...
    "BeamID","B1","ConfigurationEpoch",1,"ConsumerSlot",3, ...
    "MaxAgeSlots",4);
store.put(measurement); [stored,validity]=store.newest(consumer);
assert(string(stored.MeasurementID)=="M1" && validity.Valid);
bad=measurement; bad.UnexpectedField=1;
assertThrows(@()store.put(bad),"RSLA:MeasurementSchemaMismatch");

key=struct("UEID",1,"Direction","DL","ServingCellID",1, ...
    "ScheduledCellID",1,"BWPID",0,"MCSTable","qam64_table1", ...
    "ConfigurationEpoch",1);
olla=sixgr.phy.rsla.OLLAState(key,.1,.1,-6,6,"NACK");
assert(abs(olla.MuNackDb/olla.MuAckDb-9)<1e-12);

cfg=struct("n_rb",52); plan=sixgr.phy.refsig.HighPortCSIRSMapper.plan(cfg,512,64,"dft",1);
assert(plan.PortCount==512 && height(plan.Map)==512*64);
shared=plan.Map(plan.Map.LogicalPort==0,:).LinearREZeroBased;
assert(numel(shared)==64 && numel(unique(shared))==64);

[resolved,~]=sixgr.csi.loadTDocStudyConfig( ...
    "simulator/configs/csi_tdoc/bounded_qualification.yaml");
assert(numel(resolved.csi.bounded_flow.cqi_thresholds_db)==16);
procedure=sixgr.csi.CSITDocStudyStateTimelineEngine.run(resolved);
assert(ismember("SelectionRejected",string(procedure.Summary.Properties.VariableNames)));
assert(~ismember("FallbackUsed",string(procedure.Summary.Properties.VariableNames)), ...
    "Fail-closed state rejection must not be mislabeled as fallback use.");
badThresholds=resolved;
badThresholds.csi.bounded_flow.cqi_thresholds_db=[-100 -6 -7 zeros(1,13)];
assertThrows(@()sixgr.csi.validateTDocStudyConfig(badThresholds), ...
    "sixgr:csi:InvalidBoundedCQIThresholds");
wave=sixgr.phy.refsig.HighPortCSIRSMapper.runWaveformPoint(resolved,128,8, ...
    "walsh",1,"fixed_per_port_epre",120,10531);
assert(wave.NMSE<1e-9 && wave.SGCS>1-1e-9 && wave.Plan.PortCount==128);
assert(wave.NoiseSource=="sixgr.phy.waveform.addOccupiedREAWGN");
assert(wave.NoiseVarianceDomain=="resource_grid_pre_equalization");
assert(abs(wave.GridNoiseVariance-1e-12)<1e-15);

% Finite-SNR evidence must use the same calibrated occupied-grid Es/N0
% convention as production links and FRC conformance. This guards against
% the historical FFT-gain inflation caused by sample/grid domain mixing.
finiteWave=sixgr.phy.refsig.HighPortCSIRSMapper.runWaveformPoint( ...
    resolved,128,8,"walsh",1,"fixed_per_port_epre",5,10532);
assert(finiteWave.NMSEdB<5, ...
    "Finite-SNR high-port NMSE indicates a sample/grid noise-domain mismatch.");
assert(abs(finiteWave.GridNoiseVariance-10^(-.5))<1e-12);

% Multi-slot phase impairment is applied before OFDM, not painted onto an
% estimate after reception. The correction must therefore improve the
% estimate reconstructed from two real waveform occasions.
multi=sixgr.phy.refsig.HighPortCSIRSMapper.runMultiSlotWaveformPoint( ...
    resolved,"M1",2,"PortCount",16,"CDMSize",8,"SNRdB",80, ...
    "SpeedKmph",0,"PhaseIncrementDeg",15,"Seed",10533);
assert(height(multi.Trace)==2 && all(multi.Trace.ExecutionBackend== ...
    "nr_ofdm_streamed_high_port_occ_waveform"));
uncorrected=multi.Summary.NMSELinear(multi.Summary.ReceiverMode== ...
    "coherent_uncorrected");
corrected=multi.Summary.NMSELinear(multi.Summary.ReceiverMode== ...
    "phase_corrected");
assert(corrected<uncorrected);

fprintf("testCSITDocExactModels: PASS (canonical owners, YAML CQI, OCC, phase, Jakes, state, OLLA, 512-port plan, calibrated OFDM)\n");
end

function assertThrows(f,id)
thrown=false;
try, f(); catch cause, thrown=strcmp(cause.identifier,id); end
assert(thrown,"Expected typed error %s.",id);
end
