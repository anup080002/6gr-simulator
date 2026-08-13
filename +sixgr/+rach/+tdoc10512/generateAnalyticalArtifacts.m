function [artifacts, data] = generateAnalyticalArtifacts(runFolder,cfg,configHash)
%GENERATEANALYTICALARTIFACTS Build exact and conceptual TDoc evidence.
%
% No waveform performance value is synthesized here.  Numeric artifacts
% are deterministic arithmetic under the resolved YAML assumptions;
% sequence/flow figures are explicitly conceptual.

tableDir = fullfile(runFolder,"tables");
sourceDir = fullfile(tableDir,"figure_sources");
figureDir = fullfile(runFolder,"figures","analytical");
sixgr.util.ensureFolder(tableDir);
sixgr.util.ensureFolder(sourceDir);
sixgr.util.ensureFolder(figureDir);

td = cfg.tdoc10512;
classification = "ANALYTICAL_DERIVATION";
conceptual = "CONCEPTUAL_DIAGRAM";
scenarioID = string(cfg.meta.scenario_id);

data = struct();
data.ResponseStates = localResponseStates(td);
data.TargetDelay = localTargetDelay(td);
data.PreambleTiming = localPreambleTiming(td);
data.FrequencyStress = localFrequencyStress(td);
data.Collision = localCollision(td);
data.Partition = localPartition(td);
data.RootDemand = localRootDemand(td);
data.RARPayload = localRARPayload(td);
data.SBFDFit = localSBFDFit(td);
data.Msg3Shapes = localShapeTable(td);
data.Assumptions = localAssumptions(cfg);
data.CoverageChain = localOrderedNodes([ ...
    "Msg1 PRACH" "Msg2 RAR or MsgB" "Msg3 or MsgA" ...
    "Msg4 contention resolution" "Msg4 HARQ-ACK"], ...
    "coverage_chain_stage");
data.ShapeEdges = localShapeEdges(td);
data.OTASequence = localOrderedNodes([ ...
    "SIB and common RACH configuration" "Msg1 transmission" ...
    "RAR primary-shape indication" "Independent UE/aNB derivation" ...
    "Substitute Msg3 on complete-fit failure"],"ota_step");
data.EvidenceChain = localOrderedNodes([ ...
    "Analytical derivation" "Calibrated PRACH LLS" ...
    "Restricted-set and multicell evidence" ...
    "Procedure-level evidence"],"evidence_stage");

tableSpecs = { ...
    "T02_two_four_step_receiver_states", data.ResponseStates, conceptual
    "T03_preamble_timing_parameters", data.PreambleTiming, classification
    "T04_frequency_stress_cases", data.FrequencyStress, classification
    "T05_collision_values", data.Collision, classification
    "T06_partition_multiplexing", data.Partition, classification
    "T07_root_demand", data.RootDemand, classification
    "T08_sbfd_fit", data.SBFDFit, classification
    "T09_information_placement_policy", localInformationPlacement(), conceptual
    "T10_msg3_shape_set", data.Msg3Shapes, conceptual
    "T11_T14_configuration_assumptions", data.Assumptions, classification
    "T06_T07_rar_payload_arithmetic", data.RARPayload, classification};

artifactRows = cell(0,1);
for k = 1:size(tableSpecs,1)
    id = string(tableSpecs{k,1});
    T = tableSpecs{k,2};
    cls = string(tableSpecs{k,3});
    path = fullfile(tableDir,id+".csv");
    sixgr.util.csvWriteTable(path,T);
    artifactRows{end+1,1} = localArtifact(id,path,"",cls,"COMPLETE", ...
        "sixgr.rach.tdoc10512.generateAnalyticalArtifacts",runFolder); %#ok<AGROW>
end

