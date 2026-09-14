function ok=testHARQSchedulingDiagnostic(outputRoot,snapshotFn)
% Real HARQ allocation objects, declared MAC-only inputs; no PHY execution.
if nargin<1 || strlength(string(outputRoot))==0
    logsRoot=fullfile(pwd,'logs');
    if ~isfolder(logsRoot), mkdir(logsRoot); end
    outputRoot=tempname(logsRoot);
end
if nargin<2, snapshotFn=@sixgr.report.snapshotHARQSchedulingState; end
if ~isfolder(outputRoot), mkdir(outputRoot); end
logger=sixgr.core.Logger(fullfile(outputRoot,'owned_logger.log'),'EchoToConsole',false);
cleanupLogger=onCleanup(@()logger.close()); %#ok<NASGU>
other=fopen(fullfile(outputRoot,'unrelated_open_file.log'),'w');
assert(other>0);
cleanupOther=onCleanup(@()fclose(other)); %#ok<NASGU>
cfg=struct('mac',struct('harq',struct('numProcesses',2)));
snapshots=cell(2,1);
for index=1:2
    direction=["DL","UL"]; direction=direction(index);
    entity=sixgr.l2.mac.HARQEntity(cfg,'Direction',direction,'Logger',logger);
    allocation=entity.allocate(321,3,16,'NewData',true);
    entity.allocate(322,3,8,'NewData',true);
    procsBefore=entity.UEProcs; statsBefore=entity.Stats;
    snapshot=snapshotFn(entity);
    assert(snapshot.Available && snapshot.Direction==direction && snapshot.NumProcesses==2);
    assert(isequal(snapshot.UEList,entity.UEList));
    assert(isequaln(procsBefore,entity.UEProcs) && isequaln(statsBefore,entity.Stats));
    for ue=1:2
        actual=entity.UEProcs{ue}; projected=snapshot.Processes{ue};
        for name=string(fieldnames(projected))'
            assert(isequaln({projected.(name)},{actual.(name)}),name);
        end
        assert(~isfield(projected,'TB') && ~isfield(projected,'LastGrant') && ~isfield(projected,'SoftBuffer'));
    end
    assert(snapshot.Processes{1}(allocation.ProcessIndex).Active);
    assert(~snapshot.Processes{1}(allocation.ProcessIndex).AwaitingFeedback);
    assert(~isfield(snapshot,'Logger'));
    % The snapshot must remain a value projection after a later allocation.
    entity.allocate(321,4,24,'NewData',true);
    assert(sum([snapshot.Processes{1}.Active])==1 && sum([entity.UEProcs{1}.Active])==2);
    snapshots{index}=snapshot;
end
empty=snapshotFn([]); assert(~empty.Available && isempty(empty.Processes));
try
    snapshotFn(struct()); error('test:MissingRejection','Invalid entity must reject.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:report:InvalidHARQDiagnosticEntity'));
end
matPath=fullfile(outputRoot,'harq_scheduling_values.mat');
save(matPath,'snapshots','empty','-v7.3');
loaded=load(matPath);
assert(isequaln(loaded.snapshots,snapshots) && isequaln(loaded.empty,empty));
assert(fprintf(other,'UNRELATED_FILE_STILL_OPEN_AFTER_SAVE_LOAD\n')>0);
logger.info('OWNED_LOGGER_STILL_OPEN_AFTER_SAVE_LOAD');
logger.close();
assert(contains(fileread(fullfile(outputRoot,'owned_logger.log')),'OWNED_LOGGER_STILL_OPEN_AFTER_SAVE_LOAD'));
fprintf('HARQ_SCHEDULING_DIAGNOSTIC_PASS: readonly DL/UL process projection, no logger handles, save/load and unrelated file retained; RF=0.\n');
ok=true;
end
