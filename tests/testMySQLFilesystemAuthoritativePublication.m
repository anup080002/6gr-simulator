function ok = testMySQLFilesystemAuthoritativePublication()
%TESTMYSQLFILESYSTEMAUTHORITATIVEPUBLICATION Guard durable dual-sink ordering.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
sourcePath = which("sixgr.lls6g.runners.runSingle");
assert(strlength(string(sourcePath)) > 0, "Unable to resolve runSingle source.");
source = string(fileread(sourcePath));

assert(~contains(source, "sixgr_mysql_web_runs"), ...
    "mysql_web runs must not stage their only complete evidence under the OS temp directory.");
assert(contains(source, "logicalRunFolder = runFolder"), ...
    "mysql_web execution must write directly into the durable public result folder.");
assert(contains(source, "if localSameFolder(stagingRunFolder, logicalRunFolder)"), ...
    "Cleanup must preserve the public folder when the database mirror shares its filesystem source.");

filesystemToken = "filesystemResult = localExecuteMaterializerCommand(filesystemCmd)";
databaseToken = "databaseResult = localExecuteMaterializerCommand(databaseCmd)";
filesystemPosition = strfind(source, filesystemToken);
databasePosition = strfind(source, databaseToken);
assert(isscalar(filesystemPosition) && isscalar(databasePosition) && ...
    filesystemPosition < databasePosition, ...
    "Browser publication must materialize/verify filesystem evidence before the MySQL mirror.");
assert(contains(source, "out.FilesystemPersisted = true") && ...
    contains(source, "out.DatabasePersisted = true"), ...
    "Dual-sink receipts must separately disclose filesystem and database persistence.");

ok = true;
end
