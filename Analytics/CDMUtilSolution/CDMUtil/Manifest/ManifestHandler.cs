using System;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Microsoft.CommonDataModel.ObjectModel.Cdm;
using Microsoft.CommonDataModel.ObjectModel.Enums;
using Microsoft.CommonDataModel.ObjectModel.Storage;
using System.Collections.Generic;
using System.Linq;
using CDMUtil.Context.ADLS;
using CDMUtil.Context.ObjectDefinitions;
using System.Text.RegularExpressions;
using CDMUtil.SQL;
using Microsoft.Extensions.Logging;
using Microsoft.CommonDataModel.ObjectModel.Utilities;

namespace CDMUtil.Manifest
{
    public class ManifestReader : ManifestBase
    {
        public ManifestReader(AdlsContext adlsContext, string currentFolder, ILogger logger) : base(adlsContext, currentFolder, logger)
        {
        }
        public async static Task WaitForFolderPathsToExist(AppConfigurations c, List<SQLMetadata> metadataList, ILogger logger)
        {
            AdlsContext adlsContext = c.AdlsContext;
            string folderPath = "";
            const int maxTries = 20;
            const int secondsToWait = 10;

            for (int i = 0; i < maxTries; i++)
            {
                try
                {
                    foreach (var metadata in metadataList)
                    {

                        //chop off /*.csv from the path
                        folderPath = metadata.dataLocation.Substring(0, metadata.dataLocation.LastIndexOf("/"));
                        ManifestReader manifestHandler = new ManifestReader(adlsContext, folderPath, logger);
                        await manifestHandler.cdmCorpus.Storage.FetchAdapter(manifestHandler.cdmCorpus.Storage.DefaultNamespace).FetchAllFilesAsync("");
                        logger.LogInformation($"Folder {folderPath} exists");
                    }
                    break;
                }
                catch (System.Net.Http.HttpRequestException)
                {
                    //the path doesnt exist
                    logger.LogWarning($"Folder {folderPath} does not exist, waiting {secondsToWait} seconds then trying again, attempt {i + 1} of {maxTries}");
                    await Task.Delay(secondsToWait * 1000);
                }
            }
        }
        public async static Task<List<ManifestDefinition>> getManifestDefinitions(AppConfigurations c, ILogger logger)
        {
            ManifestReader manifestHandler = new ManifestReader(c.AdlsContext, "/", logger);

            List<string> files = await manifestHandler.cdmCorpus.Storage.FetchAdapter(manifestHandler.cdmCorpus.Storage.DefaultNamespace).FetchAllFilesAsync(c.rootFolder);
            
            List<String> filteredBlob = files.Where(b => b.EndsWith(".cdm.json") && !b.EndsWith(".manifest.cdm.json") && !b.Contains("/resolved/")).ToList();

            List<String> tableList = c.tableList;

            List<ManifestDefinition> metadataList = new List<ManifestDefinition>();

            foreach (var blob in filteredBlob)
            {
                string dataPath = blob.Replace(".cdm.json", "");
                string[] dataPathParts = dataPath.Split('/');
                string[] manifestPathParts = dataPathParts.Take(dataPathParts.Length - 1).ToArray();
                string TableName = dataPathParts.Last();

                if (tableList != null)
                {
                    if (tableList.Count == 0)
                        break;
                    else if (tableList.First() != "*" && !tableList.Contains(TableName))
                        continue;
                    else
                        tableList.Remove(TableName);
                }

                ManifestDefinition metadata = new ManifestDefinition
                {
                    TableName = dataPathParts.Last(),
                    DataLocation = dataPath,
                    ManifestName = dataPathParts[dataPathParts.Length - 2],
                    ManifestLocation = String.Join("/", manifestPathParts)
                };

                metadataList.Add(metadata);
            }

            logger.LogDebug(JsonConvert.SerializeObject(metadataList));
            return metadataList;
        }

  
    public async static Task<bool> manifestToSQLMetadata(AppConfigurations c, List<SQLMetadata> metadataList, ILogger logger, string parentFolder = "")
        {
            AdlsContext adlsContext = c.AdlsContext;
            string manifestName = c.manifestName;
            string localRoot = c.rootFolder;

            List<string> tableList = c.tableList;

            ManifestReader manifestHandler = new ManifestReader(adlsContext, localRoot, logger);

            if (manifestName != "model.json" && manifestName.EndsWith(".manifest.cdm.json") == false)
            {
                manifestName = manifestName + ".manifest.cdm.json";
            }

            try
            {
                CdmManifestDefinition manifest = manifestHandler.cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName, null, null, true).Result;

                if (manifest == null)
                {
                    logger.LogError($"Manifest: {manifestName } at Location {localRoot} is invalid");
                    return false;
                }

                foreach (var submanifest in manifest.SubManifests)
                {
                    if (tableList != null && tableList.Count == 0)
                        break;
                    string subManifestName = submanifest.ManifestName;
                    string subManifestRoot = localRoot.EndsWith('/') ? localRoot + subManifestName : localRoot + '/' + subManifestName;
                    logger.LogInformation($"Sub-Manifest:{subManifestRoot}");
                    c.manifestName = subManifestName;
                    c.rootFolder = subManifestRoot;

                    manifestToSQLMetadata(c, metadataList, logger, parentFolder);
                }

                logger.LogInformation($"Manifest:{manifest.Name}");

                foreach (CdmEntityDeclarationDefinition eDef in manifest.Entities)
                {
                    string entityName = eDef.EntityName;

                    if (tableList != null)
                    {
                        if (tableList.Count == 0)
                            break;
                        else if (tableList.First() != "*" && !tableList.Contains(entityName))
                            continue;
                        else
                            tableList.Remove(entityName);
                    }
                    
                    var entSelected = manifestHandler.cdmCorpus.FetchObjectAsync<CdmEntityDefinition>(eDef.EntityPath, manifest).Result;

                    if (entSelected.ExhibitsTraits.Count() > 1 && entSelected.ExhibitsTraits.Where(x => x.NamedReference == "has.sqlViewDefinition").Count() > 0)
                    {
                        // Custom traits sqlViewDefinition exists
                        var trait = entSelected.ExhibitsTraits.Where(x => x.NamedReference == "has.sqlViewDefinition").First();
                        CdmTraitReference cdmTrait = trait as CdmTraitReference;

                        if (cdmTrait != null && cdmTrait.Arguments != null)
                        {
                            string viewDefinition = cdmTrait.Arguments.First().Value;
                            //update view dependencies
                            updateViewDependencies(entityName, viewDefinition, metadataList, c, logger);
                            TSqlSyntaxHandler.updateViewSyntax(c, metadataList);
                        }
                    }
                    else
                    {
                        string dataLocation = getDataLocation(eDef, localRoot);

                        string dataFilePath = "https://" + Regex.Replace($"{adlsContext.StorageAccount}/{adlsContext.FileSytemName}/{dataLocation}", @"/+", @"/");
                        string metadataFilePath = "https://" + Regex.Replace($"{adlsContext.StorageAccount}/{adlsContext.FileSytemName}/{localRoot}/{manifestName}", @"/+", @"/");
                        string cdcDataFileFilePath = "https://" + Regex.Replace($"{adlsContext.StorageAccount}/{adlsContext.FileSytemName}/ChangeFeed/{entityName}/*.csv", @"/+", @"/");
                        
                        if (dataFilePath.Contains("ChangeFeed/") && c.synapseOptions.schema == "dbo")
                        {
                            entityName = "_cdc_" + entityName;
                        }
                       
                        var columnAttributes = getColumnAttributes(entSelected, c, logger);

                        metadataList.Add(new SQLMetadata()
                        {
                            entityName = entityName,
                            dataLocation = dataLocation,
                            dataFilePath = dataFilePath,
                            metadataFilePath = metadataFilePath,
                            cdcDataFileFilePath = cdcDataFileFilePath,
                            columnAttributes = columnAttributes
                        });
                    }
                    logger.LogInformation($"Table:{entityName}");

                }
            }
            catch (Exception e)
            {
                manifestHandler.cdmCorpus.Ctx.Events.ForEach(
                           logEntry => logEntry.ToList().ForEach(
                               logEntryPair => logger.LogError($"{logEntryPair.Key}={logEntryPair.Value}")
                           )
                       );
                logger.LogError(e.Message);
                logger.LogError(e.StackTrace);
            }

