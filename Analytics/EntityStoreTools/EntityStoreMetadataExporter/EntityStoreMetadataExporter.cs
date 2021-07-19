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

    /// <summary>
    /// The Entity Store Metadata Exporter class.
    /// </summary>
    public class EntityStoreMetadataExporter
    {
        /// <summary>
        /// Publishes a zip file containing all metadata for a given aggregate measurement name.
        /// </summary>
        /// <param name="measureName">The aggregate measurement (AxMeasure) name.</param>
        /// <param name="packagePath">The AOS package path.</param>
        /// <param name="axDbSqlConnectionString">The AXDB SQL connection string.</param>
        /// <param name="outputPath">The output directory path.</param>
        public static void ExportMetadata(string measureName, string packagePath, string axDbSqlConnectionString, string outputPath)
        {
            ContractValidator.MustNotBeEmpty(measureName, nameof(measureName));
            ContractValidator.MustNotBeEmpty(packagePath, nameof(packagePath));
            ContractValidator.MustNotBeEmpty(axDbSqlConnectionString, nameof(axDbSqlConnectionString));
            ContractValidator.MustNotBeEmpty(outputPath, nameof(outputPath));

            if (!Directory.Exists(outputPath))
            {
                Directory.CreateDirectory(outputPath);
            }

            var tempPath = Path.Combine(Path.GetTempPath(), "EntityStoreMetadataExporter", DateTime.Now.ToString("yyyyMMddHmmssFFFFFF"));

            Directory.CreateDirectory(tempPath);

            // write a manifest file at root folder
            WriteManifest(measureName, tempPath);

            IMetadataProvider metadataProvider;
            var metadataProviderFactory = new MetadataProviderFactory();
            var runtimeProviderConfig = new RuntimeProviderConfiguration(packagePath, includeStatic: true, strict: false);

            Console.WriteLine("Creating MetadataProvider ...");

            using (metadataProvider = metadataProviderFactory.CreateRuntimeProviderWithExtensions(runtimeProviderConfig))
            {
                Console.WriteLine($"Writing aggregate measurement metadata for '{measureName}'...");
                var measure = WriteAggregateMeasurement(measureName, metadataProvider, tempPath);

                Console.WriteLine($"Writing aggregate dimension metadata...");
                var dimensionElements = WriteAggregateDimensions(measure, metadataProvider, tempPath);

                Console.WriteLine($"Writing table metadata for '{measureName}'");
                WriteTables(dimensionElements.DimensionTables, measureName, metadataProvider, tempPath);

                Console.WriteLine($"Writing view metadata for '{measureName}'");
                WriteViews(dimensionElements.DimensionViews, metadataProvider, axDbSqlConnectionString, tempPath);
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

        private static AxAggregateMeasurement WriteAggregateMeasurement(string measureName, IMetadataProvider metadataProvider, string outputPath)
        {
            AxAggregateMeasurement measure = metadataProvider.AggregateMeasurements.Read(measureName);

            File.WriteAllText(Path.Combine(outputPath, "measure.json"), JsonConvert.SerializeObject(measure, Formatting.Indented));

            ColorConsole.WriteInfo($"\tAdded measure '{measureName}'");

            return measure;
        }

        private static AggregateDimensionElements WriteAggregateDimensions(AxAggregateMeasurement measure, IMetadataProvider metadataProvider, string outputPath)
        {
            var dimensionsPath = Path.Combine(outputPath, "dimensions");
            if (!Directory.Exists(dimensionsPath))
            {
                Directory.CreateDirectory(dimensionsPath);
            }

            var dimensionsViews = new HashSet<string>();
            var dimensionsTables = new HashSet<string>();
            var visitedElements = new HashSet<string>();
            List<AxMeasureGroup> axmgs = measure.MeasureGroups.ToList();
            foreach (AxMeasureGroup axmg in axmgs)
            {
                string tablename = axmg.Table.ToString();

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

                    var dimensionMetadataPath = Path.Combine(dimensionsPath, $"{dimensionName}.json");
                    File.WriteAllText(dimensionMetadataPath, JsonConvert.SerializeObject(dimension, Formatting.Indented));

                    if (metadataProvider.Views.Exists(dimension.Table))
                    {
                        ColorConsole.WriteInfo($"\tAdded dimension '{dimensionName}' as view '{dimension.Table.ToUpperInvariant()}'");
                        dimensionsViews.Add(dimension.Table);
                    }
                    else if (metadataProvider.Tables.Exists(dimension.Table))
                    {
                        ColorConsole.WriteInfo($"\tAdded dimension '{dimensionName}' as 'table '{dimension.Table.ToUpperInvariant()}'");
                        dimensionsTables.Add(dimension.Table);
                    }
                    else
                    {
                        ColorConsole.WriteWarning($"\tDimension '{dimensionName}' with table '{dimension.Table.ToUpperInvariant()}' cannot be identified as either view or table.");
                    }
                }
            }

            return new AggregateDimensionElements
            {
                DimensionTables = dimensionsTables,
                DimensionViews = dimensionsViews,
            };
        }

        private static void WriteViews(ISet<string> aggregateDimensionViews, IMetadataProvider metadataProvider, string axDbConnectionString, string outputPath)
        {
            var viewsPath = Path.Combine(outputPath, "views");
            if (!Directory.Exists(viewsPath))
            {
                Directory.CreateDirectory(viewsPath);
            }

            var allViewDependencies = EntityStoreMetadataExporter.RetrieveViewDependencies(aggregateDimensionViews, axDbConnectionString, viewsPath);

            foreach (string viewName in allViewDependencies)
            {
                AxView view = metadataProvider.Views.Read(viewName);

                var viewMetadataPath = Path.Combine(viewsPath, $"{viewName}.json");
                File.WriteAllText(viewMetadataPath, JsonConvert.SerializeObject(view, Formatting.Indented));

                ColorConsole.WriteInfo($"\tAdded view '{viewName}'");
            }
        }

        private static void WriteTables(ISet<string> aggregateDimensionTables, string measureName, IMetadataProvider metadataProvider, string outputPath)
        {
            var tablesPath = Path.Combine(outputPath, "tables");
            if (!Directory.Exists(tablesPath))
            {
                Directory.CreateDirectory(tablesPath);
            }

            var allTables = new HashSet<string>(aggregateDimensionTables);

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

                    var tableMetadataPath = Path.Combine(tablesPath, $"{tableName}.json");
                    File.WriteAllText(tableMetadataPath, JsonConvert.SerializeObject(tableMetadata, Formatting.Indented));

                    ColorConsole.WriteInfo($"\tAdded table '{tableName}'");
                }
                else
                {
                    ColorConsole.WriteWarning($"\tTable metadata not found for '{tableName}'");
                }
            }
        }

        private static ISet<string> RetrieveViewDependencies(ISet<string> aggregateDimensionViews, string axDbConnectionString, string viewsPath)
        {
            var viewDependencies = new HashSet<string>();

            string listOfViews = string.Join(",", aggregateDimensionViews.Select(v => $"'{v}'"));

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
            string selectStatement = @"select 
       v.name as view_name, 	   
       rootnode,
	   parentnodeid,
       Replace(Replace(Replace(m.definition,'CREATE VIEW','CREATE OR ALTER VIEW'),'GetValidFromInContextInfo','GETUTCDATE'),'GetValidToInContextInfo','GETUTCDATE') as definitions
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

                    File.AppendAllText(viewDependenciesPath, record + Environment.NewLine);
                }
            }

            return viewDependencies;
        }

        private class AggregateDimensionElements
        {
            public ISet<string> DimensionTables { get; set; }

            public ISet<string> DimensionViews { get; set; }
        }
    }
}
