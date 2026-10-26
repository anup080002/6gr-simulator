function ok=testN40ContinuationEndpointSelection()
% Filesystem pointer fixture only; these documents are not native checkpoints.
folder=string(tempname); mkdir(folder);
source=fileread(which('sixgr.validation.verifyN40CheckpointContinuation'));
first=strfind(source,'function [path,receipt]=latestEndpoint(');
last=strfind(source,'function out=projection(');
assert(isscalar(first)&&isscalar(last));
body=replace(string(source(first:last-1)), ...
    'function [path,receipt]=latestEndpoint(','function [path,receipt]=n40EndpointHarness(');
sixgr.util.writeTextFile(fullfile(folder,'n40EndpointHarness.m'),body);
addpath(folder); cleanup=onCleanup(@()rmpath(folder)); %#ok<NASGU>
root=fullfile(folder,'original'); base=fullfile(folder,'checkpoints');
mkdir(root); mkdir(fullfile(root,'meta')); mkdir(base);
paths=strings(2,1);
for k=1:2
    generation=fullfile(base,"after_slot_000060_declared_"+string(k)); mkdir(generation);
    paths(k)=string(sixgr.util.canonicalPath(fullfile(generation,'state.mat')));
    sixgr.util.jsonWrite(fullfile(generation,'checkpoint.json'), ...
        struct('Status','complete','CompletedSlotOneBased',60,'NextSlotOneBased',61));
end
for k=1:2
    writePointer(paths(k),60);
    [selected,~]=n40EndpointHarness(root,base,60,"");
    assert(selected==paths(k),'Run pointer must select one of both retained generations.');
end
mustReject(paths(2)); % The resumed endpoint must not be the baseline.
writePointer(fullfile(folder,'outside','state.mat'),60); mustReject("");
writePointer(paths(1),59); mustReject("");
ok=true;
    function writePointer(path,slot)
        sixgr.util.jsonWrite(fullfile(root,'meta','latest_slot_checkpoint.json'), ...
            struct('Checkpoint',path,'CompletedSlotOneBased',slot,'NextSlotOneBased',slot+1));
    end
    function mustReject(excluded)
        try
            n40EndpointHarness(root,base,60,excluded);
        catch cause
            assert(string(cause.identifier)=="sixgr:validation:EndpointCheckpoint",'%s',cause.message);
            return;
        end
        error('testN40ContinuationEndpointSelection:MissingGuard','Invalid endpoint pointer was accepted.');
    end
end