            bool updateViewSyntax = false;

            // Process entities from entity list file
            if (parentFolder == localRoot && c.ProcessEntities && !String.IsNullOrEmpty(c.ProcessEntitiesFilePath) && File.Exists(c.ProcessEntitiesFilePath))
            {
                string artifactsStr = File.ReadAllText(c.ProcessEntitiesFilePath);
                var entitiesList = JsonConvert.DeserializeObject<IEnumerable<Artifacts>>(artifactsStr);
                logger.LogInformation($"Process Entities");
                foreach (var entity in entitiesList)
                {
                    //update view dependencies
                    updateViewDependencies(entity.Key, entity.Value, metadataList, c, logger);
                }
                updateViewSyntax = true;                
            }

            // Process sub tables and super tables from list file
            if (parentFolder == localRoot && c.ProcessSubTableSuperTables && !String.IsNullOrEmpty(c.ProcessSubTableSuperTablesFilePath) && File.Exists(c.ProcessSubTableSuperTablesFilePath))
            {
                string artifactsStr = File.ReadAllText(c.ProcessSubTableSuperTablesFilePath);
                var subTableSuperTableList = JsonConvert.DeserializeObject<IEnumerable<Artifacts>>(artifactsStr);
                logger.LogInformation($"Process sub tables and super tables");
                foreach (var subTable in subTableSuperTableList)
                {   
                    updateViewsForSubTableSuperTables(subTable.Key, subTable.Value, metadataList, c, logger);
                }
                updateViewSyntax = true;
            }

            // at the end update the view syntax
            if (updateViewSyntax)
            {
                TSqlSyntaxHandler.updateViewSyntax(c, metadataList);
            }

