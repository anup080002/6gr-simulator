classdef SemanticFigureRenderer
    %SEMANTICFIGURERENDERER Dedicated public renderers for CSI TDoc figures.

    methods (Static)
        function result=render(fig,spec,tables,cfg)
            plotter=string(spec.plotter);
            switch plotter
                case "renderArchitectureDiagram"
                    localArchitecture(fig,tables);
                case "renderProcedureTimeline"
                    localProcedureTimeline(fig,tables{1});
                case "renderStateLifecycle"
                    localStateLifecycle(fig,tables{1});
                case "renderEffectiveSubspace"
                    localEffectiveSubspace(fig,tables);
                case "renderInterferenceTimeline"
                    localInterferenceTimeline(fig,tables{1});
                case "renderInterferenceSensitivity"
                    localInterferenceSensitivity(fig,tables);
                case "renderEarlyCSIFlow"
                    localFlow(fig,tables,"Early CSI causal flow");
                case "renderEventCSIFlow"
                    localFlow(fig,tables,"Two-stage event-triggered CSI");
                case "renderEventPareto"
                    localEventPareto(fig,tables{1});
                case "renderEnergyHypotheses"
                    localEnergy(fig,tables);
                case "renderPowerNormalization"
                    localPowerNormalization(fig,tables{1});
                case "renderNMSEPenalty"
                    localNMSEPenalty(fig,tables{1});
                case "renderResourceGrid"
                    localResourceGrid(fig,tables{1});
                case "renderMappingProof"
                    localMappingProof(fig,tables{1});
                case "renderOCCWorst"
                    localOCCWorst(fig,tables{1},string(spec.figure_id));
                case "renderOCCMeanEquality"
                    localOCCMeanEquality(fig,tables{1});
                case "renderDeterministicPhase"
                    localDeterministicPhase(fig,tables{1});
                case "renderIndependentPhase"
                    localIndependentPhase(fig,tables{1});
                case "renderChannelAging"
                    localChannelAging(fig,tables{1},cfg);
                otherwise
                    error("sixgr:csi:UnknownSemanticPlotter", ...
                        "Unknown CSI semantic plotter %s.",plotter);
            end
            localApplyLightTheme(fig);
            annotation(fig,"textbox",[.015 .003 .97 .045], ...
                "String","Evidence: "+string(spec.evidence_class)+ ...
                "  |  Limitation: "+string(spec.limitations_text), ...
                "Interpreter","none","EdgeColor","none", ...
                "Color",[.25 .25 .25],"FontSize",8, ...
                "HorizontalAlignment","center");
            result=struct("Pass",true,"Details","semantic contract passed", ...
                "IndependentTrials",localIndependentTrials(tables));
        end
    end
end

function localArchitecture(fig,tables)
nodes=tables{1}; edges=tables{2};
assert(height(nodes)==11 && height(edges)==10, ...
    "Architecture contract must contain one foundation and ten mechanisms.");
ax=localDiagramAxes(fig,"DL-CSI mechanisms share one matched evidence foundation");
layers=string(nodes.Layer); mechanisms=nodes(layers=="mechanism",:); positions=zeros(height(mechanisms),4);
mechanismId=string(mechanisms.NodeId); mechanismLabel=string(mechanisms.Label);
for k=1:height(mechanisms)
    col=mod(k-1,5); row=floor((k-1)/5);
    positions(k,:)=[.025+col*.195,.59-row*.31,.17,.19];
    localBox(ax,positions(k,:),mechanismId(k)+"  "+mechanismLabel(k), ...
        [.88 .95 1],[.10 .38 .58]);
end
foundation=nodes(layers=="foundation",:);
localBox(ax,[.08 .08 .84 .18],string(foundation.Label(1)),[.90 1 .91],[.18 .50 .25]);
for k=1:height(mechanisms)
    x=positions(k,1)+positions(k,3)/2;
    line(ax,[.5 x],[.26 positions(k,2)],"Color",[.45 .55 .58],"LineWidth",1);
