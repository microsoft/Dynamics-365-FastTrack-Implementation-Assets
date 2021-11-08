namespace SchemaComparer
{
    using System;
    using System.IO;
    using System.IO.Compression;
    using System.Linq;
    using System.Threading.Tasks;
    using CommandLine;
    using Common;
    using Common.Providers;
    using Newtonsoft.Json;
    using Newtonsoft.Json.Linq;

    public class Program
    {
        public static async Task Main(string[] args)
        {
            await Parser.Default.ParseArguments<Options>(args)
#pragma warning disable CS1998 // Async method lacks 'await' operators and will run synchronously
                .WithParsedAsync<Options>(async (options) =>
#pragma warning restore CS1998 // Async method lacks 'await' operators and will run synchronously
                {
                    SynapseSqlProvider synapseSql = null;
                    if (string.IsNullOrEmpty(options.ConnectionString))
                    {
                        ContractValidator.MustNotBeEmpty(options.Database, "database");
                        ContractValidator.MustNotBeEmpty(options.ServerName, "server-name");
                        ContractValidator.MustNotBeEmpty(options.Username, "username");
                        ContractValidator.MustNotBeEmpty(options.Password, "password");

                        synapseSql = new SynapseSqlProvider(options.ServerName, options.Username, options.Password, options.Database);
                    }
                    else
                    {
                        synapseSql = new SynapseSqlProvider(options.ConnectionString);
                    }

                    SynapseSqlProvider sqlProvider = null;
                    if (string.IsNullOrEmpty(options.AXConnectionString))
                    {
                        ContractValidator.MustNotBeEmpty(options.AXDatabase, "ax-database");
                        ContractValidator.MustNotBeEmpty(options.AXServerName, "ax-server-name");
                        ContractValidator.MustNotBeEmpty(options.AXUsername, "ax-username");
                        ContractValidator.MustNotBeEmpty(options.AXPassword, "ax-password");

                        sqlProvider = new SynapseSqlProvider(options.AXServerName, options.AXUsername, options.AXPassword, options.AXDatabase);
                    }
                    else
                    {
                        sqlProvider = new SynapseSqlProvider(options.AXConnectionString);
                    }

                    Console.WriteLine($"Schema Comparer Tool (EntityStoreTools Version {Constants.ToolsVersion})\n");

                    if (!File.Exists(options.MetadataPath))
                    {
                        throw new Exception($"File doesn't exist: {options.MetadataPath}");
                    }

                    using (var file = File.OpenRead(options.MetadataPath))
                    using (var zip = new ZipArchive(file, ZipArchiveMode.Read))
                    {
                        var entryList = zip.Entries.ToList();

                        var measurementEntry = entryList.FirstOrDefault(e => e.FullName == "measurement.json");

                        if (measurementEntry == null)
                        {
                            throw new Exception($"Cannot find measurement metadata file 'measurement.json' in the root folder of the file {options.MetadataPath}");
                        }

                        using (var stream = measurementEntry.Open())
                        {
                            var serializer = new JsonSerializer();

                            using (var sr = new StreamReader(stream))
                            using (var jsonTextReader = new JsonTextReader(sr))
                            {
                                dynamic measurementMetadata = JObject.Load(jsonTextReader);

                                CompareMeasurementTables(measurementMetadata, synapseSql, sqlProvider);
                            }
                        }
                    }
                });
        }

        private static void CompareMeasurementTables(dynamic measurementMetadata, SynapseSqlProvider synapseSql, SynapseSqlProvider sqlProvider)
        {
            foreach (var measureGroups in measurementMetadata.MeasureGroups)
            {
                var measureTableName = $"{measurementMetadata.Name}_{measureGroups.Name}";

                CompareTables(measureTableName, synapseSql, sqlProvider);

                CompareDimensionTables(measurementMetadata.Name.ToString(), measureGroups.Dimensions, synapseSql, sqlProvider);
            }
        }

        private static void CompareTables(string tableName, SynapseSqlProvider synapseSql, SynapseSqlProvider sqlProvider)
        {
            try
            {
                var query = $"SELECT column_name from information_schema.columns WHERE table_name = '{tableName}'";

                var columnsList1 = synapseSql.ReadSqlStatement(query);

                query = $"SELECT column_name from information_schema.columns WHERE table_name = '{tableName}'";

                var columnsList2 = sqlProvider.ReadSqlStatement(query);

                var firstNotSecond = columnsList1.Except(columnsList2).ToList();
                var secondNotFirst = columnsList2.Except(columnsList1).ToList();
                var commonList = columnsList1.Intersect(columnsList2);

                Console.WriteLine($"For table {tableName}:");
                Console.WriteLine($"Common columns: {string.Join(", ", commonList)}");
                Console.WriteLine($"Additional columns in Synapse: {string.Join(", ", firstNotSecond)}");
                Console.WriteLine($"Additional columns in AX: {string.Join(", ", secondNotFirst)}\n");
            }
            catch (Exception exception)
            {
                var errorMessage = $"Could not compare '{tableName}': {exception.Message}\n";

                ColorConsole.WriteError(errorMessage);
            }
        }

        private static void CompareDimensionTables(string measurementName, dynamic dimensionMetadata, SynapseSqlProvider synapseSql, SynapseSqlProvider sqlProvider)
        {
            foreach (var dimension in dimensionMetadata)
            {
                var dimensionTableName = $"{measurementName}_{dimension.Name}";

                CompareTables(dimensionTableName, synapseSql, sqlProvider);
            }
        }
    }
}
