function ok=testWriteYAMLComplexTensorRoundTrip()
setup6GRSimToolkit('Verbose',false);
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
x=reshape(sin(1:24)+1i*cos(1:24),[2 3 4]);
source=struct('Precoder',x,'SingleTensor',single(real(x)), ...
    'LogicalTensor',real(x)>0,'EmptyTensor',zeros(2,0,4), ...
    'Scalar',pi,'ComplexScalar',pi+1i*sqrt(2), ...
    'Nested',{{struct('Matrix',x(:,:,1))}});
path=fullfile(root,'tensor.yaml');
sixgr.lls6g.config.writeYAML(path,source);
decoded=sixgr.lls6g.config.readConfigFile(path);
for field=["Precoder","SingleTensor","LogicalTensor","EmptyTensor","Scalar","ComplexScalar"]
    assert(isequaln(decoded.(field),source.(field)), ...
        'Typed YAML round trip changed shape, class or values for %s.',field);
end
assert(contains(fileread(path),'column_major_v1'));
bad=sixgr.lls6g.config.yamlArrayEnvelope(x,'encode');
bad.Shape=[3 3 4];
try
    sixgr.lls6g.config.yamlArrayEnvelope(bad,'decode');
catch ME
    assert(strcmp(ME.identifier,'sixgr:yaml:InvalidArrayEnvelope'));
    ok=true; return;
end
error('test:ExpectedArrayShapeFailure','Corrupted tensor shape must be rejected.');
end
