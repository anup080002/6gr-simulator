function [ok,result]=testFourSSBPRACHMappedPreambles(cbOffset0)
% Four/16 partition -> actual native B4 Msg1 -> received RAPID -> coded RAR.
% SIB1 semantics, validity and delivery receipts are DECLARED boundaries.
% Each case is a separate one-port, noiseless unit-channel observation:
% no SSB/SIB1 reception, shared RF/channel, simultaneous UEs, Msg3 or access.
if nargin==0, cbOffset0=0; end
validateattributes(cbOffset0,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',15});
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
previous=rng; cleanup=onCleanup(@()rng(previous)); %#ok<NASGU>
rng(251025,'twister');
parent=fullfile(pwd,'results','validation','four_ssb_prach_mapped_preambles');
sixgr.util.ensureFolder(parent);
folder=tempname(parent); sixgr.util.ensureFolder(folder);
fprintf('FOUR_SSB_PRACH_MAPPED_PREAMBLES_EVIDENCE %s\n',folder);

cfg=localConfiguration();
cfg.random_access.cb_preamble_selection_policy='fixed_partition_offset';
cfg.random_access.cb_preamble_offset=cbOffset0;
choice=sixgr.mac.ra.resolveCBPreambleOffset(cfg.random_access,1,16);
assert(choice.Offset0==cbOffset0 && ~choice.NormativeUniformRandomSelection);
ssbTiming=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
assert(ssbTiming.Case=="C" && ssbTiming.Lmax==8 && ...
    ssbTiming.BandAwareResolution.BandContext=="n40" && ...
    ssbTiming.BandAwareResolution.Spectrum=="unpaired" && ...
    isequal(find(char(cfg.phy.ssb.activeBitmap)=='1')-1,0:3), ...
    'The declared component radio must retain n40 unpaired Case C and four active SSBs.');
commonPlan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
commonPlan.validateSIB1References();
siCalendar=commonPlan.sib1TransmissionOccasions(0,80);
assert(isequal(siCalendar.SSBIndex,(0:3).') && ...
    isequal(siCalendar.AbsoluteSlot,(50:53).') && all(siCalendar.PeriodSlots==40), ...
    'Use the legal four-beam Type0 calendar, not the old single-beam slot41 anchor.');
native=sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
    'FrequencyRange','FR1','DuplexMode','TDD','ConfigurationIndex',157, ...
    'CarrierSubcarrierSpacingKHz',30,'CarrierCyclicPrefix','normal', ...
    'NSizeGrid',51,'NStartGrid',cfg.phy.carrier.NStartGrid, ...
    'NCellID',cfg.phy.carrier.NCellID,'PRACHSubcarrierSpacingKHz',30, ...
    'SequenceIndex',cfg.random_access.root_sequence_index, ...
    'PreambleIndex',0,'RestrictedSet',cfg.random_access.restricted_set, ...
    'ZeroCorrelationZone',cfg.random_access.zero_correlation_zone, ...
    'Msg1FDM',1,'Msg1FrequencyStart',0);
assert(native.Format=="B4" && native.CarrierSubcarrierSpacingKHz==30);
% These are declared received semantic operands, not an executed UPER or
% BCH/SIB1 receiver. The integer CHOICE arm is canonical decimal text.
declaredSI=struct('ssbPerRACHChoice',"four",'cbPreamblesPerSSB',"16", ...
    'nPreambles',64,'activeSSBIndices0',0:3);
% Restrict this component to original native supports wholly inside its
% declared common-UL map. Do not treat the other B4 half-slot as valid or
% discard it from the native table (which would change ordinal identity).
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
declaredValidity=false(height(native.Occasions),1);
for n=1:height(native.Occasions)
    o=native.Occasions(n,:); valid=true;
    for symbol=o.StartSymbol:(o.StartSymbol+o.DurationSymbols-1)
        valid=valid && frame.IsULAllocation(o.AbsoluteSlot+floor(symbol/frame.SymbolsPerSlot), ...
            [mod(symbol,frame.SymbolsPerSlot),1]);
    end
    declaredValidity(n)=valid;
end
assert(any(declaredValidity),'Require an actual native full-common-UL occasion.');
association=sixgr.mac.ra.resolveSSBPRACHAssociation(native, ...
    declaredSI.activeSSBIndices0,4,str2double(declaredSI.cbPreamblesPerSSB), ...
    declaredSI.nPreambles,declaredValidity);
assert(association.SSBsPerRO==4 && association.CBPreamblesPerSSB==16 && ...
    association.TotalPreambles==64);
cfg.phy.prach.timing=native;
sourceRow=association.Mapping.SourceOccasionRow(1);
mapped=association.Mapping(association.Mapping.SourceOccasionRow==sourceRow & ...
    association.Mapping.ConfigurationPeriodIndex0==0,:);
mapped=sortrows(mapped,'SSBIndex0');
assert(height(mapped)==4 && isequal(mapped.SSBIndex0,(0:3).') && ...
    isequal(mapped.CBPreambleStart0,(0:16:48).') && ...
    all(mapped.CBPreambleCount==16) && numel(unique(mapped.Ordinal))==1);
save(fullfile(folder,'declared_boundaries_and_native_geometry.mat'), ...
    'cfg','native','declaredSI','declaredValidity','association','mapped','siCalendar');

rows=cell(4,1);
for k=1:4
    mapping=mapped(k,:); expected=double(mapping.CBPreambleStart0)+choice.Offset0;
    [caseCfg,preparationSlot]=localDeclaredAdmission(cfg,native,mapping,choice,declaredValidity);
    ra=sixgr.mac.ra.RAConfig(caseCfg,'RuntimeSlot',preparationSlot, ...
        'RunId',"four_ssb_partition_"+(k-1));
    assert(ra.PreambleIndex==expected && ra.PRACHOccasionOrdinal==mapping.Ordinal && ...
        ra.PRACHAbsoluteSlot==mapping.AbsoluteSlot && ...
        caseCfg.random_access.associated_ssb_index==mapping.SSBIndex0);
    assert(frame.IsULAllocation(ra.Msg3Slot,[ra.Msg3PUSCH.SymbolStart ra.Msg3PUSCH.NumSymbols]) && ...
        frame.IsDLAllocation(ra.Msg4Slot,[ra.Msg4PDSCH.SymbolStart ra.Msg4PDSCH.NumSymbols]) && ...
        frame.IsULAllocation(ra.SetupCompleteSlot, ...
            [ra.SetupCompletePUSCH.SymbolStart ra.SetupCompletePUSCH.NumSymbols]) && ...
        ra.SetupCompleteSlot==ra.Msg4Slot+2, ...
        'Retain legal downstream RA planning even though this test executes only Msg1/RAR.');
    [tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(caseCfg,ra);
    assert(tx.RARNTI==ra.RARNTI && tx.PRACHOccasionOrdinal==mapping.Ordinal);

    % The gNB searches its complete configured population. Remove the UE's
    % selected identity from both receiver inputs instead of aiding search.
    receiverCfg=caseCfg;
    receiverCfg=rmfield(receiverCfg,{'SharedRATimingBinding','SharedReceivedPRACHSelection'});
    receiverCfg.random_access=rmfield(receiverCfg.random_access, ...
        {'preamble_index','associated_ssb_index','associated_ssb_selection_source', ...
        'cb_preamble_selection_policy','cb_preamble_offset'});
    receiverPRACH=rmfield(tx.PRACHRuntimeConfig,'PreambleIndex');
    detected=sixgr.phy.ra.detectConfiguredPRACH(tx.Waveform,receiverCfg,receiverPRACH,occasion);
    assert(detected.Detected && detected.DetectedPreambleIndex==expected && ...
        isequal(detected.CandidatePreambles,(0:63).') && detected.CandidateCount==64 && ...
        ~isfield(detected,'RAPIDMatchesTx'));
    timing=sixgr.phy.ra.estimateTimingAdvanceFromPRACH( ...
        detected,tx.SampleRate_Hz,ra.CarrierSCSkHz);
    assert(timing.Valid);

    % Actual CRC-valid wrong RAPID must leave the UE waiting. A later
    % actual coded response carries the ORIGINAL detected RAPID. Neither
    % decoder receives the TX schedule, payload size, or transport bits.
    rarCfg=sixgr.phy.ra.localizeCarrierConfig(caseCfg,ra);
    monitor=sixgr.phy.ra.RARReceiveWindow(rarCfg,ra);
    assert(numel(monitor.Window.MonitoringSlots)>=2);
    receptions=cell(2,1); rarTransmissions=cell(2,1);
    for j=1:2
        scheduled=ra; scheduled.Msg2Slot=monitor.Window.MonitoringSlots(j);
        assert(commonPlan.checkPDSCH(scheduled.Msg2PDSCH,scheduled.Msg2Slot), ...
            'The actual RAR fixture must not occupy configured SSB/SI/reference resources.');
        assert(~any(siCalendar.AbsoluteSlot==scheduled.Msg2Slot), ...
            'Do not superpose the component Type1 control on scheduled SI.');
        grant=sixgr.mac.ra.buildRARULGrant(scheduled);
        rapid=detected.DetectedPreambleIndex;
        if j==1, rapid=mod(rapid+1,64); end
        mac=sixgr.mac.ra.encodeMACRAR('RAPID',rapid, ...
            'TimingAdvanceCommand',timing.TimingAdvanceCommand, ...
            'TemporaryCRNTI',ra.TempCRNTI,'ULGrant',grant);
        rarTX=sixgr.phy.ra.generateMsg2RARWaveform(rarCfg,scheduled,mac);
        info=nrOFDMInfo(rarTX.Carrier); fs=double(info.SampleRate);
        start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol( ...
            scheduled.Msg2Slot,0,monitor.Window.Numerology);
        tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
        assert(tc==fix(tc) && mod(start.Ticks,int64(tc))==0);
        first=double(idivide(start.Ticks,int64(tc),'fix'));
        observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
            first,first+size(rarTX.Waveform,1),fs,size(rarTX.Waveform,2));
        observation.append(sixgr.phy.waveform.WaveformChunk(rarTX.Waveform,first),fs);
        [monitor,outcome]=monitor.receive(scheduled.Msg2Slot,observation,rarCfg);
        assert(outcome.Observation.DCICrcPass && outcome.Observation.PDSCHCrcPass);
        if j==1
            assert(~outcome.Accepted && ~outcome.Observation.RAPIDMatches && ...
                monitor.Status=="waiting" && outcome.Observation.Result=="rapid_mismatch");
        else
            assert(outcome.Accepted && outcome.Observation.RAPIDMatches && ...
                monitor.Status=="matched" && outcome.RAR.RAPID==expected && ...
                outcome.RAR.TimingAdvanceCommand==timing.TimingAdvanceCommand && ...
                outcome.Receiver.PDCCHReceiver.CausalGrantDecodeOk);
        end
        receptions{j}=outcome; rarTransmissions{j}=rarTX;
    end
    assert(all(~monitor.Observations.ProxyUsed & ~monitor.Observations.FallbackUsed));
    rows{k}=struct('SSBIndex0',mapping.SSBIndex0,'CBPreambleStart0',mapping.CBPreambleStart0, ...
        'CBPreambleOffset0',choice.Offset0, ...
        'CBPreambleCount',mapping.CBPreambleCount,'PreambleIndexTx',ra.PreambleIndex, ...
        'PreambleIndexDetected',detected.DetectedPreambleIndex, ...
        'RARNTI',ra.RARNTI,'NativeOccasionOrdinal',ra.PRACHOccasionOrdinal, ...
        'WrongRAPIDRejected',~receptions{1}.Accepted, ...
        'MatchingRAPIDAccepted',receptions{2}.Accepted);
    save(fullfile(folder,sprintf('actual_partition_%d.mat',k-1)), ...
        'caseCfg','ra','mapping','tx','occasion','receiverCfg','receiverPRACH', ...
        'detected','timing','rarTransmissions','receptions','monitor');
end
records=vertcat(rows{:});
assert(isequal([records.PreambleIndexDetected],[0 16 32 48]+choice.Offset0) && ...
    isequal([records.CBPreambleStart0],[0 16 32 48]) && ...
    numel(unique([records.RARNTI]))==1 && numel(unique([records.NativeOccasionOrdinal]))==1, ...
    'Selected preamble offsets cannot change native RO or RA-RNTI identity.');
result=struct('Scope',"declared_four_16_association_native_B4_and_coded_RAR_unit_channel", ...
    'CBPreambleChoice',choice,'RuntimeBinderExecuted',false, ...
    'DeclaredSIB1AndValidityBoundary',true,'NativePRACHTXCount',4, ...
    'PRACHReceiverCalls',4,'CodedRARTXCount',8,'RARReceiverCalls',8, ...
    'SharedRFExecuted',false,'SSBSIB1ReceptionExecuted',false, ...
    'Msg3OrFullAccessExecuted',false,'EvidenceFolder',string(folder),'Cases',records);
save(fullfile(folder,'result.mat'),'result');
ok=true;
fprintf('FOUR_SSB_PRACH_MAPPED_PREAMBLES_PASS native_B4=4 offset=%d detected=%d,%d,%d,%d coded_RAR=8 declared_SI=1 shared_RF=0 full_access=0\n', ...
    choice.Offset0,records.PreambleIndexDetected);
end

function cfg=localConfiguration()
cfg=raStrictAnchorConfig();
cfg.scenario.name="four_ssb_mapped_preambles_component";
cfg.frequency.band_name="n40"; cfg.frequency.center_frequency_hz=2.35e9;
% Frame resolution ignores disabled initial-access defaults. Supply the
% actual carrier's unpaired context too; frequency alone would select its
% paired-spectrum compatibility branch and the wrong Case-C Lmax domain.
cfg.frequency.band_context="n40"; cfg.frequency.spectrum="unpaired";
cfg.initial_access.band_context="n40"; cfg.initial_access.spectrum="unpaired";
cfg.phy.duplex.mode="TDD";
cfg.channel.fc_Hz=2.35e9; cfg.phy.fc_Hz=2.35e9;
cfg.phy.carrier.centerFrequency_Hz=2.35e9;
cfg.phy.ssb.blockPattern="Case C"; cfg.phy.ssb.scs_kHz=30; cfg.phy.ssb.Lmax=8;
cfg.phy.ssb.activeBitmap="11110000";
% Legal n40-style common direction map: three DL slots, ten DL/two UL
% symbols in the special slot, then one UL slot at mu=1 (2.5 ms).
cfg.phy.duplex.tddCommon.ReferenceSubcarrierSpacingKHz=30;
cfg.phy.duplex.tddCommon.Pattern1=struct('PeriodicityMilliseconds',2.5, ...
    'NumDownlinkSlots',3,'NumDownlinkSymbols',10, ...
    'NumUplinkSlots',1,'NumUplinkSymbols',2);
% Table13-11 index4 puts the first four associations at10..13, away from
% native Case-C SSBs. This declared component selects ordinal3 (50..53)
% so its isolated RAR samples at the earlier Type1 opportunities also have
% no configured SI collision. No earlier SI reception is claimed here.
cfg.phy.mib.pdcchConfigSIB1=4;
cfg.phy.sib1.coreset0Index=0; cfg.phy.sib1.searchSpaceZero=4;
cfg.phy.sib1.transmissionScope="all_active_ssb_occasions";
cfg.initial_access.type0=struct('monitoring_occasion_ordinal',3);
cfg.initial_access.sib1.pdsch=struct('prb_start',0,'num_prb',24, ...
    'symbol_start',2,'num_symbols',7,'mcs',2,'rv',0);
% A scalar configured mapping is expanded to every candidate. This is NOT
% four independently measured/spatially resolved beams or a 64-TXRU test.
cfg.phy.ssb.precoderMatrices=1;
cfg.phy.ssb.precoderIDs="declared_single_port_reference";
cfg.rrc.sib1.ssb_per_rach_choice="four";
cfg.rrc.sib1.cb_preambles_per_ssb="16";
cfg.random_access.prach_format="B4";
cfg.random_access.configuration_index=157;
cfg.random_access.subcarrier_spacing_khz=30;
cfg.random_access.preamble_index=7; % Must be replaced by admitted partition.
cfg.random_access.preamble_detection_policy="strongest";
% In the five-slot map, full-DL slot2 can reach full-UL slot4 with K2=2;
% the inherited K2=1 has no full-DL -> full-UL pair in this pattern.
cfg.random_access.timing.setup_complete_k2_slots=2;
cfg.lls6g.userContext.RuntimeServingCell=1;
end

function [cfg,prep]=localDeclaredAdmission(cfg,native,m,choice,validityMask)
row=native.Occasions(m.SourceOccasionRow,:);
assert(m.ConfigurationPeriodIndex0==0 && choice.ReceivedCBPreambleCount==m.CBPreambleCount && ...
    choice.Offset0>=0 && choice.Offset0<m.CBPreambleCount);
expected=double(m.CBPreambleStart0)+choice.Offset0;
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology( ...
    struct('SCSKHz',30,'CyclicPrefix',"normal"));
time=sixgr.phy.frame.AbsoluteTime(row.PRACHWaveformStartTicks);
[~,frame,slot]=time.floorToSlot(spec);
prep=double(frame)*spec.SlotsPerFrame+double(slot);
assert(prep>=1,'Require an original native occasion with a causal preparation slot.');
s=struct('Available',true,'SelectedSSBIndex0',m.SSBIndex0,'PreambleIndex0',expected, ...
    'SelectedSSBReferenceSHA256',string(repmat('a',1,64)), ...
    'SIB1TreeSHA256',string(repmat('b',1,64)), ...
    'SelectedNativeOccasion',row,'SelectedAssociationRow',m, ...
    'NativePeriodIndex0',0,'PRACHOccasionOrdinal',row.Ordinal);
t=struct('BindingSHA256',s.SelectedSSBReferenceSHA256, ...
    'AcquisitionGenerationID',"declared_not_received_generation",'SSBIndex',m.SSBIndex0, ...
    'OriginalBCHBinding',struct('UEIndex',1,'ServingCell',1));
v=struct('SIB1TreeSHA256',s.SIB1TreeSHA256,'NativeResolutionSHA256',localEvidenceHash(native), ...
    'MIBContextSHA256',string(repmat('c',1,64)), ...
    'RepeatedValidity',validityMask);
s.ValiditySHA256=localEvidenceHash(v); s.NativeResolutionSHA256=localEvidenceHash(native);
s.MIBContextSHA256=v.MIBContextSHA256;
cfg.random_access.associated_ssb_index=m.SSBIndex0;
cfg.random_access.associated_ssb_selection_source="declared_four_16_component_boundary";
% Mirror the common-DL association owner at this declared selection
% boundary; do not leave later cases transmitting on the old SSB0 mapping.
cfg.phy.ssb.runtimeSSBIndex=m.SSBIndex0;
cfg.SharedRATimingBinding=t;
r=struct('ContractVersion',"received_prach_attempt/v1",'UEIndex',1,'ServingCell',1, ...
    'AcquisitionGenerationID',t.AcquisitionGenerationID, ...
    'SelectedSSBTimingBindingSHA256',t.BindingSHA256,'SIB1TreeSHA256',s.SIB1TreeSHA256, ...
    'PreparationSlot',prep,'NativeResolution',native,'Validity',v,'Selection',s, ...
    'CBPreambleChoice',choice);
r.SHA256=localHash(r); cfg.SharedReceivedPRACHSelection=r;
end

function h=localHash(value)
h=sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(jsonencode(value),'UTF-8')));
end

function h=localEvidenceHash(value)
% Match the original decoded-input producer's table-safe wire contract;
% the enclosing attempt receipt deliberately retains its separate seal.
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
