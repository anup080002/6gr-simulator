function ok=testTRSScoringAuthority()
% Algebraic authority/metric fixture only, not a physical TRS qualification.
setup6GRSimToolkit('Verbose',false);
reference=reshape(complex(1:24,24:-1:1),[12 2]);
estimate=reference*1.1;
ch=struct('ChannelEstimates',{{estimate}},'PilotIndices',{{(1:24).'}}, ...
    'Table',table(true,NaN,false,"",0,NaN,NaN,"",'VariableNames', ...
    {'TRSChannelEstimateAvailable','NMSE_dB','NMSEScoringAvailable', ...
    'NMSEReferenceSource','NMSEComparedComplexValues','ChannelErrorEnergy', ...
    'ChannelReferenceEnergy','Status'}));
e=struct('Source',"applied_identity_AWGN_operator_TRS_port_reference", ...
    'ReceiverEstimatorInput',false,'GainOrPhaseFitted',false, ...
    'AdditionalChannelExecutions',0);
for source=[e.Source,"applied_channel_gain_truth_shared_NR_path_filter_reference", ...
        "applied_fixed_matrix_AWGN_operator_TRS_port_reference", ...
        "standalone_awgn_known_noiseless_effective_response"]
    valid=e; valid.Source=source;
    scored=sixgr.phy.trs.scoreTRSChannelEstimates(ch,{reference},{valid});
    assert(scored.NMSEScoringAvailable && scored.NMSEReferenceSource==source);
    assert(abs(scored.MeanNMSE_dB+20)<1e-10 && ...
        scored.Table.NMSEComparedComplexValues==24);
    % Every accepted representation retains the same anti-oracle guards.
    for field=["ReceiverEstimatorInput","GainOrPhaseFitted","AdditionalChannelExecutions"]
        invalid=valid; invalid.(field)=1;
        caught=false;
        try
            sixgr.phy.trs.scoreTRSChannelEstimates(ch,{reference},{invalid});
        catch ME
            assert(string(ME.identifier)=="sixgr:phy:trs:InvalidChannelScoringAuthority");
            caught=true;
        end
        assert(caught,'Invalid %s scoring authority accepted for %s.',field,source);
    end
end
for field=["Source","ReceiverEstimatorInput","GainOrPhaseFitted", ...
        "AdditionalChannelExecutions"]
    invalid=e;
    if field=="Source", invalid.Source="synthetic_proxy";
    else, invalid.(field)=1; end
    caught=false;
    try
        sixgr.phy.trs.scoreTRSChannelEstimates(ch,{reference},{invalid});
    catch ME
        assert(string(ME.identifier)=="sixgr:phy:trs:InvalidChannelScoringAuthority");
        caught=true;
    end
    assert(caught,'Invalid scoring authority was accepted: %s',field);
end
fprintf('TRS_SCORING_AUTHORITY_PASS\n');
ok=true;
end
