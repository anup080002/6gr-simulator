classdef AnalyticalSuite
    %ANALYTICALSUITE Exact arithmetic and enumeration for AI 10.5.2.1.

    methods (Static)
        function result = run(cfg)
            a = cfg.analytical;
            result = struct();
            result.Tables = struct();
            result.Figures = struct();

            result.Figures.tdoc_fig01_pdcch_resource_chain = localResourceChain();
            result.Tables.ANA02PayloadFeasibility = localPayloadFeasibility(a);
            result.Figures.tdoc_fig02_cce_resource_tradeoff = ...
                result.Tables.ANA02PayloadFeasibility;
            [result.Tables.ANA03MappingSegments, ...
                result.Figures.tdoc_fig03_mapping_segment_framework] = ...
                localMappingSegments(a);
            result.Tables.ANA04InterleaverFeasibility = localInterleaver(a);
            result.Figures.tdoc_fig04_interleaver_feasibility_depth = ...
                result.Tables.ANA04InterleaverFeasibility;
            result.Tables.ANA05WidebandShift = localWidebandShift(a);
            result.Tables.ANA06DMRSSpacing = localDMRS(a);
            result.Figures.tdoc_fig05_dmrs_spacing_observations = ...
                result.Tables.ANA06DMRSSpacing;
            result.Tables.ANA07CCEAvailability = localCCEBudget(a);
            result.Figures.tdoc_fig06_coreset_cce_budget = ...
                result.Tables.ANA07CCEAvailability;
            [result.Tables.ANA08CandidateEnumeration, ...
                result.Tables.ANA08CandidateSummary] = localEnumeration(a);
            result.Figures.tdoc_fig07_candidate_domains = ...
                result.Tables.ANA08CandidateEnumeration;
            result.Figures.tdoc_fig08_zero_admissible_probability = ...
                result.Tables.ANA08CandidateSummary;
            result.Tables.ANA09PolarRateMatching = localPolar(a);
            result.Figures.tdoc_fig09_polar_e_over_n = ...
                result.Tables.ANA09PolarRateMatching;
            result.Tables.ANA10BitmapScaling = localBitmap(a);
            [result.Tables.ANA11RFChainGeometry, ...
                result.Figures.tdoc_fig10_rf_chain_alignment] = localRFChain();
            result.Tables.ANA12CORESET0 = localCORESET0();
            result.Figures.tdoc_fig11_coreset0_cce_availability = ...
                result.Tables.ANA12CORESET0;
            [result.Figures.tdoc_fig12_mrss_geometry, ...
                result.Figures.tdoc_fig13_evaluation_discipline] = localMRSS();
            result.Acceptance = localAcceptance(result.Tables);
            if ~all(result.Acceptance.Pass)
                failed = result.Acceptance.Check(~result.Acceptance.Pass);
                error("sixgr:phy:pdcch:tdoc:AnalyticalAcceptanceFailed", ...
                    "Exact analytical acceptance failed: %s.", strjoin(failed, ", "));
            end
        end
    end
end

function T = localResourceChain()
labels = ["Resource element (RE)";"Resource-element group (REG)"; ...
    "REG bundle";"Control-channel element (CCE)";"PDCCH candidate"; ...
    "Search Space";"CORESET"];
T = table((1:numel(labels))', ones(numel(labels),1), labels, ...
    repmat("STATIC_VISUAL",numel(labels),1), ...
    'VariableNames',{'X','Y','Label','EvidenceClass'});
end

function T = localPayloadFeasibility(a)
S = double(a.cce_sizes_reg(:));
A = double(a.payload_bits(:));
AL = double(a.aggregation_levels_feasibility(:));
rows = numel(S)*numel(A)*numel(AL);
cceSize = zeros(rows,1); payload = cceSize; aggregation = cceSize;
eReg = cceSize; eCCE = cceSize; eAL = cceSize; rawRate = cceSize;
nCCE = cceSize; feasible = false(rows,1); k = 0;
for s = S.'
    for payloadBits = A.'
        for level = AL.'
            k=k+1;
            cceSize(k)=s;payload(k)=payloadBits;aggregation(k)=level;
            eReg(k)=double(a.qpsk_bits_per_symbol)*(double(a.re_per_rb_symbol)-3);
            eCCE(k)=s*eReg(k);eAL(k)=level*eCCE(k);
            rawRate(k)=(payloadBits+24)/eAL(k);
            nCCE(k)=floor(double(a.total_reg)/s);
            feasible(k)=rawRate(k)<=1;
        end
    end
end
T=table(cceSize,payload,aggregation,eReg,eCCE,eAL,rawRate,nCCE,feasible, ...
    repmat("ANALYTICAL_EXACT",rows,1), ...
    'VariableNames',{'CCESizeREG','PayloadBits','AggregationLevel', ...
    'CodedBitsPerREG','CodedBitsPerCCE','CodedBitsPerCandidate','RawCodeRate', ...
    'CCELocationsIn288REG','PayloadFeasible','EvidenceClass'});
