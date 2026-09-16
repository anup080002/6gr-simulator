function ok=testBSRWireContract()
% Exact MAC wire/table/budget checks; no RF or normal SR lifecycle claim.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
tableCases=0;
for width=[5 8]
    path=fullfile(root,'tests','vectors','mac',sprintf('expected_bsr_%dbit_table.csv',width));
    reference=readtable(path,'TextType','string');
    for k=1:height(reference)
        index=reference.Index(k);
        if string(reference.Reserved(k))=="true"
            reject(@()sixgr.l2.mac.BSR_PHR.bufferSizeFromIndex8bit(index),'sixgr:mac:ReservedBSRIndex');
            continue;
        end
        upper=reference.UpperInclusive(k); lower=reference.LowerExclusive(k);
        if string(reference.Relation(k))=="GT", upper=Inf; end
        sample=0; if index>0, sample=lower+1; end
        if width==5
            [actualUpper,actualLower]=sixgr.l2.mac.BSR_PHR.bufferSizeFromIndex5bit(index);
            assert(sixgr.l2.mac.BSR_PHR.bufferSizeIndex5bit(sample)==index);
            payload=sixgr.l2.mac.BSR_PHR.encodeShortBSR(5,sample);
            assert(isequal(payload,uint8(5*32+index)));
            [lcg,decodedUpper,decodedLower,decodedIndex]=sixgr.l2.mac.BSR_PHR.decodeShortBSR(payload);
            assert(lcg==5 && decodedIndex==index && decodedUpper==upper && isequaln(decodedLower,lower));
            if isfinite(upper), assert(sixgr.l2.mac.BSR_PHR.bufferSizeIndex5bit(upper)==index); end
        else
            [actualUpper,actualLower]=sixgr.l2.mac.BSR_PHR.bufferSizeFromIndex8bit(index);
            assert(sixgr.l2.mac.BSR_PHR.bufferSizeIndex8bit(sample)==index);
            % Explicit zero-size field is legal even though the padding
            % builder only selects LCGs with remaining data.
            payload=uint8([1;index]);
            [decodedUpper,decodedLower,decodedIndices]=sixgr.l2.mac.BSR_PHR.decodeLongBSR(payload);
            assert(decodedUpper(1)==upper && isequaln(decodedLower(1),lower) && decodedIndices(1)==index);
            assert(all(isnan(decodedUpper(2:8))) && all(isnan(decodedIndices(2:8))));
            if sample>0, assert(isequal(sixgr.l2.mac.BSR_PHR.encodeLongBSR(sample),payload)); end
            if isfinite(upper), assert(sixgr.l2.mac.BSR_PHR.bufferSizeIndex8bit(upper)==index); end
        end
        assert(actualUpper==upper && isequaln(actualLower,lower));
        tableCases=tableCases+1;
    end
end
assert(tableCases==287);
assert(isequal(sixgr.l2.mac.BSR_PHR.encodeLongBSR([1000 0 100]),uint8([5;74;37])));
% Every bitmap: field order follows ascending LCGID and omissions are NaN.
for bitmap=0:255
    present=logical(bitget(uint8(bitmap),1:8)); ids=find(present);
    payload=uint8([bitmap ids]);
    decoded=sixgr.l2.mac.BSR_PHR.decodeBSR(62,payload);
    assert(isequal(decoded.BufferSizeFieldPresent,present));
    assert(isequal(decoded.BufferSizeIndices(present),double(ids)) && ...
        all(isnan(decoded.UpperInclusive(~present))));
end
% The highest configured LCH in LCG1 is empty: short-truncated selection
% uses active-LCH priority, while long-truncated uses configured priority.
p=struct('HighestPriorityWithData',[2 3 8 8 8 8 8 8], ...
    'HighestPriorityConfigured',[2 1 8 8 8 8 8 8]);
buffers=[100 200 0 0 0 0 0 0];
assert(isempty(sixgr.l2.mac.BSR_PHR.buildBSR(buffers,0,p)) && ...
    isempty(sixgr.l2.mac.BSR_PHR.buildBSR(buffers,1,p)));
for budget=2:5
    ce=sixgr.l2.mac.BSR_PHR.buildBSR(buffers,budget,p);
    lcids=[59 60 60 62]; assert(ce.LCID==lcids(budget-1));
    assert(ce.MACSubPDUBytes==budget);
    decoded=sixgr.l2.mac.BSR_PHR.decodeBSR(ce.LCID,ce.Payload,p);
    switch budget
        case 2
            assert(isequal(ce.ReportedLCGIDs,0) && ce.IsFixed && decoded.BufferSizeIndices(1)==8);
        case 3
            assert(isempty(ce.ReportedLCGIDs) && isequal(ce.Payload,uint8(3)) && ...
                ~any(decoded.BufferSizeFieldPresent) && decoded.BitmapMeaning=="data_available");
        case 4
            assert(isequal(ce.ReportedLCGIDs,1) && decoded.BufferSizeIndices(2)==48 && ...
                isnan(decoded.BufferSizeIndices(1)));
        case 5
            assert(isequal(ce.ReportedLCGIDs,[0 1]) && ~ce.Truncated);
    end
