function ok=testOLLAObservationValidity()
% Explicit receiver validity is authoritative over unrelated decode aliases.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.mode='amc';
cfg.phy.linkAdaptation.dlPolicy='cqi'; cfg.phy.linkAdaptation.ulPolicy='cqi';
cfg.phy.linkAdaptation.rankPolicy='fixed';
cfg.phy.linkAdaptation.outerLoopFlag=true;
cfg.phy.linkAdaptation.deltaMCSPolicy='olla';
cfg.phy.linkAdaptation.ollaStepDown=0.9; cfg.phy.linkAdaptation.ollaStepUp=0.1;
cfg.phy.pdsch.mcsTable='qam64_table1'; cfg.phy.pusch.mcsTable='qam64_table1';
cfg.phy.csi.cqiTable='table1';
cfg.phy.pdsch.nLayers=1; cfg.phy.pdsch.numLayers=1;
cfg.phy.pusch.nLayers=1; cfg.phy.pusch.numLayers=1;
for direction=["DL","UL"]
    metrics=struct('CQI',12,'RI',1,'RV',0,'IsRetransmission',false, ...
        'AckObservedValid',false,'AckObserved',false,'ObservedAck',true, ...
        'CRCPass',true,'AllowOLLAUpdate',true);
    [baseline,state]=sixgr.link.computeLinkAdaptationDecision(cfg,direction,struct('CQI',12,'RI',1));
    assert(baseline.Valid);
    [direct,event]=sixgr.link.updateOLLAStateFromHARQFeedback(cfg,direction,metrics,state);
    [decision,after]=sixgr.link.computeLinkAdaptationDecision(cfg,direction,metrics,'AdaptationState',state);
    fprintf('OLLA_INVALID %s direct_eligible=%d decision_ack_valid=%d direct_updates=%g decision_updates=%g\n', ...
        direction,event.Eligible,decision.AckObservedValid, ...
        direct.OLLAUpdateCount-state.OLLAUpdateCount,after.OLLAUpdateCount-state.OLLAUpdateCount);
    assert(~event.FeedbackKnown && ~event.Eligible && ...
        direct.DeltaMCS==state.DeltaMCS && direct.OLLAUpdateCount==state.OLLAUpdateCount && ...
        ~decision.AckObservedValid && after.DeltaMCS==state.DeltaMCS && ...
        after.OLLAUpdateCount==state.OLLAUpdateCount, ...
        'test:InvalidACKRescuedByCRC','An invalid ACK must not be rescued by generic CRC/decode fields.');

    % The inner decision also sets this validity flag when an event is not
    % authorized to update OLLA. It must not be undone by the outer updater.
    metrics.AckObservedValid=true; metrics.AckObserved=true;
    metrics.AllowOLLAUpdate=false;
    [held,after]=sixgr.link.computeLinkAdaptationDecision(cfg,direction,metrics,'AdaptationState',state);
    assert(~held.OLLAUpdateAppliedAtThisEvent && ...
        after.OLLAUpdateCount==state.OLLAUpdateCount && after.DeltaMCS==state.DeltaMCS);
    metrics.AllowOLLAUpdate=true;
    for ack=[false true]
        metrics.AckObserved=ack;
        [updated,event]=sixgr.link.updateOLLAStateFromHARQFeedback(cfg,direction,metrics,state);
        expected=-0.9; if ack, expected=0.1; end
        assert(event.Eligible && event.Ack==ack && ...
            abs(updated.DeltaMCS-state.DeltaMCS-expected)<1e-12 && ...
            updated.OLLAUpdateCount==state.OLLAUpdateCount+1);
    end
    % Existing direct-link callers without a validity contract keep their
    % own data-decoder ACK authority; this is not physical UCI qualification.
    [~,legacy]=sixgr.link.updateOLLAStateFromHARQFeedback(cfg,direction, ...
        struct('CRCPass',false,'RV',0),state);
    assert(legacy.Eligible && ~legacy.Ack);
    for value={[],NaN,2,[0 1],"false"}
        malformed=metrics; malformed.AckObservedValid=value{1};
        localReject(@()sixgr.link.updateOLLAStateFromHARQFeedback(cfg,direction,malformed,state));
        localReject(@()sixgr.link.computeLinkAdaptationDecision(cfg,direction,malformed,'AdaptationState',state));
    end
    malformed=metrics; malformed.AckObserved=NaN;
    localReject(@()sixgr.link.updateOLLAStateFromHARQFeedback(cfg,direction,malformed,state));
    malformed=rmfield(metrics,'AckObserved');
    localReject(@()sixgr.link.updateOLLAStateFromHARQFeedback(cfg,direction,malformed,state));
end
ok=true;
end

function localReject(fcn)
try
    fcn(); error('test:ExpectedInvalidObservation','Expected invalid observation rejection.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:link:InvalidHARQFeedbackObservation'),'%s',cause.message);
end
end
