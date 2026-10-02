function out = buildLLSCasePlan(cfg)
%BUILDLLSCASEPLAN Build fixed-MCS F1/F2 cases and paired coarse SNR points.
%
% A CasePlan row defines one physical curve. PointPlan contains its coarse
% SNR executions. All points of a curve share OutputGroupID, which is the
% required single-CSV/single-plot aggregation identity. Compared entries
% share RandomPairKey/ChannelSeed at each physical operating point.

arguments
    cfg struct
end

channels = cfg.lls.channels;
primary = string({channels.role}) == "primary";
channels = channels(primary);
antennaCases = cfg.lls.antenna_cases;
coarseSNR = double(cfg.statistics.coarse_snr_db(:));
baseSeed = double(cfg.lls.pairing_base_seed);

f1Entries = [sixgr.studies.ran1ai1032.MCSCatalog.baseline256(); ...
    sixgr.studies.ran1ai1032.MCSCatalog.highOrderCandidates()];
f1Table = sixgr.studies.ran1ai1032.MCSEntry.toTable(f1Entries);
f1Table = f1Table(ismember(f1Table.entry_id, ...
    ["B27";"H0";"H1";"H2";"H3"]), :);
f2Table = sixgr.studies.ran1ai1032.MCSCatalog.equalSpectralEfficiencyPairs();

rows = repmat(localEmptyCase(), 0, 1);
for ch = 1:numel(channels)
    for a = 1:numel(antennaCases)
        ranks = double(antennaCases(a).ranks(:)).';
        for rank = ranks
            physicalKey = localPhysicalKey(channels(ch), antennaCases(a), rank);
            for e = 1:height(f1Table)
                curveID = "F1:" + physicalKey + ":" + f1Table.entry_id(e);
                rows(end+1,1) = localCase("F1_B27_vs_H0_H3", "F1", ...
                    f1Table.entry_id(e), "", "", f1Table.Qm(e), ...
                    f1Table.target_code_rate_x1024(e), channels(ch), ...
                    antennaCases(a), rank, curveID, physicalKey); %#ok<AGROW>
            end
            for e = 1:height(f2Table)
                memberID = f2Table.pair_id(e) + f2Table.member(e);
                curveID = "F2:" + physicalKey + ":" + memberID;
                compareKey = physicalKey + ":" + f2Table.pair_id(e);
                rows(end+1,1) = localCase("F2_same_SE", "F2", ...
                    memberID, f2Table.pair_id(e), f2Table.member(e), ...
                    f2Table.Qm(e), f2Table.target_code_rate_x1024(e), ...
                    channels(ch), antennaCases(a), rank, curveID, compareKey); %#ok<AGROW>
            end
        end
    end
end
casePlan = struct2table(rows);

nPoint = height(casePlan) * numel(coarseSNR);
CaseID = strings(nPoint,1);
OutputGroupID = strings(nPoint,1);
ComparisonPairKey = strings(nPoint,1);
InputSNRdB = zeros(nPoint,1);
ChannelSeed = zeros(nPoint,1);
MinimumTransportBlocks = repmat(double(cfg.statistics.minimum_transport_blocks_per_point), nPoint, 1);
MinimumTBErrors = repmat(double(cfg.statistics.minimum_errors_per_point), nPoint, 1);
MaximumTransportBlocks = repmat(double(cfg.statistics.maximum_transport_blocks_per_point), nPoint, 1);
PreserveCensoredPoint = repmat(logical(cfg.statistics.preserve_censored_points), nPoint, 1);
PointStatus = repmat("planned_not_executed", nPoint, 1);

point = 0;
physicalPairs = unique(casePlan.ComparisonPairKey, "stable");
for c = 1:height(casePlan)
    pairOrdinal = find(physicalPairs == casePlan.ComparisonPairKey(c), 1);
    for s = 1:numel(coarseSNR)
        point = point + 1;
        CaseID(point) = casePlan.CaseID(c);
        OutputGroupID(point) = casePlan.OutputGroupID(c);
        ComparisonPairKey(point) = casePlan.ComparisonPairKey(c);
        InputSNRdB(point) = coarseSNR(s);
        % Deliberate common-random-number seed reuse within a comparison
        % pair at one SNR. The pair key makes this reuse explicit.
        ChannelSeed(point) = baseSeed + (pairOrdinal - 1) * numel(coarseSNR) + s;
    end
