function ok=testPRACHCalendarInputAuthority()
% Raw-input authority and unchanged native occasion map; no RX qualification.
setup6GRSimToolkit('Verbose',false);
base=struct('ScenarioName','prach_calendar_authority','CarrierFrequencyHz',700e6, ...
    'DuplexMode','FDD','NSizeGrid',52,'PRACHConfigurationIndex',16, ...
    'PRACHSubcarrierSpacing',1.25,'PRACHFormat','0','ChannelModel','AWGN', ...
    'SequenceIndex',0,'ZeroCorrelationZone',8,'FrequencyStart',0, ...
    'Msg1FDM',1,'RBOffset',0,'RBSetOffset',0);
cfg=sixgr.rach.PRACHConfig(base);
original=sixgr.rach.mapPRACHToOccasion(cfg,'OccasionIndex',1);
for name=["PRACHConfigurationIndex","SequenceIndex","ZeroCorrelationZone", ...
        "FrequencyStart","Msg1FDM","RBOffset","RBSetOffset"]
    for value={base.(name)+0.2,'P',NaN,Inf,1i,[1 2],true}
        bad=base;bad.(name)=value{1};
        localReject(@()sixgr.rach.PRACHConfig(bad),'sixgr:rach:PRACHConfig:InvalidCalendarInteger');
    end
end
localReject(@()sixgr.rach.PRACHConfig(base,'SequenceIndex',0,'LogicalRootSequenceIndex',1), ...
    'sixgr:rach:PRACHConfig:ConflictingRootSequenceOptions');
same=sixgr.rach.PRACHConfig(base,'SequenceIndex',0,'LogicalRootSequenceIndex',0);
assert(isequaln(original,sixgr.rach.mapPRACHToOccasion(same,'OccasionIndex',1)));
% An intentional standalone scalar override remains legal. This regression
% does not claim last-authored YAML alias normalization is implemented.
override=sixgr.rach.PRACHConfig(base,'SequenceIndex',1);
assert(override.SequenceIndex==1 && base.SequenceIndex==0);
fprintf('PRACH_CALENDAR_INPUT_AUTHORITY_PASS raw_indices_no_rounding_native_occasion_preserved\n');
ok=true;
end
function localReject(f,id)
try,f();catch cause,assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);return;end
error('sixgr:test:ExpectedPRACHCalendarError','Expected %s.',id);
end
