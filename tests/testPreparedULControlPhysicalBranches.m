function ok=testPreparedULControlPhysicalBranches()
% Buffer contract only: four physical branches with two logical CSI ports.
% No decoder/BLER claim is made by this isolated identity-link sample check.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_four_port_connected_research_ul_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
bs=sixgr.rf.AntennaArrayFactory.build(cfg,'bs');
assert(bs.NumElements==4 && bs.NumPorts==2);
cfg.lls6g.userContext.RuntimeServingBSAntenna=bs;
cfg.lls6g.userContext.RuntimeServingBSAntennaMeta= ...
    struct('NumPorts',bs.NumPorts,'NumElements',bs.NumElements);
out=sixgr.link.runSRSChannelEstimation(cfg,'SlotIndex',5, ...
    'TimingAdvanceSamples',0,'PrepareOnly',true);
p=out.PreparedTransmission;
assert(p.NumReceiveAntennas==4 && p.NumPhysicalTransmitAntennas==4);
array=sixgr.rf.AntennaArrayFactory.build(p.ReceiverConfig,'ue', ...
    'signal','srs','numPorts',size(p.Tx.Waveform,2));
samples=p.Tx.Waveform*array.PortToElementMatrix.';
capture=sixgr.phy.waveform.WaveformObservationBuffer( ...
    p.ReceiveStartSample,p.ReceiveEndSampleExclusive,p.SampleRateHz,4);
capture.append(sixgr.phy.waveform.WaveformChunk(samples,p.ReceiveStartSample),p.SampleRateHz);
assert(isequal(p.readObservation(capture,'receiver'),samples));
wrong=sixgr.phy.waveform.WaveformObservationBuffer( ...
    p.ReceiveStartSample,p.ReceiveEndSampleExclusive,p.SampleRateHz,2);
wrong.append(sixgr.phy.waveform.WaveformChunk(samples(:,1:2),p.ReceiveStartSample),p.SampleRateHz);
try
    p.readObservation(wrong,'receiver');
catch ME
    assert(strcmp(ME.identifier,'sixgr:link:ULControlObservationMismatch'));
    fprintf('PREPARED_UL_PHYSICAL_BRANCHES_PASS elements=4 logical_ports=2 truncated_capture_rejected=1\n');
    ok=true; return;
end
error('test:MissingRejection','A two-branch capture must not satisfy a four-element receiver.');
end
