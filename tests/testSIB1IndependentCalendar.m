function ok=testSIB1IndependentCalendar()
% Configured SI subset + actual native SI encoding/received-MIB decoding.
% Declared unit link, not shared RF/channel, UE lifecycle or global emission.
setup6GRSimToolkit('Verbose',false);
saved=rng; restore=onCleanup(@()rng(saved)); %#ok<NASGU>
folder=fullfile(pwd,'results','validation','sib1_independent_calendar', ...
    char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('SIB1_INDEPENDENT_CALENDAR_EVIDENCE %s\n',folder);
owned=~sixgr.runtime.RuntimeCallLedger.isConfigured();
if owned, sixgr.runtime.RuntimeCallLedger.configure(folder,struct('RunId',"si_calendar")); end
cleanup=onCleanup(@()releaseLedger(owned)); %#ok<NASGU>
files=[string(mfilename('fullpath'))+".m", ...
    string(which('sixgr.phy.frame.SSBTimingResolver')), ...
    string(which('sixgr.phy.frame.CommonDLResourcePlan')), ...
    string(which('sixgr.phy.broadcast.resolveSIB1ControlOccasion')), ...
    string(which('sixgr.phy.broadcast.generateSIB1Transmission')), ...
    string(which('sixgr.link.prepareSIB1Transmission'))];
hashes=arrayfun(@(f)string(sixgr.util.sha256File(f)),files);
sixgr.util.csvWriteTable(fullfile(folder,'source_hashes.csv'), ...
    table(files(:),hashes(:),'VariableNames',{'Path','SHA256'}),'PreserveSchema',true);
for scs=[15 30]
    cfg=configuration(scs,folder); original=cfg; before=rng;
    checkBWPAuthority(cfg);
    if scs==15
        carrier=sixgr.phy.grid.makeCarrier(cfg);
        [~,~,~,resolved]=sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,cfg);
        assert(carrier.NSizeGrid==25 && resolved.CORESET0Index==1 && ...
            resolved.CORESET0.RBStart==0 && resolved.CORESET0.NumRB==24 && ...
            resolved.Context.SSBFirstCommonRB==2 && resolved.Context.InitialDLBWPSize==25);
        % Preserve the original v262 failure as a negative: index0 removes
        % the two-RB offset and requires [2,26), outside this actual BWP.
        outside=cfg; outside.phy.sib1.coreset0Index=0;
        outside.phy.mib.pdcchConfigSIB1=2;
        reject(@()sixgr.phy.frame.CommonDLResourcePlan(outside), ...
            'sixgr:phy:pdcch:type0_context_not_supported');
    end
    for period=[5 10 20 40]
        c=cfg; c.phy.ssb.periodicity_ms=period; c.phy.ssb.period_ms=period;
        plan=sixgr.phy.frame.CommonDLResourcePlan(c); plan.validateSIB1References();
        carrier=sixgr.phy.grid.makeCarrier(c); P=2*carrier.SlotsPerFrame;
        first=P+2*carrier.SlotsPerSubframe; % ordinal3, Table13-11 searchSpaceZero2
        assert(plan.SIB1Slot0==first && plan.SIB1PeriodSlots==P && ...
            plan.BroadcastPeriodSlots==P && plan.SSBPeriodSlots==period*carrier.SlotsPerSubframe);
        rows=plan.sib1TransmissionOccasions(0,first+3*P);
        assert(isequal(rows.AbsoluteSlot,first+(0:2).'*P) && ...
            all(rows.FirstConfiguredAbsoluteSlot==first) && ...
            all(rows.PeriodSlots==P) && isequal(rows.RecurrenceIndex0Based,(0:2).'));
        assert(isempty(plan.sib1TransmissionOccasions(0,first)) && ...
            isempty(plan.sib1TransmissionOccasions(first,first)));
        % Moving the mutable caller clock cannot shift a configured global
        % calendar or apply ordinal3 anew to a later frame.
        moving=sixgr.phy.grid.applyRuntimeCarrierTimeline(c,10*carrier.SlotsPerFrame+1);
        moved=sixgr.phy.frame.CommonDLResourcePlan(moving);
        assert(isequaln(rows,moved.sib1TransmissionOccasions(0,first+3*P)));
        for slot=rows.AbsoluteSlot.'
            [~,bound,native,resolved,actual]=sixgr.phy.broadcast.resolveSIB1ControlOccasion( ...
                sixgr.phy.grid.makeCarrier(moving),moving,'AbsoluteSlot',slot);
            witness=sixgr.phy.pdcch.resolveType0MonitoringWindow(resolved.Context,slot,slot+1);
            assert(actual==slot && height(witness.MonitoringOccasions)==1 && ...
                resolved.SelectedMonitoringOccasion.AbsoluteSlot==slot && ...
                resolved.FirstSelectedAbsoluteSlot==first && ...
                native.NFrame==floor(slot/carrier.SlotsPerFrame) && ...
                native.NSlot==mod(slot,carrier.SlotsPerFrame) && ...
                bound.lls6g.runtime.AbsoluteSlotIndex0==slot);
            allocation=struct('PRBStart',0,'NumPRB',24,'SymbolStart',2,'NumSymbols',12);
            [free,why]=plan.checkPDSCH(allocation,slot);
            assert(~free && any(why.ConflictingOwners=="SIB1_PDSCH_and_Type0_PDCCH"));
        end
        % The other legal monitoring member is not a configured emission.
        [~,~,~,r]=sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,c);
        witness=sixgr.phy.pdcch.resolveType0MonitoringWindow(r.Context,first+1,first+2);
        assert(height(witness.MonitoringOccasions)==1);
        reject(@()sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,c,'AbsoluteSlot',first+1), ...
            'sixgr:phy:broadcast:SIB1OutsideConfiguredCalendar');
        reject(@()sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,c,'AbsoluteSlot',first-P), ...
            'sixgr:phy:broadcast:SIB1OutsideConfiguredCalendar');
        for bad={true,'1',NaN,Inf,-1,.5,[first first+P]}
            reject(@()sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,c,'AbsoluteSlot',bad{1}), ...
                'sixgr:phy:broadcast:InvalidSIB1Clock');
        end
    end
    assert(isequaln(original,cfg) && isequal(before,rng));
