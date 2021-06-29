// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace EntityStoreToSynapse
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
    }
}
