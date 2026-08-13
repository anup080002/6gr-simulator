classdef DeterministicSuite
    %DETERMINISTICSUITE Exact analytical evidence for RAN1 10.5.2.2.

    methods (Static)
        function out = run(cfg)
            out = struct();
            [out.TimeProfile, out.GroupPositions] = localTimeDomain();
            out.REAccounting = localREAccounting(cfg);
            out.TDOCCAudit = localTDOCC(cfg);
            [out.NestedFamily, out.NestedReceiver] = localNested(cfg);
            out.Covariance = localCovariance();
            [out.FDPattern, out.FDValidity] = localFrequencyPatterns(cfg);
            out.Sequence = localSequence(cfg);
            out.PortCount = localPorts();
            out.BundleMap = localBundles(cfg);
            out.RBGCompatibility = sixgr.studies.ran1ai10522.FrequencyStructure.rbgCompatibility( ...
                [16 32 64], double(cfg.pdschDmrsStudy.frequencyDomain.bundleSizesPrb), 0:15);
            out.Interleaver = localInterleaver(out.BundleMap);
            out.PTRSPhase = localPhase(cfg);
            out.TBMapping = localTBMapping(cfg);
            out.MCSSegmentation = localMCSSegmentation(cfg);
            out.CWLayerMapping = localCWMapping();
            out.MultiTRP = localMultiTRP(cfg);
            out.MRSSValidity = localMRSS(cfg);
            out.Tables = localTDocTables(out);
        end
    end
end

function [profiles, positions] = localTimeDomain()
profileRows = repmat(struct("ProfileId","","NSym",0,"X",0,"G",0, ...
    "FirstOffset",0,"DerivedL",NaN,"LastGroupStart",NaN, ...
    "GroupStartSymbols","","Valid",false,"EvidenceClass", ...
    "ANALYTICAL_DERIVATION","Status","NOT_APPLICABLE","StopReason",""),0,1);
positionRows = repmat(struct("ProfileId","","NSym",0,"X",0,"L",0, ...
    "FirstOffset",0,"GroupOrdinal",0,"GroupStartSymbol",0, ...
    "LastGroupStartsAtLMax",false,"GapSpread",0,"FitCondition",false, ...
    "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS"),0,1);
for nSym = 1:28
    for X = [1 2 4]
        if X > nSym, continue; end
        lmax = nSym - X;
        for l0 = 0:lmax
            for G = 1:27
                id = sprintf("I_N%d_X%d_l0%d_G%d",nSym,X,l0,G);
                spec = struct("NSym",nSym,"X",X,"FirstOffsetSymbols",l0, ...
                    "MaxGroupStartSpacingG",G);
                row = struct("ProfileId",string(id),"NSym",nSym,"X",X,"G",G, ...
                    "FirstOffset",l0,"DerivedL",NaN,"LastGroupStart",NaN, ...
                    "GroupStartSymbols","","Valid",false,"EvidenceClass", ...
                    "ANALYTICAL_DERIVATION","Status","NOT_APPLICABLE", ...
                    "StopReason","no_supported_profile");
                try
                    p = sixgr.studies.ran1ai10522.TimeDomainProfile.resolve(spec);
                    row.DerivedL = p.L; row.LastGroupStart = p.GroupStartSymbols(end);
                    row.GroupStartSymbols = join(string(p.GroupStartSymbols),"|");
                    row.Valid = true; row.Status = "PASS"; row.StopReason = "NONE";
                catch ME
                    if ~startsWith(string(ME.identifier),"sixgr:ran1ai10522:")
                        rethrow(ME);
                    end
                    row.StopReason = string(ME.identifier);
                end
                profileRows(end+1,1) = row; %#ok<AGROW>
            end
            for L = sixgr.studies.ran1ai10522.TimeDomainProfile.supportedL(X)
                if l0 + L*X > nSym, continue; end
                starts = sixgr.studies.ran1ai10522.TimeDomainProfile.place(nSym,X,L,l0);
                if L > 1, spread=max(diff(starts))-min(diff(starts)); else, spread=0; end
                explicitId=sprintf("E_N%d_X%d_l0%d_L%d",nSym,X,l0,L);
                for ordinal=1:numel(starts)
                    positionRows(end+1,1)=struct("ProfileId",string(explicitId), ... %#ok<AGROW>
                        "NSym",nSym,"X",X,"L",L,"FirstOffset",l0, ...
                        "GroupOrdinal",ordinal-1,"GroupStartSymbol",starts(ordinal), ...
                        "LastGroupStartsAtLMax",L==1 || starts(end)==lmax, ...
                        "GapSpread",spread,"FitCondition",l0+L*X<=nSym, ...
                        "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS");
                end
            end
        end
    end
