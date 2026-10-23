function [attempts,blocks]=collectLDPCRateMatchEvidence(trials,direction,source,sourceSHA256)
%COLLECTLDPCRATEMATCHEVIDENCE Read retained v2 selections, never rerun coding.
% One attempt row per input row; one block row per retained CW/CB. There is
% no cross-attempt, RV, buffer, UE, sweep or run pooling. The source JSON owns
% selected positions; legacy scalar differences cannot recreate that proof.
arguments
    trials table
    direction (1,1) string
    source (1,1) string
    sourceSHA256 (1,1) string = ""
end
assert(any(direction==["DL","UL"]),'sixgr:report:LDPCDirection','Use DL or UL.');
p=prototype(); attempts=struct2table(p,'AsArray',true); attempts=attempts([],:);
b=blockPrototype(); blocks=struct2table(b,'AsArray',true); blocks=blocks([],:);
for k=1:height(trials)
    r=p; r.Direction=direction; r.SourceArtifact=source;
    r.SourceArtifactSHA256=sourceSHA256; r.SourceRow=k;
    r.InputIdentityJSON=identityJSON(trials(k,:));
    r.RateMatchingContextJSON=contextJSON(trials(k,:));
    r.RateMatchAccountingJSON=textAt(trials,k,'RateMatchAccountingJSON');
    r.CodingAccountingVersion=textAt(trials,k,'CodingAccountingVersion');
    r.EvidenceID=string(sixgr.util.sha256Hex(jsonencode(struct( ...
        'Direction',direction,'SourceArtifact',source,'SourceArtifactSHA256',sourceSHA256, ...
        'SourceRow',k,'Identity',r.InputIdentityJSON,'Context',r.RateMatchingContextJSON, ...
        'Accounting',r.RateMatchAccountingJSON))));
    if strlength(strtrim(r.RateMatchAccountingJSON))==0
        attempts=[attempts;struct2table(r,'AsArray',true)]; %#ok<AGROW>
        continue;
    end
    require(r.CodingAccountingVersion=="LDPCSelectionAccounting/v2", ...
        'A declared selection archive needs its exact v2 contract.');
    try
        accounts=jsondecode(r.RateMatchAccountingJSON);
    catch cause
        error('sixgr:report:LDPCAccountingInvalid','Malformed rate-match JSON: %s',cause.message);
    end
    if isstruct(accounts), accounts=num2cell(accounts(:)); end
    require(iscell(accounts) && ~isempty(accounts), 'Retain one accounting record per codeword.');
    r.AccountingSHA256=string(sixgr.util.sha256Hex(char(r.RateMatchAccountingJSON)));
    r.NumCodewords=numel(accounts); r.NumCodeBlocks=0;
    totals=zeros(1,8);
    countNames=["EncoderOutputPositions","BufferPositions","BufferFillerPositions", ...
        "EligibleBufferPositions","SelectedPositions","UniqueSelectedPositions", ...
        "RepeatedSelections","UnselectedEligiblePositions"];
    pending=blocks([],:);
    for cw=1:numel(accounts)
        a=accounts{cw};
        require(isstruct(a) && isscalar(a) && all(isfield(a,["ContractVersion","Source",countNames])), ...
            'Every codeword must retain the complete v2 selection accounting.');
        require(string(a.ContractVersion)=="LDPCSelectionAccounting/v2" && ...
            string(a.Source)=="actual_nrRateMatchLDPC_selection_with_filler_mask", ...
            'The accounting must describe the actual filler-aware rate matcher.');
        C=numel(a.SelectedPositions); require(C>0,'Empty code-block accounting.');
        counts=zeros(C,numel(countNames));
        for j=1:numel(countNames)
            v=a.(countNames(j));
            require(isnumeric(v) && isreal(v) && isvector(v) && numel(v)==C && ...
                all(isfinite(v(:)) & v(:)>=0 & v(:)==fix(v(:))), ...
                'Accounting counts must be equally sized nonnegative integer vectors.');
            counts(:,j)=double(v(:));
        end
        require(all(counts(:,1)>0 & counts(:,2)>0 & counts(:,2)<=counts(:,1)) && ...
            all(counts(:,2)==counts(:,3)+counts(:,4)) && ...
            all(counts(:,5)==counts(:,6)+counts(:,7)) && ...
            all(counts(:,4)==counts(:,6)+counts(:,8)) && sum(counts(:,5))>0, ...
            'Buffer, filler, unique, repeated and unselected-position identities must close.');
        rv=codewordValue(trials(k,:),"RVPerCodeword","RV",cw,numel(accounts));
        if isfinite(rv), require(rv==fix(rv) && rv>=0 && rv<=3,'Invalid retained RV.'); end
        nref=codewordValue(trials(k,:),"NrefPerCodeword","Nref",cw,numel(accounts));
        if isfinite(nref)
            require(nref==fix(nref) && nref>0 && all(counts(:,2)==min(counts(:,1),nref)), ...
                'Explicit Nref must agree with the actual circular buffer.');
        end
        for cb=1:C
            q=b;
            for field=["EvidenceID","Direction","SourceArtifact","SourceArtifactSHA256", ...
                    "SourceRow","InputIdentityJSON","RateMatchingContextJSON","AccountingSHA256"]
                q.(field)=r.(field);
            end
            q.CodewordOrdinal=cw; q.CodeBlockOrdinal=cb; q.RV=rv; q.Nref=nref;
            if isfinite(rv), q.RVStatus="retained"; end
            if isfinite(nref), q.NrefStatus="retained"; end
            for j=1:numel(countNames), q.(countNames(j))=counts(cb,j); end
            q.ExcludedByBufferLimitPositions=counts(cb,1)-counts(cb,2);
            pending=[pending;struct2table(q,'AsArray',true)]; %#ok<AGROW>
        end
        totals=totals+sum(counts,1); r.NumCodeBlocks=r.NumCodeBlocks+C;
    end
    r.EncoderOutputPositions=totals(1); r.BufferPositions=totals(2);
    r.BufferFillerPositions=totals(3); r.EligibleBufferPositions=totals(4);
    r.SelectedPositions=totals(5); r.UniqueSelectedPositions=totals(6);
    r.RepeatedSelections=totals(7); r.UnselectedEligiblePositions=totals(8);
    r.ExcludedByBufferLimitPositions=totals(1)-totals(2);
    aliases=["EncodedBits","RateMatchEligibleBits","RateMatchedBits", ...
        "RateMatchUniqueSelectedBits","RateMatchRepetitionBits","RateMatchPunctureBits","NumCodeBlocks"];
    expected=[totals(1),totals(4),totals(5:8),r.NumCodeBlocks];
    for j=1:numel(aliases)
        value=numberAt(trials,k,aliases(j));
        if isfinite(value), require(value==expected(j),"Trial total contradicts selection JSON: "+aliases(j)); end
    end
    % These are retained ATTEMPT totals, not inferred allocations to a CW/CB.
    for field=["InherentLDPCPuncturedBits","SegmentationPaddingBits","CBCRCBits", ...
            "CodeBlockInputBits","TBLengthWithCRC_bits","SegmentationOverheadBits"]
        value=numberAt(trials,k,field);
        if isfinite(value), require(value>=0 && value==fix(value),"Invalid retained count: "+field); end
        r.(field)=value;
    end
    bgn=numberAt(trials,k,"BaseGraph");
    if isfinite(bgn) && isfinite(r.InherentLDPCPuncturedBits)
        require(any(bgn==[1,2]),'Invalid retained base graph.');
        % The actual post-puncture encoder lengths distinguish 66*Zc and
        % 50*Zc. Check a retained inherent-puncture total, never backfill it.
        factor=50; if bgn==1, factor=66; end
        z=pending.EncoderOutputPositions/factor;
        require(all(z==fix(z) & z>0) && r.InherentLDPCPuncturedBits==sum(2*z), ...
            'Retained inherent 2Zc count contradicts actual encoder lengths.');
    end
    if all(isfinite([r.SegmentationPaddingBits,r.CBCRCBits,r.CodeBlockInputBits,r.TBLengthWithCRC_bits]))
        require(r.CodeBlockInputBits==r.TBLengthWithCRC_bits+r.CBCRCBits+r.SegmentationPaddingBits, ...
            'Segmentation filler must not include CB CRC bits.');
    end
    if all(isfinite([r.SegmentationOverheadBits,r.SegmentationPaddingBits,r.CBCRCBits]))
        require(r.SegmentationOverheadBits==r.SegmentationPaddingBits+r.CBCRCBits, ...
            'Segmentation overhead must close from retained CB CRC and filler.');
    end
    r.SelectionAvailable=true; r.Status="v2_selection_arithmetic_verified";
    % These are per-attempt descriptive fractions, not a combined overhead.
    r.RepeatedSelectionFraction=r.RepeatedSelections/r.SelectedPositions;
    if r.EligibleBufferPositions>0
        r.UnselectedEligibleFraction=r.UnselectedEligiblePositions/r.EligibleBufferPositions;
    end
    attempts=[attempts;struct2table(r,'AsArray',true)]; %#ok<AGROW>
    blocks=[blocks;pending]; %#ok<AGROW>