            return true;

        }
        public static string getDataLocation(CdmEntityDeclarationDefinition eDef, string localRoot)
        {
            string dataLocation;
            if (eDef.DataPartitionPatterns.Count > 0)
            {
                var pattern = eDef.DataPartitionPatterns.First();
                dataLocation = localRoot + "/" + pattern.RootLocation + pattern.GlobPattern;
            }
            else if (eDef.DataPartitions.Count > 0)
            {
                dataLocation = eDef.DataPartitions[0].Location;
                string nameSpace = dataLocation.Substring(0, dataLocation.IndexOf(":") + 1);

                if (nameSpace != "")
                {
                    dataLocation = dataLocation.Replace(nameSpace, localRoot);
                }
                else
                {
                    if (dataLocation.StartsWith('/') || localRoot.EndsWith('/'))
                    {
                        dataLocation = localRoot + dataLocation;
                    }
                    else
                    {
                        dataLocation = localRoot + "/" + dataLocation;
                    }

                }
            }
            else
            {
                dataLocation = $"{localRoot}/{eDef.EntityName}/*.*";
            }

            dataLocation = dataLocation.Replace("//", "/");
            string fileName = dataLocation.Substring(dataLocation.LastIndexOf("/") + 1);
            string ext = fileName.Substring(fileName.LastIndexOf("."));
            dataLocation = dataLocation.Replace(fileName, "*" + ext);

            return dataLocation;
        }

        public static List<ColumnAttribute> getColumnAttributes(CdmEntityDefinition entityDefinition, AppConfigurations c, ILogger logger)
        {
            CdmCollection<CdmAttributeItem> cdmAttributeItem = entityDefinition.Attributes;

            IEnumerable<Artifacts> sourceColumnLength = getSourceColumnProperties(entityDefinition.EntityName, c, logger);

            List<ColumnAttribute> columnAttributes = new List<ColumnAttribute>();

            foreach (var attributeItem in cdmAttributeItem)
            {
                CdmTypeAttributeDefinition cdmAttribute = (CdmTypeAttributeDefinition)attributeItem;

                ColumnAttribute columnAttribute = new ColumnAttribute();
                columnAttribute.name = cdmAttribute.Name;
                columnAttribute.description = cdmAttribute.Description;
                columnAttribute.dataType = cdmAttribute.DataType == null ? cdmAttribute.DataFormat.ToString() : cdmAttribute.DataType.NamedReference;

                columnAttribute.maximumLength = cdmAttribute.MaximumLength != null ? (int)cdmAttribute.MaximumLength : c.synapseOptions.DefaultStringLength;
                switch (columnAttribute.dataType.ToLower())
                {
                    case "datetime":
                        columnAttribute.maximumLength = 30;
                        break;

                    case "string":
                        Artifacts TableLenghtException = sourceColumnLength.Where(x => x.Key.ToLower().EndsWith("." + columnAttribute.name.ToLower())).FirstOrDefault();
                        if (TableLenghtException != null)
                        {
                            columnAttribute.maximumLength = Convert.ToInt32(TableLenghtException.Value);
                        }
                        break;
                }
                switch (columnAttribute.name.ToLower())
                {
                    case "_sysrowid":
                        columnAttribute.dataType = "int64";
                        break;
                    case "lsn":
                    case "start_lsn":
                    case "seq_val":
                        columnAttribute.maximumLength = 60;
                        break;
                    case "dml_action":
                        columnAttribute.maximumLength = 15;
                        break;
                    case "update_mask":
                        columnAttribute.maximumLength = 200;
                        break;
                    case "createdby":
                        columnAttribute.maximumLength = 20;
                        break;
                    case "modifiedby":
                        columnAttribute.maximumLength = 20;
                        break;
                }
                var traitsCollection = cdmAttribute.AppliedTraits;

                if (traitsCollection != null && traitsCollection.Where(x => x.NamedReference == "is.constrainedList.wellKnown").Count() > 0)
                {
                    CdmTraitReference trait = cdmAttribute.AppliedTraits.Where(x => x.NamedReference == "is.constrainedList.wellKnown").First() as CdmTraitReference;
                    CdmArgumentDefinition argumentDefinition = trait.Arguments.Where(x => x.Name == "defaultList").First();

                    if (argumentDefinition.Value is CdmEntityReference)
                    {
                        var contEntDef = argumentDefinition.Value.FetchObjectDefinition<CdmConstantEntityDefinition>();
                        if (contEntDef != null)
                        {
                            columnAttribute.constantValueList = contEntDef;
                            columnAttribute.dataType = "int32";
                            //columnAttribute.maximumLength = 10;
                        }
                    }
                }

                columnAttributes.Add(columnAttribute);
            }
            return columnAttributes;
        }

