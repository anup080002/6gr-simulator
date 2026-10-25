function ok=testSSBAcquisitionWindow()
% Pure receiver-window contract checks. No physical acquisition claim.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
paths=["simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml", ...
    "simulator/configs/validation/main_independent_broadcast_access.yaml"];
for path=paths
    scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,path));
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempdir);
    carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier);
    fs=double(info.SampleRate); count=round(fs*0.007);
    a=sixgr.phy.frame.SSBAcquisitionWindow.create(cfg,fs,0,count);
    timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
    assert(isequal(a.CandidateIndices,double(timing.CandidateIndices(:).')) && ...
        numel(a.CandidateIndices)==timing.Lmax && a.EndSampleExclusive<count);
    sixgr.phy.frame.SSBAcquisitionWindow.validate(a,cfg,fs,0,count);
    % Changing gNB emission occupancy must not improve UE foreknowledge.
    reduced=cfg; reduced.phy.ssb.activeCandidateIndices0Based=0;
    b=sixgr.phy.frame.SSBAcquisitionWindow.create(reduced,fs,0,count);
    assert(isequaln(a,b),'sixgr:test:TXBitmapAcquisitionOracle', ...
        'Receiver search must not use the transmitter active bitmap.');
    bad=a; bad.CandidateIndices=bad.CandidateIndices(1);
    rejects(@()sixgr.phy.frame.SSBAcquisitionWindow.validate(bad,cfg,fs,0,count), ...
        'sixgr:phy:frame:ChangedAcquisitionWindow');
    bad=a; bad.EndSampleExclusive=bad.EndSampleExclusive-1;
    rejects(@()sixgr.phy.frame.SSBAcquisitionWindow.validate(bad,cfg,fs,0,count), ...
        'sixgr:phy:frame:ChangedAcquisitionWindow');
    rejects(@()sixgr.phy.frame.SSBAcquisitionWindow.create(cfg,fs,0,a.EndSampleExclusive-1), ...
        'sixgr:phy:frame:AcquisitionWindowOutsideArchive');
    frameSamples=round(fs*0.010);
    later=sixgr.phy.frame.SSBAcquisitionWindow.create(cfg,fs,frameSamples,count);
    assert(later.EndSampleExclusive==a.EndSampleExclusive+frameSamples && ...
        later.ArchiveEndSampleExclusive==frameSamples+count && later.SHA256~=a.SHA256 && ...
        later.HalfFrameIndex==0 && later.AbsoluteFrameNumber==1);
    rejects(@()sixgr.phy.frame.SSBAcquisitionWindow.create(cfg,fs,count,count), ...
        'sixgr:phy:frame:UnsupportedAcquisitionOrigin');
    shifted=cfg; shifted.phy.ssb.halfFrameIndex=1;
    rejects(@()sixgr.phy.frame.SSBAcquisitionWindow.create(shifted,fs,0,count), ...
        'sixgr:phy:frame:UnsupportedAcquisitionOrigin');
    if contains(path,"n40")
        assert(a.Lmax==8 && isequal(a.CandidateStartSymbolsWithinHalfFrame,[2 8 16 22 30 36 44 50]) && ...
            a.EndSampleExclusive==59556 && a.SampleRateHz==30720000, ...
            'sixgr:test:N40AcquisitionWindow','Check the exact configured receiver clock, all eight candidates and timing guard.');
    end
end
ok=true;
end
function rejects(call,id)
try
    call();
catch cause
    assert(strcmp(cause.identifier,id),'sixgr:test:UnexpectedFailure','%s',getReport(cause));
    return;
end
error('sixgr:test:MissingFailure','Expected %s.',id);
end
