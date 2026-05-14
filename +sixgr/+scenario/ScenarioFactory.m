classdef ScenarioFactory
%SIXGR.SCENARIO.SCENARIOFACTORY Scenario profile selection.
%
%   prof = sixgr.scenario.ScenarioFactory.getProfile(cfg)
%   prof = sixgr.scenario.ScenarioFactory.getProfile(cfg, scenarioName)
%
% Robust behavior:
%   - If cfg.scenario.profiles exists, it selects the requested profile.
%   - If cfg.scenario.profiles is missing (common during early bootstrap),
%     it synthesizes a profile from the flat cfg.scenario.* fields.
%
% The returned profile struct contains the fields required by the scenario
% pipeline (generateLayout, dropUEs, mobility).
%
% See also: sixgr.scenario.generateLayout, sixgr.scenario.dropUEs

    methods(Static)
        function prof = getProfile(cfg, scenarioName)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end

            % Pick active scenario name.
            if nargin < 2 || (isstring(scenarioName) && strlength(scenarioName) == 0) || (ischar(scenarioName) && isempty(scenarioName))
                scenarioName = sixgr.util.structGet(cfg, "scenario.profileName", "");
                if (isstring(scenarioName) && strlength(scenarioName) == 0) || (ischar(scenarioName) && isempty(scenarioName))
                    scenarioName = sixgr.util.structGet(cfg, "channel.propagationScenario", "");
                end
                if (isstring(scenarioName) && strlength(scenarioName) == 0) || (ischar(scenarioName) && isempty(scenarioName))
                    scenarioName = sixgr.util.structGet(cfg, "scenario.name", "UMa");
                end
            end
            scenarioName = char(string(scenarioName));

            prof = struct();

            % 1) Profile-based config (preferred)
            if isfield(cfg, 'scenario') && isfield(cfg.scenario, 'profiles') && isstruct(cfg.scenario.profiles)
                profiles = cfg.scenario.profiles;

                % Direct match
                if isfield(profiles, scenarioName)
                    prof = profiles.(scenarioName);
                    prof.name = scenarioName;
                    prof = localNormalizeProfile(prof, cfg);
                    return;
                end

                % Case-insensitive match
                fn = fieldnames(profiles);
                idx = find(strcmpi(fn, scenarioName), 1);
                if ~isempty(idx)
                    prof = profiles.(fn{idx});
                    prof.name = fn{idx};
                    prof = localNormalizeProfile(prof, cfg);
                    return;
                end

                % MakeValidName match (helps when JSON keys are not valid identifiers)
                v = matlab.lang.makeValidName(scenarioName);
                if isfield(profiles, v)
                    prof = profiles.(v);
                    prof.name = v;
                    prof = localNormalizeProfile(prof, cfg);
                    return;
                end
                % Otherwise: fall through to flat synthesis.
            end

            % 2) Flat cfg.scenario.* synthesis (bootstrap-safe)
            prof = localFromFlatConfig(cfg, scenarioName);
            prof = localNormalizeProfile(prof, cfg);
        end

        function names = availableProfiles(cfg)
            names = {};
            if nargin >= 1 && isfield(cfg, 'scenario') && isfield(cfg.scenario, 'profiles') && isstruct(cfg.scenario.profiles)
                names = fieldnames(cfg.scenario.profiles);
            end
            if isempty(names)
                names = {'UMa','UMi','InH','SMa','RMa'};
            end
        end
    end
end

% -------------------------------------------------------------------------
% Local helpers
% -------------------------------------------------------------------------

