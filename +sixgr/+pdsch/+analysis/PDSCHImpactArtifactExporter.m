classdef PDSCHImpactArtifactExporter
    %PDSCHIMPACTARTIFACTEXPORTER Persist source-bound impact evidence.

    methods (Static)
        function writeTable(outputDir, fileName, value)
            sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter. ...
                writeTable(outputDir, fileName, value);
        end

        function audit = writeSemanticFigure(outputDir, contractRow, cfg)
            audit = ...
                sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter. ...
                writeSemanticFigure(outputDir, contractRow, cfg);
        end

        function hash = fileHash(path)
            hash = ...
                sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter. ...
                fileHash(path);
        end
    end
end
