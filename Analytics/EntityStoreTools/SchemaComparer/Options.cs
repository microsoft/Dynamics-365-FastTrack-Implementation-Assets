namespace SchemaComparer
{
    using CommandLine;

    public class Options
    {
        [Option('p', "path", Required = true, HelpText = "Path to the aggregate measurement metadata zip file.")]
        public string MetadataPath { get; set; }

        [Option('c', "connection-string", Required = false, HelpText = "The connection string to the Azure Synapse database.")]
        public string ConnectionString { get; set; }

        [Option('s', "server", Required = false, HelpText = "The server name in the format: '<synapse_sql_server>.sql.azuresynapse.net'.")]
        public string ServerName { get; set; }

        [Option('u', "username", Required = false, HelpText = "The username.")]
        public string Username { get; set; }

        [Option('w', "password", Required = false, HelpText = "The user password.")]
        public string Password { get; set; }

        [Option('d', "database", Required = false, HelpText = "The name of the database.")]
        public string Database { get; set; }

        [Option('x', "ax-connection-string", Required = false, HelpText = "The connection string to the AX database.")]
        public string AXConnectionString { get; set; }

        [Option('r', "ax-server", Required = false, HelpText = "The AX server name.")]
        public string AXServerName { get; set; }

        [Option('v', "ax-username", Required = false, HelpText = "The username.")]
        public string AXUsername { get; set; }

        [Option('y', "ax-password", Required = false, HelpText = "The user password.")]
        public string AXPassword { get; set; }

        [Option('b', "ax-database", Required = false, HelpText = "The name of the database.")]
        public string AXDatabase { get; set; }
    }
}
