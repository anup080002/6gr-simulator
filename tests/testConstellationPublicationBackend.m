function ok=testConstellationPublicationBackend()
% Configured evidence paths must be the same for filesystem and MySQL.
setup6GRSimToolkit('Verbose',false);
for mode=["TDD","FDD"]
    for scope=["preview","full_allocation"]
        paths=cell(1,2);
        k=0;
        for backend=["filesystem","mysql_web"]
            k=k+1;
            cfg=struct('phy',struct('duplex',struct('mode',mode)), ...
                'outputs',struct('storageBackend',backend,'constellationCaptureScope',scope));
            [d,u]=sixgr.truth.constellationArtifactPaths(cfg,'csv');
            paths{k}=[string(d),string(u)];
            suffix="preview"; if scope=="full_allocation", suffix="samples"; end
            assert(endsWith(d,"dl_constellation_"+suffix+".csv") && ...
                endsWith(u,"ul_constellation_"+suffix+".csv"));
        end
        assert(isequal(paths{1},paths{2}));
    end
end
code=fileread(which('sixgr.truth.runWaveformLinkBundle'));
code=replace(code,sprintf('\r\n'),sprintf('\n'));
assert(contains(code,sprintf('if localCoupledLiveRuntimePublicationEnabled(cfg)\n    [dlLiveConstellationPath, ulLiveConstellationPath]')));
assert(contains(code,'dlTablePath, ulTablePath, dlConstT, ulConstT, dlConstellationPath, ulConstellationPath'));
assert(contains(code,'sixgr.util.csvWriteTable(pair{1},pair{2},"PreserveSchema",true)'));
fprintf('CONSTELLATION_PUBLICATION_BACKEND_PASS: both duplex modes, backend-independent live/final paths and failure capture wiring.\n');
ok=true;
end
