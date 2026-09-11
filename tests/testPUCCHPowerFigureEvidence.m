function ok=testPUCCHPowerFigureEvidence(sourceCSV)
% Measured waveform points only; negative fixtures must not be rendered.
setup6GRSimToolkit('Verbose',false);
repo=fileparts(fileparts(mfilename('fullpath')));
root=fullfile(repo,'tests','vectors','pucch');
if nargin==0
    profile=fullfile(repo,'simulator','configs','validation','pucch_power_waveform.yaml');
    data=sixgr.phy.pucch.PUCCHPowerVectorEvidence.build(root,'power_figure_validation',profile);
else
    data=sixgr.util.csvReadTable(sourceCSV,'TextType','string');
end
contract=readtable(fullfile(root,'desired_pucch_image_contract.csv'),'TextType','string');
row=contract(contract.ImageFile=="pucch_power_control_convergence.png",:);
assert(height(row)==1 && height(data)==48);
folder=tempname; mkdir(folder);
csv=fullfile(folder,'pucch_power_control.csv');
sixgr.util.csvWriteTable(csv,data,'PreserveSchema',true);
audit=sixgr.phy.pucch.PUCCHArtifactExporter.writeSemanticFigure(folder,row);
assert(audit.SeriesCount==3 && audit.FinitePointCount==144 && audit.SourceRowCount==48);
assert(audit.BoundYColumns=="RequestedPowerdBm|AppliedPowerdBm|MeasuredWaveformPowerdBm");
assert(audit.ActualXLabel=="Independent power-vector case");
assert(~contains(audit.ActualTitle,'convergence') && ~contains(audit.ActualTitle,'production'));
assert(audit.SourceCSV_SHA256==sixgr.phy.pucch.PUCCHArtifactExporter.sourceSHA256(folder,"pucch_power_control.csv"));
png=fullfile(folder,char(row.ImageFile));
assert(audit.PNG_SHA256==sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256(png));
assert(audit.Width>=row.MinWidth && audit.Height>=row.MinHeight);
pixels=imread(png); assert(numel(unique(pixels(:)))>20);
sixgr.util.csvWriteTable(fullfile(folder,'pucch_power_plot_audit.csv'),struct2table(audit),'PreserveSchema',true);

% All rejection cases run in a separate directory; retain the valid artifacts.
badFolder=tempname; mkdir(badFolder);
badCSV=fullfile(badFolder,'pucch_power_control.csv');
short=data(1:2,:); % Six real points cannot satisfy a ten-point contract.
checkRejected(short,row,"sixgr:phy:pucch:IncompleteFigureSemantics");
missing=removevars(data,'MeasuredWaveformPowerdBm');
checkRejected(missing,row,"sixgr:phy:pucch:IncompleteFigureSemantics");
nonfinite=data; nonfinite.MeasuredWaveformPowerdBm(:)=NaN;
checkRejected(nonfinite,row,"sixgr:phy:pucch:IncompleteFigureSemantics");
duplicate=data; duplicate.CaseID(2)=duplicate.CaseID(1);
checkRejected(duplicate,row,"sixgr:phy:pucch:IncompleteFigureSemantics");
wrongScope=data; wrongScope.EvidenceScope(:)="main_run";
checkRejected(wrongScope,row,"sixgr:phy:pucch:IncompleteFigureSemantics");
badLabel=row; badLabel.ExpectedXLabel(:)="Transmission occasion";
checkRejected(data,badLabel,"sixgr:phy:pucch:UnverifiedFigureBinding");
unsupported=row; unsupported.ImageFile(:)="pucch_bler_vs_snr.png";
checkRejected(data,unsupported,"sixgr:phy:pucch:UnverifiedFigureBinding");
fprintf('PUCCH_POWER_FIGURE_PASS rows=48 actual_points=144 png=%s\n',png);
ok=true;

    function checkRejected(value,figureContract,expectedID)
        sixgr.util.csvWriteTable(badCSV,value,'PreserveSchema',true);
        caught=false;
        try
            sixgr.phy.pucch.PUCCHArtifactExporter.writeSemanticFigure(badFolder,figureContract);
        catch exception
            assert(string(exception.identifier)==expectedID,exception.message);
            caught=true;
        end
        assert(caught,'Invalid evidence was rendered instead of rejected.');
        assert(~isfile(fullfile(badFolder,char(figureContract.ImageFile))));
    end
end
