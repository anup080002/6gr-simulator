function traffic = Traffic_FTP3(cfg, nUE, nTTI, tti_s, numCells)
%TRAFFIC_FTP3 Generate a deterministic FTP Model 3 file-arrival workload.
%
% This is an application offered-load model: fixed-size files arrive as a
% continuous-time Poisson process and are assigned uniformly to UEs.  It
% deliberately does not pretend to implement TCP congestion control.  The
% returned event ledger is the authority used to freeze identical arrivals
% across system comparators.

arguments
    cfg struct
    nUE (1,1) double {mustBeInteger,mustBePositive}
    nTTI (1,1) double {mustBeInteger,mustBePositive}
    tti_s (1,1) double {mustBePositive}
    numCells (1,1) double {mustBeInteger,mustBePositive} = 1
end

fileSizeBytes = double(sixgr.util.structGet(cfg, ...
    "traffic.ftp3.fileSizeBytes", NaN));
arrivalRatePerCell_s = double(sixgr.util.structGet(cfg, ...
    "traffic.ftp3.arrivalRatePerCell_s", NaN));
direction = upper(strtrim(string(sixgr.util.structGet(cfg, ...
    "traffic.ftp3.direction", "UL"))));
seed = double(sixgr.util.structGet(cfg, "traffic.ftp3.seed", ...
    double(sixgr.util.structGet(cfg, "run.seed", 1)) + 7303));

if ~(isscalar(fileSizeBytes) && isfinite(fileSizeBytes) && ...
        fileSizeBytes == fix(fileSizeBytes) && fileSizeBytes > 0)
    error("sixgr:traffic:FTP3MissingFileSize", ...
        "traffic.model='ftp3' requires integer traffic.ftp3.fileSizeBytes > 0.");
end
if ~(isscalar(arrivalRatePerCell_s) && isfinite(arrivalRatePerCell_s) && ...
        arrivalRatePerCell_s >= 0)
    error("sixgr:traffic:FTP3MissingArrivalRate", ...
        "traffic.model='ftp3' requires traffic.ftp3.arrivalRatePerCell_s >= 0.");
end
if ~ismember(direction, ["UL","DL"])
    error("sixgr:traffic:FTP3Direction", ...
        "traffic.ftp3.direction must be UL or DL.");
end
if ~(isscalar(seed) && isfinite(seed) && seed == fix(seed) && seed >= 0)
    error("sixgr:traffic:FTP3Seed", ...
        "traffic.ftp3.seed must be a non-negative integer.");
end

seed = mod(round(seed), 2^32 - 1);
if seed == 0
    seed = 1;
end
stream = RandStream("mt19937ar", "Seed", seed);
duration_s = double(nTTI) * double(tti_s);
totalRate_s = double(arrivalRatePerCell_s) * double(numCells);

arrivalTime_s = zeros(0, 1);
if totalRate_s > 0
    t = -log(max(rand(stream), realmin)) / totalRate_s;
    while t < duration_s
        arrivalTime_s(end+1, 1) = t; %#ok<AGROW>
        t = t - log(max(rand(stream), realmin)) / totalRate_s;
    end
end

nFiles = numel(arrivalTime_s);
arrivalTTI = min(double(nTTI), floor(arrivalTime_s ./ double(tti_s)) + 1);
if nFiles > 0
    ue = randi(stream, double(nUE), nFiles, 1);
else
    ue = zeros(0, 1);
end
fileBits = double(fileSizeBytes) * 8;
offered = zeros(nTTI, nUE);
if nFiles > 0
    offered = accumarray([arrivalTTI, ue], fileBits, ...
        [nTTI, nUE], @sum, 0);
end

offeredDL = zeros(nTTI, nUE);
offeredUL = zeros(nTTI, nUE);
if direction == "UL"
    offeredUL = offered;
else
    offeredDL = offered;
end

streamID = "ftp3:seed=" + string(seed) + ...
    ":cells=" + string(numCells) + ...
    ":ues=" + string(nUE) + ...
    ":file_bytes=" + string(fileSizeBytes) + ...
    ":lambda_per_cell_s=" + string(arrivalRatePerCell_s) + ...
    ":tti_s=" + string(tti_s) + ":n_tti=" + string(nTTI);
arrivalID = "ftp3-file-" + compose("%08d", (1:nFiles).');
eventTable = table(arrivalID, arrivalTTI, arrivalTime_s, ue, ...
    repmat(fileSizeBytes, nFiles, 1), repmat(fileBits, nFiles, 1), ...
    repmat(direction, nFiles, 1), repmat(seed, nFiles, 1), ...
    repmat(streamID, nFiles, 1), ...
    repmat("fixed_file_continuous_time_poisson", nFiles, 1), ...
    'VariableNames', {'ArrivalID','ArrivalTTI','ArrivalTime_s','UEID', ...
    'FileSizeBytes','OfferedBits','Direction','Seed','ArrivalStreamID', ...
    'ArrivalProcess'});

meanRateMbps = sum(offered, "all") / max(duration_s, eps) / 1e6;
flowTable = table("ftp3", 9, 9, "APPLICATION_WORKLOAD", direction, ...
    double(sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", 50)), ...
    fileSizeBytes, NaN, meanRateMbps, 1.0, "poisson_files", ...
    "FTP3", "FWA_CPE", double(nUE), ...
    "3gpp_ftp3_fixed_file_poisson_arrival_workload", ...
    "truthful_application_arrival_ledger_no_tcp_claim", "", ...
    'VariableNames', {'Name','QFI','FiveQI','Protocol','Direction', ...
    'PacketDelayBudget_ms','PacketSize_bytes','PacketInterval_ms', ...
    'Rate_Mbps','Weight','Burstiness','ServiceProfile','UEClass','UECount', ...
    'TransportSemanticClass','TransportTruthLabel','TransportApproximationReason'});

traffic = struct();
traffic.Model = "ftp3";
traffic.Transport = "APPLICATION_WORKLOAD";
traffic.FlowDirection = direction;
traffic.PacketDelayBudget_ms = double(sixgr.util.structGet(cfg, ...
    "traffic.packetDelayBudget_ms", 50));
traffic.OfferedBits = offered;
traffic.OfferedBitsDL = offeredDL;
traffic.OfferedBitsUL = offeredUL;
traffic.MeanBitsPerUEPerTTI = mean(offered, 1);
traffic.FlowTable = flowTable;
traffic.FlowCount = height(flowTable);
traffic.EventTable = eventTable;
traffic.ArrivalStreamID = streamID;
traffic.ModelSource = "sixgr.system.Traffic_FTP3";
traffic.DefinitionSource = "configured_fixed_file_continuous_time_poisson_ftp3";
traffic.Deterministic = true;
traffic.ProxyShapingUsed = false;
traffic.TransportSemanticClass = ...
    "3gpp_ftp3_fixed_file_poisson_arrival_workload";
traffic.TransportTruthLabel = ...
    "truthful_application_arrival_ledger_no_tcp_claim";
traffic.TransportApproximationReason = "";
traffic.FileCount = nFiles;
traffic.FileSizeBytes = fileSizeBytes;
traffic.ArrivalRatePerCell_s = arrivalRatePerCell_s;
traffic.NumCells = numCells;
end
