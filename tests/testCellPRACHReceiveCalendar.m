function ok=testCellPRACHReceiveCalendar()
% Actual selected native/configured geometry; no RF/detection/access claim.
setup6GRSimToolkit('Verbose',false);
repo=fileparts(fileparts(mfilename('fullpath')));
path=fullfile(repo,'simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
assert(isfile(path),'test:CellPRACHScenarioMissing','Use the actual selected n40 common configuration.');
s=sixgr.lls6g.config.loadScenarioConfig(path);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier);
r=struct('SampleRateHz',info.SampleRate,'NumReceiveAntennas',64, ...
    'FilterDelaySamples',7,'FilterTailSamples',31);
before=rng;
c=sixgr.truth.buildCellPRACHReceiveCalendar(cfg,1,r);
assert(isequal(before,rng) && ~c.UETransmissionRequired && ...
    c.Source=="original_gNB_common_configuration" && ...
    all(c.Validity.RepeatedValidity==c.Validity.RepeatedValidity(:,1),'all'));
changed=cfg;
changed.random_access.preamble_index=63;
changed.random_access.associated_ssb_index=3;
changed.random_access.temp_crnti=999;
changed.random_access.final_crnti=1000;
other=sixgr.truth.buildCellPRACHReceiveCalendar(changed,1,r);
assert(c.SHA256==other.SHA256,'UE selected preamble/beam/identities must not change the gNB receive calendar.');
stop=60*info.SampleRate/2000;
[whole,~]=sixgr.truth.planCellPRACHReceiveWindows(c,0,stop);
assert(~isempty(whole),'The selected n40 horizon must contain configured cell receive windows.');
split=cell(0,1);
for slot=0:59
    a=sixgr.phy.frame.slotStartSample(carrier,slot,info.SampleRate);
    b=sixgr.phy.frame.slotStartSample(carrier,slot+1,info.SampleRate);
    part=sixgr.truth.planCellPRACHReceiveWindows(c,a,b);
    split=[split;part]; %#ok<AGROW>
end
assert(isequaln(split,whole),'Lookahead must arm each window once regardless of slot chunking.');
ord=cellfun(@(w)w.OccasionOrdinal1,whole);
assert(numel(unique(ord))==numel(ord));
for k=1:numel(whole)
    p=whole{k}; native=p.OriginalNativeRow;
    assert(c.Validity.RepeatedValidity(native.Ordinal,1) && ...
        isequal(p.CandidatePreambles0,0:63) && ~p.ReceiverArmed && ~p.WaveformExecuted && ...
        p.ReceiveStartSample>=0 && p.ReceiveEndSampleExclusive>p.ReceiveStartSample);
end
tampered=c; tampered.Receiver.SearchGuardSamples=tampered.Receiver.SearchGuardSamples+1;
reject(@()sixgr.truth.planCellPRACHReceiveWindows(tampered,0,stop),'sixgr:truth:CellPRACHCalendarChanged');
bad=cfg; bad.rrc.sib1.initial_ul_bwp=struct('start_rb',1,'size_rb',20,'scs_khz',30);
reject(@()sixgr.truth.buildCellPRACHReceiveCalendar(bad,1,r),'sixgr:truth:CellPRACHInitialBWPUnsupported');
assert(isequal(before,rng));
ok=true;
fprintf('CELL_PRACH_CALENDAR_PASS windows=%d all64candidates=1 UEattemptInputs=0 RFexecutions=0\n',numel(whole));
end
function reject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,'Expected %s, got %s',id,e.identifier); return; end
error('test:CellPRACHGuardMissing','Expected %s.',id);
end
