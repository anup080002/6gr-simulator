function ok=testConfiguredSRCalendar()
% Configured opportunities and receiver schema only, not MAC or RF qualification.
root=fileparts(fileparts(mfilename('fullpath')));
logsRoot=fullfile(root,'logs','tdd_configured_sr_calendar');
if ~isfolder(logsRoot), mkdir(logsRoot); end
outputFolder=tempname(logsRoot); mkdir(outputFolder);
fprintf('TDD_CONFIGURED_SR_CALENDAR_ARTIFACT_ROOT=%s\n',outputFolder);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,'simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,outputFolder);
id=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
reject(@()sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,58), ...
    'sixgr:truth:MissingInstalledSRCalendar');
fprintf('SR_BASELINE_MISSING_CALENDAR_REPRODUCED\n');
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_configured_sr_calendar_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,outputFolder);
catalog=cfg.phy.pucch.srPeriodCatalog;
fixture=cfg.validation.pucch_resources;
localSaveEvidence(s,cfg,root,outputFolder);
legal=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,58);
assert(isequal(legal.Slot,(4:5:54).') && all(legal.ULResourceAvailable));
assert(all(legal.StartSymbol==12 & legal.NumSymbols==2) && all(legal.ResourceBlocker==""));
assert(all(legal.EvidenceClass=="configured_SR_opportunity_not_transmission_or_reception"));
assert(isequaln(legal,sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,58)));
assert(isempty(sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,3)));
bad=cfg; bad.validation.pucch_resources.scheduling_request_resources.offset_slots=1;
blocked=sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58);
assert(isequal(blocked.Slot,(2:5:57).') && ~any(blocked.ULResourceAvailable));
assert(all(blocked.ResourceBlocker=="configured_SR_symbols_not_UL_on_nominal_slot"));
assert(isempty(intersect(legal.ObligationID,blocked.ObligationID)));
badUE=ue; badUE.PendingPositiveSR=true;
reject(@()sixgr.truth.buildConfiguredSRCalendar(cfg,badUE,1,58),'sixgr:truth:InvalidSRReceiverIdentity');
badUE=ue; badUE.ActiveULBWP=ue.ActiveULBWP+1;
reject(@()sixgr.truth.buildConfiguredSRCalendar(cfg,badUE,1,58),'sixgr:truth:SRCalendarBWPMismatch');
bad=cfg; bad.validation.pucch_resources.scheduling_request_resources.PendingPositiveSR=true;
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:InvalidInstalledSRCalendar');
bad=cfg; bad.validation.pucch_resources.scheduling_request_resources.periodicity_slots=3;
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:InvalidInstalledSRCalendar');
bad.validation.pucch_resources.scheduling_request_resources.offset_slots=0;
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:UnsupportedSRPeriod');
bad=cfg; bad.validation.pucch_resources.scheduling_request_resources.resource_id=10;
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:UninstalledSRResource');
bad.validation.pucch_resources.sr_resource_ids=10;
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:InvalidSRResourceFormat');
bad=cfg; bad.validation.pucch_resources.sr_resource_ids=[];
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:UninstalledSRResource');
bad.validation.pucch_resources.scheduling_request_resources=struct([]);
none=sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58);
assert(isempty(none) && isequal(none.Properties.VariableNames,legal.Properties.VariableNames));
bad=cfg; bad.validation.pucch_resources.scheduling_request_resources=repmat(fixture.scheduling_request_resources,2,1);
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:DuplicateSRResourceConfiguration');
reject(@()sixgr.truth.buildConfiguredSRCalendar(cfg,ue,2,1),'sixgr:truth:InvalidSRCalendarRange');

bad=cfg; bad.phy.pucch=rmfield(bad.phy.pucch,'srPeriodCatalog');
reject(@()sixgr.truth.buildConfiguredSRCalendar(bad,ue,1,58),'sixgr:truth:MissingSRPeriodCatalog');
badUE=ue; badUE.PUCCHCell=ue.ServingCell+1;
reject(@()sixgr.truth.buildConfiguredSRCalendar(cfg,badUE,1,58),'sixgr:truth:SRCalendarCellMismatch');
% Installed standards table checked independently, without pretending to
% execute higher-numerology PHY by mutating the 15-kHz frame.
assert(isequal([catalog.periods_by_scs.scs_khz],[15 30 60 120 480 960]));
expectedPeriods={ [1 2 4 5 8 10 16 20 40 80], ...
    [1 2 4 5 8 10 16 20 40 80 160], ...
    [1 2 4 8 16 20 40 80 160 320], ...
    [1 2 4 5 8 10 16 40 80 160 320 640], ...
    [1 2 4 8 16 40 80 160 320 640 1280 2560], ...
    [1 2 4 8 16 40 80 160 320 640 1280 2560 5120] };
additional={[],5,[],[5 10],[],[]};
for k=1:numel(expectedPeriods)
    assert(isequal(double(catalog.periods_by_scs(k).allowed_slot_periods(:).'),expectedPeriods{k}));
    % Apply the same vector convention to both sides. For an empty list,
    % (:).' is 1-by-0 whereas the literal [] above is 0-by-0; isequal checks
    % dimensions as well as values. Keep every expected period unchanged.
    observedAdditional=double(catalog.periods_by_scs(k).additional_capability_slot_periods(:).');
    expectedAdditional=double(additional{k}(:).');
    assert(isequal(observedAdditional,expectedAdditional), ...
        'test:SRAdditionalCapabilityMismatch', ...
        'Additional-capability SR periods differ at %g kHz: expected %s, observed %s.', ...
        catalog.periods_by_scs(k).scs_khz,mat2str(expectedAdditional),mat2str(observedAdditional));
end

% Explicit algebraic overlap tables, not additional installed/RF resources.
counts=zeros(9,2);
for k=0:8
    rows=legal(ones(k,1),:);
    rows.SRResourceConfigurationID=(k:-1:1).';
    rows.SchedulingRequestID=(k-1:-1:0).';
    rows.ObligationID="declared_overlap_fixture_"+rows.SRResourceConfigurationID;
    for format=[2 3 4]
        overlap=sixgr.truth.resolveLongPUCCHSROverlap(rows,4,12,2,0,format);
        assert(overlap.OpportunityCount==k && overlap.EncodedBitCount==ceil(log2(k+1)));
        assert(isequal(overlap.SRResourceConfigurationIDs,(1:k).'));
    end
    counts(k+1,:)=[k overlap.EncodedBitCount];
end
assert(sixgr.truth.resolveLongPUCCHSROverlap(legal,4,10,2,0,2).OpportunityCount==0);
assert(sixgr.truth.resolveLongPUCCHSROverlap(legal,4,11,2,0,2).OpportunityCount==1);
assert(sixgr.truth.resolveLongPUCCHSROverlap(legal,4,12,2,1,2).OpportunityCount==0);
assert(sixgr.truth.resolveLongPUCCHSROverlap(blocked,2,12,2,0,2).OpportunityCount==0);
reject(@()sixgr.truth.resolveLongPUCCHSROverlap(legal,4,12,2,0,0),'sixgr:truth:UnsupportedSRMultiplexFormat');
duplicate=legal([1 1],:);
reject(@()sixgr.truth.resolveLongPUCCHSROverlap(duplicate,4,12,2,0,2),'sixgr:truth:DuplicateSRResourceConfiguration');
mixed=legal; mixed.UEIndex(2)=2;
reject(@()sixgr.truth.resolveLongPUCCHSROverlap(mixed,4,12,2,0,2),'sixgr:truth:MixedSRReceiverIdentity');

% Feed only configuration-derived SR bit count to the production RX schema.
csi=sixgr.phy.mimo.CSIReportConfiguration(cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfigurationEpoch);
overlap=sixgr.truth.resolveLongPUCCHSROverlap(legal,4,12,2,0,2);
obligation=struct('ObservationID',"configured_sr_csi_component", ...
    'ConfigurationEpoch',legal.PUCCHConfigurationEpoch(1),'HARQBitCount',2, ...
    'SRBitCount',overlap.EncodedBitCount,'PriorityIndex',0, ...
    'CSIReportConfigID',csi.ReportConfigID,'CSIConfigurationEpoch',csi.Epoch);
context=sixgr.truth.buildConfiguredPUCCHReceiveContext(obligation,csi);
assert(context.HARQACKBits==2 && context.SRBits==1 && context.CSIPart1Bits==csi.part1BitCount());
assert(context.Sequence1Length==3+csi.part1BitCount());
% Structural caller guard only; the calendar/overlap tests above do not
% constitute a transmitted-HARQ normal-coordinator RF test.
source=fileread(fullfile(root,'+sixgr','+truth','CoupledTruthRuntime.m'));
caller=extractBetween(string(source),'function state=prepareSharedPUCCHFeedbackRuntime(state,item)', ...
    'function state=completeSharedPUCCHFeedbackRuntime(state,item)');
assert(isscalar(caller) && contains(caller,'execution.GNBReception=sixgr.truth.buildScheduledPUCCHHARQReception(') && ...
    ~contains(caller,"isempty(sixgr.util.structGet(cfg,'validation.pucch_resources.sr_resource_ids'"));
writetable(legal,fullfile(outputFolder,'configured_SR_opportunities.csv'));
writetable(blocked,fullfile(outputFolder,'blocked_nominal_SR_opportunities.csv'));
writetable(array2table(counts,'VariableNames',{'K','EncodedSRBits'}),fullfile(outputFolder,'algebraic_overlap_counts.csv'));
save(fullfile(outputFolder,'configured_sr_calendar.mat'),'cfg','ue','catalog','legal','blocked','counts','context');
fprintf('CONFIGURED_SR_CALENDAR_PASS available=11 blocked_nominal=12 K_range=0:8 RX_schema=HARQ_SR_CSI RF_executions=0 MAC_lifecycle_qualified=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end

function localSaveEvidence(s,cfg,root,outputFolder)
meta=fullfile(outputFolder,'meta'); mkdir(meta);
inputs=fullfile(meta,'input_configs'); mkdir(inputs);
for k=1:numel(s.SourceFiles)
    [~,name,ext]=fileparts(s.SourceFiles(k));
    copyfile(s.SourceFiles(k),fullfile(inputs,sprintf('%03d_%s%s',k,name,ext)));
end
copyfile(fullfile(root,'simulator','configs','control','scheduling_request_periods_r18.yaml'),inputs);
sixgr.util.jsonWrite(fullfile(meta,'resolved_config.json'),s.toStruct());
sixgr.lls6g.config.writeYAML(fullfile(meta,'resolved_config.yaml'),s.toStruct());
sixgr.util.jsonWrite(fullfile(meta,'installed_sr_period_catalog.json'),cfg.phy.pucch.srPeriodCatalog);
sixgr.util.jsonWrite(fullfile(meta,'schema_validation_report.json'),struct( ...
    'Passed',true,'Validator','loadScenarioConfig/validateScenarioConfig','ConfigHash',s.ConfigHash));
[status,revision]=system('git rev-parse HEAD'); assert(status==0);
[status,changes]=system('git status --porcelain'); assert(status==0);
sixgr.util.jsonWrite(fullfile(meta,'environment_summary.json'),struct( ...
    'MATLABVersion',version,'Platform',computer,'Toolboxes',ver,'GitHash',strtrim(revision), ...
    'WorktreeStatus',changes,'Scope','TDD configured SR calendar and algebraic RX schema; no MAC lifecycle or RF qualification'));
sixgr.util.jsonWrite(fullfile(meta,'seeds.json'),struct('RunSeed',cfg.run.seed));
end