end
fprintf('SIB1_CALENDAR_PASS SCS15_30 SSBperiod5_10_20_40 first_ordinal3 native_period20ms\n');

% The first SI is at20ms with no SSB; its recurrence at40ms collides.
% Checking only the first transmission, or the old composite extent, misses it.
cfg=configuration(30,folder); bad=cfg;
bad.phy.ssb.periodicity_ms=40; bad.phy.ssb.period_ms=40;
bad.phy.mib.pdcchConfigSIB1=0; bad.phy.sib1.searchSpaceZero=0;
plan=sixgr.phy.frame.CommonDLResourcePlan(bad);
c=sixgr.phy.grid.makeCarrier(bad); c.NFrame=floor(plan.SIB1Slot0/c.SlotsPerFrame);
c.NSlot=mod(plan.SIB1Slot0,c.SlotsPerFrame);
ssb=sixgr.phy.frame.ssbPRBSymbolReservation(bad,c,plan.SIB1Slot0);
assert(isempty(ssb.ReservedCarrierRE0));
reject(@()plan.validateSIB1SSB(),'sixgr:phy:frame:SIB1SSBCollision');
fprintf('SIB1_RECURRING_SSB_COLLISION_PASS first_clear_later_overlap\n');

% Two original configured beam calendars retain their distinct identities.
multi=cfg; multi.phy.ssb.activeBitmap(2)=true;
multi.phy.ssb.activeCandidateIndices0Based=[0 1];
multi.phy.sib1.transmissionScope="all_active_ssb_occasions";
plan=sixgr.phy.frame.CommonDLResourcePlan(multi); plan.validateSIB1References();
rows=plan.sib1TransmissionOccasions(0,3*plan.SIB1PeriodSlots);
assert(isequal(unique(rows.SSBIndex).',[0 1]) && ...
    isequal(rows.AbsoluteSlot,[44;45;84;85]));
save(fullfile(folder,'configured_calendars.mat'),'cfg','multi','rows','bad');

% Original SSB is generated/decoded once. New SI occasions require no new
% SS/PBCH waveform or decoder, and the prior original context is not retagged.
[ssbSamples,~,association]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',5,'SSBIndex',0);
expected=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg,'SSBIndex',0);
assert(isequaln(association.SSBTiming.GridRelationship,expected.GridRelationship));
% A valid but different explicit BWP must still fail the original
% association join. Do not erase BWP identity to admit later SI clocks.
changed=cfg;
changed.phy.bwp.dl.NStartBWP=cfg.phy.carrier.NStartGrid+1;
changed.phy.bwp.dl.NSizeBWP=cfg.phy.carrier.NSizeGrid-1;
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(changed,association), ...
    'sixgr:phy:broadcast:SIB1AssociationMismatch');