figureSpecs = { ...
    "F01_common_pool_two_four_step_sequence", data.ResponseStates, conceptual, ...
        @()localPlotPolicyMatrix(data.ResponseStates)
    "F02_target_delay_interpretation", data.TargetDelay, classification, ...
        @()localPlotTargetDelay(data.TargetDelay)
    "F03_preamble_timing_decomposition", data.PreambleTiming, classification, ...
        @()localPlotPreambleTiming(data.PreambleTiming)
    "F04_normalized_frequency_stress", data.FrequencyStress, classification, ...
        @()localPlotFrequencyStress(data.FrequencyStress)
    "F05_collision_benefit", data.Collision, classification, ...
        @()localPlotCollision(data.Collision)
    "F06_partition_statistical_multiplexing", data.Partition, classification, ...
        @()localPlotPartition(data.Partition)
    "F07_root_demand", data.RootDemand, classification, ...
        @()localPlotRootDemand(data.RootDemand)
    "F08_rar_payload", data.RARPayload, classification, ...
        @()localPlotRAR(data.RARPayload)
    "F09_sbfd_ro_fit", data.SBFDFit, classification, ...
        @()localPlotSBFD(data.SBFDFit)
    "F10_ra_coverage_chain", data.CoverageChain, conceptual, ...
        @()localPlotSequence(data.CoverageChain,"Random-access coverage chain")
    "F11_msg3_complete_fit_flow", data.ShapeEdges, conceptual, ...
        @()localPlotShapeGraph(data.ShapeEdges)
    "F12_msg3_ota_sequence", data.OTASequence, conceptual, ...
        @()localPlotSequence(data.OTASequence,"Deterministic Msg3 substitution sequence")
    "F13_evidence_chain", data.EvidenceChain, conceptual, ...
        @()localPlotSequence(data.EvidenceChain,"Evidence chain and claim boundary")};

for k = 1:size(figureSpecs,1)
    id = string(figureSpecs{k,1});
    sourceT = figureSpecs{k,2};
    cls = string(figureSpecs{k,3});
    plotter = figureSpecs{k,4};
    sourcePath = fullfile(sourceDir,id+".csv");
    sixgr.util.csvWriteTable(sourcePath,sourceT);
    matPath = fullfile(sourceDir,id+".mat");
    sourceTable = sourceT; %#ok<NASGU>
    save(matPath,"sourceTable","-v7");
    pngPath = fullfile(figureDir,id+".png");
    localExportPNG(pngPath,plotter,scenarioID,cls,double(td.output.png_dpi));
    sidecar = struct("artifact_id",id,"scenario_id",scenarioID, ...
        "classification",cls,"status","COMPLETE", ...
        "config_hash",string(configHash),"source_csv",string(sourcePath), ...
        "source_csv_sha256",localFileHash(sourcePath), ...
        "producer","sixgr.rach.tdoc10512.generateAnalyticalArtifacts", ...
        "performance_claim",false);
    sixgr.util.jsonWrite(fullfile(figureDir,id+".json"),sidecar);
    artifactRows{end+1,1} = localArtifact(id,pngPath,sourcePath,cls, ...
        "COMPLETE","sixgr.rach.tdoc10512.generateAnalyticalArtifacts",runFolder); %#ok<AGROW>
end

artifacts = vertcat(artifactRows{:});
end

function T = localResponseStates(td)
cases = localRecords(td.procedure.receiver_cases);
policies = localRecords(td.procedure.response_policies);
rows = cell(numel(cases)*numel(policies),1); n = 0;
for i = 1:numel(cases)
    c = cases{i};
    for j = 1:numel(policies)
        p = policies{j}; n = n+1;
        outcome = localPolicyOutcome(string(c.id),string(p.id));
        rows{n} = table(string(c.id),string(c.description),string(p.id), ...
            logical(c.prach_detected),logical(c.msga_valid), ...
            logical(c.other_ue_evidence),outcome,"RAN2_DEPENDENCY", ...
            'VariableNames',{'CaseID','CaseDescription','ResponsePolicy', ...
            'PRACHDetected','MsgAValid','OtherUEEvidence','CandidateOutcome', ...
            'NormativeStatus'});
    end
end
T = vertcat(rows{:});
end

function outcome = localPolicyOutcome(caseID,policy)
switch policy
    case "MSGB_ONLY"
        if caseID == "PRACH_AND_MSGA"
            outcome = "MSGB_FOR_DECODED_MSGA";
        else
            outcome = "PRACH_ONLY_UE_MAY_BE_STRANDED";
        end
    case "RAR_ONLY"
        outcome = "RAR_AND_FOUR_STEP_CONTINUATION";
    case "COMBINED_MSGB_PLUS_FALLBACK_GRANT"
        outcome = "MSGB_WHEN_DECODED_PLUS_FALLBACK_GRANT";
    case "ALL_SAME_PREAMBLE_FALLBACK_TO_4STEP"
        if any(caseID == ["MIXED_SAME_PREAMBLE","AMBIGUOUS_MSGA","PRACH_ONLY"])
            outcome = "FALLBACK_ALL_TO_FOUR_STEP";
        else
            outcome = "MSGB_FOR_UNAMBIGUOUS_MSGA";
        end
    otherwise
        error("sixgr:rach:tdoc10512:UnknownPolicy", ...
            "Unknown response policy %s.",policy);
