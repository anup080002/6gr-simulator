function ok = testBroadcastWaveformPortGrid()
% Actual SI samples must match the power and resource grid in either domain.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring.yaml');
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
for domain = ["physical_element_domain","logical_rf_chain_post_analog_precoder"]
    current = sixgr.util.structSet(cfg,'initial_access.ssb.waveform_domain',domain);
    current = sixgr.util.structSet(current,'phy.ssb.waveformDomain',domain);
    % Production preparation previously rejected the logical domain before
    % any channel or receiver could execute. Keep the fixed-EPRE policy.
    p = sixgr.link.prepareCellSearchBroadcast(current,true);
    tx = p.Tx;
    expected = sixgr.link.broadcastSIB1WaveformPortGrid(tx);
    assert(string(tx.SSBInfo.WaveformDomain)==domain);
    measured = nrOFDMDemodulate(tx.Carrier,tx.SIB1Waveform,'SampleRate',p.SampleRateHz);
    measured = measured(:,1:size(expected,2),:);
    mismatch = norm(measured(:)-expected(:))/norm(expected(:));
    assert(isequal(size(measured),size(expected)) && mismatch<1e-10, ...
        'SI port grid must describe actual OFDM samples, error=%.15g.',mismatch);
    assert(size(p.TxInfo.PortGrid,3)==size(p.TransmitSamples,2) && ...
        all(isfinite(p.TxInfo.PortGrid),'all'));
    if domain=="logical_rf_chain_post_analog_precoder"
        assert(~tx.SIB1SpatialMapping.MatrixAppliedHere && ...
            isequal(expected,tx.SIB1Grid) && size(expected,3)==1 && ...
            tx.SIB1SpatialMapping.PhysicalProjectionOwner=="external_physical_projection_required");
    else
        assert(tx.SIB1SpatialMapping.MatrixAppliedHere && ...
            size(expected,3)==tx.SIB1SpatialMapping.NumPhysicalElements);
    end
    first = sixgr.phy.frame.slotStartSample(tx.Carrier,20,p.SampleRateHz);
    observation = sixgr.phy.waveform.WaveformObservationBuffer( ...
        first,first+p.NumSamples,p.SampleRateHz,size(p.TransmitSamples,2));
    observation.append(sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,first),p.SampleRateHz);
    T = sixgr.truth.buildObservedBroadcastREAllocation(p,observation,1);
    si = T(T.channel~="SSB",:);
    assert(~isempty(si) && sum(si.re_count)==nnz(expected) && ...
        all(si.port_index<size(p.TransmitSamples,2)) && ...
        all(si.waveform_port_domain==domain), ...
        'Exports must retain actual waveform-port REs, not unexecuted element projection.');
    wrong=tx; wrong.SIB1SpatialMapping.MatrixAppliedHere=~wrong.SIB1SpatialMapping.MatrixAppliedHere;
    localReject(@()sixgr.link.broadcastSIB1WaveformPortGrid(wrong));
    wrong=tx; wrong.SIB1SpatialMapping.NumWaveformColumns=size(tx.Waveform,2)+1;
    localReject(@()sixgr.link.broadcastSIB1WaveformPortGrid(wrong));
    wrong=tx; wrong.SIB1SpatialMapping.PhysicalProjectionOwner="invented_owner";
    localReject(@()sixgr.link.broadcastSIB1WaveformPortGrid(wrong));
    wrong=tx; wrong.SIB1SpatialMapping=rmfield(wrong.SIB1SpatialMapping,'MatrixAppliedHere');
    localReject(@()sixgr.link.broadcastSIB1WaveformPortGrid(wrong));
    fprintf('BROADCAST_WAVEFORM_PORT_GRID_PASS domain=%s ports=%d SI_RE=%d error=%.3g\n', ...
        domain,size(expected,3),nnz(expected),mismatch);
end
ok=true;
end

function localReject(fn)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,'sixgr:link:MissingBroadcastSIB1PortGrid'), ...
        'Unexpected rejection: %s %s',cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Missing or contradictory projection evidence must fail.');
end
