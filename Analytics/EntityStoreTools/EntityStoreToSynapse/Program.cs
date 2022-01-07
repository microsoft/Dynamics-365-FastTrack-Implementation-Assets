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

                        try
                        {
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
                        catch (Exception ex)
                        {
                            ColorConsole.WriteError(ex.ToString());
                        }
                    }
                });
        }

        private static (string, HashSet<string>) GenerateEnumTranslationsQuery(List<ZipArchiveEntry> entryList, string measureObject, Dictionary<string, string> columnNames)
        {
            HashSet<string> foundEnums = new HashSet<string>();
            string enumQuery = string.Empty;

            foreach (KeyValuePair<string, string> kvp in columnNames)
            {
                var enumEntry = entryList.FirstOrDefault(e => e.FullName == $"enums\\{measureObject.ToUpper()}_{kvp.Value.ToUpper()}.json");

                if (enumEntry == null)
                {
                    continue;
                }

                using (var stream = enumEntry.Open())
                {
                    using (var reader = new StreamReader(stream))
                    using (var jsonTextReader = new JsonTextReader(reader))
                    {
                        dynamic enumMetadata = JObject.Load(jsonTextReader);
                        foundEnums.Add(kvp.Key.ToUpper());
                        string tempQuery = " CASE ";

                        foreach (var enumKv in enumMetadata.Translations)
                        {
                            tempQuery += $"WHEN {enumMetadata.Name} = '{enumKv.Value}' THEN '{enumKv.Key}' ";
                        }

                        tempQuery += $"END AS {kvp.Key},";
                        enumQuery += tempQuery;
                    }
                }
            }

            return (enumQuery, foundEnums);
        }

        private static async Task CreateFactAndDimensionTablesAsync(List<ZipArchiveEntry> entryList, dynamic measurementMetadata, SynapseSqlProvider sqlProvider)
        {
            var aggregateMeasurementName = measurementMetadata.Name;
            var measureGroups = measurementMetadata.MeasureGroups;
            HashSet<string> dimensionViews = new HashSet<string>();
            List<string> errorList = new List<string>();

            foreach (var measureGroup in measureGroups)
            {
                Dictionary<string, string> factTableColumns = new Dictionary<string, string>();
                var commonColumns = GetCommonColumns();
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
                    if (commonColumns.Contains(attribute.Name.ToString().ToUpper()))
                    {
                        commonColumns.Remove(attribute.Name.ToString().ToUpper());
                    }

                    foreach (var keyFields in attribute.KeyFields)
                    {
                        string dimField = keyFields.DimensionField == null ? string.Empty : keyFields.DimensionField.ToString();
                        string attrName = attribute.Name == null ? string.Empty : attribute.Name.ToString();
                        string nameField = attribute.NameField == null ? string.Empty : attribute.NameField.ToString();
                        if (!dimField.Equals(nameField) && attribute.KeyFields.Count > 1)
                        {
                            attrName = dimField;
                        }

                        var reservedColumn = CheckReservedWord(dimField, attrName, createMeasureGroupQuery);

                        if (factTableColumns.TryAdd(attrName.ToUpper(), dimField.ToUpper()))
                        {
                            if (!reservedColumn.Item1)
                            {
                                createMeasureGroupQuery += $"{dimField} AS {attrName.ToUpper()},";
                            }
                            else
                            {
                                createMeasureGroupQuery = reservedColumn.Item2;
                            }
                        }
                    }
                }

                if (measureGroup.Attributes.Count == 0)
                {
                    var viewMetadataEntry = entryList.FirstOrDefault(e => e.FullName == $"views\\{measureGroup.Table.ToString().ToUpper()}.json");
                    if (viewMetadataEntry == null)
                    {
                        ColorConsole.WriteWarning($"Attr Creation: No view found in path views/{measureGroup.Table.ToString().ToUpper()}.json");
                    }

                    using (var stream = viewMetadataEntry.Open())
                    {
                        using (var sr = new StreamReader(stream))
                        using (var jsonTextReader = new JsonTextReader(sr))
                        {
                            dynamic viewMetadata = JObject.Load(jsonTextReader);

                            foreach (var attr in viewMetadata.Fields)
                            {
                                string attrName = attr.Name.ToString();
                                if (commonColumns.Contains(attrName.ToUpper()))
                                {
                                    commonColumns.Remove(attrName.ToUpper());
                                }

                                var reservedColumn = CheckReservedWord(attrName, attrName, createMeasureGroupQuery);

                                if (factTableColumns.TryAdd(attrName.ToUpper(), attrName.ToUpper()))
                                {
                                    if (!reservedColumn.Item1)
                                    {
                                        createMeasureGroupQuery += $"{attrName} AS {attrName.ToUpper()},";
                                    }
                                    else
                                    {
                                        createMeasureGroupQuery = reservedColumn.Item2;
                                    }
                                }
                            }
                        }
                    }
                }

                foreach (var measure in measureGroup.Measures)
                {
                    if (measure.Field == null)
                    {
                        if (measure.Name == null)
                        {
                            continue;
                        }

                        if (commonColumns.Contains(measure.Name.ToString().ToUpper()))
                        {
                            commonColumns.Remove(measure.Name.ToString().ToUpper());
                        }

                        var reservedColumnCheck = CheckReservedWord(measure.Name, measure.Name, createMeasureGroupQuery);
                        if (factTableColumns.TryAdd(measure.Name.ToString().ToUpper(), measure.Name.ToString().ToUpper()))
                        {
                            if (reservedColumnCheck.Item1)
                            {
                                createMeasureGroupQuery += $"1 AS {measure.Name.ToString().ToUpper()}_,";
                            }
                            else
                            {
                                createMeasureGroupQuery += $"1 AS {measure.Name.ToString().ToUpper()},";
                            }
                        }

                        continue;
                    }
                    else if (measure.Name == null)
                    {
                        if (commonColumns.Contains(measure.Field.ToString().ToUpper()))
                        {
                            commonColumns.Remove(measure.Field.ToString().ToUpper());
                        }

                        var reservedColumnCheck = CheckReservedWord(measure.Field, measure.Field, createMeasureGroupQuery);
                        if (factTableColumns.TryAdd(measure.Field.ToString().ToUpper(), measure.Field.ToString().ToUpper()))
                        {
                            if (reservedColumnCheck.Item1)
                            {
                                createMeasureGroupQuery += $"1 AS {measure.Field.ToString().ToUpper()}_,";
                            }
                            else
                            {
                                createMeasureGroupQuery += $"1 AS {measure.Field.ToString().ToUpper()},";
                            }
                        }

                        continue;
                    }

                    if (commonColumns.Contains(measure.Name.ToString().ToUpper()))
                    {
                        commonColumns.Remove(measure.Name.ToString().ToUpper());
                    }

                    var reservedColumn = CheckReservedWord(measure.Field, measure.Name, createMeasureGroupQuery);

                    if (factTableColumns.TryAdd(measure.Name.ToString().ToUpper(), measure.Field.ToString().ToUpper()))
                    {
                        if (!reservedColumn.Item1)
                        {
                            if (string.IsNullOrEmpty(measure.Field.ToString().Trim()))
                            {
                                createMeasureGroupQuery += $"{measure.Name.ToString().ToUpper()},";
                            }
                            else
                            {
                                createMeasureGroupQuery += $"{measure.Field} AS {measure.Name.ToString().ToUpper()},";
                            }
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
                            if (commonColumns.Contains(contraint.RelatedField.ToString().ToUpper()))
                            {
                                commonColumns.Remove(contraint.RelatedField.ToString().ToUpper());
                            }

                            if (factTableColumns.TryAdd(contraint.Name.ToString().ToUpper(), contraint.RelatedField.ToString().ToUpper()))
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
                        else
                        {
                            var dimensionMetadataEntry = entryList.FirstOrDefault(e => e.FullName == $"dimensions\\{dimensions.DimensionName}.json");
                            if (dimensionMetadataEntry == null)
                            {
                                throw new Exception($"FK Creation: Cannot find dimension metadata file 'dimensions/{dimensions.DimensionName}.json' in file.");
                            }

                            using (var stream = dimensionMetadataEntry.Open())
                            {
                                using (var sr = new StreamReader(stream))
                                using (var jsonTextReader = new JsonTextReader(sr))
                                {
                                    dynamic dimensionMetadata = JObject.Load(jsonTextReader);

                                    string dataSource = dimensionMetadata.Table.ToString();
                                    string fieldName = relation.Constraints[0].RelatedField.ToString();
                                    string fkQuery = SearchViewForFK(entryList, dataSource, fieldName, foreignKeyName);

                                    createMeasureGroupQuery += fkQuery;
                                }
                            }
                        }
                    }
                }

                createMeasureGroupQuery = AttachCommonColumns(createMeasureGroupQuery, commonColumns);

                (string, HashSet<string>) enumTranslations = GenerateEnumTranslationsQuery(entryList, measureGroup.Table.ToString(), factTableColumns);
                if (enumTranslations.Item2.Count() > 0)
                {
                    foreach (string column in enumTranslations.Item2)
                    {
                        createMeasureGroupQuery = RenameEnumColumns(createMeasureGroupQuery, column);
                    }

                    createMeasureGroupQuery += enumTranslations.Item1;
                }

                createMeasureGroupQuery = createMeasureGroupQuery.Remove(createMeasureGroupQuery.Length - 1);
                createMeasureGroupQuery += $" FROM {measureGroup.Table}";

                while (true)
                {
                    Console.WriteLine($"Creating measure group '{measureGroupTableName}' with statement:\t{createMeasureGroupQuery}\n");

                    try
                    {
                        await sqlProvider.RunSqlStatementAsync(createMeasureGroupQuery);

                        ColorConsole.WriteSuccess($"Created '{measureGroupTableName}'\n");
                    }
                    catch (Exception e)
                    {
                        if (e.Message.Contains($"Invalid column name 'PARTITION'"))
                        {
                            createMeasureGroupQuery = DefaultPartitionColumn(createMeasureGroupQuery);
                            continue;
                        }

                        if (e.Message.Contains($"Invalid column name 'DATAAREAID'"))
                        {
                            createMeasureGroupQuery = DefaultDataAreaIdColumn(createMeasureGroupQuery);
                            continue;
                        }

                        var errorMessage = $"Could not create MeasureGroup '{createMeasureGroupQuery}': {e.Message}\n";
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

        private static string SearchViewForFK(List<ZipArchiveEntry> entryList, string dataSource, string fieldName, string foreignKeyName)
        {
            var viewMetadataEntry = entryList.FirstOrDefault(e => e.FullName == $"views\\{dataSource.ToUpper()}.json");
            if (viewMetadataEntry == null)
            {
                ColorConsole.WriteWarning($"FK Creation: Cannot find view metadata file 'views/{dataSource.ToUpper()}.json' in file.");

                return SearchTableForFK(entryList, dataSource, fieldName, foreignKeyName);
            }

            using (var streamView = viewMetadataEntry.Open())
            {
                using (var srv = new StreamReader(streamView))
                using (var jsonTextReaderView = new JsonTextReader(srv))
                {
                    dynamic viewMetadata = JObject.Load(jsonTextReaderView);

                    if (viewMetadata.ViewMetadata.DataSources.Count > 0)
                    {
                        string dataSourceName = viewMetadata.ViewMetadata.DataSources[0].Table.ToString();
                        return SearchViewForFK(entryList, dataSourceName, fieldName, foreignKeyName);
                    }
                    else if (viewMetadata.Query != null)
                    {
                        var queryMetadataEntry = entryList.FirstOrDefault(e => e.FullName == $"queries\\{viewMetadata.Query}.json");
                        if (queryMetadataEntry == null)
                        {
                            ColorConsole.WriteWarning($"FK Creation: Cannot find query metadata file 'queries/{viewMetadata.Query}.json' in file.\n");
                            return string.Empty;
                        }

                        using (var stringQuery = queryMetadataEntry.Open())
                        {
                            using (var srq = new StreamReader(stringQuery))
                            using (var jsonTextReaderTable = new JsonTextReader(srq))
                            {
                                dynamic queryMetadata = JObject.Load(jsonTextReaderTable);

                                string dataSourceName = queryMetadata.DataSources[0].Table.ToString();
                                return SearchViewForFK(entryList, dataSourceName, fieldName, foreignKeyName);
                            }
                        }
                    }

                    return string.Empty;
                }
            }
        }

        private static string SearchTableForFK(List<ZipArchiveEntry> entryList, string tableName, string fieldName, string fkName)
        {
            var tableMetadataEntry = entryList.FirstOrDefault(e => e.FullName == $"tables\\{tableName}.json");
            if (tableMetadataEntry == null)
            {
                ColorConsole.WriteWarning($"Cannot find table metadata file 'tables/{tableName}.json' in file.");
                return string.Empty;
            }

            using (var streamTable = tableMetadataEntry.Open())
            {
                using (var srt = new StreamReader(streamTable))
                using (var jsonTextReaderTable = new JsonTextReader(srt))
                {
                    dynamic tableMetadata = JObject.Load(jsonTextReaderTable);

                    if (tableMetadata.SaveDataPerCompany == null)
                    {
                        return $"{fieldName} AS {fkName},";
                    }

                    return string.Empty;
                }
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
                    Dictionary<string, string> columns = new Dictionary<string, string>();

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
                                    columns.TryAdd(rowUniqueKeyColumnName, rowUniqueKeyColumnName);
                                }

                                if (attribute.KeyFields.Count == 1)
                                {
                                    if (commonColumns.Contains(attribute.KeyFields[0].DimensionField.ToString().ToUpper()))
                                    {
                                        commonColumns.Remove(attribute.KeyFields[0].DimensionField.ToString().ToUpper());
                                    }

                                    if (columns.TryAdd(attribute.Name.ToString().ToUpper(), attribute.KeyFields[0].DimensionField.ToString().ToUpper()))
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
                                        if (commonColumns.Contains(field.DimensionField.ToString().ToUpper()))
                                        {
                                            commonColumns.Remove(field.DimensionField.ToString().ToUpper());
                                        }

                                        if (field.DimensionField.ToString().Equals(attribute.NameField.ToString()))
                                        {
                                            if (columns.TryAdd(attribute.Name.ToString().ToUpper(), field.DimensionField.ToString().ToUpper()))
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
                                        else if (columns.TryAdd(field.DimensionField.ToString().ToUpper(), field.DimensionField.ToString().ToUpper()))
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

                            (string, HashSet<string>) enumTranslations = GenerateEnumTranslationsQuery(entryList, dimensionMetadata.Table.ToString(), columns);
                            if (enumTranslations.Item2.Count() > 0)
                            {
                                foreach (string column in enumTranslations.Item2)
                                {
                                    createDimensionQuery = RenameEnumColumns(createDimensionQuery, column);
                                }

                                createDimensionQuery += enumTranslations.Item1;
                            }

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
                        catch (Exception e)
                        {
                            if (e.Message.Contains($"Invalid column name 'PARTITION'"))
                            {
                                createDimensionQuery = DefaultPartitionColumn(createDimensionQuery);
                                continue;
                            }

                            if (e.Message.Contains($"Invalid column name 'DATAAREAID'"))
                            {
                                createDimensionQuery = DefaultDataAreaIdColumn(createDimensionQuery);
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

        private static string RenameEnumColumns(string createQuery, string enumColumn)
        {
            string input = $"{enumColumn},";
            string output = $"{enumColumn}_VALUE,";
            return createQuery.Replace(input, output);
        }

        private static string DefaultPartitionColumn(string createDimensionQuery)
        {
            return createDimensionQuery.Replace(",PARTITION", ",1 AS PARTITION");
        }

        private static string DefaultDataAreaIdColumn(string createDimensionQuery)
        {
            return createDimensionQuery.Replace(",DATAAREAID", ",'demo' AS DATAAREAID");
        }

        private static (bool, string) CheckReservedWord(dynamic dimensionField, dynamic dimensionName, string createDimensionQuery)
        {
            HashSet<string> reservedWords = new HashSet<string>()
            {
                "KEY",
                "COMMENT",
                "COUNT",
            };

            if (dimensionField == null || dimensionName == null)
            {
                return (false, createDimensionQuery);
            }

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
                "DATAAREAID",
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
                            var viewList = sqlProvider.ReadSqlStatement($"SELECT TOP(1) * FROM sys.views WHERE name = '{axViewMetadata.ViewName}'", "name");

                            if (viewList.Count == 0)
                            {
                                await sqlProvider.RunSqlStatementAsync(processedQuery);

                                ColorConsole.WriteSuccess($"Created '{axViewMetadata.ViewName}'\n");
                            }
                            else
                            {
                                ColorConsole.WriteSuccess($"View already exists. Skipping creation of '{axViewMetadata.ViewName}'\n");
                            }
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
