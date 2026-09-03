function ok = testFixedLinkCampaignSerialParallel()
%TESTFIXEDLINKCAMPAIGNSERIALPARALLEL Independent points are reproducible.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "master_sinr_sweep.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg.toStruct(), ...
    fullfile(tempdir, "fixed_link_serial_parallel_fixture"));
campaignCfg = cfg.validation.fixed_link_campaign;
campaignCfg.direction = "DL";
campaignCfg.snr_db = [10 20];
campaignCfg.mcs = 20;
campaignCfg.min_tb_per_point = 1;
campaignCfg.max_tb_per_point = 1;
campaignCfg.min_errors_for_ci = 0;
campaignCfg.max_ci_half_width = 1;
campaignCfg.trials_per_drop = 1;
configuredSeeds = double(campaignCfg.seeds(:));
assert(~isempty(configuredSeeds), ...
    "The master YAML must provide a fixed-link seed list.");
% Serial/parallel equivalence is an execution-topology check.  Bind it to
% one YAML-owned seed so the one-TB fixture remains internally valid; the
% independent multi-seed tests retain responsibility for seed coverage and
% statistical adequacy.
campaignCfg.seeds = configuredSeeds(1);
if isfield(campaignCfg, "Seeds")
    campaignCfg.Seeds = configuredSeeds(1);
end

serialCfg = campaignCfg;
serialCfg.parallel_workers = 0;
parallelCfg = campaignCfg;
parallelCfg.parallel_workers = 2;
serial = sixgr.lls6g.campaign.runFixedLinkCampaign(cfg, ...
    "Config", serialCfg, "WriteArtifacts", false);
parallel = sixgr.lls6g.campaign.runFixedLinkCampaign(cfg, ...
    "Config", parallelCfg, "WriteArtifacts", false);

assert(~serial.ParallelExecution && parallel.ParallelExecution && ...
    parallel.ParallelWorkers == 2, ...
    "Campaign output must disclose the selected execution topology.");
for field = ["Summary","DLTrials","ULTrials","TaskPlan"]
    a = localScientificTable(serial.(char(field)));
    b = localScientificTable(parallel.(char(field)));
    if ~localTablesEqual(a, b, parallel.ParallelContinuousMetricTolerance)
        error("sixgr:tests:FixedLinkSerialParallelMismatch", ...
            "Serial and parallel fixed-link field %s differ: %s.", ...
            field, localDifference(a, b));
    end
end

function detail = localDifference(a, b)
if height(a) ~= height(b) || width(a) ~= width(b)
    detail = "shape=" + mat2str(size(a)) + " vs " + mat2str(size(b));
    return;
end
bad = strings(0, 1);
for name = string(a.Properties.VariableNames)
    if ~isequaln(a.(char(name)), b.(char(name)))
        av = a.(char(name));
        bv = b.(char(name));
        if isnumeric(av) && isnumeric(bv)
            delta = abs(double(av) - double(bv));
            delta = delta(isfinite(delta));
            if isempty(delta)
                maxDelta = NaN;
            else
                maxDelta = max(delta);
            end
            bad(end+1, 1) = name + "(max_abs=" + ...
                string(maxDelta) + ")"; %#ok<AGROW>
        else
            bad(end+1, 1) = name; %#ok<AGROW>
        end
    end
end
detail = "columns=" + strjoin(bad, ",");
end
ok = true;
end

function tf = localTablesEqual(a, b, tolerance)
tf = istable(a) && istable(b) && isequal(size(a), size(b)) && ...
    isequal(string(a.Properties.VariableNames), ...
    string(b.Properties.VariableNames));
if ~tf
    return;
end
for name = string(a.Properties.VariableNames)
    av = a.(char(name));
    bv = b.(char(name));
    if isequaln(av, bv)
        continue;
    end
    if ~(isnumeric(av) && isnumeric(bv) && isequal(size(av), size(bv)))
        tf = false;
        return;
    end
    nanMask = isnan(double(av)) & isnan(double(bv));
    finiteMask = isfinite(double(av)) & isfinite(double(bv));
    if ~all(nanMask(:) | finiteMask(:))
        tf = false;
        return;
    end
    scale = max(1, max(abs([double(av(finiteMask)); ...
        double(bv(finiteMask))]), [], "omitnan"));
    if any(abs(double(av(finiteMask)) - double(bv(finiteMask))) > ...
            double(tolerance) * scale)
        tf = false;
        return;
    end
end
end

function T = localScientificTable(T)
excluded = intersect(string(T.Properties.VariableNames), ...
    ["DecodeLatency_ms","DL_DecodeLatency_ms","UL_DecodeLatency_ms", ...
    "ComputeLatency_ms","ReceiverPipelineLatency_ms", ...
    "ChannelEstimationLatency_ms","EqualizationLatency_ms"], "stable");
if ~isempty(excluded)
    T(:, cellstr(excluded)) = [];
end
end
