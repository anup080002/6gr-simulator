function paths=writeTDocStudyFigureSourceTables(runFolder,context,cfg)
%WRITEFIGURESOURCETABLES Materialize semantic, configuration-backed figure data.
% These tables describe diagrams and procedures. They never replace waveform
% evidence and are deliberately stored outside csv/lls.
folder=fullfile(runFolder,"csv","figures");
if ~isfolder(folder), mkdir(folder); end
paths=strings(0,1);
    function emit(name,T)
        path=fullfile(folder,name);
        sixgr.csi.CSITDocStudyResultWriter.write(path,T,context);
        paths(end+1,1)=string(path); %#ok<AGROW>
    end

nodeId=["FOUNDATION";"A";"B";"C";"D";"E";"F";"G";"H";"I";"J"];
label=["Matched power, overhead, practical estimation, feedback reliability, CSI age and complexity"; ...
    "CSI state and timeline";"DM-RS refinement";"Interference age"; ...
    "Early CSI";"Event-triggered CSI";"Energy hypotheses"; ...
    "Port-count normalization";"CSI-RS sharing";"CDM and OCC"; ...
    "Multi-slot phase"];
layer=["foundation";repmat("mechanism",10,1)];
emit("fig_1_1_nodes.csv",table(nodeId,label,layer, ...
    'VariableNames',{'NodeId','Label','Layer'}));
emit("fig_1_1_edges.csv",table(repmat("FOUNDATION",10,1),nodeId(2:end), ...
    repmat("common matched assumptions",10,1), ...
    'VariableNames',{'FromNode','ToNode','Relation'}));

time_slot=[0;1;2;3;4;6;8;9];
event_type=["measurement_trigger";"computation_start";"completion_and_storage"; ...
    "measurement_trigger";"completion_and_storage";"report_trigger"; ...
    "version_mismatch";"invalid_no_fallback_evidence"];
state_id=["S1";"S1";"S1";"S2";"S2";"S2";"S1";"NONE"];
cmr_id=["CMR-1";"CMR-1";"CMR-1";"CMR-2";"CMR-2";"CMR-2";"CMR-1";"NONE"];
imr_id=["IMR-1";"IMR-1";"IMR-1";"IMR-2";"IMR-2";"IMR-2";"IMR-1";"NONE"];
basis_version=[1;1;1;2;2;2;1;0]; target_time=[4;4;4;7;7;7;9;9];
valid=[true;true;true;true;true;true;false;false];
selected_by_report=[false;false;false;false;false;true;false;false];
emit("state_events.csv",table(time_slot,event_type,state_id,cmr_id,imr_id, ...
    basis_version,target_time,valid,selected_by_report));

Slot=(0:10).'; CPUOccupied=ismember(Slot,[0 1 3]);
StateAddressable=Slot>=2 & Slot<=8; StateValid=Slot>=2 & Slot<=7;
ReportSent=Slot==6; EventLabel=repmat("",numel(Slot),1);
EventLabel(Slot==0)="S1 trigger"; EventLabel(Slot==2)="S1 stored / CPU released";
EventLabel(Slot==3)="S2 trigger"; EventLabel(Slot==4)="S2 stored / CPU released";
EventLabel(Slot==6)="report selects S2"; EventLabel(Slot==8)="state expired";
emit("state_lifecycle.csv",table(Slot,CPUOccupied,StateAddressable, ...
    StateValid,ReportSent,EventLabel));

NodeId=["H";"W_S";"G";"DMRS";"W_1";"W_3"];
Label=["Physical channel H";"Scheduled precoder W_scheduled"; ...
    "Effective channel G = H W_scheduled";"DM-RS-observable effective subspace"; ...
    "Unsounded W_1";"Unsounded W_3"];
Scheduled=[true;true;true;true;false;false];
emit("dmrs_subspace_nodes.csv",table(NodeId,Label,Scheduled));
emit("dmrs_subspace_edges.csv",table(["H";"W_S";"G";"H";"H"], ...
    ["G";"G";"DMRS";"W_1";"W_3"], ...
    ["channel action";"scheduled projection";"observable";"not observed";"not observed"], ...
    'VariableNames',{'FromNode','ToNode','Relation'}));

Slot=[0;1;2;4]; Event=["t_IM measurement";"stable hypothesis"; ...
    "co-scheduled user / TRP / precoder change";"t_PDSCH application"];
