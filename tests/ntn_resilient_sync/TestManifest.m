classdef TestManifest < matlab.unittest.TestCase
    methods(Test)
        function stableHash(tc)
            a=sixgr.util.sha256Hex(uint8('resilient-ntn'));b=sixgr.util.sha256Hex(uint8('resilient-ntn'));
            tc.verifyEqual(a,b);tc.verifyEqual(strlength(a),64);
        end
        function relativeRootProducesRelativeArtifactPaths(tc)
            root=fullfile(pwd,"tmp_ntn_manifest_"+string(randi(1e9)));
            mkdir(root);cleanup=onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
            writematrix(42,fullfile(root,'payload.csv'));
            relative=erase(string(root),string(pwd)+filesep);
            scenario=struct('RunId','relative_root_test','ConfigPath','config.yaml', ...
                'ConfigSourceFiles',"config.yaml",'ConfigSHA256',repmat('a',1,64), ...
                'StateProfilesPath','states.yaml','StateProfileSHA256',repmat('b',1,64), ...
                'seed',1,'run_mode','quick');
            evidence=table("payload","ANALYTICAL",false,"PRODUCED", ...
                'VariableNames',{'Artifact','EvidenceClass','Measured','Status'});
            manifest=sixgr.ntn.resilientsync.report.buildManifest(relative,scenario,'QUICK_COMPLETE',evidence);
            paths=string({manifest.Artifacts.Path});
            tc.verifyTrue(all(~startsWith(paths,string(pwd))));
            tc.verifyTrue(any(paths=="payload.csv"));
        end
    end
end
