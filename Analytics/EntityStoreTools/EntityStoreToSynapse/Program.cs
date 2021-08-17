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
                        var entryList = zip.Entries.ToList();

                        /*
                        * Step 1: Create AxViews on Azure Synapse
                        */
                        var viewMetadataEntry = entryList.FirstOrDefault(e => e.FullName == "views\\dependencies.csv");
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
                            ColorConsole.WriteSuccess($"AxViews were created successfully.");
                        }

                        /*
                        * Step 2: Create fact and associated dimension tables.
                        */
                        // Finds the root measurement metadata
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

                                Console.WriteLine($"\nProcessing measurement '{measurementMetadata.Label}' ({measurementMetadata.Name})");

                                await CreateFactAndDimensionTablesAsync(entryList, measurementMetadata, sqlProvider);
                            }
                        }
                    }
                });
        }

        private static async Task CreateFactAndDimensionTablesAsync(List<ZipArchiveEntry> entryList, dynamic measurementMetadata, SynapseSqlProvider sqlProvider)
        {
            var aggregateMeasurementName = measurementMetadata.Name;
            var measureGroups = measurementMetadata.MeasureGroups;
            HashSet<string> dimensionTables = new HashSet<string>();

            foreach (var measureGroup in measureGroups)
            {
                var measureGroupTableName = aggregateMeasurementName + "_" + measureGroup.Name;

                var createMeasureGroupQuery = $"CREATE OR ALTER VIEW {measureGroupTableName} AS SELECT * FROM (";

                List<string> errorList = await CreateDimensionTablesAsync(entryList, aggregateMeasurementName, measureGroup.Dimensions, dimensionTables, sqlProvider);

                if (errorList.Any())
                {
                    Console.WriteLine($"\n\n{errorList.Count} dimensions could not be created. " +
                         $"Check if the dependent table(s) are synchronized in the lake and the table(s)/views(s) were created in Azure Synapse. " +
                         $"Errors:\n{string.Join('\n', errorList)}");

                    Environment.Exit(1);
                }
                else
                {
                    ColorConsole.WriteSuccess($"Dimensions were created (or exists) successfully for MeasureGroup {measureGroup.Name}.");
                }

                int counter = 1;
                foreach (var dimension in measureGroup.Dimensions)
                {
                    var dimensionTableName = aggregateMeasurementName + "_" + dimension.Name;

                    createMeasureGroupQuery += $"SELECT {AddMeasureGroupAttributes(measureGroup.Attributes, counter)}";
                    createMeasureGroupQuery += $"T{counter}.{dimension.DimensionRelations[0].DimensionAttribute} AS {dimension.DimensionRelations[0].DimensionAttribute}";
                    createMeasureGroupQuery += $" FROM {dimensionTableName} T{counter} UNION ALL ";
                    counter++;
                }

                createMeasureGroupQuery = createMeasureGroupQuery.Remove(createMeasureGroupQuery.Length - 10);
                createMeasureGroupQuery += ") AM";

                Console.WriteLine($"Creating measure group '{measureGroupTableName}' with statement:\t{createMeasureGroupQuery}\n");

                try
                {
                    await sqlProvider.RunSqlStatementAsync(createMeasureGroupQuery);

                    ColorConsole.WriteSuccess($"Created '{measureGroupTableName}'\n");
                }
                catch (SqlException e)
                {
                    var errorMessage = $"Could not create MeasureGroup '{createMeasureGroupQuery}': {e.Message}";

                    ColorConsole.WriteError(errorMessage);
                }
                finally
                {
                    // delay the running of the next statement to prevent DoS
                    await Task.Delay(100);
                }
            }
        }

        private static object AddMeasureGroupAttributes(dynamic attributes, int counter)
        {
            dynamic result = string.Empty;

            foreach (var attr in attributes)
            {
                result += $"'T{counter}.{attr.Name}' {attr.Name},";
            }

            return result;
        }

        private static async Task<IList<string>> CreateDimensionTablesAsync(List<ZipArchiveEntry> entryList, dynamic aggregateMeasurementName, dynamic dimensions, HashSet<string> dimensionTables, SynapseSqlProvider sqlProvider)
        {
            var errorList = new List<string>();

            foreach (var dimension in dimensions)
            {
                var dimensionTableName = aggregateMeasurementName + "_" + dimension.Name;

                if (dimensionTables.Add(dimensionTableName.ToString()))
                {
                    HashSet<string> columns = new HashSet<string>();

                    var createDimensionQuery = $"CREATE OR ALTER VIEW {dimensionTableName} AS SELECT ";

                    var dimensionMetadataEntry = entryList.FirstOrDefault(e => e.FullName == $"dimensions\\{dimension.DimensionName}.json");
                    if (dimensionMetadataEntry == null)
                    {
                        throw new Exception($"Cannot find dimension metadata file 'dimensions/{dimension.DimensionName}.json' in file.");
                    }

                    using (var stream = dimensionMetadataEntry.Open())
                    {
                        var serializer = new JsonSerializer();

                        using (var sr = new StreamReader(stream))
                        using (var jsonTextReader = new JsonTextReader(sr))
                        {
                            dynamic dimensionMetadata = JObject.Load(jsonTextReader);

                            foreach (var attribute in dimensionMetadata.Attributes)
                            {
                                if (attribute.KeyFields.Count == 1)
                                {
                                    createDimensionQuery += $"{attribute.KeyFields[0].DimensionField} AS {attribute.Name},";
                                }
                                else
                                {
                                    foreach (var field in attribute.KeyFields)
                                    {
                                        if (columns.Add(field.DimensionField.ToString()))
                                        {
                                            createDimensionQuery += $"{field.DimensionField},";
                                        }
                                    }

                                    if (columns.Add(attribute.Name.ToString()))
                                    {
                                        createDimensionQuery += $"'{attribute.Name}' {attribute.Name},";
                                    }
                                }
                            }

                            createDimensionQuery = AttachCommonColumns(createDimensionQuery);
                            createDimensionQuery = createDimensionQuery.Remove(createDimensionQuery.Length - 1);

                            createDimensionQuery += $" FROM {dimensionMetadata.Table}";
                        }
                    }

                    Console.WriteLine($"Creating view '{dimension.Name}' with statement:\t{createDimensionQuery}\n");

                    try
                    {
                        await sqlProvider.RunSqlStatementAsync(createDimensionQuery);

                        ColorConsole.WriteSuccess($"Created '{dimensionTableName}'\n");
                    }
                    catch (SqlException e)
                    {
                        var errorMessage = $"Could not create view '{dimensionTableName}': {e.Message}";
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

            return errorList;
        }

        private static string AttachCommonColumns(string createDimensionQuery)
        {
            List<string> commonColumns = new List<string>()
            {
                "RECID",
                "PARTITIONID",
                "DATAAREAID",
            };

            foreach (var column in commonColumns)
            {
                createDimensionQuery += $"'{column}' {column},";
            }

            return createDimensionQuery;
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
                        string processedQuery = axViewMetadata.Definition.Replace("[dbo].", string.Empty);

                        Console.WriteLine($"Creating view '{axViewMetadata.ViewName}' with statement:\t{processedQuery}\n");

                        try
                        {
                            await sqlProvider.RunSqlStatementAsync(processedQuery);

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
