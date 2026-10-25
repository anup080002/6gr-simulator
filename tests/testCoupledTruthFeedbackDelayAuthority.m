function ok = testCoupledTruthFeedbackDelayAuthority()
%TESTCOUPLEDTRUTHFEEDBACKDELAYAUTHORITY No hidden CSI-delay clamp exists.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, ...
    "phy.linkAdaptation.feedbackDelaySlots", 1);
cfg = sixgr.util.structSet(cfg, "phy.csi.feedbackDelaySlots", 1);
assert(sixgr.truth.CoupledTruthRuntime.resolveConfiguredCSIFeedbackSlots(cfg) == 1, ...
    "Coupled truth must honor the exact YAML-derived one-slot CSI delay.");

cfg = sixgr.util.structSet(cfg, ...
    "phy.linkAdaptation.feedbackDelaySlots", 7);
cfg = sixgr.util.structSet(cfg, "phy.csi.feedbackDelaySlots", 7);
assert(sixgr.truth.CoupledTruthRuntime.resolveConfiguredCSIFeedbackSlots(cfg) == 7, ...
    "Coupled truth must not replace an explicit CSI delay with a constant.");

cfg = sixgr.util.structSet(cfg, "phy.csi.feedbackDelaySlots", 6);
localAssertError(@()sixgr.truth.CoupledTruthRuntime.resolveConfiguredCSIFeedbackSlots(cfg), ...
    "sixgr:link:FeedbackDelayAuthorityMismatch");
localGenericEnqueueDelay();
ok = true;
end

function localGenericEnqueueDelay()
% Declared measurement/slot inputs to the actual queue reducer. This is NOT
% received CSI, a periodic report obligation, waveform delivery or access.
repo=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(repo,'results','validation');
if ~isfolder(folder), mkdir(folder); end
folder=tempname(folder); mkdir(folder);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(repo,'simulator','configs', ...
    'scenarios','lls_pusch_csi_delivery_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder);
assert(cfg.phy.linkAdaptation.feedbackDelaySlots==7 && cfg.phy.csi.feedbackDelaySlots==7);
beforeRNG=rng; restore=onCleanup(@()rng(beforeRNG)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
multi=sixgr.truth.resolveMultiUserSpec(cfg);
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),20);
state.CurrentServingIdx(:)=1; % Declared reducer-only serving identity.
assert(state.CSIFeedbackSlots==7 && ...
    isempty(sixgr.util.structGet(state,'SharedWaveformStream',[])));
id=cfg.phy.frame.DefaultIdentity;
rnti=sixgr.truth.CoupledRadioIdentity.resolve(state,1);
ue=struct('UEID',1,'RNTI',rnti,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
authority=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,rnti,NaN,'csi');
resource=rrc.resourceByID(authority.ResourceId);
controlSymbols=resource.Data.StartSymbol+(0:resource.Data.NumSymbols-1);
reports=table();
for sourceSlot=[3 6]
    declared=table(sourceSlot,10,8.5,1,0,0,true, ...
        "receiver_post_equalization_sinr", ...
        "measured_post_equalization_scheduling_input","OK", ...
        'VariableNames',{'Slot','WidebandCQI','SINR_dB','RIEstimate','PMI','CRI', ...
        'CRCPass','SINRSource','SINRValueRole','SINRValueStatus'});
    requested=sourceSlot+7;
    % Independently enumerate the configured physical UL symbol calendar;
    % never call the private due-slot resolver to manufacture the expectation.
    candidates=requested:requested+10;
    legal=false(size(candidates));
    for k=1:numel(candidates)
        [~,allowUL,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,candidates(k));
        span=partition.ULSymbolAllocation;
        legal(k)=allowUL && all(ismember(controlSymbols,span(1)+(0:span(2)-1)));
    end
    expectedDL=candidates(find(legal,1));
    assert(isscalar(expectedDL));
    if sourceSlot==3, assert(expectedDL==10); else, assert(expectedDL==14); end
    for direction=["DL","UL"]
        input=state; input.CurrentSlot=sourceSlot; input.CurrentCanonicalSlot=sourceSlot;
        result=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
            input,1,direction,declared,cfg,table());
        report=result.PendingCSITable;
        expected=requested; if direction=="DL", expected=expectedDL; end
        assert(height(report)==1 && report.SourceSlot==sourceSlot && ...
            report.EnqueuedSlot==sourceSlot && report.DueSlot==expected && ...
            isnan(report.CSIReferenceSlot) && ~report.Processed && ~report.CSIUCIDecodeOk && ...
            string(report.ReportIdentity)==direction+"_UE1_SRC"+string(sourceSlot)+"_DUE"+string(expected) && ...
            ~startsWith(string(report.ReportIdentity),"periodic_csi_"));
        assert(isequaln(result.LatestDLFeedback,input.LatestDLFeedback) && ...
            isequaln(result.LatestULFeedback,input.LatestULFeedback) && ...
            isempty(result.PUCCHGrantTraceTable) && ...
            isempty(sixgr.util.structGet(result,'CSIReportObligationTable',table())) && ...
            isequaln(result.ControlTrials,input.ControlTrials), ...
            'Metadata enqueue must not invent configured periodic obligations, PHY execution or decoded feedback.');
        reports=[reports;report]; %#ok<AGROW>
    end
end
scope="declared_metadata_only_generic_enqueue_delay_no_RF_no_periodic_delivery";
save(fullfile(folder,'generic_CSI_enqueue_delay_metadata.mat'),'scope','cfg','reports');
fprintf('GENERIC_CSI_ENQUEUE_DELAY_METADATA_PASS delay=7 DL_due=10,14 UL_due=10,13 RF_executions=0 folder=%s\n',folder);
end

function localAssertError(fcn, expectedIdentifier)
threw = false;
try
    fcn();
catch ME
    threw = true;
    assert(strcmp(ME.identifier, expectedIdentifier), ...
        "Expected %s, received %s.", expectedIdentifier, ME.identifier);
end
assert(threw, "Expected error %s was not raised.", expectedIdentifier);
end
