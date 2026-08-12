function [power,grid] = measureActiveREPower(waveform,bundle,startSample)
%MEASUREACTIVEREPOWER Measure power on production SSB active RE.
startSample = round(double(startSample));
if startSample < 0 || startSample >= size(waveform,1)
    error("sixgr:phy:ia:c0:channel:BadMeasurementTiming", ...
        "Active-RE measurement start sample lies outside the waveform.");
end
aligned = waveform(startSample+1:end,:);
grid = nrOFDMDemodulate(bundle.Carrier,aligned);
if size(grid,2) < 14
    error("sixgr:phy:ia:c0:channel:ShortWaveform", ...
        "Aligned waveform does not contain one complete C0 slot.");
end
grid = grid(:,1:14,:);
active = bundle.ActiveIndices;
values = zeros(numel(active),size(grid,3));
for rx = 1:size(grid,3)
    slice = grid(:,:,rx);
    values(:,rx) = slice(active);
end
power = mean(abs(values(:)).^2,"omitnan");
end
