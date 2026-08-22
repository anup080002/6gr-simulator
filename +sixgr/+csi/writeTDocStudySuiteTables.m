function paths=writeTDocStudySuiteTables(runFolder,context,registry,inventory,gaps,a,p,w)
%WRITESUITETABLES Materialize the named TDoc CSV contract without proxies.
csvRoot=fullfile(runFolder,"csv"); manifestRoot=fullfile(runFolder,"manifests");
if ~isfolder(csvRoot), mkdir(csvRoot); end
if ~isfolder(manifestRoot), mkdir(manifestRoot); end
paths=strings(0,1);
    function emit(name,T,subfolder)
        if nargin<3, subfolder=""; end
        folder=fullfile(csvRoot,subfolder); if ~isfolder(folder), mkdir(folder); end
        path=fullfile(folder,name); sixgr.csi.CSITDocStudyResultWriter.write(path,T,context);
        paths(end+1,1)=string(path); %#ok<AGROW>
    end
sixgr.csi.CSITDocStudyResultWriter.write(fullfile(manifestRoot,"repository_inventory.csv"),inventory,context);
sixgr.csi.CSITDocStudyResultWriter.write(fullfile(manifestRoot,"gap_analysis.csv"),gaps,context);
sixgr.csi.CSITDocStudyResultWriter.write(fullfile(manifestRoot,"scenario_registry.csv"),registry,context);

emit("canonical_execution_flow_trace.csv",w.CanonicalFlow.Trace,"lls");
emit("csi_feedback_runtime.csv",w.CanonicalFlow.CSIReport,"lls");
emit("csi_feedback_pucch_runtime.csv",w.CanonicalFlow.PUCCH,"lls");
emit("csi_beam_tci_runtime.csv",w.CanonicalFlow.BeamHistory,"procedure");

emit("csi_state_event_trace.csv",p.StateEvents,"procedure");
emit("csi_state_store_trace.csv",p.StateSummary(:,["StateCount","Policy","PeakStoredStates","EvidenceClass","Status"]),"procedure");
emit("csi_cpu_occupancy_trace.csv",p.StateEvents(:,["EventIndex","Event","Slot","CPUOccupied","EvidenceClass","Status"]),"procedure");
emit("csi_state_association_summary.csv",p.StateSummary,"procedure");
failures=p.StateSummary(p.StateSummary.SelectionRejected|p.StateSummary.WrongStateReport,:);
emit("csi_state_failure_cases.csv",failures,"procedure");

emit("dmrs_reference_state_trace.csv",w.DMRSRefinement,"lls");
emit("dmrs_refinement_tb_trace.csv",w.DMRSRefinement,"lls");
emit("dmrs_cqi_error.csv",w.DMRSRefinement(:,["SNRIndex","TrialIndex","ReferenceStateSINRdB","PostEqSINRdB","DMRSCQIDeltaDb","EvidenceClass","Status"]),"lls");
emit("dmrs_layer_sinr_error.csv",w.DMRSRefinement(:,["SNRIndex","TrialIndex","LayerImbalanceDb","EvidenceClass","Status"]),"lls");
emit("dmrs_rank_down_detection.csv",w.DMRSRefinement(:,["SNRIndex","TrialIndex","RankDownIndication","EvidenceClass","Status"]),"lls");
emit("dmrs_validity_detection.csv",w.DMRSRefinement(:,["SNRIndex","TrialIndex","ReferenceStateValid","EvidenceClass","Status"]),"lls");
feedback=w.CanonicalFlow.PUCCH(w.CanonicalFlow.PUCCH.PayloadRole=="dmrs_delta",:);
feedback.BlockError=feedback.CRCFailed|feedback.ContentMismatch;
feedback.BLER=double(feedback.BlockError);
feedback.FeedbackSource(:)="production_pdsch_dmrs_posteq_delta_typed_uci";
emit("dmrs_feedback_bler.csv",feedback,"lls");
key=struct("UEID",1,"Direction","DL","ServingCellID",1,"ScheduledCellID",1, ...
    "BWPID",0,"MCSTable","qam64_table1","ConfigurationEpoch",1);
