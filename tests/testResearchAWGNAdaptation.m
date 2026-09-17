function ok=testResearchAWGNAdaptation(calibrationPath)
% Actual coded calibration + controller integration, not full-band acceptance.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
c=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'tests','fixtures','research_adaptation.yaml'));
s=c.toStruct(); tag="adaptive_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
root=fullfile(pwd,'results','component_validation',tag); mkdir(root);
s.research_adaptation.calibration_file=char(fullfile(root,'calibration','trials.csv'));
if nargin>0
    assert(isfile(calibrationPath),'Only existing coded calibration can be reused.');
    s.research_adaptation.calibration_file=char(calibrationPath);
end
config=fullfile(root,'config.yaml'); sixgr.lls6g.config.writeYAML(config,s);
% The calibrator and runner both consume the front-door normalized reload,
% not this pre-serialization in-memory fixture structure.
beforeReload=s; c=sixgr.lls6g.config.loadScenarioConfig(config); s=c.toStruct();
assert(sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(beforeReload,"DL")== ...
    sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(s,"DL"));
if nargin==0
    sixgr.phy.research.calibrateAWGNAdaptation(config);
else
    fprintf('REUSING_CODED_CALIBRATION path=%s SHA256=%s\n',calibrationPath,sixgr.util.sha256File(calibrationPath));
end
ctl=sixgr.phy.research.AWGNLinkAdaptation(s,"DL");
assert(all(isfinite(ctl.ThresholdDb)));
bad=s; bad.research_dl.num_prbs=9;
localThrows(@()sixgr.phy.research.AWGNLinkAdaptation(bad,"DL"),'sixgr:research:CalibrationProfileMismatch');
out=run_6g_phy_lls_single(config,fullfile(root,'execution'),tag);
assert(out.ResultOk && out.Manifest.LinkAdaptationEnabled);
T=out.TrialTable; S=out.SummaryTable;
assert(all(T.PhysicalTxElements==4 & T.PhysicalRxElements==4));
assert(all(T.CRCPass & T.TBExact) && ~any(T.IsRetransmission));
assert(any(T.Qm==8 & T.NewDataBootstrap) && any(T.Qm==10 & ~T.NewDataBootstrap));
assert(all(T.NoiseReferenceDataREPower==0.25));
assert(all(abs(T.MeasuredTXTotalDataREPower-1)<0.05));
assert(all(S.OLLAFirstAttemptUpdates==S.TransportBlocks));
for d=["DL","UL"]
    F=readtable(fullfile(out.RunFolder,'harq','csv',lower(d)+"_feedback.csv"),'TextType','string');
    h=sixgr.phy.research.AWGNLinkAdaptation(s,d);
    feedback=table2struct(F); slot=max(F.DeliveredAtSlot);
    h.advance(feedback,slot); margin=h.OLLA.MarginDb;
    assert(abs(margin+height(F)*s.research_adaptation.ack_step_db)<1e-12);
    h.advance(feedback,slot); assert(h.OLLA.MarginDb==margin);
    % Control-event unit fixtures only; these are not exported as PHY results.
    replay=feedback(end); replay.AttemptIndex=2; replay.CRCPass=false;
    h.advance([feedback;replay],slot); assert(h.OLLA.MarginDb==margin);
    h.advance([feedback;replay],slot+32);
    [~,allowed,decision]=h.select(s,slot+32);
    assert(~allowed && decision.Reason=="outage_or_stale_measurement_no_new_TB");
    localThrows(@()h.advance([feedback;replay;feedback(end)],slot+32), ...
        'sixgr:research:DuplicateOLLAFeedback');
end
% Independent actual low-SNR first attempt supplies a real NACK to OLLA.
h=sixgr.phy.research.IdealDelayedHARQ(s,"DL");
ctl=sixgr.phy.research.AWGNLinkAdaptation(s,"DL");
h.advance(0); ctl.advance(h.Feedback,0); [sc,allowed]=ctl.select(s,0);
[plan,tb,sc]=h.reserve(sc,0,allowed);
tx=sixgr.phy.research.SharedChannelLink.transmit(sc,0,tb,"DL",'HARQKey',plan.HARQKey);
h.transmitted(plan,tx); options=h.receiveOptions(plan);
nv=s.research_awgn_mimo.reference_data_re_power/tx.OFDM.SampleToGridNoiseVarianceGain;
wave=tx.Waveform+sqrt(nv/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
rx=sixgr.phy.research.SharedChannelLink.receive(sc,0,wave,"DL",options{:});
assert(~rx.CRCPass); h.received(plan,rx); h.advance(4); ctl.advance(h.Feedback,4);
assert(abs(ctl.OLLA.MarginDb-0.45)<1e-12);
h.advance(8); ctl.advance(h.Feedback,8); [sc,allowed]=ctl.select(s,8);
assert(~allowed); [retx,retained]=h.reserve(sc,8,allowed);
assert(retx.HARQ.IsRetransmission && isequal(tb,retained));
ok=true;
fprintf('RESEARCH_AWGN_ADAPTATION_COMPONENT_PASS folder=%s calibration_PRBs=8 full_band_qualification=0\n',out.RunFolder);
end

function localThrows(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection %s.',id);
end
