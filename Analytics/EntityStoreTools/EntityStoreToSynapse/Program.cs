// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace EntityStoreToSynapse
{
    using System;
    using System.Collections.Generic;
    using System.Data.SqlClient;
    using System.Globalization;
    using System.IO;
    using System.IO.Compression;
    using System.Linq;
    using System.Threading.Tasks;
    using CommandLine;
    using Common;
    using Common.Contracts;
    using Common.Providers;
    using CsvHelper;
    using Newtonsoft.Json;
    using Newtonsoft.Json.Linq;

    public class Program
    {
        public static async Task Main(string[] args)
        {
            await Parser.Default.ParseArguments<Options>(args)
                .WithParsedAsync<Options>(async (options) =>
                {
                    SynapseSqlProvider sqlProvider = null;
                    if (string.IsNullOrEmpty(options.ConnectionString))
                    {
                        ContractValidator.MustNotBeEmpty(options.Database, "database");
                        ContractValidator.MustNotBeEmpty(options.ServerName, "server-name");
                        ContractValidator.MustNotBeEmpty(options.Username, "username");
                        ContractValidator.MustNotBeEmpty(options.Password, "password");

                        sqlProvider = new SynapseSqlProvider(options.ServerName, options.Username, options.Password, options.Database);
                    }
                    else
                    {
                        sqlProvider = new SynapseSqlProvider(options.ConnectionString);
                    }

                    if (!File.Exists(options.MetadataPath))
                    {
                        throw new Exception($"File doesn't exist: {options.MetadataPath}");
                    }

                    using (var file = File.OpenRead(options.MetadataPath))
                    using (var zip = new ZipArchive(file, ZipArchiveMode.Read))
                    {
                        // Finds the root measurement metadata
                        var entryList = zip.Entries.ToList();
                        var measurementEntry = entryList.FirstOrDefault(e => e.FullName == "measure.json");

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

                                Console.WriteLine($"Processing measurement '{measurementMetadata.Label}' ({measurementMetadata.Name})");
                            }

                            /*
                            * Step 2: Create AxViews on Azure Synapse
                            */
                            var viewMetadataEntry = entryList.FirstOrDefault(e => e.FullName == "views/dependencies.csv");
                            if (viewMetadataEntry == null)
                            {
                                throw new Exception($"Cannot find view metadata file 'views/dependencies.csv' in file {options.MetadataPath}");
                            }

                            var errorList = await CreateAxViewsAsync(viewMetadataEntry, sqlProvider);

                            if (errorList.Any())
                            {
                                Console.WriteLine($"\n\n{errorList.Count} views could not be created. " +
                                     $"Check if the dependent table(s) are synchronized in the lake and the table(s) were created in Azure Synapse. " +
                                     $"Errors:\n{string.Join('\n', errorList)}");

                                Environment.Exit(1);
                            }
                            else
                            {
                                ColorConsole.WriteSuccess($"All views were created successfully.");
                            }
                        }
                    }
                });
        }

        // Ensure all metadata is present in the package
        private static void ValidateMeasureMetadata(string measureName, string metadataRootPath)
        {
            dynamic measurementMetadata = JObject.Parse(Path.Combine(metadataRootPath, $"{measureName}.json"));

            var elements = new HashSet<string>();
            foreach (var measureGroup in measurementMetadata.MeasureGroups)
            {
                elements.Add((string)measureGroup.Table);

                foreach (var dimension in measureGroup.Dimensions)
                {
                    elements.Add((string)dimension.DimensionName);
                }
            }

            Console.WriteLine(elements);
        }

        private static async Task<IList<string>> CreateAxViewsAsync(ZipArchiveEntry viewMetadataEntry, SynapseSqlProvider sqlProvider)
        {
            var errorList = new List<string>();

            using (var stream = viewMetadataEntry.Open())
            {
                using (var reader = new StreamReader(stream))
                using (var csv = new CsvReader(reader, CultureInfo.InvariantCulture))
                {
                    var records = csv.GetRecords<AxViewMetadata>();

                    var metadataIterator = records.GetEnumerator();
                    while (metadataIterator.MoveNext())
                    {
                        var axViewMetadata = metadataIterator.Current;

                        Console.WriteLine($"Creating view '{axViewMetadata.ViewName}' with statement:\t{axViewMetadata.Definition}\n");

                        try
                        {
                            await sqlProvider.RunSqlStatementAsync(axViewMetadata.Definition);

                            ColorConsole.WriteSuccess($"Created '{axViewMetadata.ViewName}'\n");
                        }
                        catch (SqlException e)
                        {
                            var errorMessage = $"Could not create view '{axViewMetadata.ViewName}': {e.Message}";
                            errorList.Add(errorMessage);

                            ColorConsole.WriteError(errorMessage);
                        }
                        finally
                        {
                            // delay the running of the next statement to prevent DoS
                            await Task.Delay(100);
                        }
                    }
                }
            }

            return errorList;
        }
    }
}