Validity=[true;true;false;false];
Annotation=["interference estimate acquired";"A_I begins"; ...
    "stored hypothesis becomes stale";"A_I = t_PDSCH - t_IM = 4 slots"];
emit("interference_timeline.csv",table(Slot,Event,Validity,Annotation));

NodeId=["ACT";"RS";"COARSE";"FIRST";"DMRS";"NORMAL"];
Label=["IDLE/INACTIVE or carrier activation";"Available SSB / CSI-RS"; ...
    "Coarse quality / CQI";"First CSI-informed scheduling"; ...
    "DM-RS after decoded scheduled PDSCH";"Normal CSI framework"];
Stage=(1:6).'; emit("early_csi_nodes.csv",table(NodeId,Label,Stage));
emit("early_csi_edges.csv",table(["ACT";"RS";"COARSE";"FIRST";"FIRST";"DMRS"], ...
    ["RS";"COARSE";"FIRST";"DMRS";"NORMAL";"NORMAL"], ...
    ["E0-E4 start";"E1/E2 available";"causal input"; ...
    "DM-RS cannot schedule this earlier PDSCH";"transition";"E3 refinement"], ...
    'VariableNames',{'FromNode','ToNode','Constraint'}));

NodeId=["CFG";"EVENT";"S1";"DECIDE";"S2"];
Label=["NW config: threshold / hysteresis / TTT / minimum interval"; ...
    "UE event condition";"Compact stage-1 indication"; ...
    "gNB decision";"Optional detailed stage-2 CSI"];
Stage=(1:5).'; emit("event_csi_nodes.csv",table(NodeId,Label,Stage));
emit("event_csi_edges.csv",table(["CFG";"CFG";"EVENT";"S1";"DECIDE"], ...
    ["EVENT";"DECIDE";"S1";"DECIDE";"S2"], ...
    ["configured trigger";"configured response";"condition met"; ...
    "encoded UCI";"request if needed"], ...
    'VariableNames',{'FromNode','ToNode','Condition'}));

hypothesis=string(cfg.energy_hypotheses.names(:));
activePorts=double(cfg.energy_hypotheses.active_port_counts(:));
activeTRPs=double(cfg.energy_hypotheses.active_trp_counts(:));
powerOffset=double(cfg.energy_hypotheses.per_hypothesis_power_offset_db(:));
label=hypothesis+": "+activePorts+" ports, "+activeTRPs+" TRP(s), "+powerOffset+" dB";
emit("energy_hypothesis_nodes.csv",table(hypothesis,label,activePorts, ...
    activeTRPs,powerOffset,'VariableNames',{'Hypothesis','Label', ...
    'ActivePorts','ActiveTRPs','PowerOffsetDb'}));
emit("energy_hypothesis_edges.csv",table(repmat(hypothesis(1),numel(hypothesis)-1,1), ...
    hypothesis(2:end),"delta CSI: "+(2:numel(hypothesis)).', ...
    'VariableNames',{'FromHypothesis','ToHypothesis','DeltaLabel'}));

levels=["Level 1 complete CDM support";"Level 2a nested OCC/port subsets"; ...
    "Level 2b partial RE overlap"];
grid=[];
for levelIndex=1:numel(levels)
    for symbol=0:3
        for subcarrier=0:7
            switch levelIndex
                case 1
                    state=localIf(mod(subcarrier,2)==0,"shared","unused");
                case 2
                    state=localIf(mod(subcarrier,2)==0,"shared", ...
                        localIf(symbol<2,"A only","B only"));
                otherwise
                    if symbol==1 && ismember(subcarrier,2:5), state="shared";
                    elseif symbol<=1 && mod(subcarrier,2)==0, state="A only";
                    elseif symbol>=2 && mod(subcarrier,2)==1, state="B only";
                    else, state="unused"; end
            end
            cdm="G"+mod(subcarrier,double(cfg.csirs.cdm_sizes(1)));
            ports=localIf(state=="shared","A:{0..3}; B:{0..1}",state);
            grid=[grid;table(levels(levelIndex),subcarrier,symbol,state,cdm,ports, ...
                'VariableNames',{'Level','Subcarrier','Symbol','CellState', ...
                'CDMGroup','PortSubset'})]; %#ok<AGROW>
        end
    end
end
emit("sharing_resource_grid.csv",grid);
end

function value=localIf(tf,yes,no)
if tf, value=yes; else, value=no; end
end
