function out=yamlArrayEnvelope(value,mode)
% Lossless typed representation for complex/N-D configuration arrays.
% Plain YAML sequences cannot express MATLAB class, shape and complex parts.
% Values are column-major with an explicit shape; they are never magnitudes.
assert(any(string(mode)==["encode","decode"]), ...
    'sixgr:yaml:InvalidArrayEnvelopeMode','Expected encode or decode.');
marker='SixgrNumericArrayEncoding';
classes=["double","single","logical","int8","uint8","int16","uint16","int32","uint32"];
if string(mode)=="encode" && (isnumeric(value)||islogical(value)) && ...
        (~isreal(value)||ndims(value)>2)
    assert(any(string(class(value))==classes), ...
        'sixgr:yaml:UnsupportedArrayClass', ...
        'Typed YAML arrays do not support class %s.',class(value));
    out=struct('SixgrNumericArrayEncoding',"column_major_v1", ...
        'MATLABClass',string(class(value)),'Shape',double(size(value)), ...
        'IsComplex',~isreal(value),'RealColumnMajor',reshape(real(value),1,[]), ...
        'ImagColumnMajor',[]);
    if ~isreal(value), out.ImagColumnMajor=reshape(imag(value),1,[]); end
    return;
end
if isstruct(value)
    if string(mode)=="decode" && isscalar(value) && isfield(value,marker)
        required={marker,'MATLABClass','Shape','IsComplex','RealColumnMajor','ImagColumnMajor'};
        assert(isequal(sort(fieldnames(value)),sort(required(:))) && ...
            isscalar(string(value.(marker))) && string(value.(marker))=="column_major_v1", ...
            'sixgr:yaml:InvalidArrayEnvelope','Unknown or incomplete typed-array encoding.');
        arrayClass=string(value.MATLABClass);
        assert(isscalar(arrayClass) && any(arrayClass==classes), ...
            'sixgr:yaml:UnsupportedArrayClass','Invalid typed-array MATLAB class.');
        shape=double(value.Shape(:).');
        validateattributes(shape,{'numeric'},{'real','finite','integer','nonnegative','vector'});
        assert(numel(shape)>=2 && islogical(value.IsComplex) && isscalar(value.IsComplex), ...
            'sixgr:yaml:InvalidArrayEnvelope','Shape and complex flag must be explicit.');
        re=value.RealColumnMajor; im=value.ImagColumnMajor;
        assert((isnumeric(re)||islogical(re)) && isreal(re) && ...
            (isempty(re)||isvector(re)) && prod(shape)==numel(re), ...
            'sixgr:yaml:InvalidArrayEnvelope','Real array values disagree with the declared shape.');
        out=reshape(cast(re,char(arrayClass)),shape);
        if value.IsComplex
            assert(any(arrayClass==["double","single"]) && isnumeric(im) && isreal(im) && ...
                (isempty(im)||isvector(im)) && numel(im)==numel(re), ...
                'sixgr:yaml:InvalidArrayEnvelope','Invalid complex component class or shape.');
            out=complex(out,reshape(cast(im,char(arrayClass)),shape));
        else
            assert(isempty(im),'sixgr:yaml:InvalidArrayEnvelope', ...
                'Real-valued arrays cannot contain an imaginary payload.');
        end
        return;
    end
    out=value;
    names=fieldnames(value);
    for k=1:numel(value)
        for j=1:numel(names)
            out(k).(names{j})=sixgr.lls6g.config.yamlArrayEnvelope(value(k).(names{j}),mode);
        end
    end
elseif iscell(value)
    out=cellfun(@(v)sixgr.lls6g.config.yamlArrayEnvelope(v,mode),value,'UniformOutput',false);
else
    out=value;
end
end
