function plan=inspectUCIResourceInvariance(pusch,targetCodeRate,transportBlockSize, ...
        codewordLLR,context,initialIMCS,reportConfig)
% Discover resource identities across every CONFIGURED CSI-Part-2 length.
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
if isempty(reportConfig), candidates=0;
else, candidates=reportConfig.part2BitCountCandidates(); end
candidates=unique(double(candidates(:).'));
validateattributes(candidates,{'numeric'},{'vector','nonempty','finite','integer','nonnegative'});
owner=0;
if budget.OACK+budget.OCSI1+budget.OCGUCI>0
    [~,owner1]=max(initialIMCS); owner=owner1-1;
end
lower=sum(lengths(1:owner)); upper=lower+lengths(owner+1);
maps=cell(1,numel(candidates));
for k=1:numel(candidates)
    [data,ack,csi1,~]=nrULSCHDemultiplex(pusch,targetCodeRate,transportBlockSize, ...
        budget.OACK,budget.OCSI1,candidates(k)+budget.OCGUCI,localUnwrap(labels));
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
    for cw=1:count
        value=double(data{cw}(:)); base=sum(lengths(1:cw-1));
        % Zero denotes a standard demultiplexer puncturing erasure. It is
        % not an observed zero-valued received sample or a source index.
        assert(all(isfinite(value) & value==fix(value) & ...
            (value==0 | (value>base & value<=base+lengths(cw)))), ...
            'sixgr:pusch:InvalidUCIBitBudget','Invalid UL-SCH source-index map.');
        data{cw}=value;
    end
    maps{k}=struct('Part2BitCount',candidates(k),'HARQ',double(ack(:)), ...
        'CSI1',double(csi1(:)),'ULSCH',{data});
end
first=maps{1}; ackStable=true; csiStable=true; dataStable=true(1,count);
for k=2:numel(maps)
    ackStable=ackStable && isequal(first.HARQ,maps{k}.HARQ);
    csiStable=csiStable && isequal(first.CSI1,maps{k}.CSI1);
    for cw=1:count
        dataStable(cw)=dataStable(cw) && isequal(first.ULSCH{cw},maps{k}.ULSCH{cw});
    end
end
ackMap=first.HARQ; if ~ackStable, ackMap=[]; end
csiMap=first.CSI1; if ~csiStable, csiMap=[]; end
dataMap=first.ULSCH;
for cw=1:count, if ~dataStable(cw), dataMap{cw}=[]; end, end
plan=struct('Source',"configured_public_demultiplexer_index_probe", ...
    'ReceiverContextDigest',context.Digest,'OwnerCodeword',owner, ...
    'CodewordLengths',lengths,'CandidatePart2BitCounts',candidates, ...
    'HARQMappingInvariant',ackStable,'CSI1MappingInvariant',csiStable, ...
    'ULSCHMappingInvariant',dataStable, ...
    'HARQSourceIndices1Based',ackMap,'CSI1SourceIndices1Based',csiMap, ...
    'ULSCHSourceIndices1Based',{dataMap},'CandidateMaps',{maps}, ...
    'IndexSpace',"concatenated_received_codewords_zero_is_puncturing_erasure", ...
    'PhysicalExecutionEvidence',false);
end

function value=localUnwrap(cells)
if isscalar(cells), value=cells{1}; else, value=cells; end
end
