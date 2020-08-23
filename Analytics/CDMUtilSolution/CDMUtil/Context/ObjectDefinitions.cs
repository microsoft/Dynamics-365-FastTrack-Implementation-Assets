using System;
using System.Collections.Generic;
using System.Text;

namespace CDMUtil.Context.ObjectDefinitions
{

    public class EntityList
    {
        public string manifestName { get; set; } // this will store the JSON string
        public List<EntityDefinition> entityDefinitions { get; set; } // this will be the actually list. 
    }
    public class EntityDefinition
    {
        public string name { get; set; } // this will store the JSON string
        public string description { get; set; } // this will store the JSON string
        public string corpusPath { get; set; } // this will store the JSON string
        public string dataPartitionLocation { get; set; } // this will store the JSON string
        public string partitionPattern { get; set; } // this will store the JSON string
        public List<dynamic> attributes { get; set; } // this will be the actually list. 
    }

    public class ColumnAttribute
    {
        public string name;
        public string dataType;
        public int maximumLenght;
        public int precision;
        public int scale;
        public string characterSet;
        public string collation;
        public bool isPrimaryKey;
    }

    public class Artifacts
    {
        public string Key { get; set; }
        public string Value { get; set; }
    }
    public class ManifestDefinition
    {
        public string TableName { get; set; }
        public string DataLocation { get; set; }
        public string ManifestName { get; set; }
        public string ManifestLocation { get; set; }
    }
    public class ManifestDefinitions
    {
        public List<ManifestDefinition> Tables;
        public Object Manifests;
    }
    public class Table
    {
        public string TableName;
    }
    public class Manifests
    {
        public string ManifestLocation { get; set; }
        public string ManifestName { get; set; }
        public List<Table> Tables;
    }
    public class SQLStatement
    {
        public string Statement;
        public bool Created;
        public string Detail;
    }
    public class SQLStatements
    {
        public List<SQLStatement> Statements;
    }
    public class ManifestStatus
    {
        public string ManifestName;
        public bool IsManifestCreated;
    }
}
