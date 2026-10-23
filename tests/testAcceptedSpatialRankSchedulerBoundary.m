function [ok, checks] = testAcceptedSpatialRankSchedulerBoundary(outputRoot)
% Declared accepted-feedback -> exact MAC planning boundary, not a radio run.
% Type-I bits use the real codec; SRS uses the real capsule constructor.
% Neither creates an independently received waveform, access/admission,
% accepted DCI, a HARQ attempt, or a measured optimal-rank reference.
% A queue/resource policy may lower MCS or defer a grant. It cannot silently
% reinterpret a retained rank-specific PMI/TPMI at another rank without an
% independently qualified replacement spatial decision.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
assert(cfg.phy.pdsch.maxLayers==4 && cfg.phy.pusch.maxLayers==4 && ...
    cfg.phy.pusch.NumAntennaPorts==4);
if nargin<1 || strlength(string(outputRoot))==0
    root=fileparts(fileparts(mfilename('fullpath')));
    outputRoot=tempname(fullfile(root,'logs'));
end
outputRoot=char(string(outputRoot));
assert(~isfolder(outputRoot),'test:AcceptedSpatialOutputExists', ...
    'Use a fresh directory; do not overwrite an earlier diagnostic.');
mkdir(outputRoot);
prototype=struct('Scheduler',"",'Direction',"",'Policy',"", ...
    'ReportedRank',NaN,'OfferedBytes',NaN,'AvailablePRBs',NaN, ...
    'AMCInitialRank',NaN,'AMCExistingRankBound',false,'AMCSpatialRankTupleBound',false,'PlanValid',false, ...
    'PlannedRank',NaN,'PlannedMCS',NaN,'PlannedPRBs',NaN,'TBSBits',NaN, ...
    'LayerReductionSteps',NaN,'AtomicSpatialTupleRetained',false, ...
    'Passed',false,'FailureID',"",'Detail',"", ...
    'EvidenceScope',"declared_accepted_spatial_planning_boundary_no_waveform");
rows=repmat(prototype,0,1); evidence=cell(0,1);
for kind=["PF","RR"]
    for direction=["DL","UL"]
        for rankValue=[2 4]
            ue=localDeclaredUE(cfg,direction,rankValue);
            for policy=["explicit_queue_aware","automatic_small_prb"]
                current=cfg;
                % Explicit adversarial scheduler-policy inputs, not changes
                % to a physical fixture or to reported rank/PMI/quality.
                current.phy.linkAdaptation.queueAwareRankMCSReductionEnable= ...
                    policy=="explicit_queue_aware";
                current.phy.linkAdaptation.queueAwareLayerDecrementMax=1;
                current.phy.linkAdaptation.queueAwareMCSDecrementMax=2;
                current.phy.linkAdaptation.minPRBForWidebandCQIGrant=4;
                for availablePRBs=[3 24]
                    record(current,kind,direction,rankValue,policy,ue,1,availablePRBs,false);
                end
            end
            % A large-queue positive ensures the accepted tuple is usable
            % before the finite-queue candidate search is exercised.
            record(cfg,kind,direction,rankValue,"full_buffer_control",ue,1e6,24,true);
            record(cfg,kind,direction,rankValue,"empty_queue_control",ue,0,24,false);
        end
    end
end
% Additional value-boundary guards do not replace or weaken the original
% 48 exact planning cases above. An atomic tuple is not new RX authority.
for kind=["PF","RR"]
    for direction=["DL","UL"]
        for guard=["wrong_ue","wrong_rnti","wrong_cell","wrong_rank", ...
                "wrong_pmi","wrong_version","wrong_direction_or_signal", ...
                "stale_feedback","unusable_feedback","legacy_without_capsule"]
            recordGuard(kind,direction,guard);
        end
        if direction=="DL"
            recordGuard(kind,direction,"existing_type_ii_rank_contract");
            recordGuard(kind,direction,"existing_modeled_dl_rank_contract");
        end
    end
