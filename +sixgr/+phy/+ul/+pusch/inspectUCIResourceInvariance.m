function plan=inspectUCIResourceInvariance(pusch,targetCodeRate,transportBlockSize, ...
        codewordLLR,context,initialIMCS,reportConfig)
% Discover resource identities across CSI absence and all configured lengths.
% The public demultiplexer is probed with unique index labels, never decoded
% as information bits. These labels are configuration metadata, not samples
% or PHY evidence. No received values, TX payloads or chosen UE RI select a
% candidate. This helper itself does not recover or accept any feedback.
if nargin<7, reportConfig=[]; end
assert(isa(context,'sixgr.phy.ul.pusch.PUSCHUCIReceiveContext') && isscalar(context), ...
    'sixgr:pusch:MissingUCIReceiveContext','Use the gNB-owned receive context.');
budget=context.bitBudget(reportConfig);
count=double(pusch.NumCodewords);
if ~iscell(codewordLLR), codewordLLR={codewordLLR}; end
codewordLLR=reshape(codewordLLR,1,[]);
assert(numel(codewordLLR)==count,'sixgr:pusch:InvalidUCIBitBudget', ...
    'The received codeword count must match the PUSCH allocation.');
validateattributes(initialIMCS,{'numeric'},{'vector','real','finite','integer','nonnegative','numel',count});
labels=cell(1,count); lengths=zeros(1,count); offset=0;
for cw=1:count
    validateattributes(codewordLLR{cw},{'single','double'},{'vector','real','nonempty','nonnan'});
    lengths(cw)=numel(codewordLLR{cw});
    labels{cw}=offset+(1:lengths(cw)).';
    offset=offset+lengths(cw);
end
% A nominal report obligation does not establish that a UE could produce
% CSI. Keep the absent-report interpretation even when Part 2 is fixed.
% Neither received values nor UE report presence may prune this domain.
budgets=[0 0];
if ~isempty(reportConfig)
    part2=reportConfig.part2BitCountCandidates();
    part2=unique(double(part2(:).'));
    validateattributes(part2,{'numeric'},{'vector','nonempty','finite','integer','nonnegative'});
    budgets=[budgets; repmat(budget.OCSI1,numel(part2),1) part2(:)];
end
validateattributes(transportBlockSize,{'numeric'}, ...
    {'vector','real','finite','integer','nonnegative','numel',count});
owner=0;
if budget.OACK+budget.OCSI1+budget.OCGUCI>0
    [~,owner1]=max(initialIMCS); owner=owner1-1;
end
lower=sum(lengths(1:owner)); upper=lower+lengths(owner+1);
maps=cell(1,size(budgets,1));
for k=1:size(budgets,1)
    firstCount=budgets(k,1); secondCount=budgets(k,2);
    combinedCount=secondCount+budget.OCGUCI;
    if budget.OACK+firstCount+combinedCount==0
        % No-UCI data uses the original codeword; an absent UCI-only PUSCH
        % has no data or UCI map. Empty data is not a successful TB decode.
        data=labels;
        for cw=1:count
            if transportBlockSize(cw)==0, data{cw}=zeros(0,1); end
        end
        ack=zeros(0,1); csi1=ack; csi2=ack;
    else
        [data,ack,csi1,csi2]=nrULSCHDemultiplex(pusch,targetCodeRate,transportBlockSize, ...
            budget.OACK,firstCount,combinedCount,localUnwrap(labels));
    end
    if ~iscell(data), data={data}; end
    data=reshape(data,1,[]);
    assert(numel(data)==count,'sixgr:pusch:InvalidUCIBitBudget', ...
        'Demultiplexer returned an inconsistent codeword count.');
    for indices={ack,csi1}
        value=double(indices{1}(:));
        assert(all(isfinite(value) & value==fix(value) & value>lower & value<=upper), ...
            'sixgr:pusch:UCIResourceOwnerMismatch', ...
            'UCI source indices must agree with the retained original-MCS owner.');
    end
    % Short HARQ can puncture CSI2 (including its jointly coded CG-UCI).
    % The public demultiplexer restores those positions as erasures, just
    % as for punctured UL-SCH. Zero is metadata here, never source index 0.
    value=double(csi2(:));
    assert(all(isfinite(value) & value==fix(value) & ...
        (value==0 | (value>lower & value<=upper))), ...
        'sixgr:pusch:UCIResourceOwnerMismatch', ...
        'CSI2/CG-UCI indices must identify their codeword or a puncturing erasure.');
    for cw=1:count
        value=double(data{cw}(:)); base=sum(lengths(1:cw-1));
        % Zero denotes a standard demultiplexer puncturing erasure. It is
        % not an observed zero-valued received sample or a source index.
        assert(all(isfinite(value) & value==fix(value) & ...
            (value==0 | (value>base & value<=base+lengths(cw)))), ...
            'sixgr:pusch:InvalidUCIBitBudget','Invalid UL-SCH source-index map.');
        data{cw}=value;
    end
    maps{k}=struct('Part1BitCount',firstCount,'Part2BitCount',secondCount, ...
        'CSIReportPresent',firstCount>0,'CSI2AndCGUCIBitCount',combinedCount, ...
        'HARQ',double(ack(:)),'CSI1',double(csi1(:)), ...
        'CSI2AndCGUCI',double(csi2(:)),'ULSCH',{data});
end
first=maps{1}; ackStable=true; csiStable=true; secondStable=true; dataStable=true(1,count);
for k=2:numel(maps)
    ackStable=ackStable && isequal(first.HARQ,maps{k}.HARQ);
    csiStable=csiStable && isequal(first.CSI1,maps{k}.CSI1);
    secondStable=secondStable && first.CSI2AndCGUCIBitCount==maps{k}.CSI2AndCGUCIBitCount && ...
        isequal(first.CSI2AndCGUCI,maps{k}.CSI2AndCGUCI);
    for cw=1:count
        dataStable(cw)=dataStable(cw) && isequal(first.ULSCH{cw},maps{k}.ULSCH{cw});
    end
end
ackMap=first.HARQ; if ~ackStable, ackMap=[]; end
csiMap=first.CSI1; if ~csiStable, csiMap=[]; end
secondMap=first.CSI2AndCGUCI; if ~secondStable, secondMap=[]; end
dataMap=first.ULSCH;
for cw=1:count, if ~dataStable(cw), dataMap{cw}=[]; end, end
plan=struct('Source',"configured_public_demultiplexer_index_probe", ...
    'ReceiverContextDigest',context.Digest,'OwnerCodeword',owner, ...
    'CodewordLengths',lengths,'CandidateCSIInformationBitCounts',budgets, ...
    'CandidatePart1BitCounts',unique(budgets(:,1).'), ...
    'CandidatePart2BitCounts',unique(budgets(:,2).'), ...
    'CandidateDomain',"CSI_absent_and_installed_CSI_present_layouts", ...
    'HARQMappingInvariant',ackStable,'CSI1MappingInvariant',csiStable, ...
    'CSI2AndCGUCIMappingInvariant',secondStable, ...
    'ULSCHMappingInvariant',dataStable, ...
    'HARQSourceIndices1Based',ackMap,'CSI1SourceIndices1Based',csiMap, ...
    'CSI2AndCGUCISourceIndices1Based',secondMap, ...
    'ULSCHSourceIndices1Based',{dataMap},'CandidateMaps',{maps}, ...
    'IndexSpace',"concatenated_received_codewords_zero_is_puncturing_erasure", ...
    'PhysicalExecutionEvidence',false);
end

function value=localUnwrap(cells)
if isscalar(cells), value=cells{1}; else, value=cells; end
end
