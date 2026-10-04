function index=resolveGrantUEIndex(grant,populationSize)
% No rounding/clamping and no inference of array index from a C-RNTI.
if nargin<2, populationSize=flintmax-1; end
index=sixgr.util.structGet(grant,'UEIndex',NaN);
assert(isnumeric(index) && isreal(index) && isscalar(index) && isfinite(index) && ...
    index>=1 && index==fix(index) && index<=populationSize, ...
    'sixgr:system:MissingGrantUEIndex','Bind the exact internal UE index before system execution.');
index=double(index);
end
