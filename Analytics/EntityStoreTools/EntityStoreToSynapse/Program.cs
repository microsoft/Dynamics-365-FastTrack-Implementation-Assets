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

                    Console.WriteLine($"Entity Store to Synapse Tool (EntityStoreTools Version {Constants.ToolsVersion})\n");

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
            HashSet<string> dimensionViews = new HashSet<string>();
            List<string> errorList = new List<string>();

            foreach (var measureGroup in measureGroups)
            {
                HashSet<string> factTableColumns = new HashSet<string>();
                var measureGroupTableName = aggregateMeasurementName + "_" + measureGroup.Name;

                var createMeasureGroupQuery = $"CREATE OR ALTER VIEW {measureGroupTableName} AS SELECT ";

                errorList = await CreateDimensionViewsAsync(entryList, aggregateMeasurementName, measureGroup.Dimensions, dimensionViews, sqlProvider);

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

                foreach (var attribute in measureGroup.Attributes)
                {
                    var reservedColumn = CheckReservedWord(attribute.KeyFields[0].DimensionField, attribute.Name, createMeasureGroupQuery);

                    if (factTableColumns.Add(attribute.Name.ToString().ToUpper()))
                    {
                        if (!reservedColumn.Item1)
                        {
                            createMeasureGroupQuery += $"{attribute.KeyFields[0].DimensionField} AS {attribute.Name.ToString().ToUpper()},";
                        }
                        else
                        {
                            createMeasureGroupQuery = reservedColumn.Item2;
                        }
                    }
                }

                foreach (var measure in measureGroup.Measures)
                {
                    var reservedColumn = CheckReservedWord(measure.Field, measure.Name, createMeasureGroupQuery);

                    if (factTableColumns.Add(measure.Name.ToString().ToUpper()))
                    {
                        if (!reservedColumn.Item1)
                        {
                            createMeasureGroupQuery += $"{measure.Field} AS {measure.Name.ToString().ToUpper()},";
                        }
                        else
                        {
                            createMeasureGroupQuery = reservedColumn.Item2;
                        }
                    }
                }

                foreach (var dimensions in measureGroup.Dimensions)
                {
                    foreach (var relation in dimensions.DimensionRelations)
                    {
                        string foreignKeyName = $"{aggregateMeasurementName}_{dimensions.Name}_FK";
                        string foreignKeyConcat = "CONCAT(";
                        bool fkFlag = false;

                        if (relation.Constraints.Count > 1)
                        {
                            fkFlag = true;
                        }

                        foreach (var contraint in relation.Constraints)
                        {
                            if (factTableColumns.Add(contraint.RelatedField.ToString().ToUpper()))
                            {
                                createMeasureGroupQuery += $"{contraint.RelatedField} AS {contraint.Name.ToString().ToUpper()},";
                            }

                            if (fkFlag)
                            {
                                foreignKeyConcat += $"{contraint.RelatedField},'_',";
                            }
                        }

                        if (fkFlag)
                        {
                            foreignKeyConcat = foreignKeyConcat.Remove(foreignKeyConcat.Length - 5);
                            foreignKeyConcat += $") AS {foreignKeyName},";
                            createMeasureGroupQuery += foreignKeyConcat;
                        }
                    }
                }

                createMeasureGroupQuery = createMeasureGroupQuery.Remove(createMeasureGroupQuery.Length - 1);
                createMeasureGroupQuery += $" FROM {measureGroup.Table}";

                Console.WriteLine($"Creating measure group '{measureGroupTableName}' with statement:\t{createMeasureGroupQuery}\n");

                try
                {
                    await sqlProvider.RunSqlStatementAsync(createMeasureGroupQuery);

                    ColorConsole.WriteSuccess($"Created '{measureGroupTableName}'\n");
                }
                catch (SqlException e)
                {
                    var errorMessage = $"Could not create MeasureGroup '{createMeasureGroupQuery}': {e.Message}\n";
                    errorList.Add(errorMessage);

                    ColorConsole.WriteError(errorMessage);
                }
                finally
                {
                    // delay the running of the next statement to prevent DoS
                    await Task.Delay(100);
                }
            }

            if (errorList.Any())
            {
                Console.WriteLine($"\n\n{errorList.Count} measure groups could not be created. " +
                     $"Check if the dependent table(s) are synchronized in the lake and the table(s)/views(s) were created in Azure Synapse. " +
                     $"Errors:\n{string.Join('\n', errorList)}");

                Environment.Exit(1);
            }
            else
            {
                ColorConsole.WriteSuccess($"All measure groups were created successfully for aggregate measurement: {aggregateMeasurementName}.");
            }
        }

        private static object AddMeasureGroupAttributes(dynamic attributes, int counter)
        {
            dynamic result = string.Empty;

            foreach (var attr in attributes)
            {
                result += $"'T{counter}.{attr.Name}' {attr.Name.ToString().ToUpper()},";
            }

            return result;
        }

        private static async Task<IList<string>> CreateDimensionViewsAsync(List<ZipArchiveEntry> entryList, dynamic aggregateMeasurementName, dynamic dimensions, HashSet<string> dimensionTables, SynapseSqlProvider sqlProvider)
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
                            var commonColumns = GetCommonColumns();

                            foreach (var attribute in dimensionMetadata.Attributes)
                            {
                                // Add ROW_UNIQUEKEY column.
                                if (attribute.Usage == 1 && attribute.KeyFields.Count > 1)
                                {
                                    string rowUniqueKeyColumnName = "ROW_UNIQUEKEY";
                                    createDimensionQuery += $"CONCAT(";
                                    foreach (var field in attribute.KeyFields)
                                    {
                                        createDimensionQuery += $"{field.DimensionField},'_',";
                                    }

                                    createDimensionQuery = createDimensionQuery.Remove(createDimensionQuery.Length - 5);
                                    createDimensionQuery += $") AS {rowUniqueKeyColumnName},";
                                    columns.Add(rowUniqueKeyColumnName);
                                }

                                if (attribute.KeyFields.Count == 1)
                                {
                                    if (commonColumns.Contains(attribute.KeyFields[0].DimensionField.ToString().ToUpper()))
                                    {
                                        commonColumns.Remove(attribute.KeyFields[0].DimensionField.ToString().ToUpper());
                                    }

                                    if (columns.Add(attribute.Name.ToString().ToUpper()))
                                    {
                                        var reservedColumn = CheckReservedWord(attribute.KeyFields[0].DimensionField, attribute.Name, createDimensionQuery);
                                        if (!reservedColumn.Item1)
                                        {
                                            createDimensionQuery += $"{attribute.KeyFields[0].DimensionField} AS {attribute.Name.ToString().ToUpper()},";
                                        }
                                        else
                                        {
                                            createDimensionQuery = reservedColumn.Item2;
                                        }
                                    }
                                }
                                else
                                {
                                    foreach (var field in attribute.KeyFields)
                                    {
                                        if (field.DimensionField.ToString().Equals(attribute.NameField.ToString()))
                                        {
                                            if (columns.Add(attribute.Name.ToString().ToUpper()))
                                            {
                                                var reservedColumn = CheckReservedWord(field.DimensionField, attribute.Name, createDimensionQuery);
                                                if (!reservedColumn.Item1)
                                                {
                                                    createDimensionQuery += $"{field.DimensionField} AS {attribute.Name.ToString().ToUpper()},";
                                                }
                                                else
                                                {
                                                    createDimensionQuery = reservedColumn.Item2;
                                                }
                                            }
                                        }
                                        else if (columns.Add(field.DimensionField.ToString().ToUpper()))
                                        {
                                            var reservedColumn = CheckReservedWord(field.DimensionField, field.DimensionField, createDimensionQuery);
                                            if (!reservedColumn.Item1)
                                            {
                                                createDimensionQuery += $"{field.DimensionField.ToString().ToUpper()},";
                                            }
                                            else
                                            {
                                                createDimensionQuery = reservedColumn.Item2;
                                            }
                                        }
                                    }
                                }
                            }

                            createDimensionQuery = AttachCommonColumns(createDimensionQuery, commonColumns);
                            createDimensionQuery = createDimensionQuery.Remove(createDimensionQuery.Length - 1);

                            createDimensionQuery += $" FROM {dimensionMetadata.Table}";
                        }
                    }

                    while (true)
                    {
                        Console.WriteLine($"Creating dimension '{dimension.Name}' with statement:\t{createDimensionQuery}\n");

                        try
                        {
                            await sqlProvider.RunSqlStatementAsync(createDimensionQuery);

                            ColorConsole.WriteSuccess($"Created '{dimensionTableName}'\n");
                        }
                        catch (SqlException e)
                        {
                            if (e.Message.Contains($"Invalid column name 'PARTITION'"))
                            {
                                createDimensionQuery = RemovePartitionColumn(createDimensionQuery);
                                continue;
                            }

                            var errorMessage = $"Could not create dimension '{dimensionTableName}': {e.Message}\n";
                            errorList.Add(errorMessage);

                            ColorConsole.WriteError(errorMessage);
                        }
                        finally
                        {
                            // delay the running of the next statement to prevent DoS
                            await Task.Delay(100);
                        }

                        break;
                    }
                }
            }

            return errorList;
        }

        private static string RemovePartitionColumn(string createDimensionQuery)
        {
            return createDimensionQuery.Replace(",PARTITION", string.Empty);
        }

        private static (bool, string) CheckReservedWord(dynamic dimensionField, dynamic dimensionName, string createDimensionQuery)
        {
            HashSet<string> reservedWords = new HashSet<string>()
            {
                "KEY",
                "COMMENT",
            };

            if (reservedWords.Contains(dimensionField.ToString().ToUpper()))
            {
                if (reservedWords.Contains(dimensionName.ToString().ToUpper()))
                {
                    createDimensionQuery += $"{dimensionField}_ AS {dimensionName.ToString().ToUpper()}_,";
                }
                else
                {
                    createDimensionQuery += $"{dimensionField}_ AS {dimensionName.ToString().ToUpper()},";
                }

                return (true, createDimensionQuery);
            }
            else if (reservedWords.Contains(dimensionName.ToString().ToUpper()))
            {
                createDimensionQuery += $"{dimensionField} AS {dimensionName.ToString().ToUpper()}_,";

                return (true, createDimensionQuery);
            }

            return (false, createDimensionQuery);
        }

        private static HashSet<string> GetCommonColumns()
        {
            HashSet<string> commonColumns = new HashSet<string>()
            {
                "RECID",
                "PARTITION",
            };

            return commonColumns;
        }

        private static string AttachCommonColumns(string createDimensionQuery, HashSet<string> commonColumns = null)
        {
            if (commonColumns == null)
            {
                commonColumns = GetCommonColumns();
            }

            foreach (var column in commonColumns)
            {
                createDimensionQuery += $"{column.ToString().ToUpper()},";
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
                            var errorMessage = $"Could not create view '{axViewMetadata.ViewName}': {e.Message}\n";
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
