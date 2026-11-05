using System.Security.Claims;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using TraceParserWeb.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.AspNetCore.Components.Forms;

var tenant = Guid.NewGuid().ToString();
var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> { ["AzureAd:TenantId"]=tenant }).Build();
var store = new ProbeStore();
var auth = new ProbeAuthentication();
// Deliberately synthetic local signing material. BlobClient.GenerateSasUri performs no network I/O.
var options = Options.Create(new EtlImportOptions {
    StorageConnectionString = "DefaultEndpointsProtocol=https;AccountName=synthetic;AccountKey=" + Convert.ToBase64String(new byte[64]),
    ContainerName = "etl-uploads"
});
var service = new RegisteredImportService(store,auth,config,options);
var checks=0;
Check(!service.AdmissionHeld,"admission defaults open without settings changes");
await Reject<UnauthorizedAccessException>(()=>service.RegisterAsync("session","test.etl"));
await Reject<UnauthorizedAccessException>(()=>service.GetAsync(Guid.NewGuid(),default));
auth.User=User(Guid.NewGuid().ToString());
await Reject<UnauthorizedAccessException>(()=>service.RegisterAsync("session","test.etl"));
await Reject<UnauthorizedAccessException>(()=>service.GetAsync(Guid.NewGuid(),default));
Check(store.Calls==0,"tenant checks happen before any storage/SQL operation");
auth.User=User(tenant);
await Reject<ArgumentException>(()=>service.RegisterAsync("","file.etl"));
await Reject<ArgumentException>(()=>service.RegisterAsync("session","file.txt"));
await Reject<ArgumentException>(()=>service.RegisterAsync(new string('s',501),"file.etl"));
var first=await service.RegisterAsync("session","visible-file.etl");
var second=await service.RegisterAsync("session","visible-file.etl");
Check(first.ImportId!=second.ImportId,"same logical upload always registers a fresh source");
Check(first.FileName=="visible-file.etl","displayed filename is preserved");
Check(store.Names.Count==2 && store.Names[0]!=store.Names[1],"fresh paths cannot adopt legacy bytes");
Check(store.Names.All(n=>n.StartsWith("_imports/") && n.EndsWith("/visible-file.etl")),"registered names follow write-once protocol");
var query=Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(new Uri(first.SasUrl).Query);
Check(query["sp"]=="c","browser SAS only grants create, not overwrite/read/delete");
Check(query["spr"]=="https","SAS enforces TLS");
Check(new Uri(first.SasUrl).Scheme=="https","upload destination uses TLS");
store.Result=new(first.ImportId,null,"Registered",false);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.WaitingForFunction,"registered receipt is pending, not complete");
store.Result=new(first.ImportId,42,"Promoting",true);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.RetryableFailure,"interruption is explicit");
store.Result=new(first.ImportId,42,"Binding",false);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.ProcessingDimensions,"bounded bind phase is explicitly nonterminal");
store.Result=new(first.ImportId,null,"RejectedOversize",false);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.RejectedOversize,"oversize receipt is explicitly rejected, not complete");
store.Result=new(first.ImportId,null,"RejectedOversize",true);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.RejectedOversize,"oversize rejection cannot become generic retry progress");
Check(TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes==1_073_741_824,"existing 1 GiB policy is unchanged");
store.Result=new(first.ImportId,42,"Complete",false);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.Complete,"only durable completed phase maps complete");
store.Result=new(first.ImportId,42,"Deleted",false);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.Deleted,"deleted receipt is explicit");
store.Result=new(first.ImportId,42,"Deleting",false);
Check(RegisteredImportService.ToDisplay(await service.GetAsync(first.ImportId,default)).Stage==ImportStage.Deleting,"surviving root is explicit partial deletion");
store.Result=null;
Check((await service.GetAsync(first.ImportId,default)).Phase=="LegacyUntracked","missing receipt is held, never success");
await Reject<ArgumentException>(()=>service.GetAsync(Guid.Empty,default));
auth.User=User(tenant); // No owner claim: all configured-tenant users may inspect receipt status.
store.Result=new(first.ImportId,42,"Complete",false);
Check((await service.GetTraceAsync(42,default))!.Phase=="Complete","tenant-wide status does not require trace ownership");
var noHttp=new UploadBoundaryHttp();
var uploadService=new EtlUploadService(options,noHttp,new TraceService(noHttp,NullLogger<TraceService>.Instance),
    NullLogger<EtlUploadService>.Instance,service);