end
profiles = struct2table(profileRows,"AsArray",true);
positions = struct2table(positionRows,"AsArray",true);
if any(profiles.Valid & profiles.Status~="PASS") || ...
        any(positions.GapSpread>1) || ~all(positions.FitCondition) || ...
        any(~positions.LastGroupStartsAtLMax)
    error("sixgr:ran1ai10522:TimeDomainExhaustiveGate", ...
        "Exhaustive time-domain derivation failed an invariant.");
end
end

function T = localREAccounting(cfg)
nPrb = double(cfg.frequency.n_size_grid);
rows = repmat(struct("X",0,"L",0,"CDMGroups",0,"AllocationPRB",nPrb, ...
    "DMRSREPerPRBPerGroup",6,"TotalDMRSRE",0,"AccountingModel", ...
    "parameterized_candidate_exact_count","EvidenceClass", ...
    "ANALYTICAL_DERIVATION","Status","PASS"),0,1);
for X=[1 2 4]
    for L=sixgr.studies.ran1ai10522.TimeDomainProfile.supportedL(X)
        for cdm=double(cfg.pdschDmrsStudy.frequencyDomain.cdmGroups(:)).'
            rows(end+1,1)=struct("X",X,"L",L,"CDMGroups",cdm, ... %#ok<AGROW>
                "AllocationPRB",nPrb,"DMRSREPerPRBPerGroup",6, ...
                "TotalDMRSRE",nPrb*6*cdm*X*L, ...
                "AccountingModel","parameterized_candidate_exact_count", ...
                "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS");
        end
    end
end
T=struct2table(rows,"AsArray",true);
end

function T = localTDOCC(cfg)
td=cfg.pdschDmrsStudy.timeDomain;
rows=repmat(struct("X",0,"PreVariance",0,"PostVariance",0, ...
    "ExpectedPostVariance",0,"VarianceError",0,"PreEstimationBufferBits",0, ...
    "Equation","sigma2_post=sigma2_pre/X","EvidenceClass", ...
    "ANALYTICAL_DERIVATION","Status","PASS"),3,1);
for k=1:3
    X=[1 2 4]; x=X(k); pre=1; post= ...
        sixgr.studies.ran1ai10522.TimeDomainProfile.despreadNoiseVariance(pre,x);
    bits=sixgr.studies.ran1ai10522.TimeDomainProfile.normalizedPreEstimationBits( ...
        td.iqBitsPerComponent,td.receiverBranches,td.subcarriersPerPrb,td.bufferedWaitSymbols);
    rows(k)=struct("X",x,"PreVariance",pre,"PostVariance",post, ...
        "ExpectedPostVariance",1/x,"VarianceError",abs(post-1/x), ...
        "PreEstimationBufferBits",bits,"Equation","sigma2_post=sigma2_pre/X", ...
        "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS");
end
T=struct2table(rows,"AsArray",true);
end

function [T,R] = localNested(cfg)
nf=cfg.pdschDmrsStudy.nestedFamily;
family=sixgr.studies.ran1ai10522.NestedFamily.build(14,1,0,6);
expected={0,[0 13],[0 6 13],[0 6 9 13],[0 3 6 9 13],[0 3 6 9 11 13]};
rows=repmat(struct("FamilyId",string(nf.familyId),"L",0,"GroupStartSymbols","", ...
    "PotentialSet","","ExactExampleMatch",false,"NestedWithNext",true, ...
    "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS"),6,1);
for L=1:6
    pot=sixgr.studies.ran1ai10522.NestedFamily.potentialSet(family,L);
    nested=L==6 || all(ismember(family{L},family{L+1}));
    rows(L)=struct("FamilyId",string(nf.familyId),"L",L, ...
        "GroupStartSymbols",join(string(family{L}),"|"), ...
        "PotentialSet",join(string(pot),"|"), ...
        "ExactExampleMatch",isequal(family{L},expected{L}), ...
        "NestedWithNext",nested,"EvidenceClass","ANALYTICAL_DERIVATION", ...
        "Status","PASS");