function prof = localFromFlatConfig(cfg, scenarioName)
% Start from a builtin baseline, then apply overrides from cfg.scenario.*.

    prof = localBuiltinProfile(scenarioName);
    prof.name = char(string(scenarioName));

    if ~isfield(cfg, 'scenario') || ~isstruct(cfg.scenario)
        return;
    end
    sc = cfg.scenario;

    % Geometry
    area_m = sixgr.util.structGet(sc, 'geometry.area_m', prof.area_m);
    area_m = double(area_m(:).');
    if numel(area_m) == 2
        prof.area_m = area_m;
    end
    prof.wraparoundEnabled = logical(sixgr.util.structGet(sc, 'geometry.wraparound', prof.wraparoundEnabled));
    prof.wraparoundMode = char(string(sixgr.util.structGet(sc, 'geometry.wraparoundMode', ...
        sixgr.util.structGet(sc, 'geometry.wraparound_mode', sixgr.util.structGet(prof, 'wraparoundMode', "")))));

    dep = lower(char(string(sixgr.util.structGet(sc, 'geometry.deployment', ''))));
    if ~isempty(dep)
        if contains(dep, 'hex')
            prof.layoutType = 'hex_grid';
        elseif contains(dep, 'indoor')
            prof.layoutType = 'indoor_grid';
        elseif contains(dep, 'grid')
            prof.layoutType = 'rect_grid';
        end
    end

    % Layout
    prof.isd_m   = double(sixgr.util.structGet(sc, 'layout.interSiteDistance_m', prof.isd_m));
    prof.nSites  = double(sixgr.util.structGet(sc, 'layout.nSites', prof.nSites));
    prof.nSectors = double(sixgr.util.structGet(sc, 'layout.nSectorsPerSite', prof.nSectors));
    if prof.nSites <= 0, prof.nSites = 1; end
    if prof.nSectors <= 0, prof.nSectors = 1; end
    prof.nTRxP = prof.nSites * prof.nSectors;

    % gNB / TRxP parameters (tx)
    prof.bs.height_m    = double(sixgr.util.structGet(sc, 'tx.height_m', prof.bs.height_m));
    prof.bs.txPower_dBm = double(sixgr.util.structGet(sc, 'tx.txPower_dBm', prof.bs.txPower_dBm));

    % Sectorization
    az = sixgr.util.structGet(sc, 'sectorization.azimOffsets_deg', prof.sectorization.azimOffsets_deg);
    if ~isempty(az)
        prof.sectorization.azimOffsets_deg = double(az(:).');
    end

    % UE
    ueCount = double(sixgr.util.structGet(sc, 'ue.nUE', sixgr.util.structGet(sc, 'ue.count', prof.ue.count)));
    if ueCount > 0
        prof.ue.count = ueCount;
    end
    prof.ue.height_m = double(sixgr.util.structGet(sc, 'ue.height_m', prof.ue.height_m));
    prof.ue.dropMode = char(string(sixgr.util.structGet(sc, 'ue.dropMode', ...
        sixgr.util.structGet(sc, 'ue.distribution.dropMode', sixgr.util.structGet(prof.ue, 'dropMode', "")))));

    indF = sixgr.util.structGet(sc, 'ue.indoorFraction', []);
    if ~isempty(indF)
        prof.ue.distribution.indoorFraction = double(indF);
    end

    % Mobility -> speed distributions
    sp = sixgr.util.structGet(sc, 'mobility.speed_kmh', []);
    if ~isempty(sp)
        prof.ue.distribution.speeds_kmh = double(sp(:).');
    end
    sw = sixgr.util.structGet(sc, 'mobility.speedWeights', []);
    if ~isempty(sw)
        prof.ue.distribution.speedWeights = double(sw(:).');
    end
    mm = sixgr.util.structGet(sc, 'mobility.model', '');
    if ~isempty(mm)
        prof.ue.mobility.model = char(string(mm));
    end
end

function prof = localBuiltinProfile(scenarioName)
% Minimal built-in profiles to allow immediate execution.

    s = lower(char(string(scenarioName)));

    % Default baseline: UMa-like
    prof = struct();
    prof.name = 'UMa';
    prof.layoutType = 'hex_grid';
    prof.area_m = [2000 2000];
    prof.wraparoundEnabled = true;
    prof.wraparoundMode = 'hex_lattice_min_image';
    prof.isd_m = 500;
    prof.nSites = 19;
    prof.nSectors = 3;
    prof.nTRxP = 57;

    prof.bs = struct();
    prof.bs.height_m = 25;
    prof.bs.txPower_dBm = 46;

    prof.sectorization = struct();
    prof.sectorization.azimOffsets_deg = [0 120 240];

    prof.ue = struct();
    prof.ue.count = 190;
    prof.ue.height_m = 1.5;
    prof.ue.distribution = struct();
    prof.ue.distribution.indoorFraction = 0.2;
    prof.ue.distribution.speeds_kmh = [3 30 120];
    prof.ue.distribution.speedWeights = [0.7 0.2 0.1];
    prof.ue.mobility = struct();
    prof.ue.mobility.model = 'RandomWaypoint';

    if contains(s, 'inh') || contains(s, 'indoor')
        prof.name = 'InH';
        prof.layoutType = 'indoor_grid';
        prof.area_m = [120 50];
        prof.wraparoundEnabled = false;
        prof.wraparoundMode = 'disabled';
        prof.isd_m = 20;
        prof.nSites = 1;
        prof.nSectors = 1;
        prof.nTRxP = 1;
        prof.bs.height_m = 3;
        prof.bs.txPower_dBm = 24;
        prof.ue.count = 20;
        prof.ue.distribution.indoorFraction = 1.0;
        prof.ue.distribution.speeds_kmh = [0 3];
        prof.ue.distribution.speedWeights = [0.5 0.5];
    elseif contains(s, 'umi') || contains(s, 'urbanmicro') || contains(s, 'denseurban')
        prof.name = 'UMi';
        prof.isd_m = 200;
        prof.bs.height_m = 10;
        prof.bs.txPower_dBm = 30;
        prof.ue.distribution.indoorFraction = 0.5;
        prof.ue.distribution.speeds_kmh = [3 30 60];
        prof.ue.distribution.speedWeights = [0.6 0.3 0.1];
    elseif contains(s, 'sma')
        prof.name = 'SMa';
        prof.isd_m = 1299;
        prof.bs.height_m = 35;
        prof.ue.distribution.indoorFraction = 0.5;
        prof.ue.distribution.speeds_kmh = [3 30];
        prof.ue.distribution.speedWeights = [0.7 0.3];
    elseif contains(s, 'rma')
        prof.name = 'RMa';
        prof.isd_m = 1732;
        prof.bs.height_m = 35;
        prof.ue.distribution.indoorFraction = 0.5;
        prof.ue.distribution.speeds_kmh = [3 120];
        prof.ue.distribution.speedWeights = [0.5 0.5];
        prof.ue.mobility.model = 'RMaMixedSpeed';
    end
end

function prof = localNormalizeProfile(prof, cfg)
% Fill required fields and apply safe fallbacks.

    if ~isfield(prof, 'name'), prof.name = 'UMa'; end

    % Layout fields
    prof.layoutType = char(string(sixgr.util.structGet(prof, 'layoutType', 'hex_grid')));
    prof.wraparoundEnabled = logical(sixgr.util.structGet(prof, 'wraparoundEnabled', true));
    prof.wraparoundMode = char(string(sixgr.util.structGet(prof, 'wraparoundMode', '')));
    if strlength(strtrim(string(prof.wraparoundMode))) == 0
        if ~prof.wraparoundEnabled
            prof.wraparoundMode = 'disabled';
        elseif contains(lower(prof.layoutType), 'hex')
            prof.wraparoundMode = 'hex_lattice_min_image';
        else
            prof.wraparoundMode = 'rectangular_torus';
        end
    end

    area_m = sixgr.util.structGet(prof, 'area_m', [2000 2000]);
    area_m = double(area_m(:).');
    if numel(area_m) ~= 2
        area_m = [2000 2000];
    end
    prof.area_m = area_m;

    prof.isd_m = double(sixgr.util.structGet(prof, 'isd_m', 500));
    prof.nSites = double(sixgr.util.structGet(prof, 'nSites', 19));
    prof.nSectors = double(sixgr.util.structGet(prof, 'nSectors', 3));
    if prof.nSites <= 0, prof.nSites = 1; end
    if prof.nSectors <= 0, prof.nSectors = 1; end
    prof.nTRxP = double(sixgr.util.structGet(prof, 'nTRxP', prof.nSites * prof.nSectors));

    % bs
    if ~isfield(prof, 'bs') || ~isstruct(prof.bs), prof.bs = struct(); end
    prof.bs.height_m = double(sixgr.util.structGet(prof.bs, 'height_m', 25));
    prof.bs.txPower_dBm = double(sixgr.util.structGet(prof.bs, 'txPower_dBm', 46));

    % sectorization
    if ~isfield(prof, 'sectorization') || ~isstruct(prof.sectorization)
        prof.sectorization = struct();
    end
    az = sixgr.util.structGet(prof.sectorization, 'azimOffsets_deg', []);
    if isempty(az)
        az = (0:prof.nSectors-1) * (360 / prof.nSectors);
    end
    prof.sectorization.azimOffsets_deg = double(az(:).');

    % ue
    if ~isfield(prof, 'ue') || ~isstruct(prof.ue), prof.ue = struct(); end
    if ~isfield(prof.ue, 'count')
        % If flat cfg provided an explicit UE count, prefer it.
        ueCount = double(sixgr.util.structGet(cfg, 'scenario.ue.nUE', 0));
        if ueCount <= 0
            ueCount = max(1, 10 * prof.nSites);
        end
        prof.ue.count = ueCount;
    end
    prof.ue.count = double(prof.ue.count);
    if prof.ue.count <= 0, prof.ue.count = 1; end

    prof.ue.height_m = double(sixgr.util.structGet(prof.ue, 'height_m', 1.5));
    prof.ue.dropMode = char(string(sixgr.util.structGet(prof.ue, 'dropMode', 'legacy_equal_sector_drop')));

    if ~isfield(prof.ue, 'distribution') || ~isstruct(prof.ue.distribution)
        prof.ue.distribution = struct();
    end
    if ~isfield(prof.ue.distribution, 'indoorFraction')
        prof.ue.distribution.indoorFraction = double(sixgr.util.structGet(cfg, 'scenario.ue.indoorFraction', 0.2));
    end
    if ~isfield(prof.ue.distribution, 'speeds_kmh')
        prof.ue.distribution.speeds_kmh = double(sixgr.util.structGet(cfg, 'scenario.mobility.speed_kmh', [0 3]));
    end
    if ~isfield(prof.ue.distribution, 'speedWeights')
        sp = double(prof.ue.distribution.speeds_kmh(:).');
        if isempty(sp)
            prof.ue.distribution.speedWeights = 1;
        else
            prof.ue.distribution.speedWeights = ones(1, numel(sp)) / numel(sp);
        end
    end

    if ~isfield(prof.ue, 'mobility') || ~isstruct(prof.ue.mobility)
        prof.ue.mobility = struct();
    end
    if ~isfield(prof.ue.mobility, 'model')
        prof.ue.mobility.model = char(string(sixgr.util.structGet(cfg, 'scenario.mobility.model', 'RandomWaypoint')));
    end

end
