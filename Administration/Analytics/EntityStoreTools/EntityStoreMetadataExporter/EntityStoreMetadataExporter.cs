namespace EntityStoreMetadataExporter
{
    using System;
    using System.Collections.Generic;
    using System.Data.SqlClient;
    using System.IO;
    using System.IO.Compression;
    using System.Linq;
    using System.Reflection;
    using global::EntityStoreMetadataExporter.Utils;
    using Microsoft.Dynamics.AX.Metadata.MetaModel;
    using Microsoft.Dynamics.AX.Metadata.Providers;
    using Microsoft.Dynamics.AX.Metadata.Storage;
    using Microsoft.Dynamics.AX.Metadata.Storage.Runtime;
    using Newtonsoft.Json;
    using Newtonsoft.Json.Linq;

    /// <summary>
    /// The Entity Store Metadata Exporter class.
    /// </summary>
    public class EntityStoreMetadataExporter
    {
        private static string tempPath;
        private static HashSet<string> enumSet;
        private static AggregateDimensionElements aggregateDimensionElements;
        private static IMetadataProvider metadataProvider;

        /// <summary>
        /// Publishes a zip file containing all metadata for a given aggregate measurement name.
        /// </summary>
        /// <param name="measureName">The aggregate measurement (AxMeasure) name.</param>
        /// <param name="packagePath">The AOS package path.</param>
        /// <param name="axDbSqlConnectionString">The AXDB SQL connection string.</param>
        /// <param name="outputPath">The output directory path.</param>
        public static void ExportMetadata(string measureName, string packagePath, string axDbSqlConnectionString, string outputPath)
        {
            Console.WriteLine($"Entity Store Metadata Exporter Tool (EntityStoreTools Version 2.9)\n");

            ContractValidator.MustNotBeEmpty(measureName, nameof(measureName));
            ContractValidator.MustNotBeEmpty(packagePath, nameof(packagePath));
            ContractValidator.MustNotBeEmpty(axDbSqlConnectionString, nameof(axDbSqlConnectionString));
            ContractValidator.MustNotBeEmpty(outputPath, nameof(outputPath));

            if (!Directory.Exists(outputPath))
            {
                Directory.CreateDirectory(outputPath);
            }

            tempPath = Path.Combine(Path.GetTempPath(), "EntityStoreMetadataExporter", DateTime.Now.ToString("yyyyMMddHmmssFFFFFF"));
            enumSet = new HashSet<string>();

            Directory.CreateDirectory(tempPath);

            // write a manifest file at root folder
            WriteManifest(measureName, tempPath);

            aggregateDimensionElements = new AggregateDimensionElements();
            var metadataProviderFactory = new MetadataProviderFactory();
            var runtimeProviderConfig = new RuntimeProviderConfiguration(packagePath, includeStatic: true, strict: false);

            Console.WriteLine("Creating MetadataProvider ...");

            using (metadataProvider = metadataProviderFactory.CreateRuntimeProviderWithExtensions(runtimeProviderConfig))
            {
                Console.WriteLine($"Writing aggregate measurement metadata for '{measureName}'...");
                var measure = WriteAggregateMeasurement(measureName);

                Console.WriteLine($"Writing aggregate dimension metadata...");
                WriteAggregateDimensions(measure);

                Console.WriteLine($"Writing view metadata for '{measureName}'");
                WriteViews(axDbSqlConnectionString);

                Console.WriteLine($"Writing table metadata for '{measureName}'");
                WriteTables(measureName);
            }

            // generate zip file
            var destinationFile = Path.Combine(outputPath, $"{measureName}.zip");
            if (File.Exists(destinationFile))
            {
                File.Delete(destinationFile);
            }

            ZipFile.CreateFromDirectory(tempPath, destinationFile);

            ColorConsole.WriteSuccess($"Metadata exported to '{destinationFile}'");
        }

        private static void WriteManifest(string measureName, string outputPath)
        {
            var manifest = new
            {
                MeasureName = measureName,
                Version = Assembly.GetExecutingAssembly().GetName().Version.ToString(),
                GeneratedAt = DateTime.UtcNow,
            };

            File.WriteAllText(Path.Combine(outputPath, "manifest.json"), JsonConvert.SerializeObject(manifest, Formatting.Indented));
        }

        private static AxAggregateMeasurement WriteAggregateMeasurement(string measureName)
        {
            AxAggregateMeasurement measure = metadataProvider.AggregateMeasurements.Read(measureName);

            File.WriteAllText(Path.Combine(tempPath, "measurement.json"), JsonConvert.SerializeObject(measure, Formatting.Indented));

            ColorConsole.WriteInfo($"\tAdded measure '{measureName}'");

            WriteFactEnums(measure);

            return measure;
        }

        private static void WriteFactEnums(AxAggregateMeasurement measure)
        {
            foreach (var measureGroup in measure.MeasureGroups)
            {
                var tableName = measureGroup.Table.ToString();

                EnumParser(tableName);

                foreach (var axDimension in measureGroup.Dimensions)
                {
                    AxAggregateDimension dimension = metadataProvider.AggregateDimensions.Read(axDimension.DimensionName.ToString());

                    EnumParser(dimension.Table == null ? string.Empty : dimension.Table.ToString());
                }
            }
        }

        private static void EnumParser(string tableName)
        {
            if (metadataProvider.Views.Exists(tableName))
            {
                var view = metadataProvider.Views.Read(tableName);

                foreach (var field in view.Fields)
                {
                    var json = JsonConvert.SerializeObject(field, Formatting.Indented);
                    using (TextReader sr = new StringReader(json))
                    {
                        using (var jsonTextReader = new JsonTextReader(sr))
                        {
                            dynamic fieldObject = JObject.Load(jsonTextReader);

                            string fieldName = fieldObject.Name == null ? null : fieldObject.Name.ToString();
                            string dataSource = fieldObject.DataSource == null ? null : fieldObject.DataSource.ToString();
                            string dataField = fieldObject.DataField == null ? null : fieldObject.DataField.ToString();

                            if (!WriteEnumFile(tableName, fieldName, dataSource, dataField))
                            {
                                if (view.Query != null)
                                {
                                    string tableNameFromQuery = GetTableNameFromQuery(view.Query.ToString(), dataSource);

                                    if (!string.IsNullOrEmpty(tableNameFromQuery))
                                    {
                                        WriteEnumFile(tableName, fieldName, tableNameFromQuery, dataField);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            else if (metadataProvider.DataEntityViews.Exists(tableName))
            {
                var entity = metadataProvider.DataEntityViews.Read(tableName);

                foreach (var field in entity.Fields)
                {
                    var json = JsonConvert.SerializeObject(field, Formatting.Indented);
                    using (TextReader sr = new StringReader(json))
                    {
                        using (var jsonTextReader = new JsonTextReader(sr))
                        {
                            dynamic fieldObject = JObject.Load(jsonTextReader);

                            string fieldName = fieldObject.Name == null ? null : fieldObject.Name.ToString();
                            string dataSource = fieldObject.DataSource == null ? null : fieldObject.DataSource.ToString();
                            string dataField = fieldObject.DataField == null ? null : fieldObject.DataField.ToString();

                            if (!WriteEnumFile(tableName, fieldName, dataSource, dataField))
                            {
                                if (entity.Query != null)
                                {
                                    string tableNameFromQuery = GetTableNameFromQuery(entity.Query.ToString(), dataSource);

                                    if (!string.IsNullOrEmpty(tableNameFromQuery))
                                    {
                                        WriteEnumFile(tableName, fieldName, tableNameFromQuery, dataField);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            else if (metadataProvider.Tables.Exists(tableName))
            {
                var table = metadataProvider.Tables.Read(tableName);

                foreach (var field in table.Fields)
                {
                    var json = JsonConvert.SerializeObject(field, Formatting.Indented);
                    using (TextReader innerSR = new StringReader(json))
                    {
                        using (var innerJsonTextReader = new JsonTextReader(innerSR))
                        {
                            dynamic fieldObject = JObject.Load(innerJsonTextReader);

                            string fieldName = fieldObject.Name == null ? null : fieldObject.Name.ToString();
                            string enumName = fieldObject.EnumType == null ? null : fieldObject.EnumType.ToString();

                            if (!string.IsNullOrEmpty(enumName))
                            {
                                EnumWriter(tableName, fieldName, enumName);
                            }
                        }
                    }
                }
            }
        }

        private static bool WriteEnumFile(string tableName, string fieldName, string dataSource, string dataField)
        {
            if (string.IsNullOrEmpty(dataSource) || string.IsNullOrEmpty(dataField))
            {
                return false;
            }

            if (metadataProvider.Tables.Exists(dataSource))
            {
                var innerTable = metadataProvider.Tables.Read(dataSource);

                foreach (var columnEntity in innerTable.Fields)
                {
                    string columnName = columnEntity.Name.ToString();

                    if (!columnName.Equals(dataField))
                    {
                        continue;
                    }

                    var innerJson = JsonConvert.SerializeObject(columnEntity, Formatting.Indented);
                    using (TextReader innerSR = new StringReader(innerJson))
                    {
                        using (var innerJsonTextReader = new JsonTextReader(innerSR))
                        {
                            dynamic columnObject = JObject.Load(innerJsonTextReader);

                            string enumName = columnObject.EnumType;

                            if (enumName != null)
                            {
                                EnumWriter(tableName, fieldName, enumName.ToString());
                            }
                        }
                    }

                    return true;
                }

                return true;
            }
            else if (metadataProvider.DataEntityViews.Exists(dataSource))
            {
                var innerEntity = metadataProvider.DataEntityViews.Read(dataSource);

                foreach (var field in innerEntity.Fields)
                {
                    string columnName = field.Name.ToString();

                    if (!columnName.Equals(dataField))
                    {
                        continue;
                    }

                    var json = JsonConvert.SerializeObject(field, Formatting.Indented);
                    using (TextReader sr = new StringReader(json))
                    {
                        using (var jsonTextReader = new JsonTextReader(sr))
                        {
                            dynamic fieldObject = JObject.Load(jsonTextReader);

                            string innerFieldName = fieldObject.Name == null ? null : fieldObject.Name.ToString();
                            string innerDataSource = fieldObject.DataSource == null ? null : fieldObject.DataSource.ToString();
                            string innerDataField = fieldObject.DataField == null ? null : fieldObject.DataField.ToString();

                            string enumName = fieldObject.EnumType;

                            if (enumName != null)
                            {
                                EnumWriter(tableName, fieldName, enumName.ToString());
                            }
                            else
                            {
                                if (!WriteEnumFile(tableName, fieldName, innerDataSource, innerDataField))
                                {
                                    if (innerEntity.Query != null)
                                    {
                                        string tableNameFromQuery = GetTableNameFromQuery(innerEntity.Query.ToString(), innerDataSource);
                                    }
                                }
                            }
                        }
                    }

                    return true;
                }
            }
            else if (metadataProvider.Views.Exists(dataSource))
            {
                var innerView = metadataProvider.Views.Read(dataSource);

                foreach (var field in innerView.Fields)
                {
                    string columnName = field.Name.ToString();

                    if (!columnName.Equals(dataField))
                    {
                        continue;
                    }

                    var json = JsonConvert.SerializeObject(field, Formatting.Indented);
                    using (TextReader sr = new StringReader(json))
                    {
                        using (var jsonTextReader = new JsonTextReader(sr))
                        {
                            dynamic fieldObject = JObject.Load(jsonTextReader);

                            string innerFieldName = fieldObject.Name == null ? null : fieldObject.Name.ToString();
                            string innerDataSource = fieldObject.DataSource == null ? null : fieldObject.DataSource.ToString();
                            string innerDataField = fieldObject.DataField == null ? null : fieldObject.DataField.ToString();

                            string enumName = fieldObject.EnumType;

                            if (enumName != null)
                            {
                                EnumWriter(tableName, fieldName, enumName.ToString());
                            }
                            else
                            {
                                if (!WriteEnumFile(tableName, fieldName, innerDataSource, innerDataField))
                                {
                                    if (innerView.Query != null)
                                    {
                                        string tableNameFromQuery = GetTableNameFromQuery(innerView.Query.ToString(), innerDataSource);

                                        if (!string.IsNullOrEmpty(tableNameFromQuery))
                                        {
                                            WriteEnumFile(tableName, fieldName, tableNameFromQuery, innerDataField);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    return true;
                }
            }

            return false;
        }

        private static string GetTableNameFromQuery(string queryName, string dataSource)
        {
            if (string.IsNullOrEmpty(dataSource))
            {
                return string.Empty;
            }

            var queryObject = metadataProvider.Queries.Read(queryName);

            if (queryObject != null)
            {
                var json = JsonConvert.SerializeObject(queryObject, Formatting.Indented);
                using (TextReader sr = new StringReader(json))
                {
                    using (var jsonTextReader = new JsonTextReader(sr))
                    {
                        dynamic queryParsedObject = JObject.Load(jsonTextReader);
                        foreach (var source in queryParsedObject.DataSources)
                        {
                            if (source.Name.ToString().Equals(dataSource))
                            {
                                return source.Table;
                            }
                            else
                            {
                                foreach (var innerSource in source.DataSources)
                                {
                                    if (innerSource.Name.ToString().Equals(dataSource))
                                    {
                                        return innerSource.Table;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            return string.Empty;
        }

        private static bool EnumWriter(string tableName, string fieldName, string enumName)
        {
            var enumObject = metadataProvider.Enums.Read(enumName);

            if (enumObject == null)
            {
                return false;
            }

            var values = enumObject.EnumValues;

            JArray enumValues = new JArray();

            foreach (var value in values)
            {
                dynamic kv = new JObject();
                kv.Key = value.getKey();
                kv.Value = value.Value;
                enumValues.Add(kv);
            }

            dynamic enumFileObject = new JObject();

            enumFileObject.Name = fieldName.ToUpper();
            enumFileObject.EnumName = enumName.ToUpper();
            enumFileObject.Translations = enumValues;

            var enumsPath = Path.Combine(tempPath, "enums");
            var enumDependenciesPath = Path.Combine(enumsPath, $"{tableName.ToUpper()}_{fieldName.ToUpper()}.json");

            if (!Directory.Exists(enumsPath))
            {
                Directory.CreateDirectory(enumsPath);
            }

            ColorConsole.WriteInfo($"\nWriting enum file: '{tableName.ToUpper()}_{fieldName.ToUpper()}'");
            File.WriteAllText(enumDependenciesPath, JsonConvert.SerializeObject(enumFileObject, Formatting.Indented));

            return true;
        }

        private static void WriteAggregateDimensions(AxAggregateMeasurement measure)
        {
            var dimensionsPath = Path.Combine(tempPath, "dimensions");
            if (!Directory.Exists(dimensionsPath))
            {
                Directory.CreateDirectory(dimensionsPath);
            }

            var visitedElements = new HashSet<string>();
            List<AxMeasureGroup> axmgs = measure.MeasureGroups.ToList();
            foreach (AxMeasureGroup axmg in axmgs)
            {
                string tablename = axmg.Table.ToString();
                SeparateTablesAndViews(tablename);

                List<AxDimension> axads = axmg.Dimensions.ToList();
                foreach (AxDimension axad in axads)
                {
                    string dimensionName = axad.DimensionName;

                    AxAggregateDimension dimension = metadataProvider.AggregateDimensions.Read(dimensionName);

                    // skip visited elements
                    if (visitedElements.Contains(dimension.Table))
                    {
                        continue;
                    }
                    else
                    {
                        visitedElements.Add(dimension.Table);
                    }

                    var dimensionMetadataPath = Path.Combine(dimensionsPath, $"{dimensionName.ToString().ToUpper()}.json");
                    File.WriteAllText(dimensionMetadataPath, JsonConvert.SerializeObject(dimension, Formatting.Indented));

                    SeparateTablesAndViews(dimension.Table);
                }
            }
        }

        private static void SeparateTablesAndViews(string element)
        {
            if (metadataProvider.Views.Exists(element) || metadataProvider.DataEntityViews.Exists(element))
            {
                if (aggregateDimensionElements.DimensionViews.Add(element.ToUpper()))
                {
                    RecursivelyAddDataSourcesFromQuery(element);

                    ColorConsole.WriteInfo($"\tAdded element as view '{element.ToUpperInvariant()}'");
                }
            }
            else if (metadataProvider.Tables.Exists(element.ToUpper()))
            {
                if (aggregateDimensionElements.DimensionTables.Add(element))
                {
                    ColorConsole.WriteInfo($"\tAdded element as 'table '{element.ToUpperInvariant()}'");
                }
            }
            else
            {
                ColorConsole.WriteWarning($"\tElement '{element.ToUpperInvariant()}' cannot be identified as either view or table.");
            }
        }

        private static void RecursivelyAddDataSourcesFromQuery(string element)
        {
            AxView view = metadataProvider.Views.Read(element);

            if (view != null && !string.IsNullOrEmpty(view.Query))
            {
                AxQuery axQuery = metadataProvider.Queries.Read(view.Query);

                var json = JsonConvert.SerializeObject(axQuery, Formatting.Indented);
                using (TextReader sr = new StringReader(json))
                {
                    using (var jsonTextReader = new JsonTextReader(sr))
                    {
                        dynamic queryObject = JObject.Load(jsonTextReader);

                        var queriesPath = Path.Combine(tempPath, "queries");
                        if (!Directory.Exists(queriesPath))
                        {
                            Directory.CreateDirectory(queriesPath);
                        }

                        var queryMetadataPath = Path.Combine(queriesPath, $"{view.Query.ToString().ToUpper()}.json");
                        File.WriteAllText(queryMetadataPath, JsonConvert.SerializeObject(queryObject, Formatting.Indented));

                        foreach (var dataSource in queryObject.DataSources)
                        {
                            SeparateTablesAndViews(dataSource.Table.ToString());

                            RecursivelyAddDataSourcesFromDataSource(dataSource);
                        }
                    }
                }
            }
        }

        private static void RecursivelyAddDataSourcesFromDataSource(dynamic dataSource)
        {
            foreach (var source in dataSource.DataSources)
            {
                SeparateTablesAndViews(source.Table.ToString());

                RecursivelyAddDataSourcesFromDataSource(source);
            }
        }

        private static void WriteViews(string axDbConnectionString)
        {
            HashSet<string> dataSources = new HashSet<string>();

            var viewsPath = Path.Combine(tempPath, "views");
            if (!Directory.Exists(viewsPath))
            {
                Directory.CreateDirectory(viewsPath);
            }

            var allViewDependencies = RetrieveViewDependencies(axDbConnectionString, viewsPath);

            foreach (string viewName in allViewDependencies)
            {
                AxView view = metadataProvider.Views.Read(viewName);
                AxDataEntity dataEntity = metadataProvider.DataEntityViews.Read(viewName);

                var json = JsonConvert.SerializeObject(view ?? dataEntity, Formatting.Indented);
                using (TextReader sr = new StringReader(json))
                {
                    using (var jsonTextReader = new JsonTextReader(sr))
                    {
                        dynamic definition = JObject.Load(jsonTextReader);

                        foreach (var fields in definition.Fields)
                        {
                            if (fields.DataSource != null && dataSources.Add(fields.DataSource.ToString()))
                            {
                                SeparateTablesAndViews(fields.DataSource.ToString());
                            }
                        }
                    }
                }

                var viewMetadataPath = Path.Combine(viewsPath, $"{viewName}.json");
                File.WriteAllText(viewMetadataPath, JsonConvert.SerializeObject(view ?? dataEntity, Formatting.Indented));

                ColorConsole.WriteInfo($"\tAdded view '{viewName}'");
            }
        }

        private static void WriteTables(string measureName)
        {
            var tablesPath = Path.Combine(tempPath, "tables");
            if (!Directory.Exists(tablesPath))
            {
                Directory.CreateDirectory(tablesPath);
            }

            var allTables = new HashSet<string>(aggregateDimensionElements.DimensionTables);

            // add aggregate measure tables
            AxAggregateMeasurement measure = metadataProvider.AggregateMeasurements.Read(measureName);
            List<AxMeasureGroup> axmgs = measure.MeasureGroups.ToList();
            foreach (AxMeasureGroup axmg in axmgs)
            {
                string tableName = axmg.Table.ToString();
                if (metadataProvider.Tables.Exists(tableName))
                {
                    allTables.Add(tableName);
                }
            }

            // write all table metadata

            // writes a list of table names in tables.csv
            var tableListPath = Path.Combine(tablesPath, "tables.csv");
            File.WriteAllText(tableListPath, "TableName" + Environment.NewLine); // write header
            foreach (var tableName in allTables)
            {
                File.AppendAllText(tableListPath, tableName + Environment.NewLine);

                if (metadataProvider.Tables.Exists(tableName))
                {
                    AxTable tableMetadata = metadataProvider.Tables.Read(tableName);

                    var tableMetadataPath = Path.Combine(tablesPath, $"{tableName.ToString().ToUpper()}.json");
                    File.WriteAllText(tableMetadataPath, JsonConvert.SerializeObject(tableMetadata, Formatting.Indented));

                    ColorConsole.WriteInfo($"\tAdded table '{tableName}'");
                }
                else
                {
                    ColorConsole.WriteWarning($"\tTable metadata not found for '{tableName}'");
                }
            }
        }

        private static ISet<string> RetrieveViewDependencies(string axDbConnectionString, string viewsPath)
        {
            var viewDependencies = new HashSet<string>();

            string listOfViews = string.Join(",", aggregateDimensionElements.DimensionViews.Select(v => $"'{v}'"));

            string queryString = @"
                -- ***************************************************Part 1 recursion************************************* 
-----------------------------------------------BEGIN Recursive section ---------------------------------------
With allviews (nodeId, parentNodeId, nodeIdType, rootNode, depth) AS (
-- 1 Anchor member - represents the list of root nodes considered with a depth of 0  
       select nv.name as nodeId,
       CAST(null as NVARCHAR(MAX)) as parentNodeId,
       CAST('VIEW' as nvarchar(60)) COLLATE DATABASE_DEFAULT as nodeIdType,
          nv.name as rootNode,
          0 as depth
       from sys.views nv
       where schema_name(nv.schema_id) = 'dbo' AND nv.name in (" + listOfViews + @")        
       union all
-- 2 recursive member - represents the iteration path to navigate from a node to its parent
--increases depth by 1 at each iteration and keeps a trace of the initial root node from the anchor member 
       select o.name as nodeId,
       CAST(p.name as NVARCHAR(Max)) as parentNodeId,
       o.type_desc COLLATE DATABASE_DEFAULT as nodeIdType,
          allviews.rootNode as rootnode,
          allviews.depth + 1 as depth
       from sys.sql_expression_dependencies d
       join sys.objects o
                     on o.object_id = d.referenced_id
       join sys.objects p
                     on p.object_id = d.referencing_id
       join allviews on allviews.nodeId = p.name
       where 
       d.referenced_id is not null and 
-- 3 ending condition
       p.type_desc = 'VIEW' and
       schema_name(p.schema_id) = 'dbo' and schema_name(o.schema_id) = 'dbo'
)
--4 inserts the results in a temporary table for ease of use
Select * into #myEntitiestree from allviews ;
------------------------------------------------End recursive section -------------------------------

";
            string selectStatement = @"DECLARE @TablesList VARCHAR(MAX);
select @TablesList =COALESCE(@TablesList + ',', '') + nodeId from #myEntitiestree where nodeIdType = 'USER_TABLE';
select 
       v.name as view_name,          
       rootnode,
          parentnodeid,
       Replace(Replace(Replace(m.definition,'CREATE VIEW','CREATE OR ALTER VIEW'),'GetValidFromInContextInfo','GETUTCDATE'),'GetValidToInContextInfo','GETUTCDATE') as definitions,
       @TablesList as TableList
from sys.views v
join sys.sql_modules m 
     on m.object_id = v.object_id
join (Select * from #myEntitiestree mytree 
where mytree.nodeIdType = 'VIEW' and exists 
(  -- replace this section by selection of your list of tables in the lake
       Select 
       #myEntitiestree.rootNode
    from #myEntitiestree 
       where mytree.rootNode = #myEntitiestree .rootNode
       group by rootNode 
) ) as orderedViews
on orderedViews.nodeId = v.name
order by rootNode asc, depth desc
";

            using (SqlConnection connection = new SqlConnection(axDbConnectionString))
            {
                SqlCommand command = new SqlCommand(queryString, connection);
                command.Connection.Open();
                int nbrecords = command.ExecuteNonQuery();
                command.CommandText = selectStatement;
                SqlDataReader dataReader = command.ExecuteReader();

                var viewDependenciesPath = Path.Combine(viewsPath, "dependencies.csv");
                File.WriteAllText(viewDependenciesPath, string.Format("ViewName,RootViewName,ParentViewName,Definition" + Environment.NewLine));

                while (dataReader.Read())
                {
                    var viewName = dataReader[0];
                    viewDependencies.Add(viewName.ToString());

                    string record = string.Format("\"{0}\",\"{1}\",\"{2}\",\"{3}\"", dataReader[0], dataReader[1], dataReader[2], dataReader[3]);

                    AddTables(dataReader[4].ToString());

                    File.AppendAllText(viewDependenciesPath, record + Environment.NewLine);
                }
            }

            return viewDependencies;
        }

        private static void AddTables(string tables)
        {
            string[] tablesList = tables.Split(',');

            foreach (string table in tablesList)
            {
                SeparateTablesAndViews(table);
            }
        }

        private class AggregateDimensionElements
        {
            public AggregateDimensionElements()
            {
                DimensionTables = new HashSet<string>();
                DimensionViews = new HashSet<string>();
            }

            public HashSet<string> DimensionTables { get; set; }

            public HashSet<string> DimensionViews { get; set; }
        }
    }
}