end
wireCases=0;
order=[8 1 5 3 7 2 6 4];
for n=1:8
    buffers=zeros(1,8); buffers(order(1:n))=100*(1:n);
    for budget=0:11
        ce=sixgr.l2.mac.BSR_PHR.buildBSR(buffers,budget,p);
        if budget<2, assert(isempty(ce)); continue; end
        item=struct('LCID',ce.LCID,'Payload',ce.Payload,'OwnerID',"declared_BSR_wire_fixture");
        assembled=sixgr.l2.mac.MACPDUAssembler.assemble('UL',item,budget);
        parsed=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',assembled.Bytes);
        assert(numel(assembled.Bytes)==budget && numel(parsed.SubPDUs)==1 && ...
            parsed.SubPDUs.LCID==ce.LCID && isequal(parsed.SubPDUs.Payload(:),ce.Payload(:)) && ...
            assembled.PaddingBytes==budget-ce.MACSubPDUBytes);
        decoded=sixgr.l2.mac.BSR_PHR.decodeBSR(parsed.SubPDUs.LCID,parsed.SubPDUs.Payload,p);
        assert(isequal(find(decoded.BufferSizeFieldPresent)-1,ce.ReportedLCGIDs), ...
            'LCG identity/shape mismatch: active=%d budget=%d decoded=%s planned=%s.', ...
            n,budget,mat2str(size(find(decoded.BufferSizeFieldPresent))),mat2str(size(ce.ReportedLCGIDs)));
        selected=ce.ReportedLCGIDs+1;
        assert(all(buffers(selected)>decoded.LowerExclusive(selected)) && ...
            all(buffers(selected)<=decoded.UpperInclusive(selected)));
        wireCases=wireCases+1;
    end
end
assert(wireCases==80);
pColumn=p; pColumn.HighestPriorityWithData=pColumn.HighestPriorityWithData.';
pColumn.HighestPriorityConfigured=pColumn.HighestPriorityConfigured.';
assert(isequal(sixgr.l2.mac.BSR_PHR.buildBSR([100 200],4,p), ...
    sixgr.l2.mac.BSR_PHR.buildBSR([100 200],4,pColumn)));
tie=struct('HighestPriorityWithData',ones(1,8),'HighestPriorityConfigured',ones(1,8));
ce=sixgr.l2.mac.BSR_PHR.buildBSR([10 0 0 20 0 0 0 30],5,tie);
assert(isequal(ce.ReportedLCGIDs,[0 3]));
assert(isempty(sixgr.l2.mac.BSR_PHR.buildBSR(zeros(1,8),11)));
reject(@()sixgr.l2.mac.BSR_PHR.buildBSR([100 200],2),'sixgr:mac:MissingBSRPriority');
reject(@()sixgr.l2.mac.BSR_PHR.buildBSR([100 200],4),'sixgr:mac:MissingBSRPriority');
reject(@()sixgr.l2.mac.BSR_PHR.decodeBSR(60,[3 48]),'sixgr:mac:MissingBSRPriority');
for value={NaN,Inf,-1,0.5,1i,[1 2],true,'1'}
    reject(@()sixgr.l2.mac.BSR_PHR.bufferSizeIndex5bit(value{1}));
    reject(@()sixgr.l2.mac.BSR_PHR.bufferSizeIndex8bit(value{1}));
    reject(@()sixgr.l2.mac.BSR_PHR.buildBSR(100,value{1}));
end
for payload={[],[1 2],NaN,Inf,-1,256,1.5,1i,true,'1'}
    reject(@()sixgr.l2.mac.BSR_PHR.decodeShortBSR(payload{1}));
end
for payload={[],[3 1],[0 1],[1 1 1],[1 255],NaN,[1 1.5],[-1 0],ones(2)}
    reject(@()sixgr.l2.mac.BSR_PHR.decodeLongBSR(payload{1}));
end
for value={nan(1,8),ones(1,9),[1 -1],[1 .5],ones(2),struct('LCG8',1),struct('foo0',1),"1"}
    reject(@()sixgr.l2.mac.BSR_PHR.encodeLongBSR(value{1}));
end
bad=p; bad.HighestPriorityConfigured(1)=NaN;
reject(@()sixgr.l2.mac.BSR_PHR.buildBSR([100 200],4,bad));
reject(@()sixgr.l2.mac.BSR_PHR('NumLCG',9));
helper=sixgr.l2.mac.BSR_PHR;
helper.setLCGBuffer(0,10); helper.setLCGBuffer(1,20);
reject(@()helper.makeBSR('Format','short'),'sixgr:mac:InvalidShortBSRSelection');
reject(@()helper.makeBSR('Truncated',true),'sixgr:mac:MissingBSRPaddingContext');
reject(@()helper.addLCGBuffer(0,-11));
assert(helper.LCGBufferBytes(1)==10);
fprintf('BSR_WIRE_CONTRACT_PASS table_rows=%d bitmaps=256 assembled_budget_cases=%d exact_indices=1 priority_not_buffer_order=1 malformed_rejected=1 RF_executions=0 normal_SR_integration=0\n', ...
    tableCases,wireCases);
ok=true;
end
function reject(fn,id)
try, fn(); catch cause
    if nargin>1, assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier); end
    return;
end
error('test:MissingBSRRejection','Malformed or underspecified BSR input was accepted.');
end