end
end

function T = localTargetDelay(td)
rows = localRecords(td.scenarios); c = double(td.speed_of_light_mps);
n = numel(rows); id=strings(n,1); range=zeros(n,1); geo=zeros(n,1);
precomp=zeros(n,1); residual=zeros(n,1); excess=zeros(n,1); margin=zeros(n,1);
target=zeros(n,1); mode=strings(n,1);
for k=1:n
    r=rows{k}; id(k)=string(r.id); range(k)=double(r.cell_range_m);
    geo(k)=2*range(k)/c*1e6; excess(k)=double(td.target_delay.channel_excess_delay_quantile_us);
    margin(k)=double(td.target_delay.timing_margin_us);
    if logical(r.waveform_eligible)
        mode(k)="TERRESTRIAL_NO_TA";
        target(k)=geo(k)+excess(k)+margin(k);
    else
        mode(k)="ANALYTICAL_PRECOMPENSATED";
        precomp(k)=geo(k); residual(k)=double(td.target_delay.precompensation_error_us);
        target(k)=abs(geo(k)-precomp(k))+residual(k)+excess(k)+margin(k);
    end
end
T=table(id,range,geo,precomp,residual,excess,margin,target,mode, ...
    'VariableNames',{'ScenarioID','CellRangeM','GeometricRTTUs', ...
    'AppliedPrecompensationUs','ResidualPrecompensationErrorUs', ...
    'ChannelExcessDelayQuantileUs','TimingMarginUs','TargetDelayUs','Interpretation'});
end

function T = localPreambleTiming(td)
rows=localRecords(td.prach_formats); n=numel(rows);
id=strings(n,1); lra=zeros(n,1); scs=zeros(n,1); cp=zeros(n,1);
useful=zeros(n,1); reps=zeros(n,1); guard=zeros(n,1); total=zeros(n,1);
radius=zeros(n,1); backend=strings(n,1); cls=strings(n,1);
c=double(td.speed_of_light_mps); allow=double(td.analytical.timing_allowance_us);
for k=1:n
    r=rows{k}; id(k)=string(r.id); lra(k)=double(r.sequence_length);
    scs(k)=double(r.prach_scs_khz); cp(k)=double(r.cp_us);
    useful(k)=double(r.useful_sequence_us); reps(k)=double(r.repetitions);
    guard(k)=double(r.guard_us); total(k)=cp(k)+useful(k)+guard(k);
    radius(k)=c/2*max(0,min(cp(k),guard(k))-allow)*1e-6;
    backend(k)=string(r.waveform_backend); cls(k)=string(r.research_class);
end
T=table(id,lra,scs,cp,useful,reps,guard,total,radius,backend,cls, ...
    'VariableNames',{'FormatID','SequenceLength','PRACHSCSKHz','CPUs', ...
    'UsefulSequenceUs','Repetitions','GuardUs','TotalDurationUs', ...
    'AnalyticalReferenceRadiusM','WaveformBackend','ResearchClass'});
end

function T = localFrequencyStress(td)
rows=localRecords(td.scenarios); scs=[1.25 5]; c=double(td.speed_of_light_mps);
out=cell(numel(rows)*numel(scs),1); n=0;
for k=1:numel(rows)
    r=rows{k};
    fd=2*(double(r.speed_kmh)/3.6)/c*double(r.carrier_hz);
    for j=1:numel(scs)
        n=n+1;
        out{n}=table(string(r.id),double(r.carrier_hz),double(r.speed_kmh), ...
            fd,double(r.two_way_screening_doppler_hz),scs(j),fd/(scs(j)*1e3), ...
            "study_table_screening", ...
            'VariableNames',{'ScenarioID','CarrierHz','SpeedKmh', ...
            'ComputedTwoWayDopplerHz','ConfiguredTwoWayDopplerHz', ...
            'PRACHSCSKHz','NormalizedFrequencyStress','FrequencyStressMode'});
    end
