namespace EntityStoreMetadataExporter
{
    using CommandLine;

    public class Options
    {
        [Option('p', "path", Required = false, HelpText = "Path to the AOS package path (e.g. C:\\AosService\\PackagesLocalDirectory).", Default = @"K:\AosService\PackagesLocalDirectory")]
        public string PackagePath { get; set; }

        [Option('m', "measure", Required = true, HelpText = "The aggregate measurement name.")]
        public string MeasureName { get; set; }

        [Option('o', "output", Required = true, HelpText = "Directory path where the metadata should be published.")]
        public string OutputPath { get; set; }

        [Option('c', "connection-string", Required = false, HelpText = "The connection string to the AX database.")]
        public string ConnectionString { get; set; }

        [Option('s', "server", Required = false, HelpText = "The server name in the format: '<synapse_sql_server>.sql.azuresynapse.net'.")]
        public string ServerName { get; set; }

        [Option('u', "username", Required = false, HelpText = "The username.")]
        public string Username { get; set; }

        [Option('w', "password", Required = false, HelpText = "The user password.")]
        public string Password { get; set; }

        [Option('d', "database", Required = false, HelpText = "The name of the database.")]
        public string Database { get; set; }
    }
}
