function out=compareViennaMIESM(configPath,outputRoot,runTag)
%COMPAREVIENNAMIESM Execute the separately licensed local numerical oracle.
% No Vienna source or MI table is copied into SixGR. Only scalar comparison
% results and source digests are retained. This does not qualify NR BLER.
arguments
    configPath (1,1) string
    outputRoot (1,1) string
    runTag (1,1) string
end
c=sixgr.lls6g.config.readConfigFile(configPath);
assert(string(c.source_classification)=="external_lte_numerical_reference_not_nr_calibration", ...
    'sixgr:reference:Classification','External LTE comparison is not NR calibration.');
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9_-]+$','once')), ...
    'sixgr:reference:RunTag','Use a single safe run-tag component.');
root=string(c.reference_root); miPath=fullfile(root,string(c.mi_relative_path));
source=fullfile(root,'+tools','MiesmAverager.m');
assert(isfile(source) && isfile(miPath),'sixgr:reference:ViennaUnavailable', ...
    'Provide the licensed Vienna installation and its MI dataset; no substitute is used.');
folder=fullfile(outputRoot,runTag);
assert(~isfolder(folder),'sixgr:reference:OutputExists','Use a new tag to preserve prior comparison evidence.');
mkdir(folder);
oldPath=path; restore=onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(char(root),'-begin');
assert(strcmpi(strrep(which('tools.MiesmAverager'),'\','/'),strrep(source,'\','/')), ...
    'sixgr:reference:SourceIdentity','Another package shadows the requested Vienna implementation.');
parametersLTE=parameters.transmissionParameters.LteCqiParametersTS36213NonBLCEUE1( ...
    struct('mapperBlerThreshold',.1));
reference=tools.MiesmAverager(parametersLTE,char(miPath),false);
if iscell(c.sample_fractions)
    fractions=cell2mat(c.sample_fractions(:));
else
    fractions=double(c.sample_fractions);
end
interior=double(c.mi_interior_fraction);
validateattributes(fractions,{'numeric'},{'real','2d','nonempty','finite'});
validateattributes(c.cqi_indices,{'numeric'},{'real','vector','nonempty','integer','>=',1,'<=',15});
assert(numel(interior)==2 && interior(1)>0 && interior(2)<1 && interior(1)<interior(2) && ...
    all(isfinite(fractions),'all') && all(fractions>=0 & fractions<=1,'all'), ...
    'sixgr:reference:Samples','Specify interior MI bounds and sample fractions in [0,1].');
validateattributes(c.maximum_absolute_error_db,{'numeric'},{'scalar','finite','positive'});
rows=table();
for cqi=double(c.cqi_indices(:).')
    validateattributes(cqi,{'numeric'},{'scalar','integer','>=',1,'<=',15});
    qm=double(parametersLTE.getModulationOrder(cqi));
    modulation=double(parametersLTE.getModulationType(cqi));
    beta=double(parametersLTE.getBetaMIESMCalibration(cqi));
    values=reference.mutualInformationMatrix(modulation,:);
    keep=values>interior(1)*qm & values<interior(2)*qm;
    lookup=struct('SINRGrid_dB',reference.sinrList(keep), ...
        'MutualInformation_bitsPerSymbol',values(keep),'ModulationOrder',2^qm,'BetaLinear',beta);
    sixgr.phy.rsla.MIESMMapper.validateLookup(lookup);
    x=lookup.SINRGrid_dB;
    for episode=1:size(fractions,1)
        input=x(1)+fractions(episode,:)*(x(end)-x(1))+10*log10(beta);
        [~,viennaDb]=reference.average(input,cqi);
        sixgrResult=sixgr.phy.rsla.MIESMMapper.map(input,lookup,"external_lte_comparison_only");
        assert(isscalar(viennaDb) && isfinite(viennaDb), ...
            'sixgr:reference:NonfiniteReference','The installed reference did not return a finite scalar.');
        errorDb=abs(sixgrResult.EffectiveSINRDb-viennaDb);
        r=table(cqi,qm,episode,string(jsonencode(input)),viennaDb,sixgrResult.EffectiveSINRDb,errorDb, ...
            errorDb<=c.maximum_absolute_error_db,false,string(c.source_classification), ...
            'VariableNames',{'CQI','BitsPerSymbol','Episode','InputSINR_dB_JSON','ViennaEffectiveSINR_dB', ...
            'SixGREffectiveSINR_dB','AbsoluteError_dB','Passed','PrimaryResultEligible','SourceClassification'});
        rows=[rows;r]; %#ok<AGROW>
    end
end
writetable(rows,fullfile(folder,'miesm_reference_comparison.csv'));
out=struct('Ok',all(rows.Passed),'PrimaryResultEligible',false, ...
    'SourceClassification',string(c.source_classification),'Comparisons',height(rows), ...
    'MaximumAbsoluteError_dB',max(rows.AbsoluteError_dB), ...
    'Tolerance_dB',c.maximum_absolute_error_db,'RunFolder',folder, ...
    'ViennaSourceSHA256',sixgr.csi.studyFileSHA256(source), ...
    'ViennaMISHA256',sixgr.csi.studyFileSHA256(miPath), ...
    'SixGRSourceSHA256',sixgr.csi.studyFileSHA256(which('sixgr.phy.rsla.MIESMMapper')), ...
    'ConfigSHA256',sixgr.csi.studyFileSHA256(configPath));
sixgr.util.jsonWrite(fullfile(folder,'comparison_receipt.json'),out);
assert(out.Ok,'sixgr:reference:MIESMMismatch','Retained external comparison exceeds its frozen interpolation tolerance.');
end