end
T=vertcat(out{:});
end

function T = localCollision(td)
M=double(td.analytical.collision_preamble_counts(:));
K=double(td.analytical.collision_attempt_counts(:));
out=cell(numel(M)*numel(K),1); n=0;
for i=1:numel(M)
    for j=1:numel(K)
        n=n+1; unique=(1-1/M(i))^(K(j)-1);
        if K(j)<=M(i)
            logAll=sum(log((M(i)-K(j)+1):M(i)))-K(j)*log(M(i));
            allUnique=exp(logAll);
        else
            allUnique=0;
        end
        out{n}=table(M(i),K(j),unique,1-unique,K(j)*unique,allUnique, ...
            'VariableNames',{'PreambleCount','AttemptsPerRO','TaggedUniqueProbability', ...
            'TaggedCollisionProbability','ExpectedSingletonUEs','AllUniqueProbability'});
    end
end
T=vertcat(out{:});
end

function T = localPartition(td)
M=64; totalK=64; Gs=double(td.analytical.partition_counts(:));
out=cell(numel(Gs)+2,1); n=0;
for i=1:numel(Gs)
    G=Gs(i); m=M/G; k=totalK/G;
    singleton=repmat(k*(1-1/m)^(k-1),G,1);
    n=n+1; out{n}=localPartitionRow("BALANCED_G"+G,G,M,totalK, ...
        sum(singleton),sum(m*(1-1/m).^k),localJain(singleton),"balanced_proportional_load");
end
attempts=double(td.analytical.unbalanced_attempts(:)); G=numel(attempts); m=M/G;
singletons=attempts.*(1-1/m).^(max(attempts-1,0));
n=n+1; out{n}=localPartitionRow("UNBALANCED_40_8_8_8",G,M,sum(attempts), ...
    sum(singletons),sum(m*(1-1/m).^attempts),localJain(singletons),"unbalanced_reserved_classes");
duty=[1 .25 .25 .25]'; effective=attempts.*duty;
singletons=effective.*(1-1/m).^(max(effective-1,0));
n=n+1; out{n}=localPartitionRow("LIGHTLY_OCCUPIED_RESERVED",4,M,sum(effective), ...
    sum(singletons),sum(m*(1-1/m).^effective),localJain(singletons),"class_activity_duty_cycle");
T=vertcat(out{1:n});
end

function row=localPartitionRow(id,g,m,k,singletons,unused,jain,note)
row=table(string(id),g,m,k,singletons,unused,jain,string(note), ...
    'VariableNames',{'CaseID','Partitions','TotalPreambles','EffectiveAttempts', ...
    'ExpectedSingletonUEs','ExpectedUnusedPreambles','JainFairness','LoadModel'});
end

function v=localJain(x)
v=(sum(x)^2)/(numel(x)*sum(x.^2)+eps);
end

function T = localRootDemand(td)
L=double(td.analytical.root_sequence_length);
ncs=double(td.analytical.root_ncs_values(:)); targets=double(td.analytical.root_target_preambles(:));
out=cell(numel(ncs)*numel(targets),1); n=0;
for i=1:numel(ncs)
    shifts=floor(L/ncs(i));
    for j=1:numel(targets)
        n=n+1; out{n}=table(L,ncs(i),shifts,targets(j),ceil(targets(j)/shifts), ...
            "unrestricted_first_order_precheck", ...
            'VariableNames',{'SequenceLength','NCS','ShiftsPerRoot', ...
            'TargetPreambles','RootsRequired','EvidenceScope'});
    end
end
T=vertcat(out{:});
end

function T = localRARPayload(td)
entries=double(td.analytical.rar_entries(:));
nr=double(td.analytical.nr_rar_bytes_per_entry); ex=double(td.analytical.expanded_rar_bytes_per_entry);
T=table(entries,entries*nr,entries*ex,entries*nr*8,entries*ex*8, ...
    repmat("illustrative_lower_bound",numel(entries),1), ...
    'VariableNames',{'ResponseEntries','NRReferenceBytes','ExpandedExampleBytes', ...
    'NRReferenceBits','ExpandedExampleBits','DesignStatus'});
end

