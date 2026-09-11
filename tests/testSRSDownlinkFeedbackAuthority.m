function ok=testSRSDownlinkFeedbackAuthority()
% Configuration capability guard; no waveform or measurement claim.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.util.structSet(struct(),'phy.linkAdaptation.cqiSource','csi_feedback');
sixgr.truth.validateSRSDownlinkFeedbackAuthority(cfg);
for source=["srs_based","","misspelled_source"]
    cfg=sixgr.util.structSet(cfg,'phy.linkAdaptation.cqiSource',source);
    expected="sixgr:truth:UnsupportedDownlinkCQISource";
    if source=="srs_based", expected="sixgr:truth:UnqualifiedSRSDownlinkPrediction"; end
    rejected=false;
    try
        sixgr.truth.validateSRSDownlinkFeedbackAuthority(cfg);
    catch err
        if string(err.identifier)~=expected, rethrow(err); end
        rejected=true;
    end
    assert(rejected,'Unsupported DL quality authority must not silently select another source.');
end
ok=true;
end
