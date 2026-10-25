function ok=testSRSPeriodDurationValidation()
% Duration/schema/native-calendar checks only, not received-SRS evidence.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'simulator','configs','scenarios');
fdd=sixgr.lls6g.config.loadScenarioConfig(fullfile(folder,'lls_causal_access_to_data_wiring.yaml'));
tdd=sixgr.lls6g.config.loadScenarioConfig(fullfile(folder,'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
base15=fdd.toStruct(); base30=tdd.toStruct();
assert(base15.frame.scs_khz==15 && base30.frame.scs_khz==30);

% The catalogue admits positive durations, not an arbitrary ms whitelist.
% The resolved validator then checks the exact ordinary-SRS slot enum.
for base={base15,base30}
    s=base{1};
    for period=[1 4 5 2560]
        duration=period/(s.frame.scs_khz/15);
        candidate=withDuration(s,duration);
        candidate.reference_signals.srs_periodicity_slots=period;
        candidate.reference_signals.srs.period_offset=0;
        candidate.reference_signals.srs_slot_within_period=1;
        sixgr.lls6g.config.validateScenarioConfig(candidate);
    end
end
fprintf('SRS_DURATION_VALIDATION_PASS resolved15_30kHz_legal_duration_domain\n');

% Higher carrier SCS changes duration, not the ordinary base-IE slot set.
% Native calendars independently confirm the converted period; these are
% standalone clock/indices fixtures, not a mixed-BWP integration claim.
allowed=[1 2 4 5 8 10 16 20 32 40 64 80 160 320 640 1280 2560];
for scs=[15 30 60 120]
    carrier=nrCarrierConfig('SubcarrierSpacing',scs,'NSizeGrid',24);
    for period=allowed
        raw=struct('frame',struct('scs_khz',scs), ...
            'reference_signals',struct('srs_periodicity_ms',period/(scs/15)));
        sixgr.lls6g.config.validateScenarioConfig(raw,'AllowPartial',true);
        converted=sixgr.lls6g.config.resolveCarrierPeriodSlots(raw,strings(0,1), ...
            "reference_signals.srs_periodicity_ms");
        sixgr.phy.srs.validateSRSPeriodOffset(converted,0);
        native=nrSRSConfig('SRSPeriod',[converted 0]);
        assert(isequal(double(native.SRSPeriod),[period 0]));
        carrier.NSlot=0; assert(~isempty(nrSRSIndices(carrier,native)));
        carrier.NSlot=1; assert(~isempty(nrSRSIndices(carrier,native))==(period==1));
    end
end
fprintf('SRS_DURATION_VALIDATION_PASS native15_30_60_120kHz_clock_conversion\n');

% A valid slot alias must not hide an invalid explicitly supplied duration.
reject(@()sixgr.lls6g.config.validateScenarioConfig(withDuration(base30,0.3)), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod');
reject(@()sixgr.lls6g.config.validateScenarioConfig(withDuration(base15,2.5)), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod');
reject(@()sixgr.lls6g.config.validateScenarioConfig(withDuration(base15,3)), ...
    'sixgr:phy:srs:InvalidPeriodicity');
reject(@()sixgr.lls6g.config.validateScenarioConfig(withDuration(base30,1.5)), ...
    'sixgr:phy:srs:InvalidPeriodicity');
reject(@()sixgr.lls6g.config.validateScenarioConfig(withDuration(base30,1281)), ...
    'sixgr:phy:srs:InvalidPeriodicity');
for value={[],NaN,Inf,-Inf,0,-1,true,'4',"4",[4 5],1+1i}
    partial=struct('reference_signals',struct('srs_periodicity_ms',value{1}));
    reject(@()sixgr.lls6g.config.validateScenarioConfig(partial,'AllowPartial',true));
end
for value={"", "NaN", "Inf", "-1", "0", "4ms", "1+1i", ["4" "5"]}
    partial=struct('reference_signals',struct('srs',struct('periodicity',value{1})));
    reject(@()sixgr.lls6g.config.validateScenarioConfig(partial,'AllowPartial',true));
end
fprintf('SRS_DURATION_VALIDATION_PASS malformed_nonintegral_and_nonstandard_slot_rejections\n');

% Do not evaluate an inherited duration against an intermediate parent's
% SCS. The final child restores30kHz, at which2.5ms is the legal five slots.
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> test-owned unique directory
parent=struct('inherits',string(fullfile(folder, ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml')), ...
    'frame',struct('scs_khz',15), ...
    'reference_signals',struct('srs_periodicity_ms',2.5));
parentPath=fullfile(work,'parent.json'); sixgr.util.jsonWrite(parentPath,parent);
child=struct('inherits',string(parentPath),'frame',struct('scs_khz',30));
childPath=fullfile(work,'child.json'); sixgr.util.jsonWrite(childPath,child);
resolved=sixgr.lls6g.config.loadScenarioConfig(childPath);
data=resolved.toStruct();
assert(data.frame.scs_khz==30 && data.reference_signals.srs_periodicity_ms==2.5 && ...
    str2double(string(data.reference_signals.srs.periodicity))==2.5);
reloadPath=fullfile(work,'resolved.json'); sixgr.util.jsonWrite(reloadPath,data);
reloaded=sixgr.lls6g.config.loadScenarioConfig(reloadPath);
assert(reloaded.get('reference_signals.srs_periodicity_ms')==2.5);
fprintf('SRS_DURATION_VALIDATION_PASS final_inherited_clock_and_resolved_reload receiver_trials=0\n');
ok=true;
end

function s=withDuration(s,duration)
s.reference_signals.srs_periodicity_ms=duration;
s.reference_signals.srs.periodicity=char(string(duration));
end

function reject(action,id)
if nargin<2, id=""; end
try
    action();
catch cause
    if strlength(string(id))>0
        assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    else
        assert(startsWith(string(cause.identifier),"sixgr:lls6g:config:"), ...
            'Malformed duration must fail in configuration validation: %s',cause.identifier);
    end
    return;
end
error('test:MissingSRSPeriodDurationGuard','Invalid SRS duration was accepted.');
end