end
checks=struct2table(rows);
scope=struct('Version',"accepted_spatial_rank_scheduler_boundary/v1", ...
    'WaveformExecuted',false,'ReceivedFeedbackQualified',false, ...
    'AccessOrDCIQualified',false,'HARQLifecycleQualified',false, ...
    'SourceConfig',"simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml");
save(fullfile(outputRoot,'accepted_spatial_rank_scheduler_boundary.mat'), ...
    'checks','evidence','scope','cfg','-v7.3');
writetable(checks,fullfile(outputRoot,'accepted_spatial_rank_scheduler_boundary.csv'));
failed=checks(~checks.Passed,:);
for k=1:height(failed)
    fprintf(2,'ACCEPTED_SPATIAL_CASE %s %s rank=%g %s queue=%g PRBs=%g planned=%g FAIL %s %s\n', ...
        failed.Scheduler(k),failed.Direction(k),failed.ReportedRank(k),failed.Policy(k), ...
        failed.OfferedBytes(k),failed.AvailablePRBs(k),failed.PlannedRank(k), ...
        failed.FailureID(k),failed.Detail(k));
end
fprintf('ACCEPTED_SPATIAL_RANK_BOUNDARY cases=%d failures=%d waveform=0 folder=%s\n', ...
    height(checks),height(failed),outputRoot);
assert(isempty(failed),'test:AcceptedSpatialRankSchedulerBoundary', ...
    '%d/%d accepted spatial planning cases failed; retained diagnostics: %s.', ...
    height(failed),height(checks),outputRoot);