foreach(var length in new[]{TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes-1,
    TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes,TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes+1})
{
    var file=new UploadBoundaryFile(length);
    var calls=store.Calls;
    if(length>TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes)
    {
        await Reject<ArgumentOutOfRangeException>(()=>uploadService.UploadAsync(file,"synthetic-size"));
        Check(store.Calls==calls && file.StreamLimit is null,"oversize server upload stops before registration, stream or storage");
    }
    else
    {
        await Reject<UploadBoundaryReachedException>(()=>uploadService.UploadAsync(file,"synthetic-size"));
        Check(file.StreamLimit==TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes,"at/below limit server upload retains the existing bounded stream limit");
    }
}
config["UploadAdmission:Hold"]="true";
var heldCalls=store.Calls;
await Reject<UploadAdmissionHeldException>(()=>service.RegisterAsync("session","held.etl"));
await Reject<UploadAdmissionHeldException>(()=>service.RegisterAsync(User(tenant),"session","held.etl",default));
var heldFile=new UploadBoundaryFile(1024);
await Reject<UploadAdmissionHeldException>(()=>uploadService.UploadAsync(heldFile,"held"));
Check(store.Calls==heldCalls && heldFile.StreamLimit is null,"both registration paths stop before SQL, signing and opening upload stream");
var brokenStorageService=new RegisteredImportService(store,auth,config,Options.Create(new EtlImportOptions()));
await Reject<UploadAdmissionHeldException>(()=>brokenStorageService.RegisterAsync("session","held.etl"));
Check((await service.GetAsync(first.ImportId,default)).Phase=="Complete","existing receipt polling continues under hold");
Check((await service.GetTraceAsync(42,default))!.Phase=="Complete","trace status continues under hold");
Check(Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(new Uri(first.SasUrl).Query)["se"]==query["se"],
    "hold does not revoke or extend already-issued SAS expiry");
config["UploadAdmission:Hold"]="false";
Check(!service.AdmissionHeld,"explicit restore reopens admission");
await service.RegisterAsync("restored","restored.etl");
config["UploadAdmission:Hold"]=null;
Check(!service.AdmissionHeld,"removing absent-original setting restores default");
auth.User=new(); // HTTP operations must use their explicit principal, not a Blazor circuit.
checks+=await EndpointChecks.Run(service,tenant,first.ImportId,()=>store.Calls,config);
Console.WriteLine($"{checks} registered-upload boundary checks passed. No network requests or SQL connections.");

ClaimsPrincipal User(string tid)=>new(new ClaimsIdentity([new Claim("tid",tid)],"synthetic"));
void Check(bool ok,string description){if(!ok)throw new Exception(description);checks++;}
async Task Reject<T>(Func<Task> action) where T:Exception
{
    try{await action();}catch(T){checks++;return;}
    throw new Exception("Expected "+typeof(T).Name);
}
sealed class ProbeAuthentication:AuthenticationStateProvider
{
    public ClaimsPrincipal User=new();
    public override Task<AuthenticationState> GetAuthenticationStateAsync()=>Task.FromResult(new AuthenticationState(User));
}
sealed class UploadBoundaryReachedException:Exception;
sealed class UploadBoundaryHttp:IHttpClientFactory
{
    public HttpClient CreateClient(string name)=>throw new Exception("No HTTP request is permitted in upload boundary tests.");
}
sealed class UploadBoundaryFile(long length):IBrowserFile
{
    public string Name=>"synthetic-size.etl";
    public DateTimeOffset LastModified=>DateTimeOffset.UnixEpoch;
    public long Size=>length;
    public string ContentType=>"application/octet-stream";
    public long? StreamLimit { get; private set; }
    public Stream OpenReadStream(long maxAllowedSize=512000,CancellationToken cancellationToken=default)
    {
        StreamLimit=maxAllowedSize;
        throw new UploadBoundaryReachedException();
    }
}
sealed class ProbeStore:IRegisteredImportStore
{
    public int Calls;
    public List<string> Names=[];
    public DurableImportStatus? Result;
    public Task RegisterAsync(Guid id,string account,string container,string blobName,string session,CancellationToken ct)
    {Calls++;Names.Add(blobName);return Task.CompletedTask;}
    public Task<DurableImportStatus?> ReadAsync(Guid? importId,int? traceId,CancellationToken ct)
    {Calls++;return Task.FromResult(Result);}
}