end
end

function p=prototype()
p=struct('Direction',"",'SourceArtifact',"",'SourceArtifactSHA256',"",'SourceRow',NaN, ...
    'EvidenceID',"",'InputIdentityJSON',"",'RateMatchingContextJSON',"", ...
    'CodingAccountingVersion',"",'RateMatchAccountingJSON',"",'AccountingSHA256',"", ...
    'SelectionAvailable',false,'Status',"not_available_missing_v2_selection_evidence", ...
    'NumCodewords',NaN,'NumCodeBlocks',NaN,'EncoderOutputPositions',NaN, ...
    'BufferPositions',NaN,'BufferFillerPositions',NaN,'EligibleBufferPositions',NaN, ...
    'SelectedPositions',NaN,'UniqueSelectedPositions',NaN,'RepeatedSelections',NaN, ...
    'UnselectedEligiblePositions',NaN,'ExcludedByBufferLimitPositions',NaN, ...
    'InherentLDPCPuncturedBits',NaN,'SegmentationPaddingBits',NaN,'CBCRCBits',NaN, ...
    'CodeBlockInputBits',NaN,'TBLengthWithCRC_bits',NaN,'SegmentationOverheadBits',NaN, ...
    'RepeatedSelectionFraction',NaN,'UnselectedEligibleFraction',NaN);