prior=observation(ssbSamples,0,association.SampleRate_Hz);
[bch,context]=sixgr.phy.broadcast.recoverSIB1FromWaveform(prior,cfg, ...
    'RecoveryScope','SSB_MIB','CandidateSSBIndex',0);
save(fullfile(folder,'original_bch.mat'),'cfg','ssbSamples','association','bch','context','-v7.3');
assert(bch.SSBMIBComplete && bch.BCHCrcPass && bch.MIBDecoded && ...
    isa(context,'sixgr.phy.broadcast.ReceivedMIBContext'));
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
slots=plan.SIB1Slot0+[0 plan.SIB1PeriodSlots];
originalAssociation=association; originalContext=context.SHA256; originalRNG=rng;
ledger=sixgr.runtime.RuntimeCallLedger.snapshot();
status=profile('status'); assert(strcmp(status.ProfilerStatus,'off'));
profile clear; profileCleanup=onCleanup(@()profile('off')); profile on;
for k=1:numel(slots)
    slot=slots(k);
    moving=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,777);
    prepared=sixgr.link.prepareSIB1Transmission(moving,association,'AbsoluteSlot',slot);
    assert(prepared.ExecutionStage=="sib1_waveform_prepared_not_received" && ...
        prepared.RFExecutionDeferred && prepared.ChannelExecutionDeferred && ...
        ~prepared.SSBEmissionIncluded && ~prepared.PowerContext.PAApplied && ...
        prepared.AssociatedSSBIndex==0 && prepared.Tx.SIB1AbsoluteSlot==slot && ...
        prepared.Config.lls6g.runtime.AbsoluteSlotIndex0==slot && ...
        prepared.Tx.FirstSelectedAbsoluteSlot==plan.SIB1Slot0 && ...
        prepared.TransmitStartSample==prepared.Tx.WaveformStartAbsoluteSample && ...
        prepared.TransmitEndSampleExclusive==prepared.TransmitStartSample+prepared.NumSamples);
    assert(isequal(prepared.TransmitSamples,prepared.Tx.Waveform) && ...
        prepared.PowerContext.FixedSNRNormalizedReference && ...
        ~prepared.PowerContext.PhysicalDevicePowerClaim);
    capture=observation(prepared.TransmitSamples,prepared.TransmitStartSample,prepared.SampleRateHz);
    rx=sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(capture,cfg,context,'AbsoluteMonitoringSlot',slot);
    save(fullfile(folder,sprintf('original_si_%d.mat',k)),'prepared','rx','context','-v7.3');
    assert(rx.StrictOk && rx.DCICrcPass && rx.DLSCHCrcPass && rx.SIB1ASN1DecodeOk && ...
        ~rx.NewBCHReceptionAttempted && rx.PriorBCHContextSHA256==originalContext && ...
        rx.SIB1AbsoluteSlot==slot && rx.SIB1PayloadHashRx==string(prepared.Tx.SIB1PayloadHash), ...
        'test:IndependentSICalendarDecode','Actual native SI decode failed: %s / %s',rx.Status,rx.FailureReason);
