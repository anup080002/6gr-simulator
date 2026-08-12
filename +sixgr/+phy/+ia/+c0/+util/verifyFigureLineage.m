function verification = verifyFigureLineage(runFolder,lineage)
%VERIFYFIGURELINEAGE Verify C0 raster images against persisted sources.
rows = cell(height(lineage),1);
for k = 1:height(lineage)
    imagePath = char(lineage.Path(k));
    sourcePath = fullfile(runFolder,char(lineage.SourceCSV(k)));
    imageHash = "";
    sourceHash = "";
    if isfile(imagePath)
        imageHash = sixgr.phy.waveform.WaveformArtifactExporter. ...
            fileSHA256(imagePath);
    end
    if isfile(sourcePath)
        sourceHash = string(sixgr.util.sha256Hex(fileread(sourcePath)));
    end
    pass = isfile(imagePath) && isfile(sourcePath) && ...
        endsWith(imagePath,".png","IgnoreCase",true) && ...
        imageHash == lineage.ImageSHA256(k) && ...
        sourceHash == lineage.SourceSHA256(k);
    rows{k} = table(lineage.FigureID(k),string(imagePath), ...
        string(sourcePath),pass, ...
        'VariableNames',{'FigureID','ImagePath','SourcePath','Pass'});
end
verification = vertcat(rows{:});
end