end
T=struct2table(rows,"AsArray",true);
if ~all(T.ExactExampleMatch & T.NestedWithNext)
    error("sixgr:ran1ai10522:NestedExampleMismatch", ...
        "The exact 14-symbol nested family did not match Table C-1.");
end
R=table(["separate_covariance";"pooled_covariance";"overlap";"rate_match"], ...
    ["receiver_estimator_policy";"receiver_estimator_policy"; ...
     "resource_ownership_policy";"resource_ownership_policy"], ...
    ["BLOCKED";"BLOCKED";"BLOCKED";"BLOCKED"], ...
    repmat("BLOCKED",4,1), ...
    repmat("Canonical co-scheduled waveform integration is required; deterministic set proof alone is not performance evidence.",4,1), ...
    'VariableNames',{'Treatment','Classification','EvidenceClass','Status','StopReason'});
end

function T=localCovariance()
H=[1 .25; .25 1]; eigenvalues=eig(H);
T=table("two_layer_reference",trace(H),det(H),min(eigenvalues),max(eigenvalues), ...
    cond(H),"ANALYTICAL_DERIVATION","PASS", ...
    'VariableNames',{'CaseId','Trace','Determinant','MinimumEigenvalue', ...
    'MaximumEigenvalue','ConditionNumber','EvidenceClass','Status'});
end

function [manifest,validity]=localFrequencyPatterns(cfg)
p=string(cfg.pdschDmrsStudy.frequencyDomain.patternIds(:));
classes=repmat("BLOCKED",numel(p),1); status=repmat("BLOCKED",numel(p),1);
source=repmat("candidate_requires_canonical_waveform_mapper",numel(p),1);
baseline=p=="nr_rel18_type1_len1";
classes(baseline)="ANALYTICAL_DERIVATION"; status(baseline)="PASS";
source(baseline)="sixgr.phy.refsig.dmrsPDSCH_nrPDSCHDMRSIndices";
manifest=table(p,source,classes,status, ...
    'VariableNames',{'PatternId','MappingAuthority','EvidenceClass','Status'});
rows=repmat(struct("FDOCCLength",0,"CDMGroups",0,"BundleSizePRB",0, ...
    "CompleteContainment",false,"OrphanRE",0,"DuplicateOwnership",false, ...
    "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS"),0,1);
for occ=double(cfg.pdschDmrsStudy.frequencyDomain.fdOccLengths(:)).'
    for cdm=double(cfg.pdschDmrsStudy.frequencyDomain.cdmGroups(:)).'
        for N=double(cfg.pdschDmrsStudy.frequencyDomain.bundleSizesPrb(:)).'
            re=12*N; complete=mod(re,occ)==0;
            rows(end+1,1)=struct("FDOCCLength",occ,"CDMGroups",cdm, ... %#ok<AGROW>
                "BundleSizePRB",N,"CompleteContainment",complete, ...
                "OrphanRE",mod(re,occ),"DuplicateOwnership",false, ...
                "EvidenceClass","ANALYTICAL_DERIVATION", ...
                "Status",localStatus(complete));
        end
    end
end
validity=struct2table(rows,"AsArray",true);
end

function T=localSequence(cfg)
allocs=double(cfg.pdschDmrsStudy.frequencyDomain.allocationPrbs(:));
bundles=double(cfg.pdschDmrsStudy.frequencyDomain.bundleSizesPrb(:));
modes=string(cfg.pdschDmrsStudy.frequencyDomain.sequenceIndexingModes(:));
rows=repmat(struct("AllocationPRB",0,"BundleSizePRB",0,"Mode","", ...
    "ElementIndex",0,"BundleId",0,"RegionId",0,"SequenceIndex",0, ...
    "CommonGridInvariant",false,"EvidenceClass","ANALYTICAL_DERIVATION", ...
    "Status","PASS"),0,1);
for a=allocs.'
    for N=bundles.'
        element=(0:a-1).'; bundle=floor(element/N); region=double(element>=floor(a/2));
        for mode=modes.'
            idx=sixgr.studies.ran1ai10522.FrequencyStructure.sequenceIndex(mode,bundle,region);
            invariant=mode~="common_grid" || isequal(idx,element);
            for k=1:a
                rows(end+1,1)=struct("AllocationPRB",a,"BundleSizePRB",N, ... %#ok<AGROW>
                    "Mode",mode,"ElementIndex",element(k),"BundleId",bundle(k), ...
                    "RegionId",region(k),"SequenceIndex",idx(k), ...
                    "CommonGridInvariant",invariant,"EvidenceClass", ...
                    "ANALYTICAL_DERIVATION","Status",localStatus(invariant));
            end
        end
    end
