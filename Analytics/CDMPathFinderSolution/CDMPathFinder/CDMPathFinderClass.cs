using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Azure.Storage.Blobs;

namespace CDMPathFinder
{
    class CDMPathFinderClass
    {
        public string ConnectionString { get; set; }
        public string ContainerName { get; set; }
        public string TablesManifestPath { get; set; }

        public CDMPathFinderClass(string connectionString, string containerName, string tablesMainPath)
        {
            ConnectionString = connectionString;
            ContainerName = containerName;
            TablesManifestPath = tablesMainPath;
        }

        public string GetAllTablesPath()
        {
            BlobContainerClient container = new BlobContainerClient(ConnectionString, ContainerName);
            BlobClient client = container.GetBlobClient(TablesManifestPath);
            return this.GetTablesPath(container, TablesManifestPath);
        }


        private string GetTablesPath(BlobContainerClient container, string manifestPath)
        {
            string retVal = String.Empty;
            string[] origRootPathArray = manifestPath.Split('/');
            string[] nextRootPathArray = origRootPathArray.Take(origRootPathArray.Length - 1).ToArray();

            string nextRootPath = string.Join("/", nextRootPathArray) + "/";

            BlobClient client = container.GetBlobClient(manifestPath);
            StreamReader reader = new StreamReader(client.OpenRead());
            string jsonString = reader.ReadToEnd();

            //: \"(.*\/.*\.manifest.cdm.json)\"
            Regex regex = new Regex(": \"(.*\\/.*\\.manifest.cdm.json)\"");
            MatchCollection matchCollection = regex.Matches(jsonString);
            foreach (Match match in matchCollection)
            {
                GroupCollection groups = match.Groups;
                string nextManifers = groups[1].Value;
                retVal += GetTablesPath(container, nextRootPath + nextManifers);
            }
            if (matchCollection.Count == 0)
            {
                regex = new Regex("\"entityName\": \"(\\w*)\"");
                matchCollection = regex.Matches(jsonString);
                foreach (Match match in matchCollection)
                {
                    GroupCollection groups = match.Groups;
                    retVal += nextRootPath + groups[1].Value;
                    retVal += Environment.NewLine;
                }
            }
            return retVal;
        }

    }
}
