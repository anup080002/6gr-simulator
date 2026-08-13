classdef ArtifactAuditor
    %ARTIFACTAUDITOR Fail-closed semantic and byte-level UL artifact audit.

    methods (Static)
        function [audit, passed, publicationPassed] = run(runFolder)
            rows = repmat(localRow(),0,1);
            csvFiles = dir(fullfile(runFolder,"**","*.csv"));
            csvPass = ~isempty(csvFiles); badCsv = strings(0,1);
            for idx=1:numel(csvFiles)
                path=fullfile(csvFiles(idx).folder,csvFiles(idx).name);
                try
                    value=readtable(path,"Delimiter",",","VariableNamingRule","preserve");
                    ok=height(value)>0 && width(value)>0;
                catch
                    ok=false;
                end
                csvPass=csvPass&&ok;
                if ~ok,badCsv(end+1,1)=string(path);end %#ok<AGROW>
            end
            rows(end+1,1)=localMake("csv","all_csv_rectangular_nonempty",csvPass, ...
                sprintf("files=%d,bad=%d",numel(csvFiles),numel(badCsv)));

            figureManifest=readtable(fullfile(runFolder,"manifests","figure_manifest.csv"), ...
                "Delimiter",",","VariableNamingRule","preserve");
            imagePass=height(figureManifest)==22;
            for idx=1:height(figureManifest)
                path=fullfile(runFolder,replace(string(figureManifest.PNGPath(idx)),"/",filesep));
                try
                    info=imfinfo(path); pix=double(imread(path));
                    ok=info.Width==double(figureManifest.WidthPx(idx)) && ...
                        info.Height==double(figureManifest.HeightPx(idx)) && ...
                        info.Width>=1200 && info.Height>=675 && std(pix,0,"all")>0 && ...
                        sixgr.csi.fileSHA256(path)==string(figureManifest.PNG_SHA256(idx));
                catch
                    ok=false;
                end
                imagePass=imagePass&&ok;
            end
            rows(end+1,1)=localMake("figures/tdoc","22_png_decode_dimensions_hash_nonblank", ...
                imagePass,sprintf("observed=%d",height(figureManifest)));

            vectorFiles=[dir(fullfile(runFolder,"**","*.svg"));dir(fullfile(runFolder,"**","*.pdf"))];
            rows(end+1,1)=localMake("figures","raster_only_no_svg_or_pdf",isempty(vectorFiles), ...
                sprintf("vector_files=%d",numel(vectorFiles)));

            status=readtable(fullfile(runFolder,"manifests","figure_contract_status.csv"), ...
                "Delimiter",",","VariableNamingRule","preserve");
            contractPass=height(status)==86 && ...
                nnz(startsWith(string(status.FigureId),"TFIG-") & string(status.Status)=="PASS")==22 && ...
                nnz(startsWith(string(status.FigureId),"RFIG-") & string(status.Status)=="BLOCKED")==64 && ...
                ~any(startsWith(string(status.FigureId),"RFIG-") & logical(status.FileExists));
            rows(end+1,1)=localMake("manifests/figure_contract_status.csv", ...
                "contract_complete_without_placeholder_results",contractPass, ...
                sprintf("rows=%d,tdoc_pass=%d,result_blocked=%d",height(status), ...
                nnz(string(status.Status)=="PASS"),nnz(string(status.Status)=="BLOCKED")));

            inputManifest=readtable(fullfile(runFolder,"manifests","input_manifest.csv"), ...
                "Delimiter",",","VariableNamingRule","preserve");
            runMode=string(inputManifest.RunMode(1));
            actualRequired=any(runMode==["quick","tdoc"]);
            actualManifestPath=fullfile(runFolder,"manifests","actual_waveform_manifest.csv");
            actualPath="";
            if exist(actualManifestPath,"file")==2
                actualManifest=readtable(actualManifestPath,"Delimiter",",","VariableNamingRule","preserve");
                actualPath=fullfile(runFolder,replace(string(actualManifest.TrialCsv(1)),"/",filesep));
            end
            actualPass=~actualRequired || (strlength(actualPath)>0 && exist(actualPath,"file")==2);
            details="actual waveform not required for "+runMode;
            if actualRequired && actualPass
                trials=readtable(actualPath,"Delimiter",",","VariableNamingRule","preserve");
                required=["CRCSource","LLRSource","DecoderNoiseVariance"];
                actualPass=height(trials)>0 && all(ismember(required,string(trials.Properties.VariableNames)));
                if actualPass
                    truthPath=fullfile(fileparts(actualPath),"truth_contract.csv");
                    truth=readtable(truthPath,"Delimiter",",","VariableNamingRule","preserve");
                    actualPass=all(string(trials.CRCSource)=="decoded_transport_block_crc") && ...
                        all(string(trials.LLRSource)=="nrPUSCHDecode_soft_llr") && ...
                        all(isfinite(double(trials.DecoderNoiseVariance)) & double(trials.DecoderNoiseVariance)>0) && ...
                        ~any(truth{1,["UsesBLERLookupTable","UsesSyntheticBLER", ...
                        "UsesRandomPassFailModel","UsesGeometryAsLLS"]});
                end
                details=sprintf("actual_transport_blocks=%d",height(trials));
            end
            rows(end+1,1)=localMake("actual_waveform_manifest.TrialCsv", ...
                "actual_pusch_truth_no_proxy_or_placeholder",actualPass,details);

            artifactPath=fullfile(runFolder,"manifests","artifact_manifest.csv");
            artifactPass=exist(artifactPath,"file")==2; bound=0;
            if artifactPass
                artifacts=readtable(artifactPath,"Delimiter",",","VariableNamingRule","preserve");
                artifactPass=height(artifacts)>0;
                for idx=1:height(artifacts)
                    path=fullfile(runFolder,replace(string(artifacts.RelativePath(idx)),"/",filesep));
                    ok=exist(path,"file")==2 && sixgr.csi.fileSHA256(path)==string(artifacts.SHA256(idx));
                    artifactPass=artifactPass&&ok; bound=bound+1;
                end
            end
            rows(end+1,1)=localMake("manifests/artifact_manifest.csv", ...
                "all_manifest_hashes_match",artifactPass,sprintf("bound=%d",bound));

            campaign=readtable(fullfile(runFolder,"manifests","campaign_status.csv"), ...
                "Delimiter",",","VariableNamingRule","preserve");
            proposal=readtable(fullfile(runFolder,"manifests","proposal_evidence_matrix.csv"), ...
                "Delimiter",",","VariableNamingRule","preserve");
            publicationPassed=all(string(campaign.Status)=="PASS") && ...
                all(logical(proposal.ClaimSupported)) && ...
                ~any(string(campaign.CalibrationStatus)~="passed");
            rows(end+1,1)=localMake("publication","all_calibration_sls_and_proposal_gates", ...
                publicationPassed,"expected false for bounded run without controlling DOCX/FRC/SLS evidence");

            audit=struct2table(rows,"AsArray",true);
            % Integrity can pass while the publication gate remains closed.
            passed=all(audit.Pass(audit.Check~="all_calibration_sls_and_proposal_gates")) && ~publicationPassed;
        end
    end
end

function r=localRow(),r=struct("Artifact","","Check","","Pass",false,"Details","");end
function r=localMake(a,c,p,d),r=struct("Artifact",string(a),"Check",string(c),"Pass",logical(p),"Details",string(d));end
