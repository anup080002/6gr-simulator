function value=decodeEvidenceArrayPool(stored)
% Restore exact arrays before any waveform/calibration interpretation.
assert(isstruct(stored) && isscalar(stored) && ...
    all(isfield(stored,{'Schema','Template','Arrays','SHA256'})) && ...
    isequal(string(stored.Schema),"sixgr.evidence_array_pool/v1") && ...
    iscell(stored.Arrays) && iscolumn(stored.Arrays) && ...
    isstring(stored.SHA256) && numel(stored.SHA256)==numel(stored.Arrays), ...
    'sixgr:calibration:ArrayPoolSchema','Invalid evidence array pool.');
for k=1:numel(stored.Arrays)
    assert(sixgr.calibration.evidenceArraySHA256(stored.Arrays{k})==stored.SHA256(k), ...
        'sixgr:calibration:ArrayPoolDigest','Retained numeric evidence failed its digest.');
end
used=false(numel(stored.Arrays),1);
value=visit(stored.Template);
assert(all(used),'sixgr:calibration:ArrayPoolUnused','Unreferenced evidence array in pool.');

    function out=visit(in)
        out=in;
        if isstruct(in)
            if isscalar(in) && isfield(in,'Schema') && ...
                    isequal(string(in.Schema),"sixgr.evidence_array_reference/v1")
                assert(all(isfield(in,{'Index','SHA256'})) && ...
                    isnumeric(in.Index) && isscalar(in.Index) && isreal(in.Index) && ...
                    isfinite(in.Index) && in.Index==fix(in.Index) && ...
                    in.Index>=1 && in.Index<=numel(stored.Arrays), ...
                    'sixgr:calibration:ArrayPoolReference','Invalid numeric evidence reference.');
                index=double(in.Index);
                assert(isequal(string(in.SHA256),stored.SHA256(index)), ...
                    'sixgr:calibration:ArrayPoolReference','Array reference digest mismatch.');
                used(index)=true; out=stored.Arrays{index}; return;
            end
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
