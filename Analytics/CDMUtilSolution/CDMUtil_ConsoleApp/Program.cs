using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using CDMUtil.Context.ADLS;
using CDMUtil.Context.ObjectDefinitions;
using CDMUtil.Manifest;
using CDMUtil.SQL;
using System.Configuration;

namespace ManifestToSQLView
{
    class Program
    {
        static void Main(string[] args)
        {
            //get data from 
            string storageAccount= ConfigurationManager.AppSettings["StorageAccount"];
            string rootFolder   = ConfigurationManager.AppSettings["RootFolder"];
            string localFolder  = ConfigurationManager.AppSettings["ManifestLocation"];
            string manifestName = ConfigurationManager.AppSettings["ManifestName"];
            var TenantId            = ConfigurationManager.AppSettings["TenantId"];
            var AppId               = ConfigurationManager.AppSettings["AppId"] ;
            var AppSecret           = ConfigurationManager.AppSettings["AppSecret"];
            bool createDS           = System.Convert.ToBoolean(ConfigurationManager.AppSettings["CreateDS"]);
            var SAS                 = ConfigurationManager.AppSettings["SAS"];
            var pass                = ConfigurationManager.AppSettings["Password"];
            
            AdlsContext adlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                TenantId = TenantId,
                ClientAppId = AppId,
                ClientSecret = AppSecret
            };

            var statements =  ManifestHandler.CDMToSQL(adlsContext, storageAccount, rootFolder, localFolder, manifestName, SAS, pass, createDS);


            Console.WriteLine(JsonConvert.SerializeObject(statements));

        }
    }
}