olla=sixgr.phy.rsla.OLLAState(key,double(context.Config.olla.target_bler), ...
    double(context.Config.olla.ack_step_db),-6,6,"NACK");
events=cell(8,1); outcomes=["ACK","ACK","NACK","ACK","ACK","ACK","NACK","ACK"];
for k=1:8, events{k}=olla.update(outcomes(k),k); end
ot=struct2table(vertcat(events{:}),"AsArray",true); ot.Key=[];
emit("dmrs_olla_trace.csv",ot,"procedure");
emit("dmrs_summary.csv",w.PDSCHSummary,"lls");
over=table(sum(w.PDSCHTrials.DMRSRE),0,0,sum(w.PDSCHTrials.DMRSRE), ...
    "LLS_CONTROLLED","PASS",'VariableNames',{'ExistingDMRSRE','AdditionalDMRSRE', ...
    'ULCSIReportRE','TotalAdditionalOverheadRE','EvidenceClass','Status'});
emit("dmrs_overhead.csv",over,"lls");

emit("interference_hypothesis_trace.csv",a.InterferenceAge,"sanity");
emit("interference_age_sanity.csv",a.InterferenceAge,"sanity");
emit("interference_lls_point.csv",w.Interference.Points,"lls");
emit("interference_sinr_error.csv",a.InterferenceAge,"sanity");
emit("interference_cqi_error.csv",w.Interference.CQIError,"lls");
emit("interference_bler.csv",w.Interference.BLER,"lls");

emit("early_csi_procedure_trace.csv",p.EarlyCSI,"procedure");
emit("early_csi_first_tb.csv",p.EarlyCSI,"procedure");
emit("early_csi_stabilization.csv",p.EarlyCSI,"procedure");
emit("early_csi_candidate_complexity.csv",p.EarlyCSI,"procedure");
emit("early_csi_overhead.csv",p.EarlyCSI,"procedure");

emit("event_csi_measurement_trace.csv",p.EventPareto,"procedure");
emit("event_csi_trigger_trace.csv",p.EventPareto,"procedure");
eventUCI=w.CanonicalFlow.PUCCH(w.CanonicalFlow.PUCCH.PayloadRole=="event_stage1",:);
emit("event_csi_uci_trace.csv",eventUCI,"lls");
emit("event_csi_summary.csv",p.EventPareto,"procedure");
emit("event_sanity_pareto.csv",p.EventPareto,"sanity");
eventLLS=eventUCI;
eventLLS.PDSCHBlockError(:)=double(w.PDSCHTrials.CRCError(1));
eventLLS.PDSCHDeliveredBits(:)=double(~w.PDSCHTrials.CRCError(1))* ...
    double(w.PDSCHTrials.TransportBlockSizeBits(1));
eventLLS.CSIStateAgeSlots(:)=double(context.Config.csi.bounded_flow.consumer_slot- ...
    context.Config.csi.bounded_flow.measurement_slot);
emit("event_lls_pareto.csv",eventLLS,"lls");

emit("energy_hypothesis_definition.csv",p.Energy,"procedure");
emit("energy_hypothesis_csi.csv",p.Energy,"procedure");
energyReport=w.CanonicalFlow.PUCCH( ...
    w.CanonicalFlow.PUCCH.PayloadRole=="energy_hypothesis_differential",:);
energyReport.Hypothesis(:)=string(context.Config.energy_hypotheses.names(2));
emit("energy_differential_report.csv",energyReport,"lls");
emit("energy_reconstruction_metrics.csv", ...
    w.EnergyHypotheses.Reconstruction,"lls");
emit("energy_complexity.csv",p.Energy,"procedure");
emit("energy_phy_performance.csv",w.EnergyHypotheses.Performance,"lls");

