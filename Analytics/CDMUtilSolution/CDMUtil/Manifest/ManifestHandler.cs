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
using CDMUtil.SQL;

namespace CDMUtil.Manifest
{
    public class ManifestHandler
    {
        public CdmCorpusDefinition cdmCorpus;
        private const string FoundationJsonPath = "cdm:/foundations.cdm.json";
        private const int DefaultMaxLength = 1000;
        private const int DefaultPrecison = 32;
        private const int DefaultScale = 6;
        private const bool DateTimeAsString = true;
        private const bool UseCollat = false;
        private const string DefaultCollation = "Latin1_General_100_BIN2_UTF8";



        public ManifestHandler(AdlsContext adlsContext, string currentFolder)
        {
            cdmCorpus = new CdmCorpusDefinition();
            this.mountStorage(adlsContext, currentFolder);
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
                MSITokenProvider MSITokenProvider = new MSITokenProvider($"https://{adlsContext.StorageAccount}/");

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

        public async Task<bool> createManifest(EntityList entityList, bool resolveRef = true)
        {
            bool manifestCreated = false;
            string manifestName = entityList.manifestName;

            Console.WriteLine("Make placeholder manifest");
            // Add the temp manifest to the root of the local adapter in the corpus
            var localRoot = cdmCorpus.Storage.FetchRootFolder("adls");

            CdmManifestDefinition manifestAbstract = cdmCorpus.MakeObject<CdmManifestDefinition>(CdmObjectType.ManifestDef, "tempAbstract");
            localRoot.Documents.Add(manifestAbstract, "TempAbstract.manifest.cdm.json");

            // Create two entities from scratch, and add some attributes, traits, properties, and relationships in between
            Console.WriteLine("Create net new entities");

            List<EntityDefinition> EntityDefinitions = entityList.entityDefinitions;

            foreach (EntityDefinition entityDefinition in EntityDefinitions)
            {
                string entityName = entityDefinition.name;
                string entityDesciption = entityDefinition.description;
                // Create the entity definition instance
                var entity = cdmCorpus.MakeObject<CdmEntityDefinition>(CdmObjectType.EntityDef, entityName, false);
                // Add properties to the entity instance
                entity.DisplayName = entityName;
                entity.Version = "1.0.0";
                entity.Description = entityDesciption;

                List<dynamic> attributes = entityDefinition.attributes;

                foreach (var a in attributes)
                {
                    // Add type attributes to the entity instance
                    entity.Attributes.Add(sqlToCDMAttribute(cdmCorpus, a));
                }

                // Create the document which contains the entity
                var entityDoc = cdmCorpus.MakeObject<CdmDocumentDefinition>(CdmObjectType.DocumentDef, $"{entityName}.cdm.json", false);
                // Add an import to the foundations doc so the traits about partitons will resolve nicely
                entityDoc.Imports.Add(FoundationJsonPath);
                entityDoc.Definitions.Add(entity);
                // Add the document to the root of the local documents in the corpus
                localRoot.Documents.Add(entityDoc, entityDoc.Name);
                manifestAbstract.Entities.Add(entity);
            }

            CdmManifestDefinition manifestResolved = await manifestAbstract.CreateResolvedManifestAsync(manifestName, null);

            // Add an import to the foundations doc so the traits about partitons will resolve nicely
            manifestResolved.Imports.Add(FoundationJsonPath);

            foreach (CdmEntityDeclarationDefinition eDef in manifestResolved.Entities)
            {
                // Get the entity being pointed at
                var localEDef = eDef;
                var entDef = await cdmCorpus.FetchObjectAsync<CdmEntityDefinition>(localEDef.EntityPath, manifestResolved);
                var entityDefinition = EntityDefinitions.Find(x => x.name.Equals(entDef.EntityName, StringComparison.OrdinalIgnoreCase));

                if (entityDefinition != null)
                {

                    var part = cdmCorpus.MakeObject<CdmDataPartitionDefinition>(CdmObjectType.DataPartitionDef, $"{entDef.EntityName}-data");
                    eDef.DataPartitions.Add(part);
                    part.Explanation = "data files";

                    // We have existing partition files for the custom entities, so we need to make the partition point to the file location
                    part.Location = $"adls:{entityDefinition.dataPartitionLocation}/{entityDefinition.partitionPattern}";

                    if (entityDefinition.partitionPattern.Contains("parquet"))
                    {
                        part.ExhibitsTraits.Add("is.partition.format.parquet", false);
                    }
                    //default is csv
                    else
                    {
                        // Add trait to partition for csv params
                        var csvTrait = part.ExhibitsTraits.Add("is.partition.format.CSV", false);
                        csvTrait.Arguments.Add("columnHeaders", "false");
                        csvTrait.Arguments.Add("delimiter", ",");
                    }
                }
            }
            Console.WriteLine("Save the documents");
            // We can save the documents as manifest.cdm.json format or model.json
            // Save as manifest.cdm.json
            manifestCreated = await manifestResolved.SaveAsAsync($"{manifestName}.manifest.cdm.json", resolveRef);
            // Save as a model.json
            // await manifestResolved.SaveAsAsync("model.json", true);
            return manifestCreated;
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
        private async static void addExistingEntity(CdmCorpusDefinition cdmCorpus, string manifestName, CdmManifestDefinition manifestDefinition)
        {
            CdmManifestDefinition manifest = await cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName + ".manifest.cdm.json");
            if (manifest != null)
            {
                foreach (CdmEntityDeclarationDefinition eDef in manifest.Entities)
                {
                    // Create the entity definition instance
                    var entity = cdmCorpus.MakeObject<CdmEntityDefinition>(CdmObjectType.EntityDef, eDef.EntityName, false);
                    // Add properties to the entity instance
                    entity.DisplayName = eDef.EntityName;
                    entity.Version = "1.0.0";
                    entity.Description = eDef.EntityName;
                    //manifestAbstract.Entities.Add(entity.EntityName, $"resolved/{eDef.EntityName}.cdm.json/{eDef.EntityName}");


                    var entSelected = await cdmCorpus.FetchObjectAsync<CdmEntityDefinition>(eDef.EntityPath, manifest);
                    foreach (CdmTypeAttributeDefinition attribute in entSelected.Attributes)

                    {
                        //var attributes = CreateEntityAttributeWithPurposeAndDataType(cdmCorpus, attribute.Name, "hasA", attribute.DataType);
                        entity.Attributes.Add(attribute);
                    }
                    // Create the document which contains the entity
                    var entityDoc = cdmCorpus.MakeObject<CdmDocumentDefinition>(CdmObjectType.DocumentDef, $"{eDef.EntityName}.cdm.json", false);
                    // Add an import to the foundations doc so the traits about partitons will resolve nicely
                    entityDoc.Imports.Add(FoundationJsonPath);
                    entityDoc.Definitions.Add(entity);
                    // Add the document to the root of the local documents in the corpus
                    var localRoot = cdmCorpus.Storage.FetchRootFolder("adls");
                    localRoot.Documents.Add(entityDoc, entityDoc.Name);
                    manifestDefinition.Entities.Add(entity);

                }

            }
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

        public async static Task<SQLStatements> CDMToSQL(AdlsContext adlsContext, string storageAccount, string rootFolder, string localFolder, string manifestName, string SAS, string pass, bool createDS)
        {
            SQLStatements statements = new SQLStatements();
            List<SQLStatement> statementsList = new List<SQLStatement>();

            string dataSourceName = "";
            var SQLHandler = new SQLHandler(System.Environment.GetEnvironmentVariable("SQL-On-Demand"));

            var adlsURI = "https://" + storageAccount + rootFolder;

            if (createDS)
            {
                dataSourceName = "sqlOnDemandDS";
                var sqlOnDemand = SQLHandler.createDataSource(adlsURI, dataSourceName, SAS, pass);
            }

            await ManifestHandler.manifestToSQL(adlsContext, manifestName, localFolder, statementsList, dataSourceName);
            statements.Statements = statementsList;

            SQLHandler.executeStatements(statements);

            return statements;
        }
        public async static Task<bool> manifestToSQL(AdlsContext adlsContext, string manifestName, string localRoot, List<SQLStatement> statemensList, string datasourceName = "")
        {
            ManifestHandler manifestHandler = new ManifestHandler(adlsContext, localRoot);
            CdmManifestDefinition manifest = await manifestHandler.cdmCorpus.FetchObjectAsync<CdmManifestDefinition>(manifestName + ".manifest.cdm.json");

            if (manifest == null)
            {
                Console.WriteLine($"Manifest: {manifestName } at Location {localRoot} is invalid");
                return false;
            }

            foreach (var submanifest in manifest.SubManifests)
            {
                string subManifestName = submanifest.ManifestName;

                await manifestToSQL(adlsContext, subManifestName, localRoot + '/' + subManifestName, statemensList, datasourceName);

            }

            foreach (CdmEntityDeclarationDefinition eDef in manifest.Entities)
            {
                string entityName = eDef.EntityName;

                string dataLocation;

                if (eDef.DataPartitions.Count > 0)
                {
                    dataLocation = eDef.DataPartitions[0].Location;
                }
                else
                {
                    dataLocation = $"{localRoot}/{entityName}/*.*";
                }

                string fileName = dataLocation.Substring(dataLocation.LastIndexOf("/") + 1);
                string ext = fileName.Substring(fileName.LastIndexOf("."));
                dataLocation = dataLocation.Replace(fileName, "*" + ext);
                string dataSource = "";
                if (datasourceName == "")
                {
                    localRoot = $"https://{adlsContext.StorageAccount}{adlsContext.FileSytemName}{localRoot}";

                }
                else

                {
                    dataSource = $", DATA_SOURCE = '{datasourceName}'";
                }

                dataLocation = dataLocation.Replace("adls:", localRoot);
                var entSelected = await manifestHandler.cdmCorpus.FetchObjectAsync<CdmEntityDefinition>(eDef.EntityPath, manifest);
                string columnDef = string.Join(", ", entSelected.Attributes.Select(i => CdmTypeToSQl((CdmTypeAttributeDefinition)i))); ;

                var sql = $"CREATE OR ALTER VIEW {entityName} AS SELECT * FROM OPENROWSET(BULK '{dataLocation}', FORMAT = 'CSV', Parser_Version = '2.0' {dataSource}) WITH({columnDef}) as r ";
                statemensList.Add(new SQLStatement() { Statement = sql });

            }
            return true;

        }

        static string cdmToSQLDataType(string dataType)
        {

            string sqlDataType;

            switch (dataType.ToLower())
            {
                case "biginteger":
                case "int64":
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

                    if (DateTimeAsString)
                    {
                        sqlDataType = "varchar(100)";
                    }
                    else
                    {
                        sqlDataType = "datetime2";
                    }
                    break;
                case "decimal":
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
                    sqlDataType = "varchar";
                    break;
                default:
                    sqlDataType = "varchar(1000)";
                    break;
            }

            return sqlDataType;

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

        static string CdmTypeToSQl(CdmTypeAttributeDefinition typeAttributeDefinition)
        {
            string sqlColumnDef;
            string dataType;

            if (typeAttributeDefinition.DataType == null)
            {
                dataType = typeAttributeDefinition.DataFormat.ToString().ToLower();
            }
            else
            {
                dataType = typeAttributeDefinition.DataType.ToString().ToLower();
            }

            int maximumLenght = DefaultMaxLength;

            string decimalPrecisionScale = $"({DefaultPrecison}, {DefaultScale})";

            switch (dataType)
            {
                case "string":

                    if (typeAttributeDefinition.MaximumLength != null)
                    {
                        maximumLenght = (int)typeAttributeDefinition.MaximumLength;

                        if (maximumLenght < 0)
                        {
                            maximumLenght = 8000;
                        }
                    }

                    sqlColumnDef = $"{typeAttributeDefinition.Name} varchar({maximumLenght})";

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
                    sqlColumnDef = $"{typeAttributeDefinition.Name} {cdmToSQLDataType(dataType)}";
                    break;
            }


            return sqlColumnDef;
        }
    }

}
