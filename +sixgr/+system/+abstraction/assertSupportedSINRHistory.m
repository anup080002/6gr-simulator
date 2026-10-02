function assertSupportedSINRHistory(axes,supported,history)
% All corners used by multilinear interpolation must have measured curves.
assert(numel(axes)==numel(history) && isequal(size(supported), ...
    localShape(axes)), 'sixgr:abstraction:CalibrationGrid', ...
    'Supported grid shape does not match the HARQ history.');
corners=cell(1,numel(history));
for a=1:numel(history)
    axis=double(axes{a}(:)); value=double(history(a));
    assert(isfinite(value) && value>=axis(1) && value<=axis(end), ...
        'sixgr:abstraction:SINROutOfCalibration','Effective SINR is outside the measured axis.');
    exact=find(axis==value,1);
    if ~isempty(exact)
        corners{a}=exact;
    else
        low=find(axis<value,1,'last');
        corners{a}=[low low+1];
    end
end
if numel(corners)==1
    indices=corners{1};
else
    grid=cell(1,numel(corners)); [grid{:}]=ndgrid(corners{:});
    subs=cellfun(@(x)x(:),grid,'UniformOutput',false);
    indices=sub2ind(size(supported),subs{:});
end
assert(all(supported(indices)), 'sixgr:abstraction:UnsupportedSINRHistory', ...
    'This interpolation uses an unqualified conditional BLER cell.');
end

function shape=localShape(axes)
shape=cellfun(@numel,axes);
if isscalar(shape), shape=[shape 1]; end
end
