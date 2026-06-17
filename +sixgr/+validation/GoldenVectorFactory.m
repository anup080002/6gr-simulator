function out = GoldenVectorFactory(kind)
%GOLDENVECTORFACTORY Canonical constants and expected-value profiles.

if nargin < 1
    kind = "default";
end
kind = lower(strtrim(string(kind)));

switch kind
    case {"default", "constants"}
        out = localConstants();
    case "grid_profiles"
        out = localGridProfiles();
    case "issue_ids"
        out = localIssueIds();
    otherwise
        error("sixgr:validation:UnknownGoldenVector", ...
            "Unsupported GoldenVectorFactory kind '%s'.", kind);
end
end

function out = localConstants()
out = struct();
out.SpeedOfLight_mps = 299792458.0;
out.LightSpeed_mps = out.SpeedOfLight_mps;
out.Speed100kmh_mps = 100.0 / 3.6;
out.DopplerAt4GHz100kmh_Hz = (4.0e9 * out.Speed100kmh_mps) / out.SpeedOfLight_mps;
out.DistanceStart_m = 50.0;
out.DistanceEnd_m = 500.0;
out.PropagationDelay500m_s = out.DistanceEnd_m / out.SpeedOfLight_mps;
out.DefaultInjectedCFO_Hz = 500.0;
out.DefaultLateResidualCFOTarget_Hz = 200.0;
out.HighSNRThreshold_dB = 15.0;
out.MinimumHighSNRLLRMeanAbs = 0.01;
end

function T = localGridProfiles()
rows = [ ...
    struct("BandwidthHz", 20e6, "SCSkHz", 15, "NSizeGrid", 106, "SampleRateHz", 30.72e6, "ProfileId", "fr1_20mhz_15khz"); ...
    struct("BandwidthHz", 20e6, "SCSkHz", 30, "NSizeGrid", 51, "SampleRateHz", 30.72e6, "ProfileId", "fr1_20mhz_30khz"); ...
    struct("BandwidthHz", 40e6, "SCSkHz", 30, "NSizeGrid", 106, "SampleRateHz", 61.44e6, "ProfileId", "fr1_40mhz_30khz"); ...
    struct("BandwidthHz", 100e6, "SCSkHz", 30, "NSizeGrid", 273, "SampleRateHz", 122.88e6, "ProfileId", "fr1_100mhz_30khz"); ...
    struct("BandwidthHz", 100e6, "SCSkHz", 120, "NSizeGrid", 66, "SampleRateHz", 122.88e6, "ProfileId", "fr2_100mhz_120khz") ...
    ];
T = struct2table(rows);
end

function out = localIssueIds()
out = struct( ...
    "GridMismatch", "GRID-01", ...
    "MIMOMismatch", "MIMO-01", ...
    "LabelOnlySuccess", "REALPHY-001", ...
    "FunctionNotCalled", "FUNC-001", ...
    "ReferenceUnavailable", "REF-001", ...
    "NegativeMissing", "NEG-001", ...
    "ProxyDetected", "PROXY-001", ...
    "FallbackDetected", "FALLBACK-001");
end