end

function [T,F] = localMappingSegments(a)
geometries = [24 3 1;24 3 2;18 2 3];
rows = sum(geometries(:,1).*geometries(:,2));
segment = zeros(rows,1);localRB=segment;localSymbol=segment;
localREG=segment;offset=segment;globalREG=segment; k=0;
for p=1:size(geometries,1)
    nrb=geometries(p,1);duration=geometries(p,2);
    prior=sum(geometries(1:p-1,1).*geometries(1:p-1,2));
    for rb=0:nrb-1
        for sym=0:duration-1
            k=k+1;segment(k)=p;localRB(k)=rb;localSymbol(k)=sym;
            localREG(k)=rb*duration+sym;offset(k)=prior;
            globalREG(k)=prior+localREG(k);
        end
    end
end
T=table(segment,localRB,localSymbol,localREG,offset,globalREG, ...
    repmat("ANALYTICAL_EXACT",rows,1), ...
    'VariableNames',{'Segment','RBLocal','SymbolLocal','REGLocal','SegmentOffset', ...
    'REGGlobal','EvidenceClass'});
F=table([0;0;3;3],[0;24;0;24],[24;24;24;24],[3;3;3;3], ...
    ["segment_1";"segment_2";"segment_3";"segment_4"], ...
    repmat("STATIC_VISUAL",4,1), ...
    'VariableNames',{'StartSymbol','StartRB','SizeRB','DurationSymbols','Label','EvidenceClass'});
end

function T=localInterleaver(a)
rb=double(a.segment_rb(:));duration=double(a.segment_duration_symbols(:));
bundle=double(a.reg_bundle_sizes(:));r=double(a.interleaver_r(:));
rows=numel(rb)*numel(duration)*numel(bundle)*numel(r);
RB=zeros(rows,1);D=RB;L=RB;R=RB;NREG=RB;NBundle=RB;Depth=nan(rows,1);
valid=false(rows,1);classification=strings(rows,1);k=0;
for x=rb.'
 for d=duration.'
  for l=bundle.'
   for ir=r.'
    k=k+1;RB(k)=x;D(k)=d;L(k)=l;R(k)=ir;NREG(k)=x*d;
    valid(k)=mod(NREG(k),l*ir)==0;
    if valid(k)
        NBundle(k)=NREG(k)/l;Depth(k)=NREG(k)/(l*ir);
        if Depth(k)==1,classification(k)="valid_non_spreading";
        else,classification(k)="spreading_capable";end
    else
        NBundle(k)=floor(NREG(k)/l);classification(k)="invalid_divisibility";
    end
   end
  end
 end
end
T=table(RB,D,L,R,NREG,NBundle,Depth,valid,classification, ...
    repmat("ANALYTICAL_EXACT",rows,1), ...
    'VariableNames',{'SegmentRB','DurationSymbols','REGBundleSize','InterleaverR', ...
    'NREG','NBundle','InterleaverDepth','Valid','Classification','EvidenceClass'});
end

function T=localWidebandShift(a)
rb=double(a.wideband_coreset_rb(:));duration=double(a.segment_duration_symbols(:));
bundle=double(a.reg_bundle_sizes(:));rows=numel(rb)*numel(duration)*numel(bundle)*2;
RB=zeros(rows,1);D=RB;L=RB;domain=strings(rows,1);domainSize=RB;
bundleCount=RB;reachable=RB;fraction=RB;uniquePermutations=RB;k=0;
for x=rb.'
 for d=duration.'
  for l=bundle.'
   nBundle=floor(x*d/l);
   for mode=["nr_0_274","full_bundle_domain"]
    k=k+1;RB(k)=x;D(k)=d;L(k)=l;domain(k)=mode;bundleCount(k)=nBundle;
    if mode=="nr_0_274",domainSize(k)=275;else,domainSize(k)=nBundle;end
    reachable(k)=min(domainSize(k),nBundle);fraction(k)=reachable(k)/nBundle;
    uniquePermutations(k)=reachable(k);
   end
  end
 end
end
T=table(RB,D,L,domain,domainSize,bundleCount,reachable,fraction,uniquePermutations, ...
    repmat("ANALYTICAL_EXACT",rows,1), ...
    'VariableNames',{'CORESETRB','DurationSymbols','REGBundleSize','ShiftDomain', ...
    'ShiftDomainSize','NBundle','ReachableOffsets','ReachableFraction', ...
    'UniquePermutations','EvidenceClass'});
end

