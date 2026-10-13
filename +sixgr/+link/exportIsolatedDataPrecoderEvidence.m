function row=exportIsolatedDataPrecoderEvidence(tx,cfg,state,replay,context)
% Retain the actual independent TX mapping after its channel call completed.
% This is not shared-stream, scheduler or over-the-air pattern evidence.
row=struct();
if ~logical(sixgr.util.structGet(cfg,'outputs.antennaPatternSamplesEnabled',false)), return; end
root=string(sixgr.util.structGet(cfg,'run.rootRunFolder',""));
assert(strlength(root)>0 && isfolder(root), ...
    'sixgr:link:AppliedPrecoderRoot','Enabled capture requires an existing run root.');
direction=string(context.Direction);
assert(any(direction==["DL","UL"]));
inputHash=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(tx.Waveform));
columns=size(tx.Waveform,2);
if isfield(state,'ContractVersion')
    assert(logical(replay.RuntimeChannelStateUsed) && ...
        string(replay.RuntimeChannelInputWaveformSHA256)==inputHash && ...
        replay.RuntimeChannelEndSample-replay.RuntimeChannelStartSample==size(tx.Waveform,1), ...
        'sixgr:link:AppliedPrecoderNotExecuted','Require the completed channel input receipt.');
    first=double(replay.RuntimeChannelStartSample);
    if logical(replay.RuntimeChannelElementExpansionApplied)
        projection=state.PortToElementMatrix;
        assert(string(sixgr.phy.mimo.MatrixContract.digest(projection))== ...
            string(replay.RuntimeChannelElementExpansionMatrixSHA256), ...
            'sixgr:link:AppliedPrecoderProjectionMismatch','The applied spatial map must match its channel receipt.');
    else
        assert(replay.RuntimeChannelMaterializedTxPorts==columns && ...
            ~logical(sixgr.util.structGet(replay,'RuntimeChannelInputPaddedToMaterializedPorts',false)), ...
            'sixgr:link:AppliedPrecoderProjectionUnavailable', ...
            'Do not infer a physical projection for padded or mismatched waveform ports.');
        projection=eye(columns);
    end
    clockScope="runtime_channel_sample_clock";
else
    % Legacy isolated calls pass the waveform columns directly to their
    % channel (or explicit AWGN path). No port/element expansion occurs.
    assert((logical(state.UseFading) && logical(replay.ChannelFadingApplied)) || ...
        (~logical(state.UseFading) && isfinite(replay.AppliedAWGNSNR_dB)), ...
        'sixgr:link:AppliedPrecoderNotExecuted','No completed independent channel observation.');
    projection=eye(columns);
    first=0;
    clockScope="independent_trial_local_capture";
end
if direction=="DL"
    antenna=cfg.lls6g.userContext.RuntimeServingBSAntenna;
else
    antenna=cfg.lls6g.userContext.RuntimeUEAntenna;
    sixgr.phy.ul.validatePUSCHPrecoderEvidence(tx);
end
validateattributes(context.UEIndex,{'numeric'},{'scalar','integer','positive'});
validateattributes(context.ConfiguredSNR_dB,{'numeric'},{'scalar','finite','real'});
validateattributes(context.TrialIndex,{'numeric'},{'scalar','integer','positive'});
validateattributes(context.Seed,{'numeric'},{'scalar','integer','nonnegative'});
identity=context;
identity.WaveformSHA256=inputHash;
identity.PHYGrantContextId=""; % Component execution has no shared grant.
identity.StartSample=first;
identity.EndSampleExclusive=first+size(tx.Waveform,1);
identity.SampleRateHz=double(replay.SampleRate_Hz);
identity.SampleClockScope=clockScope;
identity.ExecutionScope="independent_link_execution";
identity.SameScenarioInPathEligible=false;
token=string(sixgr.phy.waveform.WaveformHash.bytes( ...
    "independent_applied_precoder/v1|"+jsonencode(identity)+"|"+ ...
    string(sixgr.phy.mimo.MatrixContract.digest(projection))));
identity.TransmissionID="independent_tx_"+token;
[weights,patterns]=sixgr.report.buildAppliedDataPrecoderTables( ...
    tx,projection,antenna,identity,cfg, ...
    "executed_data_precoder_mapping_independent_channel_completed");
paths=struct('Weights',weights,'Patterns',patterns);
for name=["Weights","Patterns"]
    relative=fullfile('beamforming','csv','executed_observations', ...
        "applied_"+lower(name)+"_"+token+".csv");
    file=fullfile(root,relative);
    sixgr.util.csvWriteTable(file,paths.(name),'PreserveSchema',true,'RoundTripNumericText',true);
    row.("AppliedDataPrecoder"+name+"CSV")=string(relative);
    row.("AppliedDataPrecoder"+name+"CSVSHA256")=string(sixgr.phy.waveform.WaveformHash.file(file));
end
row.AppliedDataPrecoderTransmissionID=identity.TransmissionID;
end
