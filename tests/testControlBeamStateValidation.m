function ok = testControlBeamStateValidation()
data=struct('TCIStateID',7,'TCIActive',true,'QCLSourceType','SSB', ...
    'QCLSourceID',3,'BeamID',91,'BeamActive',true,'BeamBlocked',false, ...
    'MeasurementSlot',20,'MeasurementMaxAgeSlots',4, ...
    'MeasurementProvenance','component_fixture_RS_state');
state=sixgr.phy.pdcch.ControlBeamState(data);
state.validateForSlot(20);
state.validateForSlot(24);
for slot=[19 25 NaN Inf -1 20.5]
    localReject(@() state.validateForSlot(slot));
end
for field=["TCIStateID","QCLSourceID","BeamID","MeasurementSlot", ...
        "MeasurementMaxAgeSlots","TCIActive","BeamActive","BeamBlocked"]
    bad=data;
    bad.(field)=NaN;
    localReject(@() sixgr.phy.pdcch.ControlBeamState(bad));
end
for field=["QCLSourceType","MeasurementProvenance"]
    bad=data;
    bad.(field)="";
    localReject(@() sixgr.phy.pdcch.ControlBeamState(bad));
end
blocked=data;
blocked.BeamBlocked=true;
blockedState=sixgr.phy.pdcch.ControlBeamState(blocked);
localReject(@() blockedState.validateForSlot(20));
ok=true;
end

function localReject(f)
try
    f();
catch ME
    assert(startsWith(string(ME.identifier),'sixgr:phy:pdcch:'));
    return;
end
error('test:ExpectedError','Invalid or stale control beam state was accepted.');
end