end
pointPlan = table(CaseID, OutputGroupID, ComparisonPairKey, InputSNRdB, ...
    ChannelSeed, MinimumTransportBlocks, MinimumTBErrors, ...
    MaximumTransportBlocks, PreserveCensoredPoint, PointStatus);

localValidate(casePlan, pointPlan, coarseSNR);
out = struct("CasePlan", casePlan, "PointPlan", pointPlan, ...
    "CaseCount", height(casePlan), "CoarsePointCount", height(pointPlan), ...
    "RefinementStep_dB", double(cfg.statistics.refinement_step_db), ...
    "RefinementPolicy", "add_0p1dB_points_around_observed_bler_or_goodput_transition", ...
    "Status", "PASS");
end

function row = localCase(family, experimentID, entryID, pairID, member, ...
        qm, rate, channel, antenna, rank, curveID, comparisonKey)
row = localEmptyCase();
row.CaseID = curveID;
row.ExperimentFamily = family;
row.ExperimentID = experimentID;
row.EntryID = entryID;
row.PairID = pairID;
row.PairMember = member;
row.Qm = double(qm);
row.TargetCodeRateX1024 = double(rate);
row.TargetCodeRate = double(rate) / 1024;
row.ChannelProfile = string(channel.profile);
row.DelaySpread_ns = double(channel.delay_spread_ns);
row.AntennaCaseID = string(antenna.id);
row.TxChains = double(antenna.tx_chains);
row.RxChains = double(antenna.rx_chains);
row.Rank = double(rank);
row.HARQEnabled = false;
row.ILLAEnabled = false;
row.OLLAEnabled = false;
row.PracticalChannelEstimation = true;
row.OutputGroupID = regexprep(lower(curveID), "[^a-z0-9]+", "_");
row.ComparisonPairKey = comparisonKey;
row.OutputContract = "one_curve_all_snr_points_one_csv_one_png";
row.ExecutionStatus = "planned_not_executed";
end

function row = localEmptyCase()
row = struct("CaseID","", "ExperimentFamily","", "ExperimentID","", ...
    "EntryID","", "PairID","", "PairMember","", "Qm",NaN, ...
    "TargetCodeRateX1024",NaN, "TargetCodeRate",NaN, ...
    "ChannelProfile","", "DelaySpread_ns",NaN, "AntennaCaseID","", ...
    "TxChains",NaN, "RxChains",NaN, "Rank",NaN, "HARQEnabled",false, ...
    "ILLAEnabled",false, "OLLAEnabled",false, ...
    "PracticalChannelEstimation",true, "OutputGroupID","", ...
    "ComparisonPairKey","", "OutputContract","", "ExecutionStatus","");
end

function key = localPhysicalKey(channel, antenna, rank)
key = lower(string(channel.profile)) + ":ds" + ...
    string(double(channel.delay_spread_ns)) + ":" + ...
    lower(string(antenna.id)) + ":r" + string(rank);
end

function localValidate(cases, points, expectedSNR)
if any(cases.Rank > min(cases.TxChains, cases.RxChains)) || ...
        any(~ismember(cases.Qm, [2 4 6 8 10])) || ...
        any(cases.HARQEnabled | cases.ILLAEnabled | cases.OLLAEnabled)
    error("sixgr:ran1ai1032:InvalidLLSCasePlan", ...
        "Fixed-MCS cases violate physical rank, Qm or adaptation constraints.");
end
for c = 1:height(cases)
    rows = points.CaseID == cases.CaseID(c);
    if ~isequal(points.InputSNRdB(rows), expectedSNR) || ...
            numel(unique(points.OutputGroupID(rows))) ~= 1
        error("sixgr:ran1ai1032:InvalidLLSPointPlan", ...
            "Every case must contain the complete ordered coarse sweep in one output group.");
    end
end
pairSNR = unique(points(:, ["ComparisonPairKey","InputSNRdB"]), "rows");
for i = 1:height(pairSNR)
    rows = points.ComparisonPairKey == pairSNR.ComparisonPairKey(i) & ...
        points.InputSNRdB == pairSNR.InputSNRdB(i);
    if numel(unique(points.ChannelSeed(rows))) ~= 1
        error("sixgr:ran1ai1032:UnpairedLLSSeeds", ...
            "Compared entries must share a channel seed at each SNR.");
    end
end
end
