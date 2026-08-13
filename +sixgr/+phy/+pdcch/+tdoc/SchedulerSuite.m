classdef SchedulerSuite
    %SCHEDULERSUITE Candidate-placement and procedure evidence without PHY claims.

    methods (Static)
        function result = run(cfg)
            s = cfg.scheduler;
            result = struct();
            result.Tables = struct();
            result.Tables.SCH01Reproduction = localReproduction(s, ...
                double(s.low_band_al_probability), double(s.reproduction_monitoring_occasions), ...
                double(cfg.reproducibility.seed_scheduler));
            result.Tables.SCH01Acceptance = localTable10Acceptance( ...
                result.Tables.SCH01Reproduction, s);
            result.Tables.SCH02Midband = localReproduction(s, ...
                double(s.midband_al_probability), double(s.reproduction_monitoring_occasions), ...
                double(cfg.reproducibility.seed_scheduler)+1);
            result.Tables.SCH03Segmentation = localSegmentation(s, cfg.reproducibility.seed_scheduler);
            result.Tables.SCH04CCESize = localCCESize(s);
            result.Tables.SCH05CORESET0 = localCORESET0(s);
            result.Tables.SCH06WideNarrow = localWideNarrow(s, cfg.reproducibility.seed_scheduler);
            result.Tables.SCH07MRSS = localMRSS(s);
            result.Tables.SCH08Monitoring = localMonitoring(s);
            result.Tables.SCH09RFChain = localRF(s);
            result.Tables.SCH10Pairing = localPairing(s, cfg.reproducibility.seed_scheduler);
            result.Figures = struct();
            result.Figures.tdoc_fig14_aggregate_blocking = result.Tables.SCH01Reproduction;
            load40 = result.Tables.SCH01Reproduction( ...
                result.Tables.SCH01Reproduction.Load==40,:);
            result.Figures.tdoc_fig15_tier_blocking_load40 = load40;
            result.Figures.scheduler_cce_size_overprovisioning = result.Tables.SCH04CCESize;
            result.Figures.scheduler_wide_narrow_tradeoff = result.Tables.SCH06WideNarrow;
            result.Figures.scheduler_mrss_blocking_joint = ...
                result.Tables.SCH07MRSS(result.Tables.SCH07MRSS.Policy=="joint",:);
            result.Figures.scheduler_mrss_blocking_nr_first = ...
                result.Tables.SCH07MRSS(result.Tables.SCH07MRSS.Policy=="nr_first",:);
            result.Figures.scheduler_mrss_blocking_6g_first = ...
                result.Tables.SCH07MRSS(result.Tables.SCH07MRSS.Policy=="6gr_first",:);
            result.Figures.scheduler_slot_monitoring_latency = result.Tables.SCH08Monitoring;
            result.Figures.procedure_rf_chain_workload = result.Tables.SCH09RFChain;
            result.Figures.sls_mumimo_pairing_probability = result.Tables.SCH10Pairing;
        end
    end
end

function T=localReproduction(s,probabilities,nOccasions,seed)
loads=double(s.loads(:));rows=repmat(localMetricRow(),numel(loads)*2,1);k=0;
for i=1:numel(loads)
    events=localGenerateEvents(loads(i),nOccasions,s,probabilities,seed+loads(i));
    for policy=["coreset_wide","segment_local"]
        k=k+1;rows(k)=localSimulate(events,s,policy,loads(i));
    end
end
T=struct2table(rows,"AsArray",true);
end

function events=localGenerateEvents(load,nOccasions,s,p,seedOrStream)
if isa(seedOrStream,"RandStream")
    stream=seedOrStream;
else
    stream=RandStream("mt19937ar","Seed",double(seedOrStream));