        static void updateViewsForSubTableSuperTables(string subTableName, string superTablesName, List<SQLMetadata> metadata, AppConfigurations configurations, ILogger logger)
        {
            if (!String.IsNullOrEmpty(configurations.AXDBConnectionString))
            {
                SQLHandler sQLHandler = new SQLHandler(configurations.AXDBConnectionString, "", logger);
                //logger.LogInformation($"Retrieving sub table super tables from AXDB connection");
                List<SQLMetadata> viewDependencices = sQLHandler.retrieveSubTableSuperTableView(configurations, superTablesName, subTableName);

                if (viewDependencices != null && viewDependencices.Count > 0)
                {
                    logger.LogInformation($"Sub table: {subTableName}, super tables: {superTablesName}");

                    foreach (var dependency in viewDependencices)
                    {
                        metadata.Add(new SQLMetadata()
                        {
                            entityName = dependency.entityName,
                            viewDefinition = dependency.viewDefinition,
                            dependentTables = dependency.dependentTables
                        });
                    }
                }                
            }            
        }

        static void updateViewDependencies(string entityName, string viewDefinition, List<SQLMetadata> metadata, AppConfigurations configurations, ILogger logger)
        {
            if (!String.IsNullOrEmpty(configurations.AXDBConnectionString))
            {
                SQLHandler sQLHandler = new SQLHandler(configurations.AXDBConnectionString, "", logger);
                // logger.LogInformation($"Retrieving dependencies from AXDB connection");
                List<SQLMetadata> viewDependencices = sQLHandler.retrieveViewDependencies(entityName);

                if (viewDependencices != null && viewDependencices.Count > 0)
                {
                    logger.LogInformation($"Entity:{entityName}, Dependent tables: {viewDependencices.FirstOrDefault().dependentTables}");

                    foreach (var dependency in viewDependencices)
                    {
                        string viewDef = dependency.viewDefinition;

                        if (!String.IsNullOrEmpty(viewDefinition) && dependency.entityName == entityName)
                        {
                            viewDef = viewDefinition;
                        }
                        metadata.Add(new SQLMetadata()
                        {
                            entityName = dependency.entityName,
                            viewDefinition = viewDef,
                            dependentTables = dependency.dependentTables
                        });
                    }
                }
                else if (!String.IsNullOrEmpty(viewDefinition))
                {
                    metadata.Add(new SQLMetadata()
                    {
                        entityName = entityName,
                        viewDefinition = viewDefinition,
                        dependentTables = ""
                    });
                }
            }
            else if (!String.IsNullOrEmpty(viewDefinition))
            {
                metadata.Add(new SQLMetadata()
                {
                    entityName = entityName,
                    viewDefinition = viewDefinition,
                    dependentTables = ""
                });
            }
        }


