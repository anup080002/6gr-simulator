function ok = testPDSCHPhaseEvidenceMCSFailClosed()
%TESTPDSCHPHASEEVIDENCEMCSFAILCLOSED Resolver errors cannot become QPSK.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
sourceRoot = fullfile(fileparts(mfilename("fullpath")),"vectors","pdsch");
scratchRoot = tempname;
mkdir(scratchRoot);
cleanup = onCleanup(@() localRemoveScratch(scratchRoot)); %#ok<NASGU>

required = [ ...
    "desired_pdsch_csv_contract.csv", ...
    "pdsch_scheduling_assignment_test_vectors.csv", ...
    "expected_pdsch_assignment_resolution.csv"];
for index = 1:numel(required)
    copyfile(fullfile(sourceRoot,required(index)), ...
        fullfile(scratchRoot,required(index)));
end

vectorPath = fullfile( ...
    scratchRoot,"pdsch_scheduling_assignment_test_vectors.csv");
vectors = readtable(vectorPath, ...
    "TextType","string","VariableNamingRule","preserve");
vectors.MCSTable(1) = "not_a_normative_mcs_table";
writetable(vectors,vectorPath);

try
    sixgr.pdsch.PDSCHPhaseEvidenceBuilder.build(scratchRoot);
catch ME
    assert(string(ME.identifier) == "sixgr:pdsch:MissingMCSTable", ...
        "Expected the resolver error, got %s.",ME.identifier);
    assert(~contains(string(ME.message),"QPSK"), ...
        "Resolver failure was converted to a QPSK placeholder.");
    fprintf("PDSCH phase evidence MCS fail-closed: 1/1 passed.\n");
    ok = true;
    return;
end
error("testPDSCHPhaseEvidenceMCSFailClosed:MissingError", ...
    "An invalid MCS table was accepted by the phase evidence builder.");
end

function localRemoveScratch(path)
if isfolder(path)
    rmdir(path,"s");
end
end
