function ok=testPeriodicCSIReportObligations()
% Resolved configuration and receiver schemas; no CSI RF execution claim.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmpi(which('sixgr.truth.buildPeriodicCSIReportObligations'), ...
    fullfile(root,'+sixgr','+truth','buildPeriodicCSIReportObligations.m')));
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.csi.reportOffsetSlots==3,'Production TDD CSI must use its configured UL report offset.');
alternative=cfg; % Current production calendar.
cfg.phy.csi.reportOffsetSlots=1; % Explicit historical regression input.
id=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
[nominal,contexts]=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,1,58);
assert(isequal(nominal.ReportSlot,(2:5:57).') && ~any(nominal.ULResourceAvailable));
assert(all(nominal.ResourceBlocker=="configured_CSI_symbols_not_UL_on_nominal_report_slot") && ...
    numel(unique(nominal.ObligationID))==height(nominal));
assert(all(cellfun(@(x)isa(x,'sixgr.phy.pucch.UCIReportContext') && ...
    x.HARQACKBits==0 && x.SRBits==0 && x.CSIPart1Bits>0,contexts)));
% Compare the historical unavailable occasions with the production calendar.
[legal,~]=sixgr.truth.buildPeriodicCSIReportObligations(alternative,ue,1,58);
assert(isequal(legal.ReportSlot,(4:5:54).') && all(legal.ULResourceAvailable) && ...
    all(legal.ResourceBlocker==""));
% No measurement source-slot or transmitted bits enter receiver identity.
snapshot=nominal;
[again,againContexts]=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,1,58);
assert(isequaln(snapshot,again) && all(cellfun(@(a,b)a.Digest==b.Digest,contexts,againContexts)));
empty=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,3,3);
assert(isempty(empty));
badUE=ue; badUE.ExpectedBits=int8([1;0]);
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(cfg,badUE,1,58), ...
    'sixgr:truth:InvalidCSIReportingIdentity');
badUE=ue; badUE.ActiveULBWP=ue.ActiveULBWP+1;
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(cfg,badUE,1,58), ...
    'sixgr:truth:CSIReportingCalendarBWPMismatch');
for invalid={1.5,NaN,Inf,0,-1,'2',1+1i}
    reject(@()sixgr.truth.CoupledTruthRuntime.isCSIReportOccasionRuntime(cfg,invalid{1},'DL'), ...
        'sixgr:truth:InvalidCSIReportSourceSlot');
end
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,5,4), ...
    'sixgr:truth:InvalidCSIReportSlot');
bad=cfg; bad.phy.csi.reportOffsetSlots=.5;
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(bad,ue,1,58), ...
    'sixgr:truth:InvalidCSIReportTiming');
bad=cfg; bad.validation.pucch_resources.csi_resource_ids=[10 10];
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(bad,ue,1,58), ...
    'sixgr:truth:UnresolvedCSIReportingResource');
logsRoot=fullfile(root,'logs');
if ~isfolder(logsRoot), mkdir(logsRoot); end
folder=tempname(logsRoot); mkdir(folder);
writetable(nominal,fullfile(folder,'historical_offset1_CSI_obligations.csv'));
writetable(legal,fullfile(folder,'production_offset3_CSI_obligations.csv'));
save(fullfile(folder,'configured_obligations.mat'),'cfg','ue','nominal','contexts','alternative','legal');
fprintf('PERIODIC_CSI_OBLIGATIONS_PASS historical_nominal_unavailable=12 production_available=11 no_shift=1 RF_executions=0 folder=%s\n',folder);
ok=true;
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
