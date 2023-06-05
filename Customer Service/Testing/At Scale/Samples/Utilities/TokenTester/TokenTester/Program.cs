using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.WebServiceClient;
using Microsoft.Xrm.Tooling.Connector;
using System.Data;
using Microsoft.Data.SqlClient;

namespace TokenTester
{
    class Program
    {
        static void Main(string[] args)
        {

            string accessToken;
            string conn = "AuthType=OAuth;Username=lt.user@msft485.onmicrosoft.com;Password=!Optimize25!;Integrated Security=false;Url=https://orgb37418c9.crm.dynamics.com;AppId=51f81489-12ee-4a9e-aaae-a2591f45987d;RedirectUri=app://58145B91-0C36-4500-8554-080854F2AC97;LoginPrompt=Never";
            string sqlconn = "Server=.;Initial Catalog=loadtest_db;Persist Security Info=False;User ID=sa;Password=P@ssw0rd1;TrustServerCertificate=True;Connection Timeout=20000;";

            {
                
                var service = new CrmServiceClient(conn);

                OrganizationWebProxyClient organizationWebProxyClient = service.OrganizationWebProxyClient;

                accessToken = organizationWebProxyClient.HeaderToken;

                Console.WriteLine(accessToken);
                Console.ReadLine();

            }

            using (SqlConnection mycon = new SqlConnection(sqlconn))
            {
                mycon.Open();
                string query = "select * from systemusers";
                SqlCommand command = new SqlCommand(query, mycon);
                command.CommandTimeout = 20000;

                if (mycon.State == ConnectionState.Open)
                {
                    //object objCount = command.ExecuteScalar();
                    //Int32 count = Convert.ToInt32(objCount);

                    SqlDataReader reader = command.ExecuteReader();

                    if (reader.HasRows)
                    { 
                        while (reader.Read())
                        {
                            Console.WriteLine("{0}\t{1}", 
                                reader.GetGuid(0), 
                                reader.GetString(1));
                        }
                    }
                }
            }
        }
    }
}