ok=true;

    function record(current,kind,direction,rankValue,policy,ue,bytes,nPRBs,requireValid)
        row=prototype; row.Scheduler=kind; row.Direction=direction;
        row.Policy=policy; row.ReportedRank=rankValue;
        row.OfferedBytes=bytes; row.AvailablePRBs=nPRBs;
        entry=struct('UE',ue,'Plan',struct(),'AttachedGrant',struct(),'AMC',struct());
        try
            scheduler=feval("sixgr.l2.mac.Scheduler"+kind,current,'Direction',direction);
            [~,initialRank,~,amc]=scheduler.selectAMC(ue);
            entry.AMC=amc;
            row.AMCInitialRank=initialRank;
            row.AMCExistingRankBound=logical(sixgr.util.structGet(amc,'ReceivedCSIRankBound',false));
            row.AMCSpatialRankTupleBound=logical(sixgr.util.structGet(amc,'SpatialRankTupleBound',false));
            assert(initialRank==rankValue && string(amc.Mode)=="cqi_table" && amc.CausalFeedbackUsable, ...
                'test:AcceptedSpatialFixture','The declared accepted tuple must reach actual CQI-based AMC unchanged.');
            symbolAllocation=current.phy.pdsch.symbolAllocation;
            if direction=="UL", symbolAllocation=current.phy.pusch.symbolAllocation; end
            before=ue;
            plan=scheduler.buildNewDataGrantPlan(ue,0:nPRBs-1,symbolAllocation,bytes);
            entry.Plan=plan;
            assert(isequaln(ue,before),'test:AcceptedSpatialInputMutation','Do not rewrite input feedback.');
            row.PlanValid=logical(plan.Valid); row.PlannedRank=plan.NumLayers;
            row.PlannedMCS=plan.MCSIndex; row.PlannedPRBs=numel(plan.PRBSet);
            row.TBSBits=plan.TBSBits; row.LayerReductionSteps=plan.LayerReductionSteps;
            if bytes==0
                assert(~plan.Valid,'test:AcceptedSpatialEmptyQueue','No padding-only demand may be manufactured.');
            elseif requireValid
                assert(plan.Valid,'test:AcceptedSpatialPositive','Large-queue control must retain a valid exact plan.');
            end
            if plan.Valid
                assert(~plan.PlanningOnlyApproximation && ...
                    plan.TBSBits==nrTBS(plan.Modulation,plan.NumLayers,numel(plan.PRBSet), ...
                    plan.NREPerPRB,plan.TargetCodeRate,plan.XOverhead) && ...
                    plan.QueuePaddingBits==max(0,plan.TBSBits-8*bytes), ...
                    'test:AcceptedSpatialExactTBS','Keep actual allocation-derived TBS and explicit padding.');
                grant=plan; grant.Direction=direction; grant.RNTI=ue.RNTI;
                grant.UEIndex=ue.UEIndex; grant.ServingCell=ue.ServingCell;
                grant.Slot=30; grant.ControlAbsoluteSlot=30;
                grant.PMI=ue.PMI; grant.CRI=ue.CRI;
                grant=scheduler.attachULSRSAuthorityToGrant(grant,ue);
                entry.AttachedGrant=grant;
                if direction=="DL"
                    assert(isequaln(grant.CSIReportProvenance,ue.CSIReportProvenance), ...
                        'test:AcceptedSpatialSourceChanged','Retain the original Type-I capsule.');
                    retainedRank=grant.CSIReportProvenance.RI;
                    retainedPMI=grant.CSIReportProvenance.PMI;
                    assert(grant.PMI==retainedPMI && grant.CRI==ue.CSIReportProvenance.CRI);
                else
                    assert(isequaln(grant.AcceptedSRSSpatialDecision,ue.AcceptedSRSSpatialDecision), ...
                        'test:AcceptedSpatialSourceChanged','Retain the original accepted-SRS capsule.');
                    retainedRank=grant.AcceptedSRSSpatialDecision.RI;
                    retainedPMI=grant.AcceptedSRSSpatialDecision.PMI;
                    assert(grant.PMI==retainedPMI && grant.TPMI==retainedPMI);
                end
                row.AtomicSpatialTupleRetained=plan.NumLayers==retainedRank;
                assert(row.AtomicSpatialTupleRetained && plan.LayerReductionSteps==0 && ...
                    row.AMCSpatialRankTupleBound && plan.SpatialRankTupleBound, ...
                    'test:AcceptedSpatialRankReinterpreted', ...
                    'Queue search changed accepted rank %g to %g while retaining its PMI/TPMI %g.', ...
                    retainedRank,plan.NumLayers,retainedPMI);
            else
                % No feasible grant is acceptable. Do not force rank, TBS,
                % admission, or throughput merely to satisfy this fixture.
                row.AtomicSpatialTupleRetained=plan.NumLayers==rankValue;
            end
            row.Passed=true;
        catch failure
            row.FailureID=string(failure.identifier); row.Detail=string(failure.message);
        end
        rows(end+1,1)=row; evidence{end+1,1}=entry; %#ok<AGROW>
    end

    function recordGuard(kind,direction,guard)
        current=cfg; current.phy.linkAdaptation.maxCSIAgeSlots=5;
        current.phy.linkAdaptation.dlMaxCSIAgeSlots=5;
        current.phy.linkAdaptation.ulMaxCSIAgeSlots=5;
        ue=localDeclaredUE(current,direction,4);
        capsule="CSIReportProvenance"; owner="UEIndex";
        if direction=="UL", capsule="AcceptedSRSSpatialDecision"; owner="TargetId"; end
        switch guard
            case "wrong_ue", ue.(capsule).(owner)=2;
            case "wrong_rnti", ue.(capsule).RNTI=702;
            case "wrong_cell", ue.(capsule).ServingCell=2;
            case "wrong_rank", ue.(capsule).RI=2;
            case "wrong_pmi", ue.(capsule).PMI=1;
            case "wrong_version", ue.(capsule).Version="unqualified_rank_hint";
            case "wrong_direction_or_signal"
                if direction=="DL", ue.(capsule).Direction="UL";
                else, ue.(capsule).SignalType="CSI-RS"; end
            case "stale_feedback", ue.FeedbackAgeSlots=6;
            case "unusable_feedback"
                ue.CausalFeedbackUsable=false;
                ue.CausalFeedbackStatus="feedback_not_causally_available";
                if direction=="UL", ue.AcceptedSRSCausalUsable=false; end
            case "legacy_without_capsule", ue=rmfield(ue,capsule);
            case "existing_type_ii_rank_contract"
                % Rank-only declared dispatch fixture, not a received Type-II
                % coefficient report. Its separate end-to-end test remains required.
                ue.ReceivedCSIReport=struct('RI',4);
                ue.PMI=NaN; ue.CSIReportProvenance.PMI=NaN;
            case "existing_modeled_dl_rank_contract"
                ue.ModeledCSIFeedback=struct('RI',4);
                ue=rmfield(ue,capsule);
        end
        row=prototype; row.Scheduler=kind; row.Direction=direction;
        row.Policy=guard; row.ReportedRank=4; row.OfferedBytes=1; row.AvailablePRBs=24;
        entry=struct('UE',ue,'Plan',struct(),'AttachedGrant',struct(),'AMC',struct());
        before=ue;
        try
            scheduler=feval("sixgr.l2.mac.Scheduler"+kind,current,'Direction',direction);
            expectsRejection=startsWith(guard,"wrong_");
            if expectsRejection
                caught=false;
                try
                    scheduler.selectAMC(ue);
                catch failure
                    assert(strcmp(failure.identifier,'sixgr:l2:mac:SpatialRankTupleMismatch'), ...
                        'test:AcceptedSpatialWrongRejection','Unexpected identity guard: %s.',failure.identifier);
                    entry.RejectionID=string(failure.identifier); caught=true;
                end
                assert(caught,'test:AcceptedSpatialMissingRejection','Inconsistent spatial tuple was accepted.');
            else
                [~,~,~,amc]=scheduler.selectAMC(ue); entry.AMC=amc;
                row.AMCSpatialRankTupleBound=amc.SpatialRankTupleBound;
                if guard=="legacy_without_capsule"
                    assert(~amc.SpatialRankTupleBound && amc.SpatialRankTupleSource=="" && ...
                        isequaln(ue,before),'test:AcceptedSpatialNoAuthorityCreation', ...
                        'No new received capsule or restriction may be manufactured for legacy input.');
                elseif startsWith(guard,"existing_")
                    plan=scheduler.buildNewDataGrantPlan(ue,0:23,current.phy.pdsch.symbolAllocation,1);
                    entry.Plan=plan;
                    assert(amc.ReceivedCSIRankBound && ~amc.SpatialRankTupleBound && ...
                        plan.Valid && plan.NumLayers==4 && plan.LayerReductionSteps==0, ...
                        'test:AcceptedSpatialExistingOwner', ...
                        'Preserve the existing Type-II/modeled rank owner without imposing Type-I PMI.');
                else
                    symbols=current.phy.pdsch.symbolAllocation;
                    if direction=="UL", symbols=current.phy.pusch.symbolAllocation; end
                    plan=scheduler.buildNewDataGrantPlan(ue,0:23,symbols,1);
                    entry.Plan=plan; row.PlanValid=plan.Valid; row.PlannedRank=plan.NumLayers;
                    assert(~amc.CausalFeedbackUsable && ~plan.Valid && plan.TBSBits==0 && ...
                        plan.SpatialRankTupleBound && isequaln(ue,before), ...
                        'test:AcceptedSpatialStaleAdmission', ...
                        'Preserving a tuple cannot authorize stale/unavailable feedback or create a TB.');
                end
            end
            assert(isequaln(ue,before),'test:AcceptedSpatialInputMutation','Do not rewrite feedback to pass a guard.');
            row.Passed=true;
        catch failure
            row.FailureID=string(failure.identifier); row.Detail=string(failure.message);
        end
        rows(end+1,1)=row; evidence{end+1,1}=entry; %#ok<AGROW>
    end