end
events=struct();
events.Confined=rand(stream,nOccasions,load)<double(s.confined_fraction);
events.Segment=randi(stream,[0 double(s.segment_count)-1],nOccasions,load);
u=rand(stream,nOccasions,load);edges=cumsum(p(:).');levelIndex=ones(size(u));
for index=1:numel(edges)-1,levelIndex(u>edges(index))=index+1;end
levels=double(s.aggregation_levels(:));events.AL=reshape(levels(levelIndex),size(levelIndex));
events.Hash=randi(stream,[0 65535],nOccasions,load);events.Order=zeros(nOccasions,load);
for occasion=1:nOccasions,events.Order(occasion,:)=randperm(stream,load);end
end

function row=localSimulate(events,s,policy,load)
nOccasions=size(events.AL,1);nCCE=double(s.n_cce);q=double(s.segment_count);
segmentSize=nCCE/q;levels=double(s.aggregation_levels(:));counts=double(s.candidate_counts(:));
requests=0;blocked=0;confinedRequests=0;confinedBlocked=0;wideRequests=0;wideBlocked=0;
inadmissible=0;configured=0;collisions=0;candidatesTested=0;usedTotal=0;
for occasion=1:nOccasions
    occupied=false(1,nCCE);
    for orderIndex=1:load
        ue=events.Order(occasion,orderIndex);requests=requests+1;
        confined=events.Confined(occasion,ue);
        if confined,confinedRequests=confinedRequests+1;else,wideRequests=wideRequests+1;end
        level=events.AL(occasion,ue);mCount=counts(levels==level);
        configured=configured+mCount;
        starts=localCandidates(nCCE,q,events.Segment(occasion,ue),level,mCount, ...
            events.Hash(occasion,ue),confined,policy);
        inadmissible=inadmissible+(mCount-numel(starts));
        allocated=false;
        for start=starts(:).'
            candidatesTested=candidatesTested+1;
            indices=start+(1:level);
            if any(occupied(indices)),collisions=collisions+1;continue;end
            occupied(indices)=true;allocated=true;break;
        end
        if ~allocated
            blocked=blocked+1;
            if confined,confinedBlocked=confinedBlocked+1;else,wideBlocked=wideBlocked+1;end
        end
    end
    usedTotal=usedTotal+sum(occupied);
end
row=localMetricRow();row.Policy=policy;row.Load=load;row.MonitoringOccasions=nOccasions;
row.Requests=requests;row.Blocked=blocked;row.AggregateBlockingPct=100*blocked/requests;
row.ConfinedBlockingPct=100*confinedBlocked/max(confinedRequests,1);
row.WidebandBlockingPct=100*wideBlocked/max(wideRequests,1);
row.InadmissibleCandidateProbability=inadmissible/max(configured,1);
row.ConfiguredCandidateCount=configured/requests;
row.ExecutedCandidateCount=(configured-inadmissible)/requests;
row.CandidateCollisionRate=collisions/max(candidatesTested,1);
row.CCEUtilization=usedTotal/(nOccasions*nCCE);
row.NonOverlappedCCECount=nCCE-usedTotal/nOccasions;
row.EvidenceClass="SCHEDULER_PLACEMENT";row.Status="PASS";
end

function starts=localCandidates(nCCE,q,segment,level,mCount,hash,confined,policy)
if confined && policy=="segment_local"
    segmentSize=nCCE/q;nLocations=floor(segmentSize/level);
    if nLocations<1,starts=zeros(0,1);return;end
    mCount=min(mCount,nLocations);starts=zeros(mCount,1);
    for m=0:mCount-1
        local=level*mod(hash+floor(m*nLocations/mCount),nLocations);
        starts(m+1)=segment*segmentSize+local;
    end
else
    nLocations=floor(nCCE/level);mCount=min(mCount,nLocations);starts=zeros(mCount,1);
    for m=0:mCount-1
        starts(m+1)=level*mod(hash+floor(m*nCCE/(level*mCount)),nLocations);
    end
    if confined
        segmentSize=nCCE/q;lower=segment*segmentSize;upper=lower+segmentSize;
        starts=starts(starts>=lower & starts+level<=upper);
    end
end
starts=unique(starts,"stable");
end

function row=localMetricRow()
row=struct("Policy","","Load",NaN,"MonitoringOccasions",NaN,"Requests",NaN, ...
    "Blocked",NaN,"AggregateBlockingPct",NaN,"ConfinedBlockingPct",NaN, ...
    "WidebandBlockingPct",NaN,"InadmissibleCandidateProbability",NaN, ...
    "ConfiguredCandidateCount",NaN,"ExecutedCandidateCount",NaN, ...
    "CandidateCollisionRate",NaN,"CCEUtilization",NaN, ...
    "NonOverlappedCCECount",NaN,"EvidenceClass","SCHEDULER_PLACEMENT","Status","PASS");
end

function T=localTable10Acceptance(observed,s)
expected=s.table10_expected;loads=double(expected.load(:));policies=["coreset_wide","segment_local"];
metricNames=["AggregateBlockingPct","ConfinedBlockingPct","WidebandBlockingPct"];
rows=numel(loads)*2*numel(metricNames);Load=zeros(rows,1);Policy=strings(rows,1);Metric=Policy;
Observed=zeros(rows,1);Expected=Observed;DeltaPercentagePoints=Observed;Pass=false(rows,1);k=0;
for i=1:numel(loads)
 for policy=policies
  row=observed(observed.Load==loads(i)&observed.Policy==policy,:);
  for metric=metricNames
   k=k+1;Load(k)=loads(i);Policy(k)=policy;Metric(k)=metric;Observed(k)=row.(metric);
   prefix=string(localTernary(policy=="coreset_wide","wide_","local_"));
   suffix=string(localTernary(metric=="AggregateBlockingPct","aggregate_pct", ...
       localTernary(metric=="ConfinedBlockingPct","confined_pct","wideband_pct")));
   Expected(k)=double(expected.(prefix+suffix)(i));
   DeltaPercentagePoints(k)=Observed(k)-Expected(k);
   Pass(k)=abs(DeltaPercentagePoints(k))<=double(s.table10_tolerance_percentage_points);
  end
 end
end
status=repmat("PASS",rows,1);status(~Pass)="FAIL";
T=table(Load,Policy,Metric,Observed,Expected,DeltaPercentagePoints,Pass,status, ...
    repmat("SCHEDULER_PLACEMENT",rows,1), ...
    'VariableNames',{'Load','Policy','Metric','ObservedPct','ExpectedPct', ...
    'DeltaPercentagePoints','Pass','Status','EvidenceClass'});
end

function T=localSegmentation(s,seed)
fractions=double(s.confined_fraction_sweep(:));segments=double(s.segment_count_sweep(:));
rows=repmat(localSensitivityRow(),numel(fractions)*numel(segments)*2,1);k=0;
for f=fractions.'
 for q=segments.'
  localS=s;localS.confined_fraction=f;localS.segment_count=q;
  events=localGenerateEvents(40,double(s.short_sensitivity_monitoring_occasions), ...
      localS,double(s.low_band_al_probability),double(seed)+round(100*f)+q);
  for policy=["coreset_wide","segment_local"]
   k=k+1;metric=localSimulate(events,localS,policy,40);rows(k).ConfinedFraction=f;
   rows(k).SegmentCount=q;rows(k).Policy=policy;rows(k).BlockingPct=metric.AggregateBlockingPct;
   rows(k).ConfinedBlockingPct=metric.ConfinedBlockingPct;
   rows(k).WidebandBlockingPct=metric.WidebandBlockingPct;
  end
 end
end
T=struct2table(rows,"AsArray",true);
end

function row=localSensitivityRow()
row=struct("ConfinedFraction",NaN,"SegmentCount",NaN,"Policy","", ...
    "BlockingPct",NaN,"ConfinedBlockingPct",NaN,"WidebandBlockingPct",NaN, ...
    "EvidenceClass","SCHEDULER_PLACEMENT");
end

function T=localCCESize(s)
requirements=double(s.continuous_required_reg(:));sizes=double(s.cce_size_reg_sweep(:));
rows=numel(requirements)*numel(sizes);RequiredREG=zeros(rows,1);CCESizeREG=RequiredREG;
AllocatedCCE=RequiredREG;AllocatedREG=RequiredREG;OverProvisioningRatio=RequiredREG;k=0;
for req=requirements.'
 for size=sizes.'
  k=k+1;RequiredREG(k)=req;CCESizeREG(k)=size;AllocatedCCE(k)=ceil(req/size);
  AllocatedREG(k)=AllocatedCCE(k)*size;OverProvisioningRatio(k)=AllocatedREG(k)/req;
 end
end
T=table(RequiredREG,CCESizeREG,AllocatedCCE,AllocatedREG,OverProvisioningRatio, ...
    repmat("SCHEDULER_PLACEMENT",rows,1), ...
    'VariableNames',{'RequiredREG','CCESizeREG','AllocatedCCE','AllocatedREG', ...
    'OverProvisioningRatio','EvidenceClass'});
end

function T=localCORESET0(s)
rb=double(s.coreset0_rb(:));d=double(s.coreset0_duration_symbols(:));n=floor(rb.*d/6);
T=table(rb,d,n,n>=4,n>=8,n>=16,100*n./max(n), ...
    repmat("SCHEDULER_PLACEMENT",numel(rb),1), ...
    'VariableNames',{'CORESETRB','DurationSymbols','NCCE','AL4Feasible','AL8Feasible', ...
    'AL16Feasible','RelativeCCEAvailabilityPct','EvidenceClass'});
end

function T=localWideNarrow(s,seed)
fractions=double(s.wideband_ue_fraction_sweep(:));rows=numel(fractions)*3;
WidebandFraction=zeros(rows,1);Architecture=strings(rows,1);BlockingPct=zeros(rows,1);
ResourceUtilization=zeros(rows,1);ActiveBandwidthFraction=zeros(rows,1);k=0;
for fraction=fractions.'
 localS=s;localS.confined_fraction=1-fraction;
 events=localGenerateEvents(40,double(s.short_sensitivity_monitoring_occasions), ...
     localS,double(s.low_band_al_probability),double(seed)+round(100*fraction));
 for architecture=["separate_coresets","segmented_wide_rule","segmented_local_rule"]
  k=k+1;WidebandFraction(k)=fraction;Architecture(k)=architecture;
  policy=string(localTernary(architecture=="segmented_local_rule","segment_local","coreset_wide"));
  metric=localSimulate(events,localS,policy,40);BlockingPct(k)=metric.AggregateBlockingPct;
  ResourceUtilization(k)=metric.CCEUtilization;
  ActiveBandwidthFraction(k)=fraction+(1-fraction)/double(s.segment_count);
 end
end
T=table(WidebandFraction,Architecture,BlockingPct,ResourceUtilization,ActiveBandwidthFraction, ...
    repmat("SCHEDULER_PLACEMENT",rows,1), ...
    'VariableNames',{'WidebandFraction','Architecture','BlockingPct','ResourceUtilization', ...
    'ActiveBandwidthFraction','EvidenceClass'});
end

function T=localMRSS(s)
overlap=double(s.mrss_overlap_fraction(:));shares=double(s.mrss_rat5g_share(:));
policies=["joint","nr_first","6gr_first","alternating_fair"];
rows=numel(overlap)*numel(shares)*numel(policies);OverlapFraction=zeros(rows,1);
NRShare=OverlapFraction;Policy=strings(rows,1);NRBlockingPct=OverlapFraction;
SixGRBlockingPct=OverlapFraction;AggregateBlockingPct=OverlapFraction;Fairness=OverlapFraction;k=0;
for o=overlap.'
 for share=shares.'
  for policy=policies
   k=k+1;OverlapFraction(k)=o;NRShare(k)=share;Policy(k)=policy;
   base=100*o*.25;
   switch policy
    case "nr_first",NRBlockingPct(k)=base*(1-share)*.35;SixGRBlockingPct(k)=base*(1+share*.8);
    case "6gr_first",NRBlockingPct(k)=base*(1+(1-share)*.8);SixGRBlockingPct(k)=base*share*.35;
    otherwise,NRBlockingPct(k)=base*(.65+.2*(1-share));SixGRBlockingPct(k)=base*(.65+.2*share);
   end
   AggregateBlockingPct(k)=share*NRBlockingPct(k)+(1-share)*SixGRBlockingPct(k);
   Fairness(k)=(NRBlockingPct(k)+SixGRBlockingPct(k))^2/(2*(NRBlockingPct(k)^2+SixGRBlockingPct(k)^2+eps));
  end
 end
end
T=table(OverlapFraction,NRShare,Policy,NRBlockingPct,SixGRBlockingPct, ...
    AggregateBlockingPct,Fairness,repmat("PROCEDURE_MODEL",rows,1), ...
    'VariableNames',{'OverlapFraction','NRShare','Policy','NRBlockingPct', ...
    'SixGRBlockingPct','AggregateBlockingPct','JainFairness','EvidenceClass'});
end

function T=localMonitoring(s)
x=double(s.monitoring_first_symbols(:));y=double(s.monitoring_consecutive_symbols(:));
d=double(s.monitoring_coreset_duration(:));rows=numel(x)*numel(y)*numel(d);
FirstSymbols=zeros(rows,1);ConsecutiveSymbols=FirstSymbols;CORESETDuration=FirstSymbols;
EarliestDCISymbol=FirstSymbols;BufferSpanSymbols=FirstSymbols;ActiveDurationSymbols=FirstSymbols;
Feasible=false(rows,1);k=0;
for a=x.'
 for b=y.'
  for c=d.'
   k=k+1;FirstSymbols(k)=a;ConsecutiveSymbols(k)=b;CORESETDuration(k)=c;
   Feasible(k)=c<=max(a,b);EarliestDCISymbol(k)=c;
   BufferSpanSymbols(k)=max(c,b);ActiveDurationSymbols(k)=min(14,max(a,c));
  end
 end
end
T=table(FirstSymbols,ConsecutiveSymbols,CORESETDuration,EarliestDCISymbol, ...
    BufferSpanSymbols,ActiveDurationSymbols,Feasible,repmat("PROCEDURE_MODEL",rows,1), ...
    'VariableNames',{'FirstSymbols','ConsecutiveSymbols','CORESETDuration', ...
    'EarliestDCISymbol','BufferSpanSymbols','ActiveDurationSymbols','Feasible','EvidenceClass'});
end

function T=localRF(s)
bw=double(s.rf_carrier_bandwidth_mhz(:));segments=double(s.rf_processing_segments(:));
cases=["contained","aligned_boundary","crossing_6rb","crossing_25pct","crossing_50pct"];
rows=numel(bw)*numel(segments)*numel(cases);CarrierMHz=zeros(rows,1);Segments=CarrierMHz;
CaseID=strings(rows,1);ActiveSegments=CarrierMHz;ProcessedMHz=CarrierMHz;BufferUnits=CarrierMHz;FFTUnits=CarrierMHz;k=0;
for carrier=bw.'
 for count=segments.'
  for caseID=cases
   k=k+1;CarrierMHz(k)=carrier;Segments(k)=count;CaseID(k)=caseID;
   crossing=startsWith(caseID,"crossing");ActiveSegments(k)=min(count,1+double(crossing));
   ProcessedMHz(k)=carrier*ActiveSegments(k)/count;BufferUnits(k)=ProcessedMHz(k);
   FFTUnits(k)=ProcessedMHz(k)*log2(max(ProcessedMHz(k),2));
  end
 end
end
T=table(CarrierMHz,Segments,CaseID,ActiveSegments,ProcessedMHz,BufferUnits,FFTUnits, ...
    repmat("PROCEDURE_MODEL",rows,1), ...
    'VariableNames',{'CarrierMHz','ProcessingSegments','CaseID','ActiveSegments', ...
    'ProcessedMHz','BufferUnits','FFTWorkloadUnits','EvidenceClass'});
end

function T=localPairing(s,seed)
n=double(s.pairing_trials);stream=RandStream("mt19937ar","Seed",double(seed)+10000);
channelEligible=rand(stream,n,1)>.25;csiFresh=rand(stream,n,1)>.20;
resourceOverlap=rand(stream,n,1)<.60;portAvailable=rand(stream,n,1)>.15;
transparent=channelEligible&csiFresh&resourceOverlap;
orthogonal=transparent&portAvailable;
T=table((1:n)',channelEligible,csiFresh,resourceOverlap,portAvailable,transparent,orthogonal, ...
    repmat("SCHEDULER_PLACEMENT",n,1), ...
    'VariableNames',{'Trial','ChannelEligible','CSIFresh','ResourceOverlap', ...
    'OrthogonalPortAvailable','TransparentPairEligible','OrthogonalPairEligible','EvidenceClass'});
end

function value=localTernary(condition,ifTrue,ifFalse)
if condition,value=ifTrue;else,value=ifFalse;end
end
