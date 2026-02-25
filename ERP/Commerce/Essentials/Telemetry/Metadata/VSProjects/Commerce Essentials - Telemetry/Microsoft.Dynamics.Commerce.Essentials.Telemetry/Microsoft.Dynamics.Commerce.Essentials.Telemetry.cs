/**
* SAMPLE CODE NOTICE
*
* THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
* OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
* THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
* NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
*/


using System;
using System.Collections.Generic;
//using System.Text.Json; // Try to get these
using Newtonsoft.Json;

namespace Microsoft.Dynamics.Commerce.Essentials.Telemetry
{
    public class TelemetryHelper
    {
        dynamic expObj;

        public dynamic ExpObj {get {return expObj;} }

        public TelemetryHelper()
        {
            expObj = new System.Dynamic.ExpandoObject();
        }

        public void add(string name, Object val)
        {
            IDictionary<string, Object> dictView = expObj as IDictionary<string, Object>;

            dictView[name] = val;
        }

        public void delete(string name)
        {
            IDictionary<string, Object> dictView = expObj as IDictionary<string, Object>;

            dictView.Remove(name);
        }

        public string serialize()
        {
            // return JsonSerializer.Serialize(expObj); // System.Text.JSON
            return JsonConvert.SerializeObject(expObj); // Newtonsoft.Json
        }
    }
}