        public static IEnumerable<Artifacts> getSourceColumnProperties(string entityName, AppConfigurations c, ILogger logger)
        {
            IEnumerable<Artifacts> SourceColumnProperties = null;

            if (String.IsNullOrEmpty(c.AXDBConnectionString))
            {
                if (String.IsNullOrEmpty(c.SourceColumnProperties) == false && File.Exists(c.SourceColumnProperties))
                {
                    string artifactsStr = File.ReadAllText(c.SourceColumnProperties);
                    SourceColumnProperties = JsonConvert.DeserializeObject<IEnumerable<Artifacts>>(artifactsStr);

                    if (SourceColumnProperties != null)
                    {
                        SourceColumnProperties = SourceColumnProperties.Where(x => x.Key.ToLower().StartsWith(entityName.ToLower() + "."));
                    }
                }
            }
            else
            {
                SQLHandler sQLHandler = new SQLHandler(c.AXDBConnectionString, "", logger);
                //  logger.LogInformation("Gettting schema infrormation from AXDB connection");
                string exceptionJson = sQLHandler.getTableMaxFieldLenght(entityName);

                if (String.IsNullOrEmpty(exceptionJson) == false)
                    SourceColumnProperties = JsonConvert.DeserializeObject<List<Artifacts>>(exceptionJson);

            }
            return SourceColumnProperties;
        }

    }
    public class ManifestWriter : ManifestBase
    {
        public ManifestWriter(AdlsContext adlsContext, string currentFolder, ILogger ilogger) : base(adlsContext, currentFolder, ilogger)
        {
        }
        public async Task<bool> createSubManifest(string manifestName, string nextFolder)
        {
            var localRoot = cdmCorpus.Storage.FetchRootFolder("adls");
            bool created = false;
            try
            {
                logger.LogInformation($"creating subManifest {manifestName}");
                CdmManifestDefinition manifest;
                
                try
                {
                    manifest = await cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName + ".manifest.cdm.json");
                }
                catch
                {
                    manifest = cdmCorpus.MakeObject<CdmManifestDefinition>(CdmObjectType.ManifestDef, manifestName + ".manifest.cdm.json");
                    localRoot.Documents.Add(manifest, manifestName + ".manifest.cdm.json");
                }
                
                if (manifest != null)
                {
                    CdmManifestDeclarationDefinition subManifest = null;
                    
                    subManifest = cdmCorpus.MakeObject<CdmManifestDeclarationDefinition>(CdmObjectType.ManifestDeclarationDef, nextFolder, simpleNameRef: false);
                   
                    if (subManifest != null)
                    {
                        subManifest.ManifestName = nextFolder;
                        subManifest.Definition = $"{nextFolder}/{nextFolder}.manifest.cdm.json";

                        //check if the submanifest already exists then return
                        foreach (var sm in manifest.SubManifests)
                        {
                            if (sm.ManifestName == subManifest.ManifestName)
                            {
                                return false;
                            }
                        }

                        manifest.SubManifests.Add(subManifest);
                        created = await manifest.SaveAsAsync($"{manifestName}.manifest.cdm.json");
                    }
                }
            }
            catch (Exception e)
            {
                this.cdmCorpus.Ctx.Events.ForEach(
                         logEntry => logEntry.ToList().ForEach(
                             logEntryPair => logger.LogError($"{logEntryPair.Key}={logEntryPair.Value}")
                         )
                     );
                logger.LogError(e.Message);
                logger.LogError(e.StackTrace);
                logger.LogError(e.Message);
                
            }
            return created;
        }

        public CdmDocumentDefinition CreateDocumentDefinition(CdmEntityDefinition cdmEntityDefinition)
        {
            // Create the document which contains the entity
            var entityDoc = this.cdmCorpus.MakeObject<CdmDocumentDefinition>(CdmObjectType.DocumentDef, $"{cdmEntityDefinition.EntityName}.cdm.json", false);

            entityDoc.Definitions.Add(cdmEntityDefinition);

            return entityDoc;
        }


        public CdmEntityDefinition CreateCdmEntityDefinition(EntityDefinition entityDefinition)
        {

            var cdmEntity = this.cdmCorpus.MakeObject<CdmEntityDefinition>(CdmObjectType.EntityDef, entityDefinition.name, simpleNameRef: false);

            cdmEntity.DisplayName = entityDefinition.description;

            List<dynamic> attributes = entityDefinition.attributes;

            foreach (var a in attributes)
            {
                // Add type attributes to the entity instance
                cdmEntity.Attributes.Add(sqlToCDMAttribute(cdmCorpus, a));
            }
            return cdmEntity;
        }
        public CdmEntityDefinition CreateCdmEntityDefinition(CdmEntityDeclarationDefinition entityDefinition)
        {

            var cdmEntity = this.cdmCorpus.MakeObject<CdmEntityDefinition>(CdmObjectType.EntityDef, entityDefinition.EntityName, simpleNameRef: false);

            cdmEntity.EntityName = entityDefinition.EntityName;
            cdmEntity.DisplayName = entityDefinition.EntityName;

            var entSelected = entityDefinition.Ctx.Corpus.FetchObjectAsync<CdmEntityDefinition>(entityDefinition.EntityPath).Result;

            var attributes = entSelected.Attributes;

            foreach (var a in attributes)
            {
                // Add type attributes to the entity instance
                cdmEntity.Attributes.Add(a);
            }

            return cdmEntity;
        }

        public CdmManifestDefinition addPartition(CdmManifestDefinition manifest, EntityDefinition entityDefinition)
        {
            foreach (CdmEntityDeclarationDefinition eDef in manifest.Entities)
            {
                if (eDef.EntityName.Equals(entityDefinition.name, StringComparison.OrdinalIgnoreCase))
                {
                    var part = cdmCorpus.MakeObject<CdmDataPartitionDefinition>(CdmObjectType.DataPartitionDef, $"{entityDefinition.name}-data");
                    eDef.DataPartitions.Add(part);
                    part.Explanation = "data files";

                    // We have existing partition files for the custom entities, so we need to make the partition point to the file location
                    part.Location = $"{entityDefinition.dataPartitionLocation}/{entityDefinition.partitionPattern}";

                    if (entityDefinition.partitionPattern.Contains("parquet"))
                    {
                        part.ExhibitsTraits.Add("is.partition.format.parquet", false);
                    }
                    //default is csv
                    else
                    {
                        // Add trait to partition for csv params
                        CdmTraitReference csvTrait = part.ExhibitsTraits.Add("is.partition.format.CSV", false) as CdmTraitReference;

                        csvTrait.Arguments.Add("columnHeaders", "false");
                        csvTrait.Arguments.Add("delimiter", ",");
                    }

                }
            }
            return manifest;
        }


        public async Task<bool> createManifest(EntityList entityList, ILogger logger, bool createModelJson = false)
        {
            bool manifestCreated = false;
            string manifestName = entityList.manifestName;
            // Add to root folder.
            var adlsRoot = cdmCorpus.Storage.FetchRootFolder("adls");

            List<EntityDefinition> EntityDefinitions = entityList.entityDefinitions;
            try
            {
                logger.LogInformation($"Initializing manifest {manifestName}.manifest.cdm.json ");

                CdmManifestDefinition manifest;

                try
                {
                    // Read manifest if exists.
                    manifest = cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName + ".manifest.cdm.json").Result;
                }
                catch
                {
                    // Make the temp manifest and add it to the root of the local documents in the corpus
                    manifest = cdmCorpus.MakeObject<CdmManifestDefinition>(CdmObjectType.ManifestDef, manifestName);
                }
                
                // Add an import to the foundations doc so the traits about partitons will resolve nicely
                manifest.Imports.Add(FoundationJsonPath);

                // Add to root folder.
                adlsRoot.Documents.Add(manifest, $"{manifestName}.manifest.cdm.json");
                
                if (manifest != null)
                {
                    foreach (EntityDefinition entityDefinition in EntityDefinitions)
                    {
                        foreach (CdmEntityDeclarationDefinition localEntityDefinition in manifest.Entities.ToList())
                        {
                            if (localEntityDefinition.EntityName.Equals(entityDefinition.name, StringComparison.OrdinalIgnoreCase))
                            {
                                manifest.Entities.Remove(currObject: localEntityDefinition);
                            }
                        }
                    }
                    foreach (EntityDefinition entityDefinition in EntityDefinitions)
                    {
                        logger.LogInformation($"Creating entity {entityDefinition.name} in manifest {manifestName}");
                        var cdmEntityDefinition = this.CreateCdmEntityDefinition(entityDefinition);
                        var cdmEntityDocument = this.CreateDocumentDefinition(cdmEntityDefinition);
                        // Add Imports to the entity document.
                        cdmEntityDocument.Imports.Add(FoundationJsonPath);

                        // Add the document to the root of the local documents in the corpus.
                        adlsRoot.Documents.Add(cdmEntityDocument, cdmEntityDocument.Name);

                        // Add the entity to the manifest.
                        manifest.Entities.Add(cdmEntityDefinition);

                        this.addPartition(manifest, entityDefinition);
                    }

                    logger.LogInformation($"Creating manifest {manifestName}.manifest.cdm.json ");
                    // We can save the documents as manifest.cdm.json format or model.json
                    // Save as manifest.cdm.json 
                    manifestCreated = manifest.SaveAsAsync($"{manifestName}.manifest.cdm.json", true).Result;
                    logger.LogInformation($"{manifestName}.manifest.cdm.json created");
                    // Save as a model.json
                    if (createModelJson)
                    {
                        bool created = manifest.SaveAsAsync("model.json", true).Result;
                        logger.LogInformation("model.json saved");
                    }
                }
            }
            catch (Exception e)
            {
                this.cdmCorpus.Ctx.Events.ForEach(
                          logEntry => logEntry.ToList().ForEach(
                              logEntryPair => logger.LogError($"{logEntryPair.Key}={logEntryPair.Value}")
                          )
                      );
                logger.LogError(e.Message);
                logger.LogError(e.StackTrace);
                logger.LogError(e.Message);
            }
            return manifestCreated;
        }
        public async Task<bool> manifestToModelJson(AdlsContext adlsContext, string manifestName, string localRoot, CdmManifestDefinition modelJson = null, bool root = true)
        {

            ManifestWriter manifestHandler = new ManifestWriter(adlsContext, localRoot, null);
            CdmManifestDefinition manifest;

            if (root)
            {
                // Add to root folder.
                var cdmFolderDefinition = manifestHandler.cdmCorpus.Storage.FetchRootFolder("adls");

                // Read if model.json exists.
                modelJson = await manifestHandler.cdmCorpus.FetchObjectAsync<CdmManifestDefinition>("model.json");
                if (modelJson == null)
                {
                    // Make the temp manifest and add it to the root of the local documents in the corpus
                    modelJson = manifestHandler.cdmCorpus.MakeObject<CdmManifestDefinition>(CdmObjectType.ManifestDef, "model.json");

                    // Add an import to the foundations doc so the traits about partitons will resolve nicely
                    modelJson.Imports.Add(FoundationJsonPath);

                    // Add to root folder.
                    cdmFolderDefinition.Documents.Add(modelJson, $"model.json");
                }
            }

            manifest = await manifestHandler.cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName + ".manifest.cdm.json");
            Console.WriteLine($"Reading Manifest : {manifest.Name}");

            foreach (var submanifest in manifest.SubManifests)
            {
                string subManifestName = submanifest.ManifestName;

                await this.manifestToModelJson(adlsContext, subManifestName, localRoot + '/' + subManifestName, modelJson, false);

            }

            foreach (CdmEntityDeclarationDefinition eDef in manifest.Entities.ToList())
            {
                Console.WriteLine($"Adding Entity : {eDef.EntityName}");
                var cdmEntityDefinition = this.CreateCdmEntityDefinition(eDef);
                var cdmEntityDocument = this.CreateDocumentDefinition(cdmEntityDefinition);
                // Add Imports to the entity document.
                cdmEntityDocument.Imports.Add(FoundationJsonPath);

                // Add the document to the root of the local documents in the corpus.
                var cdmFolderDefinition = modelJson.Ctx.Corpus.Storage.FetchRootFolder("adls");
                cdmFolderDefinition.Documents.Add(cdmEntityDocument, cdmEntityDocument.Name);

                // Add the entity to the manifest.
                modelJson.Entities.Add(cdmEntityDefinition);

                CdmEntityDeclarationDefinition modelJsonEdef = modelJson.Entities.Item(eDef.EntityName);
                if (eDef.DataPartitions.Count > 0)
                {
                    var dataPartition = eDef.DataPartitions.First();
                    dataPartition.Location = manifestName + "/" + dataPartition.Location;
                    modelJsonEdef.DataPartitions.Add(dataPartition);
                }
                if (eDef.DataPartitionPatterns.Count > 0)
                {
                    var DataPartitionPatterns = eDef.DataPartitionPatterns.First();
                    DataPartitionPatterns.RootLocation = manifestName + "/" + DataPartitionPatterns.RootLocation;
                    modelJsonEdef.DataPartitionPatterns.Add(DataPartitionPatterns);
                }
            }
            bool created = false;

            if (root)
            {
                await modelJson.FileStatusCheckAsync();
                created = await modelJson.SaveAsAsync("model.json", true);
            }

            return created;
        }

        public static CdmManifestDeclarationDefinition CreateSubManifestDefinition(CdmCorpusDefinition cdmCorpus, string nextFolder)
        {
            var subManifest = cdmCorpus.MakeObject<CdmManifestDeclarationDefinition>(CdmObjectType.ManifestDeclarationDef, nextFolder, simpleNameRef: false);
            subManifest.ManifestName = nextFolder;
            subManifest.Definition = $"{nextFolder}/{nextFolder}.manifest.cdm.json";

            return subManifest;
        }
        private static CdmTypeAttributeDefinition CreateEntityAttributeWithPurposeAndDataType(CdmCorpusDefinition cdmCorpus, string attributeName, string purpose, string dataType)
        {
            var entityAttribute = CreateEntityAttributeWithPurpose(cdmCorpus, attributeName, purpose);
            entityAttribute.DataType = cdmCorpus.MakeRef<CdmDataTypeReference>(CdmObjectType.DataTypeRef, dataType, true);

            return entityAttribute;
        }
        /// <summary>
        /// Create an type attribute definition instance with provided purpose.
        /// </summary>
        /// <param name="cdmCorpus"> The CDM corpus. </param>
        /// <param name="attributeName"> The directives to use while getting the resolved entities. </param>
        /// <param name="purpose"> The manifest to be resolved. </param>
        /// <returns> The instance of type attribute definition. </returns>
        private static CdmTypeAttributeDefinition CreateEntityAttributeWithPurpose(CdmCorpusDefinition cdmCorpus, string attributeName, string purpose)
        {
            var entityAttribute = cdmCorpus.MakeObject<CdmTypeAttributeDefinition>(CdmObjectType.TypeAttributeDef, attributeName, false);
            entityAttribute.Purpose = cdmCorpus.MakeRef<CdmPurposeReference>(CdmObjectType.PurposeRef, purpose, true);
            return entityAttribute;

        }
        public async static Task<ManifestDefinitions> getManifestDefinition(string artifactsFile, string tableList)
        {
            using (StreamReader r = new StreamReader(artifactsFile))
            {
                string artifactsStr = await r.ReadToEndAsync();
                var artifacts = JsonConvert.DeserializeObject<List<Artifacts>>(artifactsStr);
                string[] tables = tableList.Split(',');
                List<ManifestDefinition> ManifestDefinitions = new List<ManifestDefinition>();

                foreach (string table in tables)
                {
                    string tableName, key, value, manifestName, manifestLocation;

                    tableName = table.Trim();
                    key = "tables:" + tableName.ToLower();

                    var artifact = artifacts.Find(x => x.Key.ToLower().Equals(key));

                    if (artifact != null)
                    {
                        value = artifact.Value;
                    }
                    else
                    {
                        value = "Tables/Custom/" + tableName.ToUpper();
                    }
                    manifestLocation = value.Substring(0, (value.Length - (tableName.Length + 1)));
                    manifestName = manifestLocation.Substring(manifestLocation.LastIndexOf('/') + 1);

                    ManifestDefinition md = new ManifestDefinition();

                    md.TableName = value.Substring(value.LastIndexOf("/") + 1);
                    md.DataLocation = value;
                    md.ManifestLocation = manifestLocation;
                    md.ManifestName = manifestName;

                    ManifestDefinitions.Add(md);
                }
                var grouped = ManifestDefinitions.GroupBy(c => new { c.ManifestLocation, c.ManifestName })
                                                 .Select(g => new
                                                 {
                                                     ManifestLocation = g.Key.ManifestLocation,
                                                     ManifestName = g.Key.ManifestName,
                                                     Tables = g.Select(table => new { table.TableName })
                                                 });

                var mds = new ManifestDefinitions() { Tables = ManifestDefinitions, Manifests = grouped };

                return mds;
            }
        }
        static string sqlToCDMDataType(string sqlDataType)
        {
            string cdmDataType;

            switch (sqlDataType.ToLower())
            {
                case "bigint":
                case "biginteger":
                    cdmDataType = "bigInteger";
                    break;

                case "int":
                case "tinyint":
                case "smallint":
                case "smallinteger":
                    cdmDataType = "smallInteger";
                    break;

                case "datetime":
                case "date":
                    cdmDataType = "date";
                    break;


                case "decimal":
                case "numeric":
                case "real":
                case "float":
                    cdmDataType = "decimal";
                    break;

                case "uniqueidentifier":
                    cdmDataType = "guid";
                    break;
                case "datetimeoffset":
                case "nvarchar":
                case "nchar":
                case "ntext":
                case "varchar":
                case "char":
                case "text":
                    cdmDataType = "string";
                    break;
                case "binary":
                case "varbinary":
                case "image":
                    cdmDataType = "binary";
                    break;
                default:
                    cdmDataType = "string";
                    break;
            }

            return cdmDataType;
        }
        static CdmTypeAttributeDefinition sqlToCDMAttribute(CdmCorpusDefinition cdmCorpus, dynamic columnAttribute)
        {
            CdmTypeAttributeDefinition entityAttribute;
            string name = System.Convert.ToString(columnAttribute.name);
            string dataType = System.Convert.ToString(columnAttribute.dataType);

            if (System.Convert.ToInt32(columnAttribute.IsPrimaryKey) == 1)
            {
                entityAttribute = CreateEntityAttributeWithPurpose(cdmCorpus, name, "identifiedBy");
            }
            else
            {
                entityAttribute = CreateEntityAttributeWithPurpose(cdmCorpus, name, "hasA");
            }

            string cdmType = sqlToCDMDataType(dataType);
            entityAttribute.DataType = cdmCorpus.MakeRef<CdmDataTypeReference>(CdmObjectType.DataTypeRef, cdmType, true);

            if (cdmType.ToLower().Equals("string"))
            {
                if (UseCollat)
                {
                    string collation = $"Collate {DefaultCollation}";

                    if (columnAttribute.collation != null)
                    {
                        collation = $"Collate  {System.Convert.ToString(columnAttribute.collation)}";
                    }
                    entityAttribute.Explanation = collation;
                }

                int maximumLenght = 100;

                if (columnAttribute.maximumLength != null)
                {
                    maximumLenght = System.Convert.ToInt32(columnAttribute.maximumLength);
                }
                entityAttribute.MaximumLength = maximumLenght;

            }
            if (cdmType.ToLower().Equals("decimal"))
            {
                int precision = DefaultPrecison, scale = DefaultScale;

                if (columnAttribute.precision != null && columnAttribute.scale != null)
                {
                    precision = System.Convert.ToInt32(columnAttribute.precision);
                    scale = System.Convert.ToInt32(columnAttribute.scale);
                }

                entityAttribute.Explanation = $"({precision},{scale})";
            }

            return entityAttribute;
        }
    }

    public class ManifestBase
    {
        protected ILogger logger;
        protected EventCallback eventCallback;
        public CdmCorpusDefinition cdmCorpus;
        protected const string FoundationJsonPath = "cdm:/foundations.cdm.json";
        public int DefaultStringLength = 100;
        protected const int DefaultPrecison = 32;
        protected const int DefaultScale = 6;
        protected const bool UseCollat = false;
        protected const string DefaultCollation = "Latin1_General_100_BIN2_UTF8";


        public ManifestBase(AdlsContext adlsContext, string currentFolder, ILogger _logger)
        {
            cdmCorpus = new CdmCorpusDefinition();
            eventCallback = new EventCallback();
            cdmCorpus.SetEventCallback(eventCallback, CdmStatusLevel.Warning);
            logger = _logger;
            this.mountStorage(adlsContext, currentFolder);
        }

        private void mountStorage(AdlsContext adlsContext, string localFolder)
        {

            string firstChar;

            string rootFolder = adlsContext.FileSytemName;

            firstChar = rootFolder.Substring(0, 1);
            if (firstChar != "/")
            {
                rootFolder = "/" + rootFolder;
            }

            firstChar = localFolder.Substring(0, 1);
            if (firstChar != "/")
            {
                localFolder = "/" + localFolder;
            }

            if (rootFolder.EndsWith("/"))
            {
                rootFolder = rootFolder.Remove(rootFolder.Length - 1, 1);
            }
            if (localFolder.EndsWith("/"))
            {
                localFolder = localFolder.Remove(localFolder.Length - 1, 1);
            }

            if (adlsContext.MSIAuth == true)
            {
                MSITokenProvider MSITokenProvider = new MSITokenProvider($"https://{adlsContext.StorageAccount}/", adlsContext.TenantId);

                cdmCorpus.Storage.Mount("adls", new ADLSAdapter(
                  adlsContext.StorageAccount, // Hostname.
                  rootFolder + localFolder, // Root.
                  MSITokenProvider
                ));
            }

            else if (adlsContext.ClientAppId != null && adlsContext.ClientSecret != null)
            {
                cdmCorpus.Storage.Mount("adls", new ADLSAdapter(
                adlsContext.StorageAccount, // Hostname.
                rootFolder + localFolder, // Root.
                adlsContext.TenantId,  // Tenant ID.
                adlsContext.ClientAppId,  // Client ID.
                adlsContext.ClientSecret // Client secret.
              ));
            }
            else if (adlsContext.SharedKey != null)
            {
                cdmCorpus.Storage.Mount("adls", new ADLSAdapter(
              adlsContext.StorageAccount, // Hostname.
              rootFolder + localFolder, // Root.
              adlsContext.SharedKey
                ));
            }

            cdmCorpus.Storage.DefaultNamespace = "adls"; // local is our default. so any paths that start out navigating without a device tag will assume local
        }



    }

}