end
profile off; calls=profile('info'); clear profileCleanup;
names=string({calls.FunctionTable.FunctionName});
assert(~any(contains(names,'SSB_Tx')|contains(names,'PBCH_Recovery')|contains(names,'nrWaveformGenerator')));
after=sixgr.runtime.RuntimeCallLedger.snapshot(); added=after(height(ledger)+1:end,:);
for name=["sixgr.phy.dl.PDCCH_Tx","sixgr.phy.dl.PDSCH_Tx","sixgr.phy.dl.PDCCH_Rx","sixgr.phy.dl.PDSCH_Rx"]
    assert(sum(added.FunctionName==name)==2,'Expected two actual %s calls.',name);
end
assert(isequaln(association,originalAssociation) && context.SHA256==originalContext && isequal(rng,originalRNG));
save(fullfile(folder,'original_call_evidence.mat'),'added','calls','slots');

% Absolute-power preparation uses the same original native grid and applies
% its declared nominal budget once; it is not a shared RF execution claim.
absolute=cfg; absolute.integration.run_mode="GEOMETRY_NETWORK";
absolute.integration.configured_snr_is_link_authority=false;
absolute.integration.power_reference_mode="absolute_calibrated_sqrt_mw";
absolute.powerAndRF.downlinkPowerNormalizationPolicy="fixed_epre_over_configured_bwp";
p=sixgr.link.prepareSIB1Transmission(absolute,association,'AbsoluteSlot',slots(2));
assert(p.PowerContext.ScaleApplied && ~p.PowerContext.FixedSNRNormalizedReference && ...
    p.PowerContext.PhysicalDevicePowerClaim && string(p.PowerContext.WaveformAmplitudeUnit)=="sqrt_mW" && ...
    p.PowerContext.NormalizationWaveformStartAbsoluteSymbolIndex0==slots(2)*p.Carrier.SymbolsPerSlot && ...
    isequal(p.TransmitSamples,p.Tx.Waveform.*cast(p.PowerContext.AmplitudeScale,'like',p.Tx.Waveform)));
save(fullfile(folder,'original_absolute_power_preparation.mat'),'p');
assert(isequal(hashes,arrayfun(@(f)string(sixgr.util.sha256File(f)),files)));
fprintf('SIB1_INDEPENDENT_CALENDAR_PASS actual_BCH=1 actual_SI_TX_RX=2 shared_emission_claim=0 folder=%s\n',folder);
ok=true;
end

function checkBWPAuthority(cfg)
% Configuration/native-TX geometry checks; no received measurement claim.
implicit=cfg;
if isfield(implicit.phy,'bwp') && isfield(implicit.phy.bwp,'dl')
    for name=["NStartBWP","NSizeBWP"]
        if isfield(implicit.phy.bwp.dl,name)
            implicit.phy.bwp.dl=rmfield(implicit.phy.bwp.dl,name);
        end
    end
end
explicit=implicit;
explicit.phy.bwp.dl.NStartBWP=cfg.phy.carrier.NStartGrid;
explicit.phy.bwp.dl.NSizeBWP=cfg.phy.carrier.NSizeGrid;
a=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(implicit);
b=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(explicit);
[~,~,native]=sixgr.phy.dl.SSB_Tx(implicit,'TimingOnly',true);
assert(isequaln(a.GridRelationship,b.GridRelationship) && ...
    isequaln(a.GridRelationship,native.SSBTiming.GridRelationship));

% Caller-supplied final carrier geometry owns absent BWP dimensions.
first=cfg.phy.carrier.NStartGrid+1; count=cfg.phy.carrier.NSizeGrid+2;
overridden=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(implicit, ...
    'NStartGrid',first,'NSizeGrid',count);