end

function ue=localDeclaredUE(cfg,direction,rankValue)
ue=struct('UEIndex',1,'RNTI',701,'ServingCell',1,'CQI',12, ...
    'RI',rankValue,'PMI',0,'TPMI',0,'CRI',0,'DLBufferBytes',1,'ULBufferBytes',1, ...
    'FeedbackValid',true,'CausalFeedbackUsable',true,'FeedbackAgeSlots',1, ...
    'CausalFeedbackStatus',"declared_admitted_value_boundary", ...
    'SchedulerCQISource',"runtime_reported_cqi_declared_test_boundary", ...
    'ReceivedCSIReport',struct());
if direction=="DL"
    installed=cfg.phy.csi.reportConfiguration; request=installed; request.Rank=rankValue;
    [~,tuple]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
    values=tuple; values.RI=rankValue; values.PMI=0; values.CRI=0;
    values.CQI_CW0=ue.CQI; values.LI=0;
    tx=sixgr.phy.mimo.CSIReportConfiguration(request,cfg.phy.csi.reportConfigurationEpoch);
    rx=sixgr.phy.mimo.CSIReportConfiguration(installed,cfg.phy.csi.reportConfigurationEpoch);
    encoded=tx.build(values); decoded=rx.decode(encoded.Part1Bits,encoded.Part2Bits);
    assert(decoded.RI==rankValue && decoded.PMI==0 && decoded.CRI==0);
    report=struct('Direction',"DL",'UEIndex',1,'RNTI',701,'ServingCell',1, ...
        'SourceSignal',"received_CSI_UCI",'CSIUCIDecodeOk',true, ...
        'SourceSlot',28,'DueSlot',29,'DeliveredSlot',29,'CSIReferenceSlot',28, ...
        'ReportIdentity',"declared_codec_report_rank_"+rankValue, ...
        'CSIReportConfigID',string(installed.ReportConfigID), ...
        'CSIConfigurationEpoch',cfg.phy.csi.reportConfigurationEpoch, ...
        'CSIUCIChannel',decoded.UCIChannel,'CSIUCITransport',"declared_codec_boundary_not_radio", ...
        'CQI',decoded.CQI_CW0,'RI',decoded.RI,'PMI',decoded.PMI,'CRI',decoded.CRI, ...
        'CSIUCIDecodedBitCount',numel(encoded.Part1Bits)+numel(encoded.Part2Bits), ...
        'CSIUCIDecodedBitsToken',string(sixgr.runtime.RawCSVArrayCodec.encode( ...
        [encoded.Part1Bits;encoded.Part2Bits])));
    for name=["LI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
        report.(name)=double(sixgr.util.structGet(decoded,name,NaN));
    end
    ue.CSIReportProvenance=sixgr.truth.captureReceivedCSIProvenance(report);
    ue.CSIReportDecisionContext=struct();
    assert(~ue.CSIReportProvenance.ReceiverObservationBound);
else
    % Deliberately slot-only declared measurement: no fabricated receiver
    % capture, installed-context digest, physical power, or sample clock.
    measurement=struct('MeasurementId',"declared_srs_rank_"+rankValue, ...
        'SignalType',"SRS",'TargetType',"UE",'TargetId',1,'ServingCell',1, ...
        'ProducerSlot',28,'AvailableSlot',29,'Valid',true,'RI',rankValue,'PMI',0);
    ue.AcceptedSRSSpatialDecision=sixgr.truth.captureAcceptedSRSSpatialDecision( ...
        measurement,ue.RNTI,rankValue,0);
    ue.AcceptedSRSCausalUsable=true;
    ue.AcceptedSRSCausalAgeSlots=2;
    ue.AcceptedSRSCausalStatus="declared_admitted_value_boundary";
    ue.SRSValid=true; ue.SRSCausalUsable=true;
    ue.SRSCausalMeasurementId=measurement.MeasurementId;
    ue.LastSuccessfulSRSSlot=28; ue.SRSAgeSlots=2; ue.SRSCausalAgeSlots=2;
    ue.SRSCausalStatus="declared_admitted_value_boundary";
end
end