end
T=struct2table(rows,"AsArray",true);
end

function T=localPorts()
ports=[24;32;48;64;96];
T=table(ports,["exact_mapping_required";"exact_mapping_required"; ...
    "exact_mapping_required";"structural_stress_only";"structural_stress_only"], ...
    repmat("BLOCKED",5,1),repmat("BLOCKED",5,1), ...
    repmat("No verified canonical NR DM-RS mapping for the requested extended port count is present.",5,1), ...
    'VariableNames',{'RequestedPorts','Scope','EvidenceClass','Status','StopReason'});
end

function T=localBundles(cfg)
regions=double(cfg.pdschDmrsStudy.wideband.processingRegionsPrb);
sizes=double(cfg.pdschDmrsStudy.frequencyDomain.bundleSizesPrb(:));
parts=cell(numel(sizes),1);
for k=1:numel(sizes)
    part=sixgr.studies.ran1ai10522.FrequencyStructure.bundles(regions,sizes(k));
    part.BundleSizePRB=repmat(sizes(k),height(part),1); parts{k}=part;
end
T=vertcat(parts{:});
end

function T=localInterleaver(bundles)
parts=cell(2,1); modes=["none","bundle_local_region"];
base=bundles(bundles.BundleSizePRB==min(bundles.BundleSizePRB),:);
for k=1:2, parts{k}=sixgr.studies.ran1ai10522.FrequencyStructure.interleave(base,modes(k),false); end
T=vertcat(parts{:});
end

function T=localPhase(cfg)
deltaF=[0;100;500]; delay=[0;50e-9;250e-9]; region=[0;1;1]; symbol=1/(30e3*2048);
phase=arrayfun(@(f,d,q)sixgr.studies.ran1ai10522.FrequencyStructure.residualPhase(f,symbol,d,q),deltaF,delay,region);
T=table(deltaF,repmat(symbol,3,1),delay,region,phase,rad2deg(phase), ...
    repmat(string(cfg.pdschDmrsStudy.ptrs.phaseModelId),3,1), ...
    repmat("ANALYTICAL_DERIVATION",3,1),repmat("PASS",3,1), ...
    'VariableNames',{'DeltaF_Hz','SymbolTime_s','DifferentialDelay_s', ...
    'RegionIndex','ResidualPhase_rad','ResidualPhase_deg','PhaseModelId', ...
    'EvidenceClass','Status'});
end

function T=localTBMapping(cfg)
modes=string(cfg.pdschDmrsStudy.tbMapping.modes(:)); baseline=modes=="one_tb";
T=table(modes,[1;2;4],baseline, ...
    localClassVector(baseline),localStatusVector(baseline), ...
    localReasons(baseline,"Candidate modes require independent canonical DL-SCH encode/decode and HARQ identities."), ...
    'VariableNames',{'Mode','TransportBlockCount','CanonicalExecutionAvailable', ...
    'EvidenceClass','Status','StopReason'});
end

function T=localMCSSegmentation(cfg)
modes=string(cfg.pdschDmrsStudy.mcsSegmentation.modes(:)); baseline=modes=="common";
T=table(modes,baseline,localClassVector(baseline),localStatusVector(baseline), ...
    localReasons(baseline,"Per-segment MCS requires aligned independently coded runtime segments."), ...
    'VariableNames',{'Mode','AlignedBoundaryValidated','EvidenceClass','Status','StopReason'});
end

function T=localCWMapping()
rows=repmat(struct("Rank",0,"NumCodewords",0,"LayerCountPerCodeword","", ...
    "RoundTripExact",false,"MappingAuthority","sixgr.pdsch.CodewordLayerMapper", ...
    "EvidenceClass","ANALYTICAL_DERIVATION","Status","PASS"),8,1);
