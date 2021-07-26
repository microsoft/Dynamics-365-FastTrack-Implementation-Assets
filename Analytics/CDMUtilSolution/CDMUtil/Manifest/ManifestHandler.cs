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

namespace CDMUtil.Manifest
{
    public class ManifestReader : ManifestBase
    {
        public ManifestReader(AdlsContext adlsContext, string currentFolder) : base(adlsContext, currentFolder)
        {
        }
        public async static Task<bool> manifestToSQLMetadata(AdlsContext adlsContext, string manifestName, string localRoot, List<SQLMetadata> metadataList, bool dateTimeAsString = false, bool convertDateTime = false,  List<string> tableList = null)
        {
            ManifestReader manifestHandler = new ManifestReader(adlsContext, localRoot);

            if (manifestName != "model.json" && manifestName.EndsWith(".manifest.cdm.json") == false)
            {
                manifestName = manifestName + ".manifest.cdm.json";
            }

            try
            {
                CdmManifestDefinition manifest =  manifestHandler.cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName, null, null, true).Result;
           
                if (manifest == null)
                {
                    Console.WriteLine($"Manifest: {manifestName } at Location {localRoot} is invalid");
                    return false;
                }

                foreach (var submanifest in manifest.SubManifests)
                {
                    if (tableList != null && tableList.Count == 0)
                        break;
                    string subManifestName = submanifest.ManifestName;
                    string subManifestRoot = localRoot.EndsWith('/') ? localRoot + subManifestName: localRoot + '/' + subManifestName;
                    Console.WriteLine($"Reading Sub-Manifest:{subManifestRoot}");
                    await manifestToSQLMetadata(adlsContext, subManifestName, subManifestRoot, metadataList, dateTimeAsString, convertDateTime, tableList);
                }
                
                Console.WriteLine($"Reading Manifest:{manifest.Name}");

                foreach (CdmEntityDeclarationDefinition eDef in manifest.Entities)
                {
                    string entityName = eDef.EntityName;
                
                    if (tableList != null && tableList.Count == 0)
                        break;
                    else if (tableList.First() != "*" && !tableList.Contains(entityName))
                        continue;
                    else
                        tableList.Remove(entityName);

                    var entSelected =  manifestHandler.cdmCorpus.FetchObjectAsync<CdmEntityDefinition>(eDef.EntityPath, manifest).Result;

                    Console.WriteLine($"Reading Entity:{entityName}");

                    if (entSelected.ExhibitsTraits.Count() > 1 && entSelected.ExhibitsTraits.Where(x => x.NamedReference == "has.sqlViewDefinition").Count() > 0)
                    {
                        // Custom traits sqlViewDefinition exists
                        var trait = entSelected.ExhibitsTraits.Where(x => x.NamedReference == "has.sqlViewDefinition").First();
                        CdmTraitReference cdmTrait = trait as CdmTraitReference;

                        if (cdmTrait != null)
                        {
                            string viewDefinition = cdmTrait.Arguments.First().Value;

                            metadataList.Add(new SQLMetadata()
                            {
                                entityName = entityName,
                                viewDefinition = viewDefinition
                            });
                        }

                    }
                    else
                    {
                        string dataLocation = getDataLocation(eDef, localRoot);

                        string dataFilePath = "https://" + Regex.Replace($"{adlsContext.StorageAccount}/{adlsContext.FileSytemName}/{dataLocation}", @"/+", @"/");
                        string metadataFilePath = "https://" + Regex.Replace($"{adlsContext.StorageAccount}/{adlsContext.FileSytemName}/{localRoot}/{localRoot.Remove(localRoot.Length - 1).Split('/').Last()}.manifest.cdm.json", @"/+", @"/");
                        string cdcDataFileFilePath = "https://" + Regex.Replace($"{adlsContext.StorageAccount}/{adlsContext.FileSytemName}/ChangeFeed/{entityName}/*.csv", @"/+", @"/");

                        string columnDef = string.Join(", ", entSelected.Attributes.Select(i => CdmTypeToSQl((CdmTypeAttributeDefinition)i, dateTimeAsString)));

                        string  columnNames = string.Join(", ", entSelected.Attributes.Select(i => CdmAttributeToColumnNames((CdmTypeAttributeDefinition)i, convertDateTime)));
                 
                        metadataList.Add(new SQLMetadata()
                        {
                            entityName = entityName,
                            columnDefinition = columnDef,
                            dataLocation = dataLocation,
                            columnNames = columnNames,
                            dataFilePath = dataFilePath,
                            metadataFilePath = metadataFilePath,
                            cdcDataFileFilePath = cdcDataFileFilePath
                        });
                    }


                }
            }
            catch (Exception e)
            {
                Console.WriteLine(e.Message);
                Console.WriteLine(e.StackTrace);
            }
            return true;
            
        }
        static string getDataLocation(CdmEntityDeclarationDefinition eDef, string localRoot)
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
        static string cdmToSQLDataType(string dataType, bool dateTimeAsString = false)
        {

            string sqlDataType;

            switch (dataType.ToLower())
            {
                case "biginteger":
                case "int64":
                case "bigint":
                    sqlDataType = "bigInt";
                    break;
                case "smallinteger":
                case "int":
                case "int32":
                    sqlDataType = "bigInt";
                    break;
                case "date":
                case "datetime":
                case "datetime2":

                    if (dateTimeAsString)
                    {
                        sqlDataType = "nvarchar(30)";
                    }
                    else
                    {
                        sqlDataType = "datetime2";
                    }
                    break;
                case "decimal":
                case "double":
                    sqlDataType = "decimal";
                    break;
                case "boolean":
                    sqlDataType = "tinyint";
                    break;
                case "guid":
                    sqlDataType = "uniqueidentifier";
                    break;
                case "binary":
                    sqlDataType = "binary";
                    break;
                case "string":
                    sqlDataType = "nvarchar";
                    break;
                default:
                    sqlDataType = "nvarchar(100)";
                    break;
            }

            return sqlDataType;

        }
        static string CdmTypeToSQl(CdmTypeAttributeDefinition typeAttributeDefinition, bool dateTimeAsString = false)
        {
            string sqlColumnDef;
            string dataType;


            if (typeAttributeDefinition.DataType == null)
            {
                dataType = typeAttributeDefinition.DataFormat.ToString().ToLower();
            }
            else
            {
                dataType = typeAttributeDefinition.DataType.NamedReference.ToLower();
            }


            int maximumLenght = DefaultMaxLength; 
            
            if (typeAttributeDefinition.Name.ToLower() == "lsn" ||
                typeAttributeDefinition.Name.ToLower() == "start_lsn" ||
                typeAttributeDefinition.Name.ToLower() == "seq_val" )
            {
                maximumLenght = 50;
            }
            if (typeAttributeDefinition.Name.ToLower() == "dml_action" ||
                typeAttributeDefinition.Name.ToLower() == "update_mask")
            {
                maximumLenght = 5;
            }
            if (typeAttributeDefinition.Name.ToLower() == "dataareaid")
            {
                maximumLenght = 5;
            }
           
            string decimalPrecisionScale = $"({DefaultPrecison}, {DefaultScale})";

            switch (dataType)
            {
                case "string":

                    if (typeAttributeDefinition.MaximumLength != null)
                    {
                        maximumLenght = (int)typeAttributeDefinition.MaximumLength;

                        if (maximumLenght < 0)
                        {
                            maximumLenght = 4000;
                        }
                    }

                    sqlColumnDef = $"{typeAttributeDefinition.Name} nvarchar({maximumLenght})";

                    if (UseCollat)
                    {
                        string collation = $"Collate {DefaultCollation}";

                        if (typeAttributeDefinition.Explanation != null)
                        {
                            collation = typeAttributeDefinition.Explanation;
                        }
                        sqlColumnDef = $" {sqlColumnDef}  {collation}";
                    }

                    break;
                case "decimal":

                    if (typeAttributeDefinition.Explanation != null)
                    {
                        decimalPrecisionScale = typeAttributeDefinition.Explanation;
                    }

                    sqlColumnDef = $"{typeAttributeDefinition.Name} decimal {decimalPrecisionScale}";
                    break;
                default:
                    sqlColumnDef = $"{typeAttributeDefinition.Name} {cdmToSQLDataType(dataType, dateTimeAsString)}";
                    break;
            }


            return sqlColumnDef;
        }
        static string CdmAttributeToColumnNames(CdmTypeAttributeDefinition typeAttributeDefinition, bool convertDatetime = false)
        {
            string sqlColumnNames;
            string dataType;

            if (typeAttributeDefinition.DataType == null)
            {
                dataType = typeAttributeDefinition.DataFormat.ToString().ToLower();
            }
            else
            {
                dataType = typeAttributeDefinition.DataType.NamedReference.ToLower();
            }

            switch (dataType)
            {
                case "date":
                case "datetime":
                case "datetime2":
                    if (convertDatetime)
                    {
                        sqlColumnNames = $" TRY_CONVERT(DATETIME2, {typeAttributeDefinition.Name}, 102) as {typeAttributeDefinition.Name}";
                    }
                    else
                    {
                        sqlColumnNames = $"{typeAttributeDefinition.Name}";
                    }
                    break;
                case  "string":
                    sqlColumnNames = $"{typeAttributeDefinition.Name}";
                    // Custom traits sqlViewDefinition exists
                    var traitsCollection = typeAttributeDefinition.AppliedTraits;

                    if (traitsCollection.Where(x => x.NamedReference == "is.constrainedList.wellKnown").Count()>0)
                    {
                        
                       CdmTraitReference trait = typeAttributeDefinition.AppliedTraits.Where(x => x.NamedReference == "is.constrainedList.wellKnown").First() as CdmTraitReference;
           
                        CdmArgumentDefinition argumentDefinition = trait.Arguments.Where(x => x.Name == "defaultList").First();
                        
                        if (argumentDefinition.Value is CdmEntityReference)
                        {
                            var contEntDef = argumentDefinition.Value.FetchObjectDefinition<CdmConstantEntityDefinition>();
                            sqlColumnNames = $"CASE {typeAttributeDefinition.Name} "; 
                            foreach (List<string> constantValueList in contEntDef.ConstantValues)
                            {
                                sqlColumnNames += $"{ " When " + constantValueList[3] + " Then '" + constantValueList[2]}'";
                            }
                            sqlColumnNames += $" END AS {typeAttributeDefinition.Name}";
                        }
                       
                    }

                    break;
                default:
                    sqlColumnNames = $"{typeAttributeDefinition.Name}";
                    break;
            }


            return sqlColumnNames;
        }

        
    }
    public class ManifestWriter : ManifestBase
    {
        public ManifestWriter(AdlsContext adlsContext, string currentFolder) : base(adlsContext, currentFolder)
        {
        }
        public async Task<bool> createSubManifest(string manifestName, string nextFolder)
        {
            var localRoot = cdmCorpus.Storage.FetchRootFolder("adls");
            bool created = false;

            CdmManifestDefinition manifest = await cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName + ".manifest.cdm.json");

            if (manifest == null)
            {
                manifest = cdmCorpus.MakeObject<CdmManifestDefinition>(CdmObjectType.ManifestDef, manifestName);
                localRoot.Documents.Add(manifest, manifestName + ".manifest.cdm.json");
            }

            var subManifest = cdmCorpus.MakeObject<CdmManifestDeclarationDefinition>(CdmObjectType.ManifestDeclarationDef, nextFolder, simpleNameRef: false);
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


        public async Task<bool> createManifest(EntityList entityList, bool createModelJson = false)
        {

            bool manifestCreated = false;
            string manifestName = entityList.manifestName;
            // Add to root folder.
            var adlsRoot = cdmCorpus.Storage.FetchRootFolder("adls");

            List<EntityDefinition> EntityDefinitions = entityList.entityDefinitions;

            // Read manifest if exists.
            CdmManifestDefinition manifest =  cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName + ".manifest.cdm.json").Result;

            if (manifest == null)
            {
                // Make the temp manifest and add it to the root of the local documents in the corpus
                manifest = cdmCorpus.MakeObject<CdmManifestDefinition>(CdmObjectType.ManifestDef, manifestName);

                // Add an import to the foundations doc so the traits about partitons will resolve nicely
                manifest.Imports.Add(FoundationJsonPath);

                // Add to root folder.
                adlsRoot.Documents.Add(manifest, $"{manifestName}.manifest.cdm.json");

            }
            else
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
            }

            foreach (EntityDefinition entityDefinition in EntityDefinitions)
            {
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

            Console.WriteLine("Save the documents");
            // We can save the documents as manifest.cdm.json format or model.json
            // Save as manifest.cdm.json 
            manifestCreated = manifest.SaveAsAsync($"{manifestName}.manifest.cdm.json", true).Result;

            // Save as a model.json
            if (createModelJson)
            {
                bool created = manifest.SaveAsAsync("model.json", true).Result;
                Console.WriteLine("model.json saved");
            }

            return manifestCreated;
        }
        public async Task<bool> manifestToModelJson(AdlsContext adlsContext, string manifestName, string localRoot, CdmManifestDefinition modelJson = null, bool root = true)
        {

            ManifestWriter manifestHandler = new ManifestWriter(adlsContext, localRoot);
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
                case "datetimeoffset":
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

                int maximumLenght = DefaultMaxLength;

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
        public CdmCorpusDefinition cdmCorpus;
        protected const string FoundationJsonPath = "cdm:/foundations.cdm.json";
        protected const int DefaultMaxLength = 100;
        protected const int DefaultPrecison = 32;
        protected const int DefaultScale = 6;
        protected const bool UseCollat = false;
        protected const string DefaultCollation = "Latin1_General_100_BIN2_UTF8";
        protected const string dataSourceName = "sqlOnDemandDS";

        public ManifestBase(AdlsContext adlsContext, string currentFolder)
        {
            cdmCorpus = new CdmCorpusDefinition();
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
