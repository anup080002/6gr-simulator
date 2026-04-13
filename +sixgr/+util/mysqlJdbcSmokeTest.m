function info = mysqlJdbcSmokeTest(opts)
%MYSQLJDBCSMOKETEST Run a small validation query through JDBC.
%
%   info = sixgr.util.mysqlJdbcSmokeTest()
%
% Returns a struct with server version, current user, and active database.

arguments
    opts.Host {mustBeTextScalar} = localEnvOrDefault("MYSQL_HOST", "localhost")
    opts.Port (1,1) double = str2double(localEnvOrDefault("MYSQL_PORT", "3306"))
    opts.Database {mustBeTextScalar} = localEnvOrDefault("MYSQL_DATABASE", "")
    opts.Username {mustBeTextScalar} = localEnvOrDefault("MYSQL_USER", "")
    opts.Password {mustBeTextScalar} = localEnvOrDefault("MYSQL_PASSWORD", "")
    opts.DriverVersion {mustBeTextScalar} = "8.4.0"
    opts.UseSSL (1,1) logical = true
    opts.AllowPublicKeyRetrieval (1,1) logical = true
    opts.ConnectTimeoutMs (1,1) double = 10000
end

conn = sixgr.util.connectMySQLJDBC( ...
    Host=opts.Host, ...
    Port=opts.Port, ...
    Database=opts.Database, ...
    Username=opts.Username, ...
    Password=opts.Password, ...
    DriverVersion=opts.DriverVersion, ...
    UseSSL=opts.UseSSL, ...
    AllowPublicKeyRetrieval=opts.AllowPublicKeyRetrieval, ...
    ConnectTimeoutMs=opts.ConnectTimeoutMs);
cleanupConn = onCleanup(@() conn.close());

stmt = conn.createStatement();
cleanupStmt = onCleanup(@() stmt.close());
rs = stmt.executeQuery([ ...
    "SELECT VERSION() AS server_version, " + ...
    "CURRENT_USER() AS current_user_name, " + ...
    "DATABASE() AS current_database_name"]);
cleanupRs = onCleanup(@() rs.close());

if ~rs.next()
    error("sixgr:util:mysqlJdbcSmokeTest:EmptyResult", ...
        "Expected one row from the JDBC smoke test query.");
end

info = struct();
info.ServerVersion = string(rs.getString("server_version"));
info.CurrentUser = string(rs.getString("current_user_name"));
info.CurrentDatabase = string(rs.getString("current_database_name"));

clear cleanupRs cleanupStmt cleanupConn;

end

function value = localEnvOrDefault(name, defaultValue)
value = getenv(name);
if isempty(value)
    value = defaultValue;
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:mysqlJdbcSmokeTest:BadType", ...
        "Input must be a char vector or string scalar.");
end
end
