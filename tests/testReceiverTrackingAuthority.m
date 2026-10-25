function testReceiverTrackingAuthority
% Metadata boundary only: no claim of executed tracking measurement/RF.
resolve=@sixgr.phy.rx.resolveReceiverTrackingAuthority;
for direction=["DL","UL"]
    empty=resolve(struct(),direction);
    assert(~empty.Processed && ~empty.DirectionCompatible);
    s=struct('TRSProcessed',true,'TrackingMeasurementDirection',direction, ...
        'TrackingConsumerDirection',direction,'TrackingEstimateSource',"declared_boundary", ...
        'TimingEstimateAvailable',true,'TimingEstimate_samples',-3, ...
        'CFOEstimateAvailable',true,'EstimatedCFO_Hz',430);
    before=s; a=resolve(s,direction);
    assert(a.Processed && a.DirectionCompatible && isequaln(s,before));
    assert(a.Source=="declared_boundary" && a.Status=="authorized_same_receiver_direction");
    for name=["TrackingMeasurementDirection","TrackingConsumerDirection","TrackingEstimateSource"]
        localThrows(@()resolve(rmfield(s,name),direction),'sixgr:phy:rx:MissingTrackingAuthority');
    end
    bad=s; bad.TrackingMeasurementDirection=42;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.TrackingMeasurementDirection=["DL","UL"];
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.TrackingDirectionCompatible='true';
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.RuntimeTRSProcessed=false;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:ConflictingTrackingAuthority');
    bad=s; bad.RuntimeTRSTimingEstimate_samples=4;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:ConflictingTrackingAuthority');
    bad=s; bad.EstimatedCFO_Hz='A';
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.EstimatedCFO_Hz=NaN;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.TimingEstimate_samples=NaN;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.RuntimeTRSAgeSlots=-1;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.RuntimeTRSTrackingUpdateTime_s=-1;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:InvalidTrackingAuthority');
    bad=s; bad.RuntimeTRSRuntimeEvidenceSource="different_original_source";
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:ConflictingTrackingAuthority');
    opposite="UL"; if direction=="UL", opposite="DL"; end
    bad=s; bad.RuntimeTRSMeasurementDirection=opposite;
    localThrows(@()resolve(bad,direction),'sixgr:phy:rx:ConflictingTrackingAuthority');
    bad=s; bad.TrackingMeasurementDirection=opposite; bad.TrackingDirectionCompatible=true;
    a=resolve(bad,direction);
    assert(~a.DirectionCompatible && a.Status=="rejected_cross_direction_receiver_state");
    % Native runtime aliases need no invented explicit-state labels.
    r=struct('RuntimeTRSProcessed',true,'RuntimeTRSMeasurementDirection',direction, ...
        'RuntimeReceiverTrackingConsumerDirection',direction, ...
        'RuntimeReceiverTrackingDirectionCompatible',true, ...
        'RuntimeReceiverTrackingAuthorityStatus','authorized_same_receiver_direction', ...
        'RuntimeReceiverTrackingAuthorityReason','', ...
        'RuntimeTRSRuntimeEvidenceSource','original_runtime_trial', ...
        'RuntimeTRSTimingEstimateAvailable',true,'RuntimeTRSTimingEstimate_samples',-3, ...
        'RuntimeTRSAgeSlots',0,'RuntimeTRSTrackingUpdateTime_s',0);
    a=resolve(r,direction); assert(a.DirectionCompatible && a.Source=="original_runtime_trial");
    r.TrackingMeasurementDirection=lower(direction);
    a=resolve(r,direction); assert(a.DirectionCompatible);
end
fprintf('testReceiverTrackingAuthority: PASS (declared metadata boundary only)\n');
end

function localThrows(f,id)
try
    f();
catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s.',id,err.identifier);
    return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
