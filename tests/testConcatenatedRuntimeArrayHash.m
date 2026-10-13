function ok=testConcatenatedRuntimeArrayHash()
% Byte identity against the existing full-array hash, across time segments
% and all trailing spatial/path dimensions. Small arrays only in this test.
setup6GRSimToolkit('Verbose',false);
values=reshape(1:11*3*4*2,11,3,4,2)/17;
cases={values,complex(values,-values/13),single(complex(values,values/7)), ...
    int16(values*11),logical(mod(round(values*17),3)), ...
    zeros(0,3,4,2),zeros(7,0),[0;-0;Inf;-Inf;NaN],complex([NaN;Inf],[1;-2])};
for k=1:numel(cases)
    x=cases{k}; n=size(x,1);
    cuts=unique([0 min(1,n) min(4,n) n]);
    parts=cell(numel(cuts)-1,1);
    for j=1:numel(parts)
        subs=repmat({':'},1,ndims(x)); subs{1}=cuts(j)+1:cuts(j+1);
        parts{j}=x(subs{:});
    end
    if isempty(parts), parts={x}; end
    % Empty time segments are legal and must not change the logical shape.
    subs=repmat({':'},1,ndims(x)); subs{1}=[];
    paddedParts=[{x(subs{:})};parts;{x(subs{:})}];
    expected=sixgr.phy.waveform.WaveformHash.runtimeArray(cat(1,paddedParts{:}));
    for bound=[1 7 19 262144]
        [actual,evidence]=sixgr.phy.waveform.concatenatedRuntimeArrayHash(paddedParts,bound);
        assert(actual==expected,'The bounded hash changed the existing runtime-array byte identity.');
        assert(isequal(evidence.Dimensions,size(x)) && evidence.ElementCount==numel(x) && ...
            ~evidence.FullConcatenationAllocated && evidence.MaximumWorkingElementCount<=bound && ...
            evidence.AdditionalChannelExecutions==0);
    end
end
% Swapping time segments or physical columns must remain detectable.
x=complex(reshape(1:60,10,3,2),reshape(61:120,10,3,2));
parts={x(1:3,:,:),x(4:end,:,:)};
a=sixgr.phy.waveform.concatenatedRuntimeArrayHash(parts,7);
assert(a~=sixgr.phy.waveform.concatenatedRuntimeArrayHash(fliplr(parts),7));
changed=parts; changed{2}(1,2,2)=changed{2}(1,2,2)+1i;
assert(a~=sixgr.phy.waveform.concatenatedRuntimeArrayHash(changed,7));
localError(@()sixgr.phy.waveform.concatenatedRuntimeArrayHash({zeros(2,3),zeros(4,2)}), ...
    'WAVEFORM:ConcatenatedArrayShapeMismatch');
localError(@()sixgr.phy.waveform.concatenatedRuntimeArrayHash({zeros(2,3),single(zeros(4,3))}), ...
    'WAVEFORM:ConcatenatedArrayShapeMismatch');
localError(@()sixgr.phy.waveform.concatenatedRuntimeArrayHash({sparse(eye(2))}), ...
    'WAVEFORM:InvalidConcatenatedArrayParts');
ok=true;
disp('CONCATENATED_RUNTIME_ARRAY_HASH_PASS: exact historical digest, bounded working arrays.');
end

function localError(action,id)
try
    action();
catch cause
    assert(string(cause.identifier)==id,'Expected %s, received %s.',id,cause.identifier);
    return;
end
error('sixgr:test:ExpectedError','Expected %s.',id);
end