end

function p=blockPrototype()
p=struct('Direction',"",'SourceArtifact',"",'SourceArtifactSHA256',"",'SourceRow',NaN, ...
    'EvidenceID',"",'InputIdentityJSON',"",'RateMatchingContextJSON',"",'AccountingSHA256',"", ...
    'CodewordOrdinal',NaN,'CodeBlockOrdinal',NaN,'RV',NaN,'RVStatus',"not_retained", ...
    'Nref',NaN,'NrefStatus',"not_retained_not_inferred_from_buffer_length", ...
    'EncoderOutputPositions',NaN,'BufferPositions',NaN,'BufferFillerPositions',NaN, ...
    'EligibleBufferPositions',NaN,'SelectedPositions',NaN,'UniqueSelectedPositions',NaN, ...
    'RepeatedSelections',NaN,'UnselectedEligiblePositions',NaN,'ExcludedByBufferLimitPositions',NaN);
end

function text=identityJSON(row)
names=string(row.Properties.VariableNames);
fixed=["ExecutionID","RunID","RunFolder","RunTag","ScenarioID","ConfigHash","ScenarioConfigHash", ...
    "RandomSeed","ChannelSeed","Seed","SeedBase","SweepPointIndex","ConfiguredSNR_dB", ...
    "UEIndex","UEID","RNTI","ServingCell","CellID","Frame","Slot","AbsoluteSlot", ...
    "LogicalTBID","TransmissionAttemptID","TBIdentity","IdentityContractVersion","AttemptIdentitySource", ...
    "HARQProcess","HarqID","NDI","NDIEpoch","HARQIsRetransmission","CodewordIndex", ...
    "ObservationID","ReceiverID","ReceiverClockDomain","ReceiverClockEpoch", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "ConfigurationEpoch","RFConfigurationEpoch","ReceiverConfigurationEpoch", ...
    "ExecutionBackend","ExecutionProfile","ExecutionTaxonomy","ApproximationMode", ...
    "Source","Status","TruthStatus","ProxyUsed","FallbackUsed"];
keep=ismember(names,fixed) | startsWith(names,"Sweep") | startsWith(names,"Point") | startsWith(names,"Population");
text=string(jsonencode(table2struct(row(:,keep),'ToScalar',true)));
end

function text=contextJSON(row)
names=string(row.Properties.VariableNames);
keep=contains(names,"RV") | contains(names,"Nref") | ismember(names, ...
    ["Modulation","ModulationOrderQm","Layers","BaseGraph","CodeBlockLength_bits", ...
     "TargetCodeRate","CurrentRateMatchedBits","OriginalRateMatchedBits","TBSize_bits"]);
text=string(jsonencode(table2struct(row(:,keep),'ToScalar',true)));
end

function value=codewordValue(row,vectorName,scalarName,cw,nCW)
value=NaN; names=string(row.Properties.VariableNames);
if ismember(vectorName,names)
    raw=row.(vectorName); if iscell(raw) && isscalar(raw), raw=raw{1}; end
    require(isnumeric(raw) && isreal(raw) && numel(raw)==nCW, ...
        "Retain the complete per-codeword context: "+vectorName);
    require(~any(isinf(raw(:))),"Invalid infinite codeword context: "+vectorName);
    value=double(raw(cw));
elseif ismember(scalarName,names)
    value=numberAt(row,1,scalarName);
end
end

function value=numberAt(T,k,name)
value=NaN;
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name)(k,:); if iscell(raw) && isscalar(raw), raw=raw{1}; end
if ischar(raw) || isstring(raw)
    token=string(raw); require(isscalar(token),"Expected scalar count: "+name);
    raw=str2double(token);
    require(~isnan(raw) || ismissing(token) || any(lower(strtrim(token))==["","nan","<missing>"]), ...
        "Malformed numeric count: "+name);
end
require(isnumeric(raw) && isreal(raw) && isscalar(raw) && ~isinf(raw), ...
    "Expected finite or unavailable scalar count: "+name);
value=double(raw);
end

function value=textAt(T,k,name)
value="";
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name)(k,:); if iscell(raw) && isscalar(raw), raw=raw{1}; end
if isnumeric(raw) && isscalar(raw) && isnan(raw), return; end
value=string(raw); require(isscalar(value),"Expected scalar text: "+name);
if ismissing(value), value=""; end
end

function require(condition,message)
assert(isscalar(condition) && condition,'sixgr:report:LDPCAccountingInvalid','%s',message);
end
