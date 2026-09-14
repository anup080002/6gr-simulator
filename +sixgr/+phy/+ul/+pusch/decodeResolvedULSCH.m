function result=decodeResolvedULSCH(llr,resolved,pusch,tbs,rate,rv,layouts, ...
        maxIterations,algorithm,priorLLR,priorLayouts)
% Decode each known UL-SCH map independently; no decision for unknown maps.
% Caller must bind mapping status and coding inputs to the actual capture.
[layers,~]=sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(pusch.NumLayers);
count=numel(layers);
assert(iscell(llr) && numel(llr)==count && islogical(resolved) && numel(resolved)==count, ...
    'sixgr:pusch:InvalidResolvedCodewords','Provide one LLR stream and logical mapping flag per codeword.');
llr=reshape(llr,1,[]); resolved=reshape(resolved,1,[]);
validateattributes(tbs,{'numeric'},{'vector','real','finite','integer','positive','numel',count});
validateattributes(rate,{'numeric'},{'vector','real','finite','>',0,'<',1,'numel',count});
validateattributes(rv,{'numeric'},{'vector','real','finite','integer','>=',0,'<=',3,'numel',count});
validateattributes(maxIterations,{'numeric'},{'scalar','real','finite','integer','positive'});
assert((ischar(algorithm) || (isstring(algorithm) && isscalar(algorithm))) && strlength(string(algorithm))>0, ...
    'sixgr:pusch:MissingLDPCPolicy','Pass the resolved LDPC algorithm explicitly.');
layouts=localCells(layouts,count,'CodingLayout');
priorLLR=localCells(priorLLR,count,'HARQSoftBufferLLR');
priorLayouts=localCells(priorLayouts,count,'HARQSoftBufferLayout');
modulation=string(pusch.Modulation);
if isscalar(modulation), modulation=repmat(modulation,1,count); end
assert(numel(modulation)==count,'sixgr:pusch:InvalidResolvedCodewords','Modulation must identify each codeword.');
blocks=cell(1,count); evidence=cell(1,count);
attempted=false(1,count); crcPass=nan(1,count); crcError=nan(1,count);
for cw=1:count
    blocks{cw}=zeros(0,1,'int8');
    e=struct('CodewordIndex',cw-1,'TransportBlockSize',tbs(cw), ...
        'MappingResolved',resolved(cw),'DecodeAttempted',false, ...
        'CRCAvailable',false,'CRCPass',NaN,'CRCError',NaN, ...
        'Reason',"ulsch_resource_mapping_unresolved", ...
        'CodingLayout',struct(),'RateRecovery',struct(),'HARQCombining',struct(), ...
        'CodeBlockCRCError',false(0,1),'Source',"not_decoded");
    if ~resolved(cw)
        assert(isempty(llr{cw}),'sixgr:pusch:UnresolvedCodewordHasLLR', ...
            'Unresolved mapping must not carry a guessed data stream.');
        evidence{cw}=e;
        continue;
    end
    validateattributes(llr{cw},{'single','double'},{'vector','real','nonempty','nonnan'});
    supplied=layouts{cw}; nref=[];
    if ~isempty(supplied)
        assert(isstruct(supplied) && isscalar(supplied) && isfield(supplied,'Nref'), ...
            'sixgr:pusch:ResolvedCodingLayoutMismatch','A supplied layout must be a complete coding contract.');
        nref=supplied.Nref;
    end
    layout=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
        'TransportBlockSize',tbs(cw),'TargetCodeRate',rate(cw),'RV',rv(cw), ...
        'Modulation',modulation(cw),'NumLayers',layers(cw), ...
        'RateMatchedBitCount',numel(llr{cw}),'Nref',nref);
    if ~isempty(supplied)
        for field=["TransportBlockSize","RV","Modulation","NumLayers", ...
                "RateMatchedBitCount","Direction","BaseGraph","TBCRCType", ...
                "Nref","CombineSignature","RateMatchSignature"]
            assert(isfield(supplied,field) && isequal(supplied.(field),layout.(field)), ...
                'sixgr:pusch:ResolvedCodingLayoutMismatch', ...
                'Codeword %d supplied %s differs from the capture-bound coding contract.',cw-1,field);
        end
    end
    [recovered,recovery]=sixgr.phy.phycode.rateRecoverLDPC(llr{cw},tbs(cw), ...
        rate(cw),rv(cw),modulation(cw),layers(cw),double(layout.NumCodeBlocks), ...
        nref,'CodingLayout',layout);
    [combined,combining]=sixgr.phy.harq.combineSoftLLR(recovered,priorLLR{cw}, ...
        'CurrentLayout',layout,'PriorLayout',priorLayouts{cw},'CodewordIndex',cw);
    started=tic;
    [decoded,iterations,parity]=sixgr.phy.phycode.ldpcDecode(combined, ...
        double(layout.BaseGraph),maxIterations,algorithm);
    [withCRC,cbErrors]=sixgr.phy.tb.desegmentLDPC(decoded,double(layout.BaseGraph), ...
        double(layout.TransportBlockLengthWithCRC));
    [bits,pass,err]=sixgr.phy.tb.checkCRC(withCRC,layout.TBCRCType);
    latency=toc(started);
    assert(isscalar(pass) && isscalar(err) && numel(bits)==tbs(cw), ...
        'sixgr:pusch:InvalidResolvedDecodeOutput','Actual TB decode must return its configured length and CRC.');
    blocks{cw}=int8(bits(:)); attempted(cw)=true;
    crcPass(cw)=double(pass); crcError(cw)=double(err);
    e.DecodeAttempted=true; e.CRCAvailable=true; e.CRCPass=double(pass); e.CRCError=double(err);
    e.Reason=""; e.CodingLayout=layout; e.RateRecovery=recovery; e.HARQCombining=combining;
    e.CodeBlockCRCError=cbErrors; e.DecodeLatency_s=latency;
    e.ActualIterations=iterations; e.FinalParityChecks=parity;
    e.Source="received_ULSCH_LLR_rate_recovery_LDPC_and_TB_CRC";
    evidence{cw}=e;
end
result=struct('TransportBlocks',{blocks},'MappingResolved',resolved, ...
    'DecodeAttempted',attempted,'CRCAvailable',attempted, ...
    'CRCPass',crcPass,'CRCError',crcError,'CodewordEvidence',{evidence}, ...
    'AllTransportBlocksPassed',all(attempted & crcPass==1), ...
    'Source',"independent_received_ULSCH_codeword_decoding");
end

function cells=localCells(value,count,label)
if isempty(value) || (isstruct(value) && isscalar(value) && isempty(fieldnames(value)))
    cells=cell(1,count);
elseif iscell(value) && numel(value)==count
    cells=reshape(value,1,[]);
elseif count==1
    cells={value};
else
    error('sixgr:pusch:MissingPerCodewordCodingAuthority', ...
        '%s must identify each codeword independently; scalar authority cannot be broadcast.',label);
end
end
