using System.Net;

namespace StoreMonitoringAlertFunction.Models;

public sealed record AgentFlowResult(
    HttpStatusCode StatusCode,
    string ResponseBody)
{
    public bool IsSuccessStatusCode => (int)StatusCode is >= 200 and <= 299;
}