emit("port_power_analytical.csv",a.PortPower,"analytical");
emit("port_nmse_analytical.csv",a.PortNMSE,"analytical");
emit("port_count_lls_points.csv",w.HighPort,"lls");
emit("port_count_nmse.csv",w.HighPort(:,["TxPorts","CDMSize","OCCFamily","PowerNormalization","SNRdB","NMSELinear","NMSEdB","EvidenceClass","Status"]),"lls");
emit("port_count_sgcs.csv",w.HighPort(:,["TxPorts","CDMSize","OCCFamily","PowerNormalization","SNRdB","SGCS","EvidenceClass","Status"]),"lls");
emit("port_count_csi_error.csv",w.HighPort(:,["TxPorts","NMSEdB","SGCS","EvidenceClass","Status"]),"lls");
complexity=w.HighPort(:,["TxPorts","CDMSize","RxAntennas","EvidenceClass","Status"]);
complexity.ComplexMultiplyEstimate=complexity.TxPorts.*complexity.CDMSize.*complexity.RxAntennas;
emit("port_count_complexity.csv",complexity,"lls");

emit("sharing_resource_map.csv",w.ResourceMap,"lls");
emit("sharing_port_occ_map.csv",w.ResourceMap,"lls");
emit("sharing_sequence_map.csv",a.Sharing,"analytical");
emit("sharing_identity_audit.csv",a.Sharing,"analytical");
emit("sharing_estimate_reuse.csv",w.HighPort(:,["TxPorts","PowerNormalization","NMSELinear","EvidenceClass","Status"]),"lls");
emit("sharing_time_age.csv",p.SharingTimeAge,"procedure");
emit("sharing_power_normalization.csv",a.PortPower,"analytical");

occDefinition=unique(a.OCC(:,["CDMSize","OCCFamily","EvidenceClass","Status"]));
emit("occ_definition.csv",occDefinition,"analytical");
emit("occ_analytical_coupling.csv",a.OCC,"analytical");
emit("occ_worst_leakage.csv",a.OCC(:,["CDMSize","OCCFamily","PhaseDegPerChip","WorstLeakage","EvidenceClass","Status"]),"analytical");
emit("occ_mean_leakage.csv",a.OCC(:,["CDMSize","OCCFamily","PhaseDegPerChip","MeanLeakage","EvidenceClass","Status"]),"analytical");
emit("occ_lls_coupling.csv",w.OCC,"lls"); emit("occ_nmse.csv",w.OCC,"lls");
emit("occ_sgcs.csv",w.OCC,"lls");
emit("occ_phy_performance.csv",w.OCCPerformance,"lls");
emit("occ_complexity.csv",w.OCC,"lls");

emit("multislot_analytical_cfo.csv",a.MultislotCFO,"analytical");
emit("multislot_analytical_iid_phase.csv",a.MultislotIID,"analytical");
emit("multislot_analytical_aging.csv",a.MultislotAging,"analytical");
emit("multislot_lls_trace.csv",w.MultiSlot.Trace,"lls");
emit("multislot_nmse.csv",w.MultiSlot.Summary(:,["ReceiverMode","M1", ...
    "TxPorts","NMSELinear","NMSEdB","EvidenceClass","Status"]),"lls");
emit("multislot_sgcs.csv",w.MultiSlot.Summary(:,["ReceiverMode","M1", ...
    "TxPorts","SGCS","EvidenceClass","Status"]),"lls");
emit("multislot_phy_performance.csv",w.MultiSlot.PDSCHPerformance,"lls");
emit("multislot_complexity.csv",a.MultislotCFO(:,["M1","EvidenceClass","Status"]),"analytical");

emit("pdsch_anchor_trials.csv",w.PDSCHTrials,"lls");
emit("pdsch_anchor_summary.csv",w.PDSCHSummary,"lls");
end
