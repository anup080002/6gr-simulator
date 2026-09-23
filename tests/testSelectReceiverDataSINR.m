function ok=testSelectReceiverDataSINR()
% Metadata-authority fixtures only; no physical qualification claim.
row=struct('PostEqSINR_dB',21.5, ...
    'PostEqSINRSource',"post_equalization_sinr_from_equalizer_channel_estimate", ...
    'PostEqSINRValueRole',"measured_post_equalization_scheduling_input", ...
    'PostEqSINRValueStatus',"OK_decision_residual_bounded", ...
    'ReceiverHestSINR_dB',-30, ...
    'ReceiverHestSINRSource',"receiver_hest_reference_signal_measurement", ...
    'ReceiverHestSINRValueRole',"estimated",'ReceiverHestSINRValueStatus',"OK");
[value,source,role,status]=sixgr.link.selectReceiverDataSINR(row);
assert(value==21.5 && source==row.PostEqSINRSource && role==row.PostEqSINRValueRole && ...
    status==row.PostEqSINRValueStatus,'Do not rename measurement provenance.');
tableRow=struct2table(row);
assert(sixgr.link.selectReceiverDataSINR(tableRow)==value);
cases=2;
for reference=[-30 6 19.7776672573192 21.5 40 NaN]
    changed=row; changed.ReceiverHestSINR_dB=reference;
    assert(sixgr.link.selectReceiverDataSINR(changed)==value);
    cases=cases+1;
end
for diagnostic=["NMSE_dB","TrueChannelNMSE_dB","EVMProxySINR_dB","ConfiguredSNR_dB"]
    changed=row; changed.(diagnostic)=-80;
    assert(sixgr.link.selectReceiverDataSINR(changed)==value);
    cases=cases+1;
end
for field=["PostEqSINRSource","PostEqSINRValueRole","PostEqSINRValueStatus"]
    for bad=["","NaN","unavailable","failed","rejected","proxy","oracle_true_channel", ...
            "configured_sweep","receiver_hest_reference_signal_measurement", ...
            "estimated","not_for_scheduling","not_post_equalization", ...
            "conservative_min_channel_estimate_posteq","predicted_post_equalization"]
        changed=row; changed.(field)=bad;
        assert(isnan(sixgr.link.selectReceiverDataSINR(changed)), ...
            'Untrusted %s=%s must not be rescued by the reference SINR.',field,bad);
        cases=cases+1;
    end
end
unknownStatus=row; unknownStatus.PostEqSINRValueStatus="unknown";
assert(isnan(sixgr.link.selectReceiverDataSINR(unknownStatus)));
cases=cases+1;
for bad={NaN,Inf,-Inf,[1 2],1+1i,"21.5",true}
    changed=row; changed.PostEqSINR_dB=bad{1};
    assert(isnan(sixgr.link.selectReceiverDataSINR(changed)));
    cases=cases+1;
end
% A differently valued legacy alias cannot override canonical data evidence.
alias=row; alias.MeasuredTrialSINR_dB=8;
alias.MeasuredTrialSINRSource=row.PostEqSINRSource;
alias.MeasuredTrialSINRValueRole=row.PostEqSINRValueRole;
alias.MeasuredTrialSINRValueStatus=row.PostEqSINRValueStatus;
assert(sixgr.link.selectReceiverDataSINR(alias)==21.5);
alias.PostEqSINR_dB=NaN;
assert(sixgr.link.selectReceiverDataSINR(alias)==8);
alias.MeasuredSINR_dB=7; alias.MeasuredTrialSINR_dB=NaN;
assert(sixgr.link.selectReceiverDataSINR(alias)==7);
alias.MeasuredTrialSINRSource="receiver_hest_reference_signal_measurement";
assert(isnan(sixgr.link.selectReceiverDataSINR(alias)));
cases=cases+4;
fprintf('SELECT_RECEIVER_DATA_SINR_PASS cases=%d waveform_qualification=0\n',cases);
ok=true;
end