function T = localSBFDFit(td)
s=td.sbfd; widths=double(s.ul_subband_widths_mhz(:));
guards=double(s.edge_guard_prbs(:)); ro=double(s.ro_bandwidth_mhz); prb=double(s.prb_bandwidth_mhz);
out=cell(numel(widths)*numel(guards),1); n=0;
for i=1:numel(widths)
    for j=1:numel(guards)
        n=n+1; guardMHz=guards(j)*prb;
        fit=max(0,floor((widths(i)-2*guardMHz)/ro));
        out{n}=table(widths(i),guards(j),guardMHz,ro,fit, ...
            'VariableNames',{'ULSubbandMHz','EdgeGuardPRBs','EdgeGuardEachMHz', ...
            'ROBandwidthMHz','MaximumFDMROs'});
    end
end
T=vertcat(out{:});
end

function T=localShapeTable(td)
rows=localRecords(td.msg3_shapes); n=numel(rows); id=strings(n,1);
prbs=strings(n,1); symbols=strings(n,1); reps=strings(n,1); hop=strings(n,1); use=strings(n,1);
for k=1:n
    r=rows{k}; id(k)=string(r.id); prbs(k)=localValueText(r.prbs);
    symbols(k)=localValueText(r.symbols); reps(k)=localValueText(r.repetitions);
    hop(k)=strjoin(string(r.hopping_options),"|"); use(k)=string(r.intended_use);
end
T=table(id,prbs,symbols,reps,hop,use, ...
    'VariableNames',{'ShapeID','PRBs','Symbols','Repetitions','HoppingOptions','IntendedUse'});
end

function T=localShapeEdges(td)
rows=localRecords(td.msg3_shape_edges); n=numel(rows); from=strings(n,1); to=strings(n,1);
for k=1:n, from(k)=string(rows{k}.from); to(k)=string(rows{k}.to); end
T=table((1:n)',from,to,repmat("configured_directed_fallback",n,1), ...
    'VariableNames',{'Order','FromShape','ToShape','EdgeType'});
end

function T=localAssumptions(cfg)
keys=["scenario_id";"campaign_mode";"prach_format";"carrier_hz"; ...
    "carrier_scs_khz";"channel_model";"delay_spread_ns";"speed_kmh"; ...
    "ue_tx_antennas";"anb_rx_antennas";"target_false_alarm_probability"; ...
    "frequency_stress_waveform_mode";"svg_enabled"];
values=[string(cfg.meta.scenario_id);string(cfg.tdoc10512.campaign_mode); ...
    string(cfg.random_access.prach_format);string(cfg.random_access.carrier_frequency_hz); ...
    string(cfg.random_access.carrier_scs_khz);string(cfg.random_access.channel_model); ...
    string(cfg.random_access.delay_spread_ns);string(cfg.random_access.speed_kmh); ...
    string(cfg.random_access.num_tx_antennas);string(cfg.random_access.num_rx_antennas); ...
    string(cfg.random_access.target_false_alarm_probability); ...
    string(cfg.tdoc10512.waveform_frequency_stress_mode);string(cfg.tdoc10512.output.save_svg)];
T=table(keys,values,repmat("resolved_yaml",numel(keys),1), ...
    'VariableNames',{'Parameter','Value','Authority'});
end

function T=localInformationPlacement()
item=["coarse_msg3_resource_need";"msg3_size_class";"identity"; ...
    "detailed_capability";"phr";"early_beam_or_csi";"on_demand_request"];
placement=["coarse_early_indication_candidate";"msg3_or_msga";"msg3_or_msga"; ...
    "msg3_or_later";"msg3_or_later";"msg3_or_msga_candidate";"msg3_or_later"];
T=table(item,placement,repmat("policy_analysis_not_normative",numel(item),1), ...
    'VariableNames',{'InformationClass','CandidatePlacement','NormativeStatus'});
end

function T=localOrderedNodes(labels,kind)
n=numel(labels); T=table((1:n)',string(labels(:)),repmat(string(kind),n,1), ...
    'VariableNames',{'Order','Node','NodeType'});
end

