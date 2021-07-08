// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace EntityStoreMetadataExporter
{
    using System;
    using System.Data.SqlClient;
    using CommandLine;
    using global::EntityStoreMetadataExporter.Utils;

    /// <summary>
    /// The application entrypoint.
    /// </summary>
    public class Program
    {
        public static void Main(string[] args)
        {
            Parser.Default.ParseArguments<Options>(args)
                .WithParsed<Options>((options) =>
                {
                    var connectionString = options.ConnectionString;
                    if (string.IsNullOrEmpty(options.ConnectionString))
                    {
                        ContractValidator.MustNotBeEmpty(options.Database, "database");
                        ContractValidator.MustNotBeEmpty(options.ServerName, "server-name");
                        ContractValidator.MustNotBeEmpty(options.Username, "username");
                        ContractValidator.MustNotBeEmpty(options.Password, "password");

                        var connectionStringBuilder = new SqlConnectionStringBuilder();
                        connectionStringBuilder.DataSource = options.ServerName;
                        connectionStringBuilder.UserID = options.Username;
                        connectionStringBuilder.Password = options.Password;
                        connectionStringBuilder.InitialCatalog = options.Database;

                        connectionString = connectionStringBuilder.ConnectionString;
                    }

                    EntityStoreMetadataExporter.ExportMetadata(options.MeasureName, options.PackagePath, connectionString, options.OutputPath);
                });
            }
    }
}
