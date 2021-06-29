// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace EntityStoreMetadataExporter
{
    using System;
    using System.Collections.Generic;
    using System.Data.SqlClient;
    using System.IO;
    using System.Linq;
    using Microsoft.Dynamics.AX.Metadata.MetaModel;
    using Microsoft.Dynamics.AX.Metadata.Providers;
    using Microsoft.Dynamics.AX.Metadata.Storage;
    using Microsoft.Dynamics.AX.Metadata.Storage.Runtime;
    using Newtonsoft.Json;

    public class MetaDataExporter
    {
        private static List<string> views = new List<string>();

        public static void ExtractAggMeasurmentEntities(string packageDir, string measuregroupname, string outputFile)
        {
            IMetadataProvider metadataprovider;
            var metadataProviderFactory = new MetadataProviderFactory();
            var runtimeProviderConfig = new RuntimeProviderConfiguration(packageDir, true, false);
            Console.WriteLine("Creating MetadataProvider ...");
            using (metadataprovider = metadataProviderFactory.CreateRuntimeProviderWithExtensions(runtimeProviderConfig))
            {
                AxAggregateMeasurement measure = metadataprovider.AggregateMeasurements.Read(measuregroupname);
                File.WriteAllText(outputFile, string.Empty);
                List<AxMeasureGroup> axmgs = measure.MeasureGroups.ToList();
                foreach (AxMeasureGroup axmg in axmgs)
                {
                    string tablename = axmg.Table.ToString();
                    File.AppendAllText(outputFile, "'" + tablename + "',");

                    List<AxDimension> axads = axmg.Dimensions.ToList();
                    foreach (AxDimension axad in axads)
                    {
                        string axagdimension = axad.DimensionName;
                        AxAggregateDimension dimension = metadataprovider.AggregateDimensions.Read(axagdimension);
                        File.AppendAllText(outputFile, "'" + dimension.Table + "',");
                    }
                }
            }
        }

        public static void ExtractAggMeasurementList(string packageDir, string measuregroupname, string outputFile)
        {
            IMetadataProvider metadataprovider;
            var metadataProviderFactory = new MetadataProviderFactory();
            var runtimeProviderConfig = new RuntimeProviderConfiguration(packageDir, true, false);
            Console.WriteLine("Creating MetadataProvider ...");
            using (metadataprovider = metadataProviderFactory.CreateRuntimeProviderWithExtensions(runtimeProviderConfig))
            {
                AxAggregateMeasurement measure = metadataprovider.AggregateMeasurements.Read(measuregroupname);
                File.WriteAllText(outputFile, string.Empty);
                List<AxMeasureGroup> axmgs = measure.MeasureGroups.ToList();

                IQueryable<AxMeasureGroup> measuregroups = measure.MeasureGroups.AsQueryable<AxMeasureGroup>();
                List<string> tables = measuregroups.Select(mg => mg.Table).ToList();
                File.AppendAllLines(outputFile, tables);

                var dimensions = measuregroups.Select(mg => mg.Dimensions);

                var dimensionNames = dimensions.Select(d => d.Select(e => e.DimensionName).ToList());

                foreach (List<string> axads in dimensionNames)
                {
                    foreach (string axad in axads)
                    {
                        AxAggregateDimension dimension = metadataprovider.AggregateDimensions.Read(axad);
                        File.AppendAllText(outputFile, dimension.Table + Environment.NewLine);
                    }
                }
            }
        }

        public static void ExtractAggMeasurementJson(string packageDir, string measuregroupname, string outputFile)
        {
            IMetadataProvider metadataprovider;
            var metadataProviderFactory = new MetadataProviderFactory();
            var runtimeProviderConfig = new RuntimeProviderConfiguration(packageDir, true, false);
            Console.WriteLine("Creating MetadataProvider ...");
            using (metadataprovider = metadataProviderFactory.CreateRuntimeProviderWithExtensions(runtimeProviderConfig))
            {
                AxAggregateMeasurement measure = metadataprovider.AggregateMeasurements.Read(measuregroupname);
                File.WriteAllText(outputFile, JsonConvert.SerializeObject(measure));

                List<AxMeasureGroup> axmgs = measure.MeasureGroups.ToList();
                foreach (AxMeasureGroup axmg in axmgs)
                {
                    string tablename = axmg.Table.ToString();

                    List<AxDimension> axads = axmg.Dimensions.ToList();
                    foreach (AxDimension axad in axads)
                    {
                        string axagdimension = axad.DimensionName;
                        AxAggregateDimension dimension = metadataprovider.AggregateDimensions.Read(axagdimension);
                        File.WriteAllText(outputFile.Replace(".json", axagdimension + ".json"), JsonConvert.SerializeObject(dimension));

                        if (metadataprovider.Views.Exists(dimension.Table))
                        {
                            if (!MetaDataExporter.views.Exists(x => x.Contains("'" + dimension.Table + "'")))
                            {
                                views.Add("'" + dimension.Table + "'");
                            }
                        }
                    }
                }

                string listOfViews = string.Join(",", views);
                string ctrcommandtext = @"
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
                string selectstatement = @"select 
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

                MetaDataExporter.RunRecursiveViewDependencies(ctrcommandtext, selectstatement, "Server=<TODO>;Database=<TODO>;User Id=<TODO>;Password=<TODO>;");
                foreach (string viewstr in views)
                {
                    string viewstrfinal = viewstr.Replace("'", string.Empty);
                    AxView view = metadataprovider.Views.Read(viewstrfinal);
                    File.WriteAllText(outputFile.Replace(".json", "_DS_" + viewstrfinal + ".json"), JsonConvert.SerializeObject(view));
                }
            }
        }

        private static void RunRecursiveViewDependencies(string queryString, string selectstatement, string connectionString)
        {
            using (SqlConnection connection = new SqlConnection(
                       connectionString))
            {
                SqlCommand command = new SqlCommand(queryString, connection);
                command.Connection.Open();
                int nbrecords = command.ExecuteNonQuery();
                command.CommandText = selectstatement;
                SqlDataReader datareader = command.ExecuteReader();
                File.AppendAllText(@"C:\code\entity-store\ListOfViews.csv", string.Format("ViewName,RootViewName,ParentViewName,Definition" + Environment.NewLine));
                while (datareader.Read())
                {
                    if (!views.Exists(x => x.Contains("'" + datareader[0] + "'")))
                    {
                        views.Add("'" + datareader[0] + "'");
                    }

                    string record = string.Format("\"{0}\",\"{1}\",\"{2}\",\"{3}\"", datareader[0], datareader[1], datareader[2], datareader[3]);
                    File.AppendAllText(@"C:\code\entity-store\ListOfViews.csv", record + Environment.NewLine);
                }
            }
        }

        private static void ExtractAggDimensionsJson(string packageDir, string dimensionname, string outputFile)
        {
            IMetadataProvider metadataprovider;
            var metadataProviderFactory = new MetadataProviderFactory();
            var runtimeProviderConfig = new RuntimeProviderConfiguration(packageDir, true, false);
            Console.WriteLine("Creating MetadataProvider ...");
            using (metadataprovider = metadataProviderFactory.CreateRuntimeProviderWithExtensions(runtimeProviderConfig))
            {
                AxAggregateDimension measure = metadataprovider.AggregateDimensions.Read(dimensionname);
                File.WriteAllText(outputFile, JsonConvert.SerializeObject(measure));
            }
        }
    }
}
