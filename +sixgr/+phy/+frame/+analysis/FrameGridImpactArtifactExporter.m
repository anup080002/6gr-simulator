classdef FrameGridImpactArtifactExporter
    %FRAMEGRIDIMPACTARTIFACTEXPORTER CSV/PNG writer for frame-grid impact.
    %
    % The semantic plot writer is shared with the PUSCH component-impact
    % exporter because both contracts use the same source-hash and image
    % audit schema.  It plots only finite observations read from the named
    % CSV artifacts.

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
