# Optimize customer account statement printing with Dynamics 365 finance and operations
In Dynamics 365 Finance and Operations, we have out of the box capability to print or email (based on print management setup etc.) customer account statements. Many organizations experience inefficiencies when printing customer account statements if you have large number of customers. Single-threaded printing processes can take several hours to complete, while multi-threaded printing attempts frequently fail and result in errors if you enable ‘Use parallel processing’ as highlighted below.
 
# Cause of the Issue:
A customer account statement controller class utilizes an SRSPrintMgmtController framework, which processes statements by generating bundles and creating batch tasks for every 10 customer accounts. When you have large number of customer accounts, the system attempts to create a batch task for each group of 10 customers, resulting in millions of objects being held in memory, and sometimes it fails without any error. 
This is a batch-retryable process; therefore, batch framework keeps retrying repeatedly—up to five retries—before ultimately failing. This leads to extended error resolution times. Batch job log doesn’t show any error or info.
Sometimes, you filter to run this report based on customer group etc. to manage the number of customers that becomes cumbersome for AR team.

# Explanation (technical):
 In SrsPrintMgmtController class > generateBundles() keeps creating batchHeader, saves into memory. From the code below, we should improve this to save batchHeader.save after creating the batchHeader instead of at the end as highlighted below and parameterize the bundle size. 
 
# Code fix using extension:
Create a new class e.g. SACustAccountStatementExtController by extending it with CustAccountStatementExtController, override generateBundles() to efficiently handle batchHeader creation.
```
Internal final class SACustAccountStatementExtController extends CustAccountStatementExtController 
{ 
	/// <summary> 
	/// Generates “Bundles” child tasks that can be run in parallel on the batch server 
	/// </summary> 
	/// <param name=”_bundleSizeMax”> 
	/// Maximum number of customers to be put in each bundle 
	/// </param> 
	/// <remarks> 
	/// Bundles are split using the recIds of the primary DataSource. If there is a better way to /// split up bundles for a particular report this method should be overridden. 
	/// </remarks> 

protected void generateBundles(int _bundleSizeMax = #DefaultBundleSizeMax)
{ 

BatchHeader batchHeader = BatchHeader::getCurrentBatchHeader(); QueryRun qr = new QueryRun(this.batchParentQuery()); 
RecId recId; 
Set recIds = new Set(Types::Int64); 
Set allRecIds = new Set(Types::Int64);
int bundleCount = 1;
    // Create bundles
	_bundleSizeMax = 50; **//change the bundle size or parameterize it to test and fine-tune based on your volume**
    while(qr.next())
    {
        recId = qr.getNo(1).RecId; // Use primary data source
        
        if(!allRecIds.in(recId))
        {
            recIds.add(recId);
            allRecIds.add(recId);
            
            // As bundle fills up, schedule a task
            if(recIds.elements() >= _bundleSizeMax)
            {
                if (isFlightEnabled(#NoDuplicateBundleFix))
                {
                    batchHeader.addTask(this.newChildReport(recIds, strFmt(“@BI:ChildTaskInMultiThreadedBatchJob”, this.parmReportName(), bundleCount)));
                }
                else
                {
                    batchHeader.addRuntimeTask(this.newChildReport(recIds, strFmt(“@BI:ChildTaskInMultiThreadedBatchJob”, this.parmReportName(), bundleCount)), BatchHeader::getCurrentBatchTask().RecId);
                }
                bundleCount++;
                recIds = new Set(Types::Int64);
                batchHeader.save(); //efficient way to save
            }
        }
    }
    
    if(recIds.elements() > 0)
    {
        if (isFlightEnabled(#NoDuplicateBundleFix))
        {
            batchHeader.addTask(this.newChildReport(recIds, strFmt(“@BI:ChildTaskInMultiThreadedBatchJob”, this.parmReportName(), bundleCount)));
        }
        else
        {
            batchHeader.addRuntimeTask(this.newChildReport(recIds, strFmt(“@BI:ChildTaskInMultiThreadedBatchJob”, this.parmReportName(), bundleCount)), BatchHeader::getCurrentBatchTask().RecId);
        }
        batchHeader.save(); //efficient way to save
    }
    
    
}

public static void main(Args _args)
{
    SrsPrintMgmtFormLetterController controller = new SACustAccountStatementExtController();
    controller.parmReportName(PrintMgmtDocType::construct(PrintMgmtDocumentType::CustAccountStatement).getDefaultReportFormat());
    controller.parmArgs(_args);
    SACustAccountStatementExtController::startControllerOperation(controller, _args);
}

/// <summary>
/// Starts the operation for the given <c>SrsPrintMgmtFormLetterController</c> class instance.
/// </summary>
/// <param name="_controller">
/// <c>SrsPrintMgmtFormLetterController</c> class instance to be started.
/// </param>
/// <param name="_args">
/// <c>Args</c> instance from the main.
/// </param>
protected static void startControllerOperation(SrsPrintMgmtFormLetterController _controller, Args _args)
{
    _controller.startOperation();
}
}
```
Extend CustAccountStatementExt output menu-item and change the object to SACustAccountStatementExtController class (new class name that you created in above step). 
 

# Result:
After this change, batch process doesn’t error out and able to print customer account statement effectively using parallel processing by creating tasks efficiently. You don’t need to break or submit multiple customer account statement batch jobs filtering by customer groups etc. 

