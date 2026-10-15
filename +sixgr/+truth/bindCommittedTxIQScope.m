function capture = bindCommittedTxIQScope(capture,direction)
%BINDCOMMITTEDTXIQSCOPE Describe the samples actually captured by the producer.
% This is one observed interval, not a continuous whole-run recording.
arguments
    capture (1,1) struct
    direction (1,1) string {mustBeMember(direction,["DL","UL"])}
end
authority = string(sixgr.util.structGet(capture,'WaveformAuthority',''));
composite = authority=="exact_runtime_transmitter_composite_observation";
if direction=="DL"
    assert(composite || authority=="exact_runtime_pdsch_waveform", ...
        'sixgr:truth:UnknownCommittedIQAuthority', ...
        'DL IQ scope requires an explicit producer waveform authority.');
    capture.EndpointType = "gnb_grant_component";
    capture.ArtifactScope = "first_committed_grant_component";
    capture.VSGImportScope = "single_grant_component_not_complete_cell_transmission";
    if composite
        capture.EndpointType = "gnb_transmitter";
        capture.ArtifactScope = "first_committed_grant_observed_composite_interval";
        capture.VSGImportScope = "actual_composite_transmitter_interval_not_continuous_run";
    end
    capture.CompositeTransmitterWaveform = composite;
else
    assert(composite || authority=="exact_runtime_pusch_waveform", ...
        'sixgr:truth:UnknownCommittedIQAuthority', ...
        'UL IQ scope requires an explicit producer waveform authority.');
    capture.EndpointType = "ue_transmitter";
    capture.ArtifactScope = "first_committed_ue_grant_waveform";
    capture.VSGImportScope = "selected_ue_pusch_waveform_not_continuous_run";
    capture.CompositeTransmitterWaveform = composite;
    if composite
        capture.ArtifactScope = "first_committed_ue_grant_observed_composite_interval";
        capture.VSGImportScope = "actual_ue_composite_interval_not_continuous_run";
    end
end
end