end
text(ax,.5,.29,"common assumptions and evidence lineage", ...
    "HorizontalAlignment","center","FontAngle","italic","FontSize",9);
end

function localProcedureTimeline(fig,T)
eventType=string(T.event_type); completed=eventType=="completion_and_storage";
reportSlot=min(T.time_slot(eventType=="report_trigger"));
assert(nnz(completed & T.time_slot<reportSlot)>=2);
assert(any(T.selected_by_report) && any(~T.valid));
types=unique(eventType,"stable");
ax=axes(fig,"Position",[.17 .14 .78 .76]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
for k=1:height(T)
    lane=find(types==eventType(k),1);
    color=localIf(T.valid(k),[.05 .48 .72],[.78 .20 .16]);
    scatter(ax,T.time_slot(k),lane,85,color,"filled");
    label=string(T.state_id(k))+"  "+replace(eventType(k),"_"," ");
    if T.selected_by_report(k), label=label+"  [SELECTED]"; end
    if T.time_slot(k)>=max(T.time_slot)-1
        xText=T.time_slot(k)-.08; alignment="right";
    else
        xText=T.time_slot(k)+.08; alignment="left";
    end
    text(ax,xText,lane+.08,label,"FontSize",8,"Interpreter","none", ...
        "HorizontalAlignment",alignment);
end
yticks(ax,1:numel(types)); yticklabels(ax,replace(types,"_"," "));
xlabel(ax,"Slot"); ylabel(ax,"Procedure lane");
title(ax,"CSI state completion, storage, report selection and invalidation");
xlim(ax,[min(T.time_slot)-.5 max(T.time_slot)+.5]);
ylim(ax,[.55 numel(types)+.45]);
end

function localStateLifecycle(fig,T)
signals=[T.CPUOccupied,T.StateAddressable,T.StateValid,T.ReportSent];
assert(all(ismember(signals(:),[0 1])) && ...
    any(T.CPUOccupied~=T.StateAddressable));
names=["CPU occupied","State addressable","State valid","Report sent"];
ax=axes(fig,"Position",[.09 .14 .88 .76]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
colors=lines(4);
for k=1:4
    stairs(ax,T.Slot,double(signals(:,k))+1.45*(4-k), ...
        "LineWidth",2,"Color",colors(k,:),"DisplayName",names(k));
end
eventLabel=string(T.EventLabel); events=find(strlength(eventLabel)>0);
for k=events.'
    marker=xline(ax,T.Slot(k),":",eventLabel(k),"LabelOrientation","horizontal", ...
        "FontSize",8,"Color",[.3 .3 .3]);
    marker.HandleVisibility="off";
end
xlabel(ax,"Slot"); ylabel(ax,"Separated binary traces");
yticks(ax,[]); legend(ax,"Location","eastoutside");
title(ax,"Computation ends before stored CSI state ceases to be addressable");
end

function localEffectiveSubspace(fig,tables)
nodes=tables{1};
nodeId=string(nodes.NodeId);
assert(any(~nodes.Scheduled) && all(ismember(["H","W_S","G","DMRS"],nodeId)));
ax=localDiagramAxes(fig,"Scheduled effective-subspace DM-RS observability");
pos=containers.Map({'H','W_S','G','DMRS','W_1','W_3'}, ...
    {[.04 .50 .15 .18],[.26 .50 .19 .18],[.53 .50 .18 .18], ...
    [.78 .46 .18 .26],[.29 .17 .15 .14],[.55 .17 .15 .14]});
for k=1:height(nodes)
    p=pos(char(nodeId(k)));
    if nodes.Scheduled(k), face=[.86 .95 1]; edge=[.08 .38 .65];
    else, face=[.94 .94 .94]; edge=[.55 .55 .55]; end
    localBox(ax,p,string(nodes.Label(k)),face,edge);
end
localArrow(ax,.19,.59,.26,.59); localArrow(ax,.45,.59,.53,.59);
localArrow(ax,.71,.59,.78,.59);
line(ax,[.19 .365],[.50 .31],"LineStyle","--","Color",[.55 .55 .55]);
line(ax,[.19 .625],[.50 .31],"LineStyle","--","Color",[.55 .55 .55]);
text(ax,.5,.06,"One scheduled DM-RS occasion does not directly observe arbitrary unscheduled W alternatives.", ...
    "HorizontalAlignment","center","FontWeight","bold","FontSize",10);
end

function localInterferenceTimeline(fig,T)
event=string(T.Event); annotationText=string(T.Annotation);
assert(any(contains(event,"t_IM")) && any(contains(event,"t_PDSCH")) && ...
    any(contains(event,"change")));
ax=axes(fig,"Position",[.09 .18 .88 .68]); hold(ax,"on"); box(ax,"on");
plot(ax,[min(T.Slot) max(T.Slot)],[.5 .5],"k-","LineWidth",2);
for k=1:height(T)
    color=localIf(T.Validity(k),[.05 .55 .34],[.80 .24 .18]);
    scatter(ax,T.Slot(k),.5,110,color,"filled");
    text(ax,T.Slot(k),.62+mod(k,2)*.12,event(k)+newline+annotationText(k), ...
        "HorizontalAlignment","center","FontSize",8);
end
text(ax,mean([min(T.Slot) max(T.Slot)]),.18,"A_I = t_{PDSCH} - t_{IM}", ...
    "HorizontalAlignment","center","FontWeight","bold");
xlabel(ax,"Slot"); yticks(ax,[]); ylim(ax,[0 1]);
title(ax,"Interference estimate, hypothesis changes and PDSCH application");
end

function localInterferenceSensitivity(fig,tables)
S=tables{1}; L=tables{2};
assert(all(ismember(["RMSECI95LowdB","RMSECI95HighdB","N","Seed"], ...
    string(S.Properties.VariableNames))) && all(S.N>=1));
assert(height(L)>=2 && all(L.CovarianceApplied));
layout=tiledlayout(fig,1,2,"Padding","compact","TileSpacing","compact");
layout.Position=[.06 .11 .90 .80];
ax=nexttile(layout); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
for p=unique(S.ChangeProbabilityPerSlot).'
    q=S(S.ChangeProbabilityPerSlot==p,:);
    errorbar(ax,q.InterferenceAgeSlots,q.EffectiveSINRRMSEdB, ...
        q.EffectiveSINRRMSEdB-q.RMSECI95LowdB, ...
        q.RMSECI95HighdB-q.EffectiveSINRRMSEdB,"o-","LineWidth",1.4, ...
        "DisplayName","p="+p);
end
xlabel(ax,"Interference-estimate age (slots)"); ylabel(ax,"RMS SINR error (dB)");
title(ax,"Normalized sanity model (95% CI)"); legend(ax,"Location","northwest");
text(ax,.02,.02,"N="+max(S.N)+", seed="+S.Seed(1),"Units","normalized", ...
    "VerticalAlignment","bottom","FontSize",8);
ax=nexttile(layout); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
for k=1:height(L)
    scatter(ax,L.InterferenceAgeSlots(k),L.PostEqSINRdB(k),90,"filled", ...
        "DisplayName",replace(string(L.CovariancePolicy(k)),"_"," "));
end
xlabel(ax,"Measured-covariance age (slots)"); ylabel(ax,"Post-equalization SINR (dB)");
title(ax,"Bounded production PDSCH / MMSE-IRC"); legend(ax,"Location","best");
text(ax,.02,.02,"Paired waveform points; "+string(L.EqualizerType(1)), ...
    "Units","normalized","VerticalAlignment","bottom","FontSize",8);
end

function localFlow(fig,tables,titleText)
nodes=tables{1}; edges=tables{2};
ax=localDiagramAxes(fig,titleText); n=height(nodes);
x=linspace(.025,.84,n); width=min(.14,.78/n); centers=zeros(n,2);
for k=1:n
    p=[x(k),.46,width,.24]; centers(k,:)=[p(1)+p(3)/2,p(2)+p(4)/2];
    localBox(ax,p,localWrapLabel(string(nodes.Label(k)),18), ...
        [.88 .95 1],[.10 .38 .62]);
end
for k=1:height(edges)
    nodeId=string(nodes.NodeId);
    from=find(nodeId==string(edges.FromNode(k)),1);
    to=find(nodeId==string(edges.ToNode(k)),1);
    if isempty(from)||isempty(to), error("sixgr:csi:BrokenDiagramEdge","Unknown flow node."); end
    if ismember("Constraint",string(edges.Properties.VariableNames))
        edgeLabel=string(edges.Constraint(k));
    else
        edgeLabel=string(edges.Condition(k));
    end
    if to-from==1
        localArrow(ax,centers(from,1)+width/2,centers(from,2), ...
            centers(to,1)-width/2,centers(to,2));
        yLabel=.39-.055*mod(k,2);
    else
        yRoute=.78+.045*mod(k,2);
        line(ax,[centers(from,1) centers(from,1) centers(to,1)], ...
            [.70 yRoute yRoute],"Color",[.25 .35 .40],"LineWidth",1.2);
        localArrow(ax,centers(to,1),yRoute,centers(to,1),.70);
        yLabel=yRoute+.025;
    end
    text(ax,mean(centers([from to],1)),yLabel,localWrapLabel(edgeLabel,22), ...
        "HorizontalAlignment","center","FontSize",6.5,"Interpreter","none");
end
end

function localEventPareto(fig,T)
assert(all(ismember(["MAECI95Low","MAECI95High","N","Seed"], ...
    string(T.Properties.VariableNames))));
ax=axes(fig,"Position",[.09 .15 .87 .75]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
policy=string(T.Policy); policies=unique(policy,"stable"); colors=lines(numel(policies));
for k=1:numel(policies)
    q=T(policy==policies(k),:);
    errorbar(ax,q.ReportsPer100Slots,q.MeanAbsoluteStateError, ...
        q.MeanAbsoluteStateError-q.MAECI95Low, ...
        q.MAECI95High-q.MeanAbsoluteStateError,"o","LineStyle","none", ...
        "Color",colors(k,:),"MarkerFaceColor",colors(k,:), ...
        "DisplayName",replace(policies(k),"_"," ")+" raw");
end
[x,order]=sort(T.ReportsPer100Slots); y=T.MeanAbsoluteStateError(order);
front=false(size(x)); best=Inf;
for k=1:numel(x)
    if y(k)<best-1e-12, front(k)=true; best=y(k); end
end
plot(ax,x(front),y(front),"k-","LineWidth",2.2,"DisplayName","non-dominated frontier");
xlabel(ax,"Reports per 100 slots"); ylabel(ax,"Mean absolute channel-state error");
title(ax,"Periodic and event-triggered single-UE sanity Pareto");
legend(ax,"Location","best");
text(ax,.02,.02,"95% CI; N="+max(T.N)+", seed="+T.Seed(1)+ ...
    ". Multi-UE congestion and UPT: SLS REQUIRED.","Units","normalized", ...
    "FontSize",8,"VerticalAlignment","bottom");
end

function localEnergy(fig,tables)
nodes=tables{1}; edges=tables{2}; performance=tables{3};
nodeHypothesis=string(nodes.Hypothesis); performanceHypothesis=string(performance.Hypothesis);
assert(any(nodeHypothesis=="H0") && height(performance)==height(nodes));
ax=localDiagramAxes(fig,"Differential CSI for configured physical energy hypotheses");
ref=find(nodeHypothesis=="H0",1); center=[.5 .57];
localBox(ax,[.38 .48 .24 .20],string(nodes.Label(ref)),[.88 1 .89],[.14 .50 .22]);
others=setdiff(1:height(nodes),ref); positions=[.06 .16;.38 .13;.70 .16];
for k=1:numel(others)
    i=others(k); p=[positions(k,:) .24 .18];
    localBox(ax,p,string(nodes.Label(i)),[.88 .95 1],[.10 .38 .62]);
    localArrow(ax,center(1),.48,p(1)+.12,p(2)+.18);
    row=performance(performanceHypothesis==nodeHypothesis(i),:);
    text(ax,p(1)+.12,p(2)-.035,"post-EQ SINR "+compose("%.2f",row.PostEqSINRdB)+" dB", ...
        "HorizontalAlignment","center","FontSize",8);
end
text(ax,.5,.81,"H0 is the full configured reference; arrows carry delta CSI", ...
    "HorizontalAlignment","center","FontWeight","bold");
text(ax,.5,.06,"Network energy saving and scheduler benefit require SLS.", ...
    "HorizontalAlignment","center","FontSize",9);
end

function localPowerNormalization(fig,T)
ports=unique(T.TxPorts); assert(all(ismember([128 256 512],ports.')));
layout=tiledlayout(fig,1,2,"Padding","compact","TileSpacing","compact");
layout.Position=[.06 .15 .90 .72];
for panel=1:2
    ax=nexttile(layout); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
    normalization=string(T.PowerNormalization);
    for mode=unique(normalization,"stable").'
        q=sortrows(T(normalization==mode,:),"TxPorts");
        if panel==1, value=q.PerPortEPREdBm-q.PerPortEPREdBm(q.TxPorts==128);
        else, value=q.TotalCSIRSPowerdBm-q.TotalCSIRSPowerdBm(q.TxPorts==128); end
        plot(ax,q.TxPorts,value,"o-","LineWidth",1.8, ...
            "DisplayName",localPowerLabel(mode));
    end
    xlabel(ax,"Number of CSI-RS ports"); ylabel(ax,"Relative power (dB)");
    if panel==1, title(ax,"Per-port EPRE relative to 128 ports");
    else, title(ax,"Total CSI-RS power relative to 128 ports"); end
    xticks(ax,[128 256 512]); legend(ax,"Location","best");
end
heading=sgtitle(layout,"Analytical normalization only; no channel or throughput claim");
heading.Color=[.08 .10 .12];
end

function localNMSEPenalty(fig,T)
ax=axes(fig,"Position",[.09 .15 .87 .75]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
normalization=string(T.PowerNormalization);
for mode=unique(normalization,"stable").'
    q=sortrows(T(normalization==mode,:),"TxPorts");
    perDelta=q.PerPortEPREdBm-q.PerPortEPREdBm(q.TxPorts==128);
    penalty=-perDelta;
    plot(ax,q.TxPorts,penalty,"o-","LineWidth",1.9,"DisplayName",localPowerLabel(mode));
end
xlabel(ax,"Number of CSI-RS ports"); ylabel(ax,"Idealized LS NMSE penalty (dB)");
xticks(ax,[128 256 512]); legend(ax,"Location","northwest");
title(ax,"NMSE penalty relative to the 128-port reference (equal RE per port)");
end

function localResourceGrid(fig,T)
levelValue=string(T.Level); cellState=string(T.CellState); cdmGroup=string(T.CDMGroup);
levels=unique(levelValue,"stable"); assert(numel(levels)==3);
layout=tiledlayout(fig,1,3,"Padding","compact","TileSpacing","compact");
layout.Position=[.06 .16 .90 .73];
states=["unused","A only","B only","shared"];
for k=1:3
    selected=levelValue==levels(k); q=T(selected,:); qState=cellState(selected); qGroup=cdmGroup(selected);
    ax=nexttile(layout); matrix=zeros(8,4);
    for r=1:height(q), matrix(q.Subcarrier(r)+1,q.Symbol(r)+1)=find(states==qState(r),1)-1; end
    imagesc(ax,0:3,0:7,matrix); axis(ax,"xy");
    colormap(ax,[.93 .93 .93;.25 .58 .85;.93 .55 .20;.20 .68 .43]);
    caxis(ax,[0 3]); xticks(ax,0:3); yticks(ax,0:7);
    if k==2, xlabel(ax,"OFDM symbol"); end
    ylabel(ax,"Subcarrier"); title(ax,levels(k));
    for r=1:height(q)
        if qState(r)=="shared"
            text(ax,q.Symbol(r),q.Subcarrier(r),qGroup(r), ...
                "HorizontalAlignment","center","FontSize",7,"Color","white");
        end
    end
    if k==1
        hold(ax,"on"); stateColors=[.93 .93 .93;.25 .58 .85;.93 .55 .20;.20 .68 .43];
        handles=gobjects(4,1);
        for s=1:4
            handles(s)=plot(ax,nan,nan,"s","MarkerSize",9, ...
                "MarkerFaceColor",stateColors(s,:),"MarkerEdgeColor",[.3 .3 .3]);
        end
        legend(ax,handles,cellstr(states),"Location","northwest", ...
            "Orientation","vertical","FontSize",7);
    end
end
heading=sgtitle(layout,"Reference CSI-RS support: unused, A only, B only and shared REs");
heading.Color=[.08 .10 .12]; heading.FontSize=13;
end

function localMappingProof(fig,T)
density=unique(T.Density,"stable"); assert(numel(density)>=2);
dense=T(T.Density==density(1),:); sparse=T(T.Density==density(end),:);
shared=intersect(dense.AbsoluteCoordinate,sparse.AbsoluteCoordinate);
[~,ia]=ismember(shared,dense.AbsoluteCoordinate); [~,ib]=ismember(shared,sparse.AbsoluteCoordinate);
absoluteMismatch=abs(complex(dense.AbsoluteSequenceReal(ia),dense.AbsoluteSequenceImag(ia))- ...
    complex(sparse.AbsoluteSequenceReal(ib),sparse.AbsoluteSequenceImag(ib)));
compactMismatch=abs(complex(dense.CompactedSequenceReal(ia),dense.CompactedSequenceImag(ia))- ...
    complex(sparse.CompactedSequenceReal(ib),sparse.CompactedSequenceImag(ib)));
assert(max(absoluteMismatch)<1e-12 && any(compactMismatch>1e-12));
layout=tiledlayout(fig,1,3,"Padding","compact","TileSpacing","compact");
layout.Position=[.06 .11 .90 .80];
ax=nexttile(layout); stem(ax,dense.AbsoluteCoordinate,ones(height(dense),1),".","DisplayName","dense"); hold(ax,"on");
stem(ax,sparse.AbsoluteCoordinate,.65*ones(height(sparse),1),".","DisplayName","sparse");
xlabel(ax,"Absolute subcarrier coordinate"); ylabel(ax,"Active mask"); title(ax,"Active coordinates"); legend(ax);
ax=nexttile(layout); plot(ax,shared,dense.AbsoluteSequenceReal(ia),"o-","DisplayName","resource A"); hold(ax,"on");
plot(ax,shared,sparse.AbsoluteSequenceReal(ib),"x--","DisplayName","resource B");
xlabel(ax,"Shared absolute coordinate"); ylabel(ax,"Sequence real part"); title(ax,"Absolute-index identity"); legend(ax);
ax=nexttile(layout); semilogy(ax,shared,max(absoluteMismatch,1e-16),"o-","DisplayName","absolute indexing"); hold(ax,"on");
semilogy(ax,shared,max(compactMismatch,1e-16),"x-","DisplayName","compacted counterexample");
xlabel(ax,"Shared absolute coordinate"); ylabel(ax,"Mismatch magnitude"); title(ax,"Proof and counterexample"); legend(ax);
end

function localOCCWorst(fig,T,id)
phase=localIf(id=="FIG-2.10-1",5,15); q=T(T.PhaseDegPerChip==phase,:);
assert(~isempty(q)); ax=axes(fig,"Position",[.09 .17 .87 .68]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
reference=T(ismember(T.PhaseDegPerChip,[5 15]),:);
allDb=10*log10(reference.WorstLeakage);
familyValue=string(q.OCCFamily);
for family=unique(familyValue,"stable").'
    s=sortrows(q(familyValue==family,:),"CDMSize");
    plot(ax,s.CDMSize,10*log10(max(s.WorstLeakage,realmin)),"o-", ...
        "LineWidth",1.8,"DisplayName",localOCCLabel(family));
end
ylim(ax,[floor(min(allDb)/5)*5 ceil(max(allDb)/5)*5]);
xlabel(ax,"CDM size (chips)"); ylabel(ax,"Worst-pair leakage (dB)");
title(ax,"Deterministic "+phase+" degree/chip linear phase ramp"); legend(ax,"Location","best");
text(ax,.02,.02,"Ideal full unitary basis; phase-only diagonal distortion; no channel, noise, estimator or throughput claim.", ...
    "Units","normalized","FontSize",8,"VerticalAlignment","bottom");
end

function localOCCMeanEquality(fig,T)
family=string(T.OCCFamily); walsh=T(family=="walsh",:); dft=T(family=="dft",:);
walsh=sortrows(walsh,["CDMSize","PhaseDegPerChip"]);
dft=sortrows(dft,["CDMSize","PhaseDegPerChip"]);
assert(height(walsh)==height(dft) && isequal(walsh.CDMSize,dft.CDMSize) && ...
    isequal(walsh.PhaseDegPerChip,dft.PhaseDegPerChip));
delta=walsh.MeanLeakage-dft.MeanLeakage;
assert(max(abs(delta))<1e-12);
ax=axes(fig,"Position",[.09 .16 .87 .74]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
for M=unique(walsh.CDMSize).'
    selected=walsh.CDMSize==M; q=walsh(selected,:); d=delta(selected);
    plot(ax,q.PhaseDegPerChip,d, ...
        "o-","LineWidth",1.5,"DisplayName","L="+M);
end
xlabel(ax,"Linear phase increment (degrees per chip)");
ylabel(ax,"Walsh minus DFT mean leakage"); title(ax,"A = C^H D_\phi C: mean-leakage equality in the phase-only model");
legend(ax,"Location","best");
end

function localDeterministicPhase(fig,T)
assert(max(T.AbsoluteError)<1e-12);
ax=axes(fig,"Position",[.09 .15 .87 .75]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
for M=unique(T.M1).'
    q=sortrows(T(T.M1==M,:),"PhaseIncrementDeg");
    plot(ax,q.PhaseIncrementDeg,q.ClosedFormGain,"o-","LineWidth",1.6,"DisplayName","M_1="+M);
end
xlabel(ax,"Phase increment per slot (degrees)"); ylabel(ax,"Normalized coherent gain");
title(ax,"|sin(M_1 DeltaPhi/2)/(M_1 sin(DeltaPhi/2))|^2; limit 1 at zero"); legend(ax,"Location","best");
end

function localIndependentPhase(fig,T)
assert(all(T.N>=1) && all(isfinite(T.Seed)) && ...
    all(T.GainCI95Low<=T.MonteCarloGain & T.GainCI95High>=T.MonteCarloGain));
ax=axes(fig,"Position",[.09 .15 .87 .75]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
for M=unique(T.M1).'
    q=sortrows(T(T.M1==M,:),"PhaseStdDeg");
    plot(ax,q.PhaseStdDeg,q.TheoreticalGain,"-","LineWidth",1.8,"DisplayName","M_1="+M+" expectation");
    errorbar(ax,q.PhaseStdDeg,q.MonteCarloGain,q.MonteCarloGain-q.GainCI95Low, ...
        q.GainCI95High-q.MonteCarloGain,".","HandleVisibility","off");
end
xlabel(ax,"Phase standard deviation (degrees)"); ylabel(ax,"Expected normalized coherent gain");
title(ax,"Independent phase discontinuity: expectation and Monte-Carlo 95% CI"); legend(ax,"Location","best");
text(ax,.02,.02,"N="+max(T.N)+", seed="+T.Seed(1),"Units","normalized","FontSize",8);
end

function localChannelAging(fig,T,cfg)
assert(all(T.MinimumEigenvalue>-1e-8));
ax=axes(fig,"Position",[.09 .15 .87 .75]); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
for M=unique(T.M1).'
    q=sortrows(T(T.M1==M,:),"SpeedKmph");
    plot(ax,q.SpeedKmph,q.ChannelAgingGain,"o-","LineWidth",1.8,"DisplayName","M_1="+M);
end
xlabel(ax,"UE speed (km/h)"); ylabel(ax,"Normalized coherent gain");
title(ax,"Jakes isotropic aging: f_D = v f_c/c"); legend(ax,"Location","best");
text(ax,.02,.02,"f_c="+double(cfg.carrier.center_frequency_hz)/1e9+ ...
    " GHz; slot="+double(cfg.multislot.slot_duration_s)*1e3+ ...
    " ms; SCS="+double(cfg.carrier.scs_khz)+" kHz", ...
    "Units","normalized","FontSize",8);
end

function ax=localDiagramAxes(fig,titleText)
ax=axes(fig,"Position",[.035 .08 .93 .84]); axis(ax,[0 1 0 1]); axis(ax,"off"); hold(ax,"on");
title(ax,titleText,"FontSize",14,"FontWeight","bold");
end

function localBox(ax,position,label,face,edge)
rectangle(ax,"Position",position,"Curvature",.08,"FaceColor",face, ...
    "EdgeColor",edge,"LineWidth",1.5);
text(ax,position(1)+position(3)/2,position(2)+position(4)/2,label, ...
    "HorizontalAlignment","center","VerticalAlignment","middle", ...
    "Interpreter","none","FontSize",8,"FontWeight","bold", ...
    "Clipping","on");
end

function localArrow(ax,x1,y1,x2,y2)
quiver(ax,x1,y1,x2-x1,y2-y1,0,"Color",[.25 .35 .40], ...
    "LineWidth",1.4,"MaxHeadSize",.35);
end

function localApplyLightTheme(fig)
set(fig,"Color","white"); dark=[.08 .10 .12];
axesList=findall(fig,"Type","axes");
for k=1:numel(axesList)
    ax=axesList(k);
    set(ax,"Color","white","XColor",dark,"YColor",dark, ...
        "GridColor",[.72 .74 .76],"MinorGridColor",[.82 .84 .86]);
end
texts=findall(fig,"Type","text");
for k=1:numel(texts), texts(k).Color=dark; end
legends=findall(fig,"Type","legend");
for k=1:numel(legends)
    set(legends(k),"Color","white","TextColor",dark,"EdgeColor",[.65 .67 .69]);
end
end

function wrapped=localWrapLabel(label,maxCharacters)
words=split(strtrim(string(label)));
lines=strings(0,1); current="";
for k=1:numel(words)
    candidate=strtrim(current+" "+words(k));
    if strlength(candidate)>maxCharacters && strlength(current)>0
        lines(end+1,1)=current; %#ok<AGROW>
        current=words(k);
    else
        current=candidate;
    end
end
if strlength(current)>0, lines(end+1,1)=current; end
wrapped=strjoin(lines,newline);
end

function value=localPowerLabel(mode)
if string(mode)=="fixed_total_csirs", value="Fixed total CSI-RS power";
else, value="Fixed per-port EPRE"; end
end

function value=localOCCLabel(family)
if string(family)=="walsh", value="Walsh OCC"; else, value="DFT OCC"; end
end

function trials=localIndependentTrials(tables)
trials=0;
for k=1:numel(tables)
    names=string(tables{k}.Properties.VariableNames);
    if ismember("N",names), trials=max(trials,max(double(tables{k}.N),[],"omitnan"));
    elseif ismember("TrialIndex",names), trials=max(trials,height(tables{k})); end
end
end

function value=localIf(tf,yes,no)
if tf, value=yes; else, value=no; end
end
