function layout = resultLayout(runFolder)
%RESULTLAYOUT Canonical, analysis-friendly result layout for simulator runs.
%
% The simulator writes one structured tree per run:
%   <runFolder>/
%     meta/
%     reports/{csv,mat,image,profiling}/
%     logs/
%     air_interface/{csv,mat,image,logs}/
%     air_interface/detailed/{csv,mat,image,logs}/
%     control/{csv,image}/
%     harq/csv/
%     system/{csv,mat,image,logs}/
%     mmtc/{csv,mat,image,logs}/
%     interference/csv/
%     beamforming/csv/
%     numerology/csv/
%     rf/csv/
%     v2x/csv/
%     ntn/csv/
%     packet_flow/{csv,mat,image,logs}/
%     calibration/

runFolder = char(string(runFolder));

layout = struct();
layout.Root = runFolder;

layout.MetaDir = fullfile(runFolder, "meta");
layout.LogDir = fullfile(runFolder, "logs");

layout.ManifestsDir = fullfile(runFolder, "manifests");
layout.SummariesDir = fullfile(runFolder, "summaries");
layout.RawDir = fullfile(runFolder, "raw");
layout.TablesDir = fullfile(runFolder, "tables");
layout.TracesDir = fullfile(runFolder, "traces");
layout.MapsDir = fullfile(runFolder, "maps");
layout.PlotsDir = fullfile(runFolder, "plots");
layout.ComparisonsDir = fullfile(runFolder, "comparisons");
layout.DebugDir = fullfile(runFolder, "debug");

layout.ReportDir = fullfile(runFolder, "reports");
layout.ReportCSVDir = fullfile(layout.ReportDir, "csv");
layout.ReportMATDir = fullfile(layout.ReportDir, "mat");
layout.ReportImageDir = fullfile(layout.ReportDir, "image");
layout.ReportProfilingDir = fullfile(layout.ReportDir, "profiling");

layout.AirInterfaceDir = fullfile(runFolder, "air_interface");
layout.AirInterfaceCSVDir = fullfile(layout.AirInterfaceDir, "csv");
layout.AirInterfaceMATDir = fullfile(layout.AirInterfaceDir, "mat");
layout.AirInterfaceImageDir = fullfile(layout.AirInterfaceDir, "image");
layout.AirInterfaceLogDir = fullfile(layout.AirInterfaceDir, "logs");

layout.DetailedLLSDir = fullfile(layout.AirInterfaceDir, "detailed");
layout.DetailedLLSCSVDir = fullfile(layout.DetailedLLSDir, "csv");
layout.DetailedLLSMATDir = fullfile(layout.DetailedLLSDir, "mat");
layout.DetailedLLSImageDir = fullfile(layout.DetailedLLSDir, "image");
layout.DetailedLLSLogDir = fullfile(layout.DetailedLLSDir, "logs");

layout.ControlDir = fullfile(runFolder, "control");
layout.ControlCSVDir = fullfile(layout.ControlDir, "csv");
layout.ControlImageDir = fullfile(layout.ControlDir, "image");

layout.HARQDir = fullfile(runFolder, "harq");
layout.HARQCSVDir = fullfile(layout.HARQDir, "csv");

layout.SystemDir = fullfile(runFolder, "system");
layout.SystemCSVDir = fullfile(layout.SystemDir, "csv");
layout.SystemMATDir = fullfile(layout.SystemDir, "mat");
layout.SystemImageDir = fullfile(layout.SystemDir, "image");
layout.SystemLogDir = fullfile(layout.SystemDir, "logs");

layout.MMTCDir = fullfile(runFolder, "mmtc");
layout.MMTCCSVDir = fullfile(layout.MMTCDir, "csv");
layout.MMTCMATDir = fullfile(layout.MMTCDir, "mat");
layout.MMTCImageDir = fullfile(layout.MMTCDir, "image");
layout.MMTCLogDir = fullfile(layout.MMTCDir, "logs");

layout.InterferenceDir = fullfile(runFolder, "interference");
layout.InterferenceCSVDir = fullfile(layout.InterferenceDir, "csv");

layout.BeamformingDir = fullfile(runFolder, "beamforming");
layout.BeamformingCSVDir = fullfile(layout.BeamformingDir, "csv");
layout.BeamformingImageDir = fullfile(layout.BeamformingDir, "image");

layout.NumerologyDir = fullfile(runFolder, "numerology");
layout.NumerologyCSVDir = fullfile(layout.NumerologyDir, "csv");

layout.RFDir = fullfile(runFolder, "rf");
layout.RFCSVDir = fullfile(layout.RFDir, "csv");

layout.V2XDir = fullfile(runFolder, "v2x");
layout.V2XCSVDir = fullfile(layout.V2XDir, "csv");

layout.NTNDir = fullfile(runFolder, "ntn");
layout.NTNCSVDir = fullfile(layout.NTNDir, "csv");

layout.PacketFlowDir = fullfile(runFolder, "packet_flow");
layout.PacketFlowCSVDir = fullfile(layout.PacketFlowDir, "csv");
layout.PacketFlowMATDir = fullfile(layout.PacketFlowDir, "mat");
layout.PacketFlowImageDir = fullfile(layout.PacketFlowDir, "image");
layout.PacketFlowLogDir = fullfile(layout.PacketFlowDir, "logs");

layout.CalibrationDir = fullfile(runFolder, "calibration");

layout.ConfigResolvedJSON = fullfile(layout.MetaDir, "config_resolved_full_campaign.json");
layout.RunManifestJSON = fullfile(layout.MetaDir, "run_manifest.json");
layout.EnvironmentJSON = fullfile(layout.MetaDir, "environment.json");
layout.SeedsCSV = fullfile(layout.MetaDir, "seeds.csv");
layout.ApproximationsCSV = fullfile(layout.MetaDir, "approximations_used.csv");
layout.CalibrationSourceJSON = fullfile(layout.MetaDir, "calibration_source.json");

layout.CampaignReportMD = fullfile(layout.ReportDir, "full_campaign_report.md");
layout.CampaignReportMAT = fullfile(layout.ReportMATDir, "full_campaign_report.mat");
layout.CategoryAuditCSV = fullfile(layout.ReportCSVDir, "full_3gpp_category_audit.csv");
layout.ArtifactChecklistCSV = fullfile(layout.ReportCSVDir, "full_3gpp_artifact_checklist.csv");
layout.ArtifactChecklistMD = fullfile(layout.ReportDir, "full_3gpp_artifact_checklist.md");
layout.RequiredOutputsCSV = fullfile(layout.ReportCSVDir, "full_3gpp_required_outputs.csv");
layout.TruthScanCSV = fullfile(layout.ReportCSVDir, "truth_primary_artifact_scan.csv");
end