function localExportPNG(path,plotter,scenarioID,classification,resolution)
fig=figure("Visible","off","Color","w","Position",[100 100 1200 720]);
clean=onCleanup(@()close(fig)); %#ok<NASGU>
plotter();
annotation(fig,"textbox",[.04 .945 .92 .04], ...
    "String",scenarioID+" | "+classification,"Interpreter","none", ...
    "FontWeight","normal","FontSize",10,"Color",[.12 .15 .20], ...
    "EdgeColor","none","HorizontalAlignment","center");
localApplyRasterTheme(fig);
sixgr.util.exportFigureArtifact(fig,path,"Resolution",resolution);
end

function localApplyRasterTheme(fig)
% MATLAB desktop themes must not leak into saved technical figures.
axesList=findall(fig,"Type","axes");
for k=1:numel(axesList)
    ax=axesList(k);
    set(ax,"FontSize",10,"LineWidth",0.8,"Color","w", ...
        "XColor",[.12 .15 .20],"YColor",[.12 .15 .20], ...
        "GridColor",[.55 .60 .66],"MinorGridColor",[.72 .75 .79], ...
        "TickLabelInterpreter","none");
    ax.Position=[.10 .14 .84 .72];
    ax.Title.Color=[.12 .15 .20];
    ax.XLabel.Color=[.12 .15 .20];
    ax.YLabel.Color=[.12 .15 .20];
    ax.ZLabel.Color=[.12 .15 .20];
end
textObjects=findall(fig,"Type","text");
for k=1:numel(textObjects), textObjects(k).Color=[.12 .15 .20]; end
legends=findall(fig,"Type","legend");
for k=1:numel(legends)
    set(legends(k),"Color","w","TextColor",[.12 .15 .20], ...
        "EdgeColor",[.45 .49 .54]);
end
end

function localPlotPolicyMatrix(T)
axis off; policies=unique(T.ResponsePolicy,"stable"); cases=unique(T.CaseID,"stable");
text(.02,.95,"Common-pool two-step/four-step response alternatives", ...
    "FontSize",14,"FontWeight","bold","Units","normalized");
for i=1:numel(cases)
    y=.84-(i-1)*.19; text(.02,y,cases(i),"FontWeight","bold","Units","normalized");
    for j=1:numel(policies)
        row=T(T.CaseID==cases(i)&T.ResponsePolicy==policies(j),:);
        text(.22+(j-1)*.19,y,policies(j)+newline+row.CandidateOutcome, ...
            "FontSize",8,"Units","normalized","Interpreter","none");
    end
end
text(.02,.03,"Conceptual alternatives only; final MAC behavior remains a RAN2 dependency.", ...
    "Units","normalized","FontAngle","italic");
end

function localPlotTargetDelay(T)
bar(categorical(T.ScenarioID),[T.GeometricRTTUs T.ResidualPrecompensationErrorUs ...
    T.ChannelExcessDelayQuantileUs T.TimingMarginUs],"stacked");
ylabel("Delay contribution (us)"); grid on; legend(["geometric RTT","precomp error","excess delay","margin"],"Location","best");
title("Target-delay decomposition (analytical; not detector performance)");
end

function localPlotPreambleTiming(T)
bar(categorical(T.FormatID),[T.CPUs T.UsefulSequenceUs T.GuardUs],"stacked");
ylabel("Duration (us)"); grid on; legend(["CP","useful sequence","guard"],"Location","best");
title("PRACH timing decomposition");
end

function localPlotFrequencyStress(T)
ids=unique(T.ScenarioID,"stable"); scs=unique(T.PRACHSCSKHz,"stable"); Z=zeros(numel(ids),numel(scs));
for i=1:numel(ids), for j=1:numel(scs), Z(i,j)=T.NormalizedFrequencyStress(T.ScenarioID==ids(i)&T.PRACHSCSKHz==scs(j)); end, end
bar(categorical(ids),Z); ylabel("two-way Doppler / PRACH SCS"); grid on;
legend("SCS "+string(scs)+" kHz","Location","best"); title("Normalized frequency-stress screening");
end

function localPlotCollision(T)
hold on; M=unique(T.PreambleCount,"stable");
for k=1:numel(M), r=T(T.PreambleCount==M(k),:); plot(r.AttemptsPerRO,r.TaggedCollisionProbability,"-o","DisplayName","M="+M(k)); end
grid on; xlabel("Attempts per RO"); ylabel("Tagged collision probability"); legend("Location","northwest"); title("Collision-only benefit"); hold off;
end