function T=localDMRS(a)
dmrs=double(a.dmrs_re_per_reg(:));scs=double(a.scs_hz(:));
rows=numel(dmrs)*numel(scs);N=zeros(rows,1);SCS=N;spacing=N;aliasUs=N;
eReg=N;increase=N;k=0;
for n=dmrs.'
 for deltaF=scs.'
  k=k+1;N(k)=n;SCS(k)=deltaF;spacing(k)=12/n;
  aliasUs(k)=1e6/(spacing(k)*deltaF);
  eReg(k)=2*(12-n);increase(k)=100*(eReg(k)/18-1);
 end
end
T=table(N,SCS,spacing,aliasUs,eReg,increase, ...
    repmat("ANALYTICAL_EXACT",rows,1), ...
    'VariableNames',{'DMRSPerREG','SCSHz','NominalSpacingSubcarriers', ...
    'AliasWindowUs','CodedBitsPerREGQPSK','CodedResourceIncreasePct','EvidenceClass'});
end

function T=localCCEBudget(a)
rb=double(a.cce_budget_rb(:));duration=double(a.cce_budget_duration_symbols(:));
al=double(a.cce_budget_aggregation_levels(:));rows=numel(rb)*numel(duration)*numel(al);
RB=zeros(rows,1);D=RB;AL=RB;NCCE=RB;DMin=RB;feasible=false(rows,1);realisable=false(rows,1);k=0;
for x=rb.'
 for d=duration.'
  for level=al.'
   k=k+1;RB(k)=x;D(k)=d;AL(k)=level;NCCE(k)=floor(x*d/6);
   DMin(k)=ceil(6*level/x);feasible(k)=NCCE(k)>=level;realisable(k)=d<=14;
  end
 end
end
T=table(RB,D,AL,NCCE,DMin,feasible,realisable, ...
    repmat("ANALYTICAL_EXACT",rows,1), ...
    'VariableNames',{'CORESETRB','DurationSymbols','AggregationLevel','NCCE', ...
    'MinimumDurationSymbols','Feasible','RealisableWithinNormalCPSlot','EvidenceClass'});
end

function [detail,summary]=localEnumeration(a)
nCCE=double(a.enumeration_n_cce);q=double(a.enumeration_segments);
segSize=nCCE/q;levels=double(a.enumeration_aggregation_levels(:));
counts=double(a.enumeration_candidate_counts(:));
rows=sum(nCCE./levels);L=zeros(rows,1);M=L;Y=L;admissible=L;
boundarySafeFraction=L;startsText=strings(rows,1);k=0;
for index=1:numel(levels)
 level=levels(index);mCount=counts(index);domain=nCCE/level;
 for residue=0:domain-1
  k=k+1;starts=zeros(mCount,1);
  for m=0:mCount-1
   starts(m+1)=level*mod(residue+floor(m*nCCE/(level*mCount)),domain);
  end
  inside=starts>=0 & starts+level<=segSize;
  allBoundarySafe=mod(starts,segSize)+level<=segSize;
  L(k)=level;M(k)=mCount;Y(k)=residue;admissible(k)=sum(inside);
  boundarySafeFraction(k)=mean(allBoundarySafe);startsText(k)=strjoin(string(starts),"|");
 end
end
detail=table(L,M,Y,admissible,boundarySafeFraction,startsText, ...
    repmat("ENUMERATION_EXACT",rows,1), ...
    'VariableNames',{'AggregationLevel','ConfiguredCandidates','HashResidue', ...
    'AdmissibleCandidates','BoundarySafeFraction','CandidateStartsCCE','EvidenceClass'});
summary=groupsummary(detail,"AggregationLevel",["mean","sum"],"AdmissibleCandidates");
summary.ZeroAdmissibleProbability=zeros(height(summary),1);
summary.MeanBoundarySafeFraction=zeros(height(summary),1);
for i=1:height(summary)
 mask=detail.AggregationLevel==summary.AggregationLevel(i);
 summary.ZeroAdmissibleProbability(i)=mean(detail.AdmissibleCandidates(mask)==0);
 summary.MeanBoundarySafeFraction(i)=mean(detail.BoundarySafeFraction(mask));
end
summary.EvidenceClass=repmat("ENUMERATION_EXACT",height(summary),1);
end

function T=localPolar(a)
al=[1;2;4;8;16;32];payload=140*ones(size(al));K=payload+24;
E=108*al;N=double(a.polar_n_max)*ones(size(al));ratio=E./N;
mode=strings(size(al));mode(ratio<1)="puncturing_or_shortening";
mode(ratio==1)="mother_code_length";mode(ratio>1)="repetition";
T=table(al,payload,K,E,N,ratio,mode,repmat("ANALYTICAL_EXACT",numel(al),1), ...
    'VariableNames',{'AggregationLevel','PayloadBits','PolarK','RateMatchedE', ...
    'PolarNMax','EoverN','RateMatchState','EvidenceClass'});