assert(overridden.GridRelationship.NStartGrid==first && ...
    overridden.GridRelationship.NSizeGrid==count && ...
    overridden.GridRelationship.NStartBWP==first && ...
    overridden.GridRelationship.NSizeBWP==count);
bounded=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(implicit, ...
    'NStartGrid',first,'NSizeGrid',count,'NStartBWP',first+1,'NSizeBWP',count-2);
assert(bounded.GridRelationship.NStartBWP==first+1 && ...
    bounded.GridRelationship.NSizeBWP==count-2);
reject(@()sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(explicit, ...
    'NStartGrid',first,'NSizeGrid',count), ...
    'sixgr:phy:frame:SSBBWPOutsideCarrierGrid');
outside=explicit; outside.phy.bwp.dl.NSizeBWP=count;
reject(@()sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(outside), ...
    'sixgr:phy:frame:SSBBWPOutsideCarrierGrid');
for name=["NStartBWP","NSizeBWP"]
    for raw={NaN,Inf,-1,.5,true,'1',[],[0 1]}
        invalid=explicit; invalid.phy.bwp.dl.(name)=raw{1};
        reject(@()sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(invalid), ...
            'sixgr:phy:frame:InvalidSSBBWP');
        reject(@()sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(implicit,name,raw{1}), ...
            'sixgr:phy:frame:InvalidSSBBWP');
    end
end
fprintf('SIB1_BWP_AUTHORITY_PASS scs=%g absent_full_native_match=1 explicit_guards=1\n', ...
    cfg.phy.carrier.SubcarrierSpacing);
end

function cfg=configuration(scs,folder)
if scs==15
    scenario=sixgr.lls6g.config.loadScenarioConfig( ...
        'simulator/configs/scenarios/lls_causal_access_to_data_wiring.yaml');
    cfg=sixgr.lls6g.buildInternalConfig(scenario,folder);
    coreset0=floor(double(cfg.phy.mib.pdcchConfigSIB1)/16);
    assert(coreset0==1,'The original 25-RB scenario must retain its legal two-RB CORESET offset.');
else
    cfg=sixgr.config.defaultConfig(); cfg.run.strictMode=true;
    cfg.phy.carrier.NSizeGrid=51; cfg.phy.carrier.NCellID=17;
    cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
    cfg.phy.channelBandwidth_MHz=20; cfg.frequency.bandwidth_hz=20e6;
    coreset0=0;
end
cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
cfg.phy.sib1.enable=true; cfg.phy.pdcch.enable=true;
cfg.phy.csirs.enable=false; cfg.phy.trs.enable=false;
cfg.initial_access.type0.monitoring_occasion_ordinal=3;
cfg.initial_access.sib1.pdsch=struct('prb_start',0,'num_prb',24, ...
    'symbol_start',2,'num_symbols',12,'mcs',0,'rv',0,'ptrs_enabled',false);
cfg.phy.sib1.coreset0Index=coreset0; cfg.phy.sib1.searchSpaceZero=2;
cfg.phy.mib.pdcchConfigSIB1=16*coreset0+2; cfg.phy.mib.dmrsTypeAPosition=2;
cfg.phy.ssb.periodicity_ms=40; cfg.phy.ssb.period_ms=40;
cfg.phy.ssb.runtimeSSBIndex=0;
timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
cfg.phy.ssb.activeBitmap=false(1,timing.Lmax); cfg.phy.ssb.activeBitmap(1)=true;
cfg.phy.ssb.activeCandidateIndices0Based=0;
cfg.phy.sib1.transmissionScope="selected_ssb_occasion";
cfg.integration.run_mode="FIXED_SNR_SWEEP";
cfg.integration.configured_snr_is_link_authority=true;
cfg.integration.power_reference_mode="normalized_unit_es";
cfg.rf.pa.enable=false;
end

function out=observation(samples,first,fs)
out=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),fs,size(samples,2));
out.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
end

function reject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:SIB1CalendarMissingGuard','Expected %s.',id);
end

function releaseLedger(owned)
if owned, sixgr.runtime.RuntimeCallLedger.reset(); end
end
