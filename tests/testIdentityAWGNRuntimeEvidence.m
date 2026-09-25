function ok=testIdentityAWGNRuntimeEvidence()
% Declared metadata fixtures, not a fading/antenna-pattern qualification.
cfg=struct('channel',struct('sharedIdentityAWGNEnabled',true));
T=fixture();
before=T;
assert(sixgr.analytics.identityAWGNRuntimeEvidence(T,cfg,4,4));
assert(isequaln(T,before),'Classification must not relabel primary observations.');
for n=[1 2 4]
    t=T;
    for name=["ConfiguredTxAntennas","ConfiguredRxAntennas", ...
            "PhysicalTxAntennas","PhysicalRxAntennas","TxWaveformColumns","RxWaveformBranches"]
        t.(name)(:)=n;
    end
    t.Rank(:)=n;
    assert(sixgr.analytics.identityAWGNRuntimeEvidence(t,cfg,n,n));
end
for name=string(T.Properties.VariableNames)
    bad=removevars(T,name);
    assert(~sixgr.analytics.identityAWGNRuntimeEvidence(bad,cfg,4,4), ...
        'Missing evidence must not pass: %s.',name);
    bad=T;
    if isstring(bad.(name))
        bad.(name)(1)="wrong";
    elseif contains(name,"Applied") || contains(name,"Uses")
        bad.(name)(1)=1;
    else
        bad.(name)(1)=NaN;
    end
    assert(~sixgr.analytics.identityAWGNRuntimeEvidence(bad,cfg,4,4), ...
        'Contradictory evidence must not pass: %s.',name);
end
bad=T; bad.RxWaveformBranches(1)=3;
assert(~sixgr.analytics.identityAWGNRuntimeEvidence(bad,cfg,4,4));
bad=T; bad.Rank(1)=5;
assert(~sixgr.analytics.identityAWGNRuntimeEvidence(bad,cfg,4,4));
bad=T; bad.Layers=[1;1];
assert(~sixgr.analytics.identityAWGNRuntimeEvidence(bad,cfg,4,4));
cfg.channel.sharedIdentityAWGNEnabled=false;
assert(~sixgr.analytics.identityAWGNRuntimeEvidence(T,cfg,4,4));
cfg.channel.awgnSpatialMatrixDL=[.8 0 .6 0;0 .6 0 .8];
M=T;
M.ChannelObjectClass(:)="explicit_fixed_matrix_sample_operator";
M.ChannelArrayHandlingStatus(:)="awgn_configured_spatial_matrix_no_array_kernel";
M.ElementPatternChannelApplicability(:)="not_applicable_awgn_fixed_matrix_channel";
for field=["ConfiguredRxAntennas","PhysicalRxAntennas","RxWaveformBranches"]
    M.(field)(:)=2;
end
assert(sixgr.analytics.identityAWGNRuntimeEvidence(M,cfg,4,2));
M.Rank(2)=3;
assert(~sixgr.analytics.identityAWGNRuntimeEvidence(M,cfg,4,2));
fprintf('IDENTITY_AWGN_RUNTIME_EVIDENCE_PASS metadata_only=1 dimensions=1,2,4\n');
ok=true;
end
function T=fixture()
row=struct('ChannelModel',"AWGN",'ChannelModelApplied',"AWGN", ...
    'ChannelArrayModel',"awgn_no_array_channel", ...
    'ChannelObjectSource',"sixgr.channel.IdentityAWGNRuntime.materialize", ...
    'ChannelObjectClass',"explicit_identity_sample_operator", ...
    'ChannelArrayHandlingStatus',"awgn_identity_spatial_dimensions_no_array_kernel", ...
    'ElementPatternChannelApplicability',"not_applicable_awgn_identity_channel", ...
    'ConfiguredTxAntennas',4,'ConfiguredRxAntennas',4, ...
    'PhysicalTxAntennas',4,'PhysicalRxAntennas',4, ...
    'TxWaveformColumns',4,'RxWaveformBranches',4, ...
    'ChannelUsesSameRuntimeAntennaAssumptions',false,'ChannelUsesCountOnlyAntennaModel',false, ...
    'TransmitElementPatternApplied',false,'ReceiveElementPatternApplied',false,'Rank',1);
T=struct2table([row;row]); T.Rank(2)=2;
end