end

function T=localBitmap(a)
rb=double(a.flat_bitmap_rb(:));groups=ceil(rb/6);
T=table(rb,groups,groups*6-rb,repmat("ANALYTICAL_EXACT",numel(rb),1), ...
    'VariableNames',{'CORESETRB','BitmapGroups','UnusedRBInLastGroup','EvidenceClass'});
end

function [T,F]=localRFChain()
T=table(["contained";"aligned_boundary";"crossing_boundary"], ...
    [1;1;2],[200;200;400],[1;1;2],[1;1;2], ...
    repmat("PROCEDURE_MODEL",3,1), ...
    'VariableNames',{'CaseID','ActiveProcessingSegments','ProcessedBandwidthMHz', ...
    'BufferSpanUnits','FFTWorkloadUnits','EvidenceClass'});
F=table([0;200;150],[200;200;100],[1;1;2], ...
    ["segment_1";"segment_2";"cross_boundary_coreset"], ...
    repmat("STATIC_VISUAL",3,1), ...
    'VariableNames',{'StartMHz','WidthMHz','Lane','Label','EvidenceClass'});
end

function T=localCORESET0()
rb=[12;15;24;25;48];duration=[2;3;3;3;3];nCCE=floor(rb.*duration/6);
T=table(rb,duration,nCCE,nCCE>=4,nCCE>=8,nCCE>=16, ...
    repmat("ANALYTICAL_EXACT",numel(rb),1), ...
    'VariableNames',{'CORESETRB','DurationSymbols','NCCE','AL4Feasible', ...
    'AL8Feasible','AL16Feasible','EvidenceClass'});
end

function [F12,F13]=localMRSS()
F12=table([0;0;36;60],[48;72;48;36],[1;2;2;3], ...
    ["NR_CORESET";"6GR_CORESET";"partial_overlap";"coordinated_partition"], ...
    repmat("STATIC_VISUAL",4,1), ...
    'VariableNames',{'StartCCE','WidthCCE','Lane','Label','EvidenceClass'});
labels=["Exact arithmetic";"Exact enumeration";"Scheduler placement"; ...
    "Calibrated waveform LLS";"Full implementation conclusion"];
F13=table((1:5)',ones(5,1),labels,repmat("STATIC_VISUAL",5,1), ...
    'VariableNames',{'X','Y','Label','EvidenceClass'});
end

function T=localAcceptance(t)
checks=["coded_bits_per_cce";"cce_locations";"dmrs_resource_increase"; ...
    "table6_zero_probability";"table6_mean_candidates"; ...
    "table6_al16_boundary_fraction";"coreset0_geometry"];
pass=false(numel(checks),1);measured=strings(numel(checks),1);expected=strings(numel(checks),1);
ana02=t.ANA02PayloadFeasibility;
pass(1)=isequal(unique(ana02.CodedBitsPerCCE).',[72 108 144]);
measured(1)=strjoin(string(unique(ana02.CodedBitsPerCCE).'),"|");expected(1)="72|108|144";
pass(2)=isequal(unique(ana02.CCELocationsIn288REG).',[36 48 72]);
measured(2)=strjoin(string(unique(ana02.CCELocationsIn288REG).'),"|");expected(2)="36|48|72";
inc=unique(round(t.ANA06DMRSSpacing.CodedResourceIncreasePct,10)).';
pass(3)=max(abs(inc-[0 11.1111111111 22.2222222222]))<1e-9;
measured(3)=strjoin(string(inc),"|");expected(3)="0|11.1111111111|22.2222222222";
s=t.ANA08CandidateSummary;[~,order]=sort(s.AggregationLevel);s=s(order,:);
zero=s.ZeroAdmissibleProbability.';means=s.mean_AdmissibleCandidates.';
pass(4)=max(abs(zero-[0 0 0 .5 5/6]))<1e-12;
measured(4)=strjoin(string(zero),"|");expected(4)="0|0|0|0.5|0.833333333333";
pass(5)=max(abs(means-[2 1.5 1 .5 1/6]))<1e-12;
measured(5)=strjoin(string(means),"|");expected(5)="2|1.5|1|0.5|0.166666666667";
al16=s.MeanBoundarySafeFraction(s.AggregationLevel==16);
pass(6)=abs(al16-2/3)<1e-12;measured(6)=string(al16);expected(6)="0.666666666667";
pass(7)=isequal(t.ANA12CORESET0.NCCE.',[4 7 12 12 24]);
measured(7)=strjoin(string(t.ANA12CORESET0.NCCE.'),"|");expected(7)="4|7|12|12|24";
T=table(checks,pass,measured,expected,repmat("ANALYTICAL_EXACT",numel(checks),1), ...
    'VariableNames',{'Check','Pass','Measured','Expected','EvidenceClass'});
end
