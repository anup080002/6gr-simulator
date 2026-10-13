function stored=encodeEvidenceArrayPool(value)
% Lossless deduplication of dense numeric evidence, not quantization.
% Retain each distinct bit pattern once. Struct/cell shape and every field
% are restored by the inverse codec before scientific validation.
pool=cell(0,1); digests=strings(0,1);
lookup=containers.Map('KeyType','char','ValueType','double');
template=visit(value);
stored=struct('Schema',"sixgr.evidence_array_pool/v1", ...
    'Template',{template},'Arrays',{pool},'SHA256',digests);

    function out=visit(in)
        out=in;
        if (isnumeric(in) || islogical(in)) && ~issparse(in) && numel(in)>=1024
            digest=sixgr.calibration.evidenceArraySHA256(in);
            key=char(digest);
            if isKey(lookup,key)
                index=lookup(key);
            else
                index=numel(pool)+1; lookup(key)=index;
                pool{index,1}=in; digests(index,1)=digest;
            end
            out=struct('Schema',"sixgr.evidence_array_reference/v1", ...
                'Index',index,'SHA256',digest);
        elseif isstruct(in)
            assert(~(isscalar(in) && isfield(in,'Schema') && ...
                isequal(string(in.Schema),"sixgr.evidence_array_reference/v1")), ...
                'sixgr:calibration:ArrayPoolReservedSchema', ...
                'Input cannot contain an unresolved array reference.');
            fields=fieldnames(in);
            for element=1:numel(in)
                for field=1:numel(fields)
                    name=fields{field}; out(element).(name)=visit(in(element).(name));
                end
            end
        elseif iscell(in)
            for element=1:numel(in), out{element}=visit(in{element}); end
        end
    end
end