function localPlotPartition(T)
bar(categorical(T.CaseID),T.ExpectedSingletonUEs); grid on; ylabel("Expected singleton UEs per RO"); title("Partition statistical-multiplexing comparison");
end

function localPlotRootDemand(T)
hold on; targets=unique(T.TargetPreambles,"stable");
for k=1:numel(targets), r=T(T.TargetPreambles==targets(k),:); plot(r.NCS,r.RootsRequired,"-o","DisplayName","M="+targets(k)); end
grid on; xlabel("N_{CS}"); ylabel("Roots required"); legend("Location","northwest"); title("Unrestricted-set root-demand pre-check"); hold off;
end

function localPlotRAR(T)
bar(categorical(string(T.ResponseEntries)),[T.NRReferenceBytes T.ExpandedExampleBytes]);
grid on; xlabel("RAR response entries"); ylabel("Payload lower bound (bytes)");
legend(["NR reference","expanded identifier example"],"Location","northwest"); title("RAR payload arithmetic");
end

function localPlotSBFD(T)
hold on; guards=unique(T.EdgeGuardPRBs,"stable");
for k=1:numel(guards), r=T(T.EdgeGuardPRBs==guards(k),:); plot(r.ULSubbandMHz,r.MaximumFDMROs,"-o","DisplayName","guard="+guards(k)+" PRB/edge"); end
grid on; xlabel("SBFD UL sub-band (MHz)"); ylabel("Maximum frequency-domain ROs"); legend("Location","northwest"); title("SBFD PRACH RO fit"); hold off;
end

function localPlotSequence(T,plotTitle)
axis off; n=height(T); x=linspace(.08,.92,n);
for k=1:n
    rectangle("Position",[x(k)-.07,.42,.14,.18],"Curvature",.12,"FaceColor",[.88 .95 1],"EdgeColor",[.1 .35 .6]);
    text(x(k),.51,T.Node(k),"HorizontalAlignment","center","Units","normalized","FontSize",9,"Interpreter","none");
    if k<n, annotation("arrow",[x(k)+.07 x(k+1)-.07],[.51 .51]); end
end
title(plotTitle); text(.02,.08,"Conceptual flow; no performance gain is asserted.","Units","normalized","FontAngle","italic");
end

function localPlotShapeGraph(T)
axis off; text(.05,.9,"Configured directed Msg3 complete-fit traversal","FontSize",14,"FontWeight","bold","Units","normalized");
for k=1:height(T)
    y=.78-(k-1)*.17;
    text(.15,y,T.FromShape(k),"Units","normalized","FontSize",12,"FontWeight","bold");
    annotation("arrow",[.35 .58],[y y]);
    text(.68,y,T.ToShape(k),"Units","normalized","FontSize",12,"FontWeight","bold");
end
text(.05,.08,"A shape is selected only after complete symbol/PRB/DMRS/hopping fit checks.","Units","normalized","FontAngle","italic");
end

function row=localArtifact(id,path,source,classification,status,producer,root)
info=dir(path);
row=table(string(id),string(localRelative(path,root)),string(localRelative(source,root)), ...
    string(classification),string(status),localFileHash(path),double(info.bytes),string(producer), ...
    'VariableNames',{'ArtifactID','RelativePath','SourceCSV','Classification', ...
    'Status','SHA256','Bytes','Producer'});
end

function value=localRelative(path,root)
if strlength(string(path))==0, value=""; return; end
p=string(char(java.io.File(char(string(path))).getCanonicalPath()));
r=string(char(java.io.File(char(string(root))).getCanonicalPath()));
prefix=r+filesep; value=erase(p,prefix);
end

function value=localFileHash(path)
fid=fopen(path,"r");
if fid<0, error("sixgr:rach:tdoc10512:ArtifactRead","Cannot read artifact %s.",path); end
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,"*uint8"); value=sixgr.util.sha256Hex(bytes);
end

function rows=localRecords(value)
if iscell(value), rows=value(:); elseif isstruct(value), rows=arrayfun(@(x)x,value(:),'UniformOutput',false); else, error("sixgr:rach:tdoc10512:BadCatalog","Catalog must contain structure records."); end
end

function textValue=localValueText(value)
if isnumeric(value), textValue=strjoin(string(value(:)'),"|"); else, textValue=strjoin(string(value),"|"); end
end