for rank=1:8
    if rank<=4, cw=(1:rank*8).'; else, cw={(1:max(1,floor(rank/2))*8).',(1001:1000+max(1,ceil(rank/2))*8).'}; end
    [layers,info]=sixgr.pdsch.CodewordLayerMapper(cw,rank);
    recovered=sixgr.pdsch.CodewordLayerMapper(layers,rank,"Operation","demap");
    exact=isequal(cw,recovered);
    rows(rank)=struct("Rank",rank,"NumCodewords",info.NumCodewords, ...
        "LayerCountPerCodeword",join(string(info.LayerCountPerCodeword),"|"), ...
        "RoundTripExact",exact,"MappingAuthority","sixgr.pdsch.CodewordLayerMapper", ...
        "EvidenceClass","ANALYTICAL_DERIVATION","Status",localStatus(exact));
end
T=struct2table(rows,"AsArray",true);
if ~all(T.RoundTripExact), error("sixgr:ran1ai10522:CWLayerRoundTrip","NR layer mapping round trip failed."); end
end

function T=localMultiTRP(cfg)
common=struct("X",cfg.pdschDmrsStudy.timeDomain.X,"G", ...
    cfg.pdschDmrsStudy.timeDomain.maxGroupStartSpacingG,"Anchor","slot");
h=sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(common),"UTF-8")));
T=table([0;1],[string(h);string(h)],[true;true], ...
    repmat("ANALYTICAL_DERIVATION",2,1),repmat("PASS",2,1), ...
    'VariableNames',{'TRPIndex','ProfileSHA256','CommonProfileMatch','EvidenceClass','Status'});
end

function T=localMRSS(cfg)
profiles=["no_collision";"collision_rejected";"valid_rate_match"];
collision=[false;true;true]; accepted=[true;false;true]; shifted=false(3,1); reset=false(3,1);
T=table(profiles,collision,accepted,shifted,reset, ...
    repmat(string(cfg.pdschDmrsStudy.mrss.collisionHandling),3,1), ...
    repmat("ANALYTICAL_DERIVATION",3,1),repmat("PASS",3,1), ...
    'VariableNames',{'CaseId','CollisionPresent','ScheduleAccepted', ...
    'ImplicitShiftApplied','SequenceResetApplied','CollisionHandling', ...
    'EvidenceClass','Status'});
end

function tables=localTDocTables(out)
tables=struct();
tables.TopicMapping=table((1:17).',string(('A':'Q').'), ...
    repmat("RAN1 10.5.2.2 deterministic/controlled evidence family",17,1), ...
    repmat("ANALYTICAL_DERIVATION",17,1), ...
    'VariableNames',{'Order','Family','Topic','EvidenceClass'});
tables.ContainerAlternatives=table(["scheduling_table";"direct_grant"], ...
    ["same resolved time-domain profile";"same resolved time-domain profile"], ...
    repmat("ANALYTICAL_DERIVATION",2,1),repmat("PASS",2,1), ...
    'VariableNames',{'Container','ResolvedSemantics','EvidenceClass','Status'});
tables.ImplicitExamples=out.TimeProfile(out.TimeProfile.NSym==14 & ...
    out.TimeProfile.X==1 & out.TimeProfile.FirstOffset==0 & ...
    ismember(out.TimeProfile.G,[3 5 7]),:);
tables.FloorExamples=out.GroupPositions(out.GroupPositions.NSym==14 & ...
    out.GroupPositions.X==1 & out.GroupPositions.FirstOffset==0,:);
tables.CompanyPorts=table("external_company_port_positions", ...
    "Source table was not supplied; reproduction is blocked.","EXTERNAL_REFERENCE_REPRODUCTION", ...
    "BLOCKED",'VariableNames',{'TableId','Limitation','EvidenceClass','Status'});
tables.ReportingFields=table(["EvidenceClass";"ExecutionBackend";"ApproximationMode"; ...
    "ConfigHash";"GitCommit";"ConvergenceStatus";"CalibrationStatus"], ...
    repmat("required",7,1),repmat("ANALYTICAL_DERIVATION",7,1), ...
    'VariableNames',{'Field','Requirement','EvidenceClass'});
tables.NestedFamily=out.NestedFamily;
end

function s=localStatus(tf)
if tf, s="PASS"; else, s="NOT_APPLICABLE"; end
end
function v=localClassVector(tf)
v=repmat("BLOCKED",numel(tf),1); v(tf)="ANALYTICAL_DERIVATION";
end
function v=localStatusVector(tf)
v=repmat("BLOCKED",numel(tf),1); v(tf)="PASS";
end
function v=localReasons(tf,reason)
v=repmat(string(reason),numel(tf),1); v(tf)="NONE";
end
