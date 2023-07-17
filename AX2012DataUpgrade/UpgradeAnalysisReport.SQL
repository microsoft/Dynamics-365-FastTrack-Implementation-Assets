--
-- This source code or script is freeware and is provided on an "as is" basis without warranties of any kind, 
-- whether express or implied, including without limitation warranties that the code is free of defect, fit for a particular purpose or non-infringing.
-- The entire risk as to the quality and performance of the code is with the end user.
--

--
-- AX 2012 to D365 Upgrade Analysis Report
--
-- Please run the script against your AX 2012 database
-- Results may be copied into a spreadsheet 
--

IF(OBJECT_ID('tempdb..#D365UpgradeAnalysisReport') IS NOT NULL)
BEGIN 
	DROP TABLE #D365UpgradeAnalysisReport
END

CREATE TABLE #D365UpgradeAnalysisReport (
    RuleID INT,
	RuleSection NVARCHAR(100),
    RuleName NVARCHAR(100),
    Observation NVARCHAR(MAX),
	Recommendation NVARCHAR(MAX),
	AdditionalComments NVARCHAR(MAX)
);

DECLARE @RuleID INT;
DECLARE @RuleSection NVARCHAR(100);
DECLARE @RuleName NVARCHAR(500);
DECLARE @Observation NVARCHAR(MAX);
DECLARE @AdditionalComments NVARCHAR(MAX);
DECLARE @Recommendation NVARCHAR(MAX);

--
-- Tuning Parameters
--
DECLARE @LargeTableThreshold INT = 10000 -- Threshold for large table analysis (in MB)
DECLARE @EstimatedSavingThreshold INT = 100 -- Threshold for data cleanup operations (in MB)

--
-- Rule Section: Deprecated Features 
--
SET @RuleSection = 'Deprecated Features';

	--
	-- Rule: Upgrade Deprecated feature Virtual companies
	--
	SET @RuleID = 100
	SET @RuleName = 'Upgrade Deprecated feature Virtual companies';
	SET @Observation  = 'The virtual companies feature is deprecated in Dynamics 365 for Operations. This rule has identified that virtual companies exist in the AX2012 environment. This configuration will not function in Dynamics 365 for Operations.';
	SET @Recommendation  = 'Look at the cross company data sharing feature in Dynamics 365 for Operations: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/sysadmin/cross-company-data-sharing';
	SET @AdditionalComments  = '';
	IF((SELECT COUNT(*) AS TotalActiveVirtualCompanies FROM DataArea WHERE IsVirtual = 1) > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END


	--
	-- Rule: Upgrade Deprecated tables
	--
	SET @RuleID = 105
	SET @RuleName = 'Upgrade Deprecated tables';
	SET @Observation  = 'The tables listed are deprecated in Dynamics 365 for Operations. This rule has identifed data exists in one or more of these tables, please ensure either this data is not required or write a customization  to move the data. Tables: ';
	SET @Recommendation  = 'A developer should review the output of this rule to determine whether data is required and write custom code to retain the data is necessary.';
	SET @AdditionalComments  = '';
	DECLARE @deprecatedTables NVARCHAR(MAX)
	DECLARE @tablename NVARCHAR(256), @indexName NVARCHAR(256)
	DECLARE @sql NVARCHAR(MAX)
	DECLARE @xml XML
	SET @deprecatedTables = 'BankBorderoPaymTrans_BR,BankBorderoReport_BR,BankBorderoTable_BR,BankFileArchFileTypeTable,BankFileArchParameters,BankIBSLog_BE,BankIBSLogArchive_BE,BankStmtISODiscrepancy,BorderoNumberSequenceTable_BR,BudgetPlanMatrixField,CustEgiroFtxAnalyse,CustEgiroParameters,CustEgiroSegmentTrans,CustEinvoiceDatasource,CustEinvoiceLines,CustEinvoiceTable,ECPCustSignUp,'
	SET @deprecatedTables = @deprecatedTables + 'ECPParameters,ECPPresentation,EMSAssignment,EMSConversion,EMSConversionFlowRelation,EMSConversionLine,EMSConversionProcessRelation,EMSDailyFlow,EMSFlow,EMSFlowBudget,EMSInvoiceRegisterFlowRelation,EMSMapFilterProcess,EMSMapFilterSubstance,EMSMapFilterSubstanceCategory,EMSMapPosition,EMSMeter,EMSMeterFlowRelation,EMSMeterReading,EMSParameter,'
	SET @deprecatedTables = @deprecatedTables + 'EMSProcess,EMSProcessEquityShare,EMSProcessMap,EMSProcessReference,EMSProcessRelation,EMSPurchOrderFlowRelation,EMSSubstance,EMSSubstanceCategory,ESSActivitySite,EUSalesListReportingAmountSource,EUSalesListReportingLineAmount,FBGiaSetupParameters_BR,FBGiaStSetupParameters_BR,FBSintegraParameters_BR,FBStageAssetDepreciationTrans_BR,'
	SET @deprecatedTables = @deprecatedTables + 'FBStageBundleTask_BR,FBStageChangeLog_BR,FBStageCIAPAssetTable_BR,FBStageCIAPFiscalDocumentLine_BR,FBStageFiscalDocument_BR,FBStageFiscalDocumentComplInfo_BR,FBStageFiscalDocumentInstallment_BR,FBStageFiscalDocumentLine_BR,FBStageFiscalDocumentRefProcess_BR,FBStageFiscalReceipt_BR,FBStageFiscalReceiptLine_BR,FBStageIntegratedFiscalDocument_BR,'
	SET @deprecatedTables = @deprecatedTables + 'FBStageInventBalance_BR,FBStageNonFiscalOperation_BR,FBStageNonFiscalOpReferencedProcess_BR,FBStageNonFiscalOpTaxTrans_BR,FBStageReferencedFiscalDocument_BR,FBStageRetailZReport_BR,FBStageRetailZReportTotalizer_BR,FBStageRetailZReportTotalizerTaxTrans_BR,FBStageTaxWithholdTrans_BR,FBStageValidationLog_BR,FBStageValidationMessageLog_BR,'
	SET @deprecatedTables = @deprecatedTables + 'FBTaxStatement_BR,HcmEmploymentBonus,HcmEmploymentInsurance,HcmEmploymentStockOption,HcmGoalType,HcmGoalTypeTemplate,HcmIncomeTaxCategory,HcmIncomeTaxCode,HcmInsuranceType,HcmPayrollBasis,HcmPayrollCategory,HcmPayrollDeduction,HcmPayrollDeductionType,HcmPayrollFrame,HcmPayrollFrameCategory,HcmPayrollLine,HcmPayrollPension,HcmPayrollPremium,'
	SET @deprecatedTables = @deprecatedTables + 'HcmPayrollScaleLevel,HcmReminderType,HcmWorkerAction,HcmWorkerActionCompEmpl,HcmWorkerActionEmployment,HcmWorkerActionHire,HcmWorkerActionTerminate,HcmWorkerReminder,HcmWorkerTaxInfo,HRMCompPayrollEntity,IntrastatReportHeader,IntrastatReportLines,IntrastatServicePoint_FI,LedgerAuditFileTransactionLog_NL,LedgerBalanceSheetDimFileFormat,'
	SET @deprecatedTables = @deprecatedTables + 'LedgerBalColumnsDim,LedgerBalColumnsDimQuery,LedgerBalHeaderDim,LedgerChartOfAccountsStructure,LedgerCheckListSetup_CN,LedgerGDPdUField,LedgerGDPdUGroup,LedgerGDPdURelation,LedgerGDPdUTable,LedgerGDPdUTableSelection,LedgerOpenCloseTerm_BR,LedgerRowDef,LedgerRowDefErrorLog,LedgerRowDefLine,LedgerRowDefLineCalc,LedgerRRGECommonSectionLines_W,'
	SET @deprecatedTables = @deprecatedTables + 'LedgerRRGECommonSections_W,LedgerRRGEDConfigurations_W,LedgerRRGEDelimiters_W,LedgerRRGEDIdentifiers_W,LedgerRRGEDocuments_W,LedgerRRGEDocumentVersions_W,LedgerRRGEDParameters_W,LedgerRRGEDSendRecvLog_W,LedgerRRGEDSendStatuses_W,LedgerRRGEExpressionLines_W,LedgerRRGEFormatPeriods_W,LedgerRRGEHistoryCompare_W,LedgerRRGEPatternValue_W,'
	SET @deprecatedTables = @deprecatedTables + 'LedgerRRGEPermissibleValue_W,LedgerRRGEProperties_W,LedgerRRGEPropertyCells_W,LedgerRRGEPropertyLayoutLines_W,LedgerRRGEPropertyLayouts_W,LedgerRRGEPropertyVersions_W,LedgerRRGEQueries_W,LedgerRRGERequisiteTypes_W,LedgerRRGESectionProperties_W,LedgerRRGETableColumns_W,LedgerRRGETableLayouts_W,LedgerRRGETempFiles_W,LedgerRRGETemplates_W,'
	SET @deprecatedTables = @deprecatedTables + 'LedgerRRGETemplateSections_W,LedgerXBRLProperties,LvPaymentOrderInfo,LvPayOrderSubAmount,NoSaleFiscalDocumentTransaction_BR,PBABOMRouteOccurrence,PBACustGroup,PBADefault,PBADefaultRoute,PBADefaultRouteTable,PBADefaultVar,PBAGraphicParameters,PBAGraphicParametersInterval,PBAGraphicParametersVariable,PBAGroup,PBAInventItemGroup,PBALanguageTxt,'
	SET @deprecatedTables = @deprecatedTables + 'PBAParameters,PBAReuseBOMRoute,PBARule,PBARuleAction,PBARuleActionValue,PBARuleActionValueCode,PBARuleActionValueCodeParm,PBARuleClause,PBARuleClauseSet,PBARuleClauseVersion,PBARuleCodeCompiled,PBARuleDebuggerTable,PBARuleLine,PBARuleLineCode,PBARuleLineCodeParm,PBARuleLineSimple,PBARulePBAId2ConsId,PBARuleTableConstraint,'
	SET @deprecatedTables = @deprecatedTables + 'PBARuleTableConstraintColumn,PBARuleTableConstraintRef,PBARuleVariable,PBARuleVariableLine,PBATable,PBATableGenerateItemId,PBATableGenerateItemVariables,PBATableGroup,PBATableInstance,PBATablePrice,PBATablePriceCurrencySetup,PBATablePriceSetup,PBATablePriceSetupCode,PBATableVariable,PBATableVariableDefaultVal,PBATableVariableVal,PBATreeBOM,'
	SET @deprecatedTables = @deprecatedTables + 'PBATreeCase,PBATreeCode,PBATreeDefault,PBATreeDocRef,PBATreeFor,PBATreeInfoLog,PBATreeInventDim,PBATreeNode,PBATreeRoute,PBATreeRouteOpr,PBATreeSimpel,PBATreeSwitch,PBATreeTable,PBATreeTableSelect,PBATreeTableVal,PBAUserProfiles,PBAUserProfileUserRelation,PBAVariable,PBAVariableVal,PBAVarPBAProfiles,PBAVersion,PlInventExternalForProcessing,'
	SET @deprecatedTables = @deprecatedTables + 'PlInventJournalExternal,PlInventPackingSlipExtJour,PlInventPackingSlipExtTrans,PlInventSumExternal,PlInventTransExternal,ProdReceiptFinalizeBatchWorkItem,ProjServerParameters,ProjServerSettings,ReqDemPlanAccuracyForecast,ReqDemPlanForecastSSASParameters,RetailEFDocumentToBeInquired_BR,RetailFiscalDocumentLegalText_BR,'
	SET @deprecatedTables = @deprecatedTables + 'RetailFiscalDocumentReference_BR,SyncActivityCategoryLookup,SyncApp,SyncAppCompany,SyncCompanyLookup,SyncCompoundDataTrans,SyncCompoundDependTrans,SyncCompoundTrans,SyncCompoundType,SyncCustTableLookup,SyncErrorDataTrans,SyncHierarchyTreeTable,SyncIntegratedFields,SyncParameters,SyncProjActivityAssignment,SyncProjDailyTransaction,'
	SET @deprecatedTables = @deprecatedTables + 'SyncProjGroupLookup,SyncProjInvoiceTableLookup,SyncProjResource,SyncProjStatusLookup,SyncProjTable,SyncProjTransaction,SyncProjTypeLookup,SyncSimpleTrans,SyncSimpleType,SyncSimpleTypeKey,SyncSimpleTypeTable,SyncWrkCtrTable,SysManagedCodeAccessSpecifierInfo,SysManagedCodeCodeCommentInfo,SysManagedCodeExpression,SysManagedCodeExpressionMethodCallInfo,'
	SET @deprecatedTables = @deprecatedTables + 'SysManagedCodeExpressionParameter,SysManagedCodeExpressionPropertyCallInfo,SysManagedCodeMethod,SysManagedCodeMethodAccessSpecifirInfo,SysManagedCodeNamespace,SysManagedCodeNamespaceImport,SysManagedCodeProperty,SysManagedCodePropertyAccessSpecifirInfo,SysManagedCodeStatement,SysManagedCodeType,SysManagedCodeTypeAccessSpecifirInfo,'
	SET @deprecatedTables = @deprecatedTables + 'SysManagedCodeVariable,SysManagedCodeVariableAccessSpecifirInfo,TaxEdivatConfiguration,TaxEdivatErrors,TaxEdivatGeneral,TaxEdivatReturnedErrors,TaxExternalInvoice_CN,TaxExternalProjectInvoice,TaxExternalSalesInvoice_CN,TaxReportCodeCalculation_CZ,TaxReportXmlAttribute_CZ,TaxReportXmlElement_CZ,TaxTexts_FI,TaxYearlyComSetupExclude_IT,'
	SET @deprecatedTables = @deprecatedTables + 'TrvCarRentalCharge,TrvDisputeReasonCodeMaster,TrvDisputes,TrvEnhancedTaxInfo,TrvHotelCharge,TrvItineraryCharge,TrvTaxCharge,TSTimesheetLineComments,TutorialJournalName,TutorialJournalTable,TutorialJournalTrans,VendInternalIntraCommunityInvoice,VendOutPaymForParams_FI,XBRLTaxonomy,XBRLTaxonomyArc,XBRLTaxonomyComplexType,XBRLTaxonomyComplexTypeValue,'
	SET @deprecatedTables = @deprecatedTables + 'XBRLTaxonomyElement,XBRLTaxonomyElementValue,XBRLTaxonomyExtendedLink,XBRLTaxonomyFile,XBRLTaxonomyLabelElement,XBRLTaxonomyLines,XBRLTaxonomyLocator,XBRLTaxonomyReferenceElement,XBRLTaxonomyTable'
	SET @deprecatedTables = REPLACE(@deprecatedTables,' ', '')
	SET @xml = (SELECT CAST('<cr>'+REPLACE(@deprecatedTables, ',', '</cr><cr>')+'</cr>' AS XML) AS STRING) 

	IF(OBJECT_ID('tempdb..#tempDeprecatedTables') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempDeprecatedTables
	END

	CREATE TABLE #tempDeprecatedTables
	(
		TableName VARCHAR(50)
	)

	DECLARE tableCursor CURSOR FOR 
		select t.value('.','varchar(max)') as DEPRECATEDTABLES from @xml.nodes('//cr') as a(t);
	OPEN tableCursor;
	FETCH NEXT FROM tableCursor INTO @tablename;
	WHILE @@FETCH_STATUS = 0
		BEGIN
			IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @tablename))
			BEGIN
				SET @sql = 'if((select count(@@ROWCOUNT) from ' + @tablename + ') > 0) insert into #tempDeprecatedTables values(''' + @tablename + ''')'
				EXEC (@SQL)
			END
			FETCH NEXT FROM tableCursor INTO @tablename;
		END
	CLOSE tableCursor;
	DEALLOCATE tableCursor;

	IF((SELECT COUNT(*) AS TotalDeprecatedTables FROM #tempDeprecatedTables) > 0)
	BEGIN
		SET @Observation = @Observation +  (SELECT TOP 1 STUFF((SELECT ', ' + TableName FROM #tempDeprecatedTables FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS ConcatenatedString FROM #tempDeprecatedTables)
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Partition validation
	--
	SET @RuleID = 110
	SET @RuleName = 'Upgrade Partition validation';
	SET @Observation  = 'Dynamics 365 for Operations does not support multiple partitions. This rule has identified multiple partitions exist in the AX2012 environment. This means that upgrade to Dynamics 365 for Operations is not possible.';
	SET @Recommendation  = '';
	SET @AdditionalComments  = '';
	IF((SELECT COUNT(*) AS TotalPartitions FROM Partitions) > 1)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END


--
-- Rule Section: Application Settings
--
SET @RuleSection = 'Application Settings';

	--
	-- Rule: Application Version
	--
	DECLARE @ModelDatabase AS VARCHAR(100)
	DECLARE @Count AS INT
	SET @RuleID = 200
	SET @RuleName = 'Application Version';
	DECLARE @VersionMajorMinor DECIMAL(2,1);
	DECLARE @VersionBuildRevision DECIMAL(8,4);
	SET @ModelDatabase = DB_NAME() + '_Model'
	SET @SQL = N'SELECT @VersionMajorMinor = CAST((CAST(T1.VERSIONMAJOR AS VARCHAR) + ''.'' + CAST(T1.VERSIONMINOR AS VARCHAR)) AS DECIMAL(2,1)), @VersionBuildRevision = CAST((CAST(T1.VERSIONBUILDNO AS VARCHAR) + ''.'' + CAST(T1.VERSIONREVISION AS VARCHAR)) AS DECIMAL(8,4)) '
	SET @SQL = @SQL + N'FROM [' + @ModelDatabase + '].[dbo].SYSMODELMANIFEST T1 CROSS '
	SET @SQL = @SQL + N'JOIN [' + @ModelDatabase + '].[dbo].SYSMODELELEMENTDATA T2 CROSS '
	SET @SQL = @SQL + N'JOIN [' + @ModelDatabase + '].[dbo].SYSMODELELEMENT T3 CROSS '
	SET @SQL = @SQL + N'JOIN [' + @ModelDatabase + '].[dbo].SYSMODELLAYER T4 '
	SET @SQL = @SQL + N'WHERE (T1.RECID=T2.MODELID) '
	SET @SQL = @SQL + N'AND ((((T2.MODELELEMENT=T3.RECID) '
	SET @SQL = @SQL + N'AND (T3.ELEMENTTYPE=13)) '
	SET @SQL = @SQL + N'AND (T3.PARENTID=(SELECT AXID FROM [' + @ModelDatabase + '].[dbo].SYSMODELELEMENT WHERE NAME = ''APPLICATIONVERSION'' AND ELEMENTTYPE = 45))) '
	SET @SQL = @SQL + N'AND (T3.NAME=''applBuildNo'')) '
	SET @SQL = @SQL + N'AND ((T4.RECID=T2.LAYER) '
	SET @SQL = @SQL + N'AND (T4.LAYER=(SELECT ID FROM [' + @ModelDatabase + '].[dbo].LAYER WHERE NAME = ''SYP'')))'
	EXEC sp_executesql @SQL, N'@VersionMajorMinor DECIMAL(2,1) OUTPUT, @VersionBuildRevision DECIMAL(8,4) OUTPUT', @VersionMajorMinor OUTPUT, @VersionBuildRevision OUTPUT
	IF(@VersionMajorMinor < 6.2) 
	BEGIN 
		SET @Observation  = 'AX 2012 RTM (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is NOT a supported upgrade path ';
		SET @Recommendation  = 'Only AX 2012 R2 CU9 and AX 2012 R3 CU13 are supported upgrade paths';	
	END
	IF(@VersionMajorMinor = 6.2) 
	BEGIN 
		IF(@VersionBuildRevision < 3000.110)
		BEGIN
			SET @Observation  = 'AX 2012 R2 CU8 or lower (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is NOT a supported upgrade path ';
			SET @Recommendation  = 'Only AX 2012 R2 CU9 or higher is a supported upgrade path';	
		END
		ELSE
		BEGIN
			SET @Observation  = 'AX 2012 R2 CU9 or higher (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is a supported upgrade path ';
			SET @Recommendation  = 'Validate version to ensure you are on a valid supported version of AX 2012 R2 CU9 or higher. ';	
		END
	END
	IF(@VersionMajorMinor = 6.3) 
	BEGIN 
		IF(@VersionBuildRevision < 6000.149)
		BEGIN
			SET @Observation  = 'AX 2012 R3 CU12 or lower (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is NOT a supported upgrade path ';
			SET @Recommendation  = 'Only AX 2012 R3 CU13 or higher is a supported upgrade path';	
		END
		ELSE
		BEGIN
			SET @Observation  = 'AX 2012 R3 CU13 or higher (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is a supported upgrade path ';
			SET @Recommendation  = 'Validate version to ensure you are on a valid supported version of AX 2012 R3 CU13 or higher. ';	
		END
	END
	SET @AdditionalComments  = '';
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Alert Rules
	--
	SET @RuleID = 205
	SET @RuleName = 'Alert Rules';
	SET @Observation  = 'This rule has identified that alerts exist in the AX2012 environment.';
	SET @Recommendation  = 'Alerts may not upgrade, and may need to be recreated. For details on alerts see: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/fin-ops/get-started/create-alerts';
	SET @AdditionalComments  = '';
	IF((SELECT COUNT(*) AS TotalActiveAlertRules FROM EventRule) > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Document Attachments File Share
	--
	SET @RuleID = 210
	SET @RuleName = 'Document Attachments File Share';
	SET @Observation  = 'This rule has identified that you have document attachments on a file share';
	SET @Recommendation  = 'Attachments on a file share need to be migrated into the database to get upgraded, see: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/migration-upgrade/migrate-doc-attachments-ax-2012';
	SET @AdditionalComments  = '';
	IF((SELECT COUNT(T1.RECID) FROM DOCUREF T1 JOIN DOCUTYPE T2 ON T1.TYPEID = T2.TYPEID AND T1.PARTITION = T2.PARTITION AND T1.REFCOMPANYID = T2.DATAAREAID WHERE T2.FILEPLACE = 0) > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Document Attachments SharePoint
	--
	SET @RuleID = 215
	SET @RuleName = 'Document Attachments SharePoint';
	SET @Observation  = 'This rule has identified that you have document attachments in SharePoint';
	SET @Recommendation  = 'Migration of attachments in SharePoint is not currently supported. You will need to manually migrate these as needed';
	SET @AdditionalComments  = '';
	IF((SELECT COUNT(T1.RECID) FROM DOCUREF T1 JOIN DOCUTYPE T2 ON T1.TYPEID = T2.TYPEID AND T1.PARTITION = T2.PARTITION AND T1.REFCOMPANYID = T2.DATAAREAID WHERE T2.FILEPLACE = 3) > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Development ISV VAR Models
	--
	SET @RuleID = 220
	SET @RuleName = 'Development ISV VAR Models';
	SET @Observation  = 'It has been identified that you may have modules and models (customization) from an ISV or Microsoft Partner (VAR)';
	SET @Recommendation  = 'Work with you ISV and\or VAR to ensure any modules and models you continue to need are available for D365';
	SET @AdditionalComments  = '';
	SET @ModelDatabase = DB_NAME() + '_Model'
	SET @SQL = N'SELECT @Count = COUNT(T1.ID) FROM [' + @ModelDatabase + '].dbo.MODEL T1 JOIN [' + @ModelDatabase + '].dbo.MODELMANIFEST T2 ON T1.ID = T2.ID '
	SET @SQL = @SQL + N'WHERE T1.LAYERID IN (SELECT ID FROM [' + @ModelDatabase + '].dbo.LAYER WHERE NAME IN (''ISV'',''ISP'',''VAR'',''VAP'')) '
	SET @SQL = @SQL + N'AND T2.NAME NOT IN  (''ISV Model'',''ISP Model'',''VAR Model'',''VAP Model'')'
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT
	IF(@Count > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

--
-- Rule Section: Database Settings
--
SET @RuleSection = 'Database Settings';

	--
	-- Rule: Database Collation
	--
	SET @RuleID = 300
	SET @RuleName = 'Database Collation';
	SET @Observation  = 'Database Collation is not SQL_Latin1_General_CP1_CI_AS';
	SET @Recommendation  = 'In order to upgrade a Tier 1 Development Cloud Hosted Environment or VHD, the collation of the database needs to be changed to SQL_Latin1_General_CP1_CI_AS. [NOTE!!]: The change in collation is handled automatically by the Data Migration Toolkit for Tier 2 Self-Service Environments';
	SET @AdditionalComments  = '';
	IF((select collation_name from sys.databases where name = DB_NAME()) != 'SQL_Latin1_General_CP1_CI_AS')
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	
	--
	-- Rule: Database Size
	--
	SET @RuleID = 305
	SET @RuleName = 'Database Size';
	SET @Observation  = 'Database size is over 250GB';
	SET @Recommendation  = 'Upgrading larger databases may require more planning, testing and tuning of the upgrade process, especially for the Self-Service (Tier 2+) upgrade process where replication is used';
	SET @AdditionalComments  = '';
	IF((SELECT SUM(size * 8 / 1024 / 1024) AS 'Database_Size' FROM sys.master_files WHERE DB_NAME(database_id) = DB_NAME() AND TYPE = 0) >= 250)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: RCSI not configured
	--
	SET @RuleID = 310
	SET @RuleName = 'RCSI not configured';
	SET @Observation  = 'Read Committed Snapshot Isolation (RCSI) is not configured on the database';
	SET @Recommendation  = 'Enable RSCI on this database with the following (Edit database name as needed): ALTER DATABASE MicrosoftDynamicsAX SET READ_COMMITTED_SNAPSHOT ON';
	SET @AdditionalComments  = '';
	IF((SELECT is_read_committed_snapshot_on FROM sys.databases WHERE [name] = DB_NAME()) = 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

--
-- Rule Section: Database Saving
--
DECLARE @TotalEstimatedSavingInMB INT;
DECLARE @TotalEstimatedSavingInMBReal AS REAL;
SET @RuleSection = 'Database Saving';

	--
	-- Rule: Backup Database
	--
	SET @RuleID = 400
	SET @RuleName = 'Backup Database';
	SET @Observation  = 'The following rules may suggest data clean up or data changes';
	SET @Recommendation  = 'Before cleaning or making any changes to the environment, please ensure you have a full backup';
	SET @AdditionalComments  = ''
	INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
	VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);

	--
	-- Rule: Large Tables
	--
	SET @RuleID = 405
	SET @RuleName = 'Large Tables';
	IF(OBJECT_ID('tempdb..#LARGETABLES') IS NOT NULL)
	BEGIN 
		DROP TABLE #LARGETABLES
	END
	SELECT T2.name AS TableName, 
		T1.data_compression_desc AS CompressionType,
		SUM(T3.total_pages) * 8 / 1024  AS TotalSpaceMB, 
		SUM(T3.used_pages) * 8 / 1024  AS UsedSpaceMB
		INTO #LARGETABLES
	FROM sys.partitions AS T1
	INNER JOIN sys.tables AS T2 ON T2.object_id = T1.object_id
	INNER JOIN sys.allocation_units T3 ON T1.partition_id = T3.container_id
	WHERE T1.index_id in (0,1)
	AND T1.data_compression_desc = 'NONE'
	GROUP BY T2.Name, T1.data_compression_desc
	HAVING SUM(T3.used_pages) * 8 / 1024  > @LargeTableThreshold
	IF((SELECT COUNT(1) FROM #LARGETABLES) > 0)
	BEGIN
		SET @Observation  = 'Large tables detected. There is\are ' + CAST((SELECT COUNT(1) FROM #LARGETABLES) AS VARCHAR) + ' table(s) over ' + CAST(@LargeTableThreshold AS VARCHAR) + 'MB in size.';
		SET @Recommendation  = 'It may be beneficial to compress large tables prior to the upgrade, see: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/migration-upgrade/compress-tables-ax-2012';
		SET @AdditionalComments  = 'Following large tables detected: ' + (SELECT TOP 1 STUFF((SELECT ', ' + TableName + ' - ' + CAST(UsedSpaceMB AS VARCHAR) + 'MB ' FROM #LARGETABLES FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS ConcatenatedString FROM #LARGETABLES)
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade AIF document log cleanup
	--
	SET @RuleID = 410
	SET @RuleName = 'Upgrade AIF document log cleanup';
	SET @Observation  = 'Delete the XML document history for old AIF messages to recover database space. This rule has found XML documents stored in history which are over 1 year old, the estimate here is for deleting all history over 1 year. Note that the message log remains, this function only deletes the related document XML';
	SET @Recommendation  = '1. Click System administration > Periodic > Services and Application Integration Framework > History. 2. In the Display by field, select Document. 3. Select a document, and then click Clear document XML. 4. To clear all the versions of the XML document that exist in the system, click Clear all versions. 5. To clear all intermediate versions of the XML document, click Clear interim versions. for outbound documents, this action clears all versions except the version that has the highest version number. For inbound documents, this action clears all versions except the first version.';
	SET @TotalEstimatedSavingInMB = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
										FROM sys.tables t
										INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
										INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
										INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
										WHERE t.NAME ='AIFDOCUMENTLOG'
										GROUP BY t.Name,p.Rows),0) * count(AIFDOCUMENTLOG.recID))/1024 as TotalEstimatedSavingInMB
										FROM AIFDOCUMENTLOG, AIFMESSAGELOG
										WHERE AIFDOCUMENTLOG.MESSAGEID = AIFMESSAGELOG.MESSAGEID
										and DateDiff(year, AIFMESSAGELOG.CREATEDDATETIME, GetDate()) > 1);
	SET @AdditionalComments = 'Total Estimated Saving In MB:' + CAST(@TotalEstimatedSavingInMB AS NVARCHAR)
	IF(@TotalEstimatedSavingInMB > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Archive future time registrations
	--
	SET @RuleID = 415
	SET @RuleName = 'Upgrade Archive future time registrations';
	SET @Observation  = 'Time registrations which have been accidentally entered with a future date can be archived. Once this process has been executed you need to run the archive cleanup to delete the records from Production control > Inquiries > Registrations > Raw registrations archive';
	SET @Recommendation  = 'Click Production control > Periodic > Clean up > Archive future registrations. Click ok, or use batch options to set a recurring job.';
	SET @AdditionalComments  = '';

	SET @TotalEstimatedSavingInMB = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
										FROM sys.tables t
										INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
										INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
										INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
										WHERE t.NAME ='JMGTERMREG'
										GROUP BY t.Name,p.Rows),0) * count(JMGTERMREG.recID)) /1024 as TotalEstimatedSavingInMB
										FROM JMGTERMREG
										WHERE  DateDiff(day, GetDate(), JMGTERMREG.REGDATETIME) > 1);
	SET @AdditionalComments = 'Total Estimated Saving In MB:' + CAST(@TotalEstimatedSavingInMB AS NVARCHAR)
	IF(@TotalEstimatedSavingInMB > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Batch cleanup
	--
	SET @RuleID = 420
	SET @RuleName = 'Upgrade Batch cleanup';
	SET @Observation  = 'Delete batch jobs which have ended successfully.';
	SET @Recommendation  = '1.Click Home > Inquiries > Batch jobs > My batch jobs. 2. Click Functions, and then select Delete. 3. In the Select batch transactions for deletion dialog box, enter the criteria to use for deleting jobs. for example, to delete all jobs that have ended, for Field select Status, for Criteria, select Ended, and then click OK.';
	IF(OBJECT_ID('tempdb..#tempBatchTablesSizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempBatchTablesSizes
	END

	CREATE TABLE #tempBatchTablesSizes (SavingInKBBatchJob REAL, SavingInKBBatch REAL, SavingInKBBatchJobAlerts REAL, TotalEstimatedSavingInMB REAL)

	INSERT into #tempBatchTablesSizes (SavingInKBBatchJob)
	SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
					FROM sys.tables t
					INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
					INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
					INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
					WHERE t.NAME ='BATCHJOB'
					GROUP BY t.Name,p.Rows),0) * count(BATCHJOB.recID)
					FROM BATCHJOB
					WHERE BATCHJOB.STATUS = 4

	UPDATE #tempBatchTablesSizes
	SET SavingInKBBatch = (SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
							FROM sys.tables t
							INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
							INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
							INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
							WHERE t.NAME ='BATCH'
							GROUP BY t.Name,p.Rows),0) * count(BATCH.recID)
							FROM BATCHJOB, BATCH
							WHERE BATCHJOB.STATUS = 4
							and BATCHJOB.RECID = BATCH.BATCHJOBID)

	UPDATE #tempBatchTablesSizes
	SET SavingInKBBatchJobAlerts =  (SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
										FROM sys.tables t
										INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
										INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
										INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
										WHERE t.NAME ='BATCHJOBALERTS'
										GROUP BY t.Name,p.Rows),0) * count(BATCHJOBALERTS.recID)
										FROM BATCHJOB, BATCHJOBALERTS
										WHERE BATCHJOB.STATUS = 4
										and BATCHJOB.RECID = BATCHJOBALERTS.BATCHJOBID)

	UPDATE #tempBatchTablesSizes 
	SET TotalEstimatedSavingInMB = (SavingInKBBatchJobAlerts + SavingInKBBatch + SavingInKBBatchJob) /1024;

	DECLARE @SavingInKBBatchJobAlerts AS REAL;
	DECLARE @SavingInKBBatch AS REAL;
	DECLARE @SavingInKBBatchJob AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempBatchTablesSizes);
	SET @SavingInKBBatchJobAlerts = (SELECT SavingInKBBatchJobAlerts FROM #tempBatchTablesSizes);
	SET @SavingInKBBatch = (SELECT SavingInKBBatch FROM #tempBatchTablesSizes);
	SET @SavingInKBBatchJob = (SELECT SavingInKBBatchJob FROM #tempBatchTablesSizes);
	DROP TABLE #tempBatchTablesSizes

	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB Batch Job Alerts: ' + CAST(@SavingInKBBatchJobAlerts AS NVARCHAR) + ', Saving In KB Batch: ' + CAST(@SavingInKBBatch AS NVARCHAR) + ', Saving In KB Batch Job: ' + CAST(@SavingInKBBatchJob AS NVARCHAR)
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade BOM calculation cleanup
	--
	SET @RuleID = 425
	SET @RuleName = 'Upgrade BOM calculation cleanup';
	SET @Observation  = 'If performing BOM calculations the BOMCalcTable and BOMCalcTrans tables can become large. Once calculated this data is not generally needed. The purpose of this old data is to go back and look at old calculations, if this is not part of your business process then you may clean it up. A rule of thumb is that a customer should keep a few months of data and purge the rest.';
	SET @Recommendation  = 'Step 1 - Purging the BOMCalcTrans Before running the script, replace the following information: # of records to group = A while loop has been implemented to minimize the SQL Transaction Log growth. The while loop will delete records in groups of the number that you enter (example 1 million 1000000). The process will take a significant amount of time to complete on large data sets. Company = Enter the name of the company that you want to delete BOMCalcTrans records Date = Enter a date and the qualifier (example < > or =) of which records you want to delete. Below is an example of deleting the BOMCalcTable records for company dmo with transaction date less than 1/31/2023. DELETE BOMCALCTABLE WHERE TRANSDATE < ''2023-01-31 00:00:00.000'' AND DATAAREAID = ''dmo''';
	IF(OBJECT_ID('tempdb..#tempBOMTablesSizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempBOMTablesSizes
	END

	CREATE TABLE #tempBOMTablesSizes
	(
		 SavingInKBBomCalcTable REAL,
		 SavingInKBBomCalcTrans REAL,
		 TotalEstimatedSavingInMB REAL
	)

	INSERT INTO #tempBOMTablesSizes(SavingInKBBomCalcTable)
	SELECT
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	 FROM sys.tables t
	 INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	 INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	 INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	 WHERE t.NAME ='BOMCALCTABLE'
	 GROUP BY t.Name,p.Rows),0) * count(recID)
	FROM BOMCALCTABLE 
	where DateDiff(month, TransDate, getDate()) > 6

	UPDATE #tempBOMTablesSizes
	SET SavingInKBBomCalcTrans = (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
		   FROM sys.tables t
		   INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
		   INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
		   INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
		   WHERE t.NAME ='BOMCALCTRANS'
		   GROUP BY t.Name,p.Rows),0) * count(recID)
		   FROM BOMCALCTRANS 
		   where DateDiff(month, TransDate, getDate()) > 6)

	UPDATE #tempBOMTablesSizes
	SET TotalEstimatedSavingInMB = (SavingInKBBomCalcTrans + SavingInKBBomCalcTable) /1024

	DECLARE @SavingInKBBomCalcTrans AS REAL;
	DECLARE @SavingInKBBomCalcTable AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempBOMTablesSizes);
	SET @SavingInKBBomCalcTrans = (SELECT SavingInKBBomCalcTrans FROM #tempBOMTablesSizes);
	SET @SavingInKBBomCalcTable = (SELECT SavingInKBBomCalcTable FROM #tempBOMTablesSizes);
	DROP TABLE #tempBOMTablesSizes

	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB Bom Calc Trans: ' + CAST(@SavingInKBBomCalcTrans AS NVARCHAR) + ', Saving In KB Bom Calc Table: ' + CAST(@SavingInKBBomCalcTable AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	--
	-- Rule: Upgrade Calendar date cleanup
	--
	SET @RuleID = 430
	SET @RuleName = 'Upgrade Calendar date cleanup';
	SET @Observation  = 'Cleanup calendar dates older than a certain date. This rule has found calendar dates over 1 year old. This function will not delete the calendars themselves, but only the dates within the calendar that are older than the date you specify.';
	SET @Recommendation  = 'Click Organization administration > Periodic > Calendar cleanup. Use this form to specify the end date for deleting old working times. All old working hours up to, but not including, this date are deleted.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='WORKCALENDARDATE'
											GROUP BY t.Name,p.Rows),0) * count(WORKCALENDARDATE.recID))/1024 as TotalEstimatedSavingInMB
											FROM WORKCALENDARDATE
											WHERE DateDiff(year, WORKCALENDARDATE.TRANSDATE, GetDate()) > 1);
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Database log cleanup
	--
	SET @RuleID = 435
	SET @RuleName = 'Upgrade Database log cleanup';
	SET @Observation  = 'Delete database log records older than a certain date. This rule has checked for logs over 1 year old. You can also delete logs only for a certain table or other specific criteria.';
	SET @Recommendation  = '1. Click System administration > Inquiries > Database > Database log. Click Clean up log. 2. Choose a method of selecting logs to delete by entering the table ID that they refer to, or the type of log, or the created date and time. 3. Use the Database log cleanup tab to determine when to run the log cleanup task.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='SYSDATABASELOG'
											GROUP BY t.Name,p.Rows),0) * count(SYSDATABASELOG.recID))/1024 as TotalEstimatedSavingInMB
											FROM SYSDATABASELOG
											WHERE DateDiff(year,SYSDATABASELOG.CREATEDDATETIME, GetDate())  > 1)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	
	--
	-- Rule: Upgrade Delete absence journals
	--
	SET @RuleID = 440
	SET @RuleName = 'Upgrade Delete absence journals';
	SET @Observation  = 'Use the “Delete absence journals” process to delete all empty journals that have not been transferred for approval. The exceptions to this rule are empty journals that contain a period that is before a journal that contains planned, or future, absences. if planned absences exist in a future period but you still want to delete the journal, you can cancel approval and then repeat the delete journal procedure.';
	SET @Recommendation  = '1. Click Human resources > Periodic > Absence > Delete absence journals. 2. Choose one of the following actions: ◦ Click OK to delete all absence journals. ◦ Click Select to select the employees to delete absence journals for.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (
											ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='HRMABSENCETABLE'
											GROUP BY t.Name,p.Rows),0) * count(HRMABSENCETABLE.recID)) /1024 as TotalEstimatedSavingInMB
											FROM HRMABSENCETABLE
											WHERE  HRMABSENCETABLE.STATUS in (0,1))
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Delete project journals
	--
	SET @RuleID = 445
	SET @RuleName = 'Upgrade Delete project journals';
	SET @Observation  = 'You can delete project journals from which transactions have been posted. By deleting these project journals, you can help make more system resources available.';
	SET @Recommendation  = '1.Click Project management and accounting > Periodic > Journals > Delete project journals. 2. In the Delete project journals form, click Select. 3. In the ProjJournalCleanUp form, in the Criteria field, select the journal(s) that you want to delete. 4. Click OK.';
	IF(OBJECT_ID('tempdb..#tempProjJournalsSizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempBOMTablesSizes
	END

	CREATE TABLE #tempProjJournalsSizes
	(
	 SavingInKBProjJournalTable REAL,
	 SavingInKBProjJournalTrans REAL,
	 SavingInKBProdBegBalJournalTrans_CostSales REAL,
	 SavingInKBProdBegBalJournalTrans_Fee REAL,
	 SavingInKBProdBegBalJournalTrans_OnAcc REAL,
	 TotalEstimatedSavingInMB REAL
	)

	INSERT into #tempProjJournalsSizes (SavingInKBProjJournalTable)
	SELECT 
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PROJJOURNALTABLE'
	GROUP BY t.Name,p.Rows),0) * count(PROJJOURNALTABLE.recID)
	FROM PROJJOURNALTABLE
	WHERE PROJJOURNALTABLE.POSTED = 1

	UPDATE #tempProjJournalsSizes
	SET SavingInKBProjJournalTrans =  
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PROJJOURNALTRANS'
	GROUP BY t.Name,p.Rows),0) * count(PROJJOURNALTRANS.recID)
	FROM PROJJOURNALTABLE, PROJJOURNALTRANS
	WHERE PROJJOURNALTABLE.POSTED = 1
	and PROJJOURNALTABLE.JOURNALID = PROJJOURNALTRANS.JOURNALID)

	UPDATE #tempProjJournalsSizes
	set SavingInKBProdBegBalJournalTrans_CostSales =  
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PROJBEGBALJOURNALTRANS_COSTSALES'
	GROUP BY t.Name,p.Rows),0) * count(PROJBEGBALJOURNALTRANS_COSTSALES.recID)
	FROM PROJJOURNALTABLE, PROJBEGBALJOURNALTRANS_COSTSALES
	WHERE PROJJOURNALTABLE.POSTED = 1
	and PROJJOURNALTABLE.JOURNALID = PROJBEGBALJOURNALTRANS_COSTSALES.JOURNALID)

	UPDATE #tempProjJournalsSizes
	set SavingInKBProdBegBalJournalTrans_Fee =  
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PROJBEGBALJOURNALTRANS_FEE'
	GROUP BY t.Name,p.Rows),0) * count(PROJBEGBALJOURNALTRANS_FEE.recID)
	FROM PROJJOURNALTABLE, PROJBEGBALJOURNALTRANS_FEE
	WHERE PROJJOURNALTABLE.POSTED = 1
	and PROJJOURNALTABLE.JOURNALID = PROJBEGBALJOURNALTRANS_FEE.JOURNALID)

	UPDATE #tempProjJournalsSizes
	SET SavingInKBProdBegBalJournalTrans_OnAcc =  
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PROJBEGBALJOURNALTRANS_ONACC'
	GROUP BY t.Name,p.Rows),0) * count(PROJBEGBALJOURNALTRANS_ONACC.recID)
	FROM PROJJOURNALTABLE, PROJBEGBALJOURNALTRANS_ONACC
	WHERE PROJJOURNALTABLE.POSTED = 1
	and PROJJOURNALTABLE.JOURNALID = PROJBEGBALJOURNALTRANS_ONACC.JOURNALID)

	UPDATE #tempProjJournalsSizes
	SET TotalEstimatedSavingInMB = (SavingInKBProdBegBalJournalTrans_OnAcc + SavingInKBProdBegBalJournalTrans_Fee + SavingInKBProdBegBalJournalTrans_CostSales + SavingInKBProjJournalTrans + SavingInKBProjJournalTable) /1024

	DECLARE @SavingInKBProjJournalTable AS REAL;
	DECLARE @SavingInKBProjJournalTrans AS REAL;
	DECLARE @SavingInKBProdBegBalJournalTrans_CostSales AS REAL;
	DECLARE @SavingInKBProdBegBalJournalTrans_Fee AS REAL;
	DECLARE @SavingInKBProdBegBalJournalTrans_OnAcc AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempProjJournalsSizes);
	SET @SavingInKBProjJournalTable = (SELECT SavingInKBProjJournalTable FROM #tempProjJournalsSizes);
	SET @SavingInKBProjJournalTrans = (SELECT SavingInKBProjJournalTrans FROM #tempProjJournalsSizes);
	SET @SavingInKBProdBegBalJournalTrans_CostSales = (SELECT SavingInKBProdBegBalJournalTrans_CostSales FROM #tempProjJournalsSizes);
	SET @SavingInKBProdBegBalJournalTrans_Fee = (SELECT SavingInKBProdBegBalJournalTrans_Fee FROM #tempProjJournalsSizes);
	SET @SavingInKBProdBegBalJournalTrans_OnAcc = (SELECT SavingInKBProdBegBalJournalTrans_OnAcc FROM #tempProjJournalsSizes);
	DROP TABLE #tempProjJournalsSizes
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB ProjJournalTable: ' + CAST(@SavingInKBProjJournalTable AS NVARCHAR) + ', Saving In KB ProjJournalTrans: ' + CAST(@SavingInKBProjJournalTrans AS NVARCHAR) + ', Saving In KB ProdBegBalJournalTrans_CostSales: ' + CAST(@SavingInKBProdBegBalJournalTrans_CostSales AS NVARCHAR)  + ', Saving In KB ProdBegBalJournalTrans_Fee: ' + CAST(@SavingInKBProdBegBalJournalTrans_Fee AS NVARCHAR)  + ', Saving In KB ProdBegBalJournalTrans_OnAcc: ' + CAST(@SavingInKBProdBegBalJournalTrans_OnAcc AS NVARCHAR)  
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	
	--
	-- Rule: Upgrade Delete unsent project quotations
	--
	SET @RuleID = 450
	SET @RuleName = 'Upgrade Delete unsent project quotations';
	SET @Observation  = 'Deleting unsent project quotations to recover database space. It is possible to create a filter to delete only selected quotations. note that it is not possible to delete "Sent" quotations, to delete a "Sent" quotation first update it to Lost or Cancelled.';
	SET @Recommendation  = '1.Click Project management and accounting > Periodic > Quotations > Delete quotations. 2. In the Delete quotations form, click the Select button. if necessary, customize the query to match your needs. 3. Click OK to transfer the quotations to the Delete quotations form. if the query transfers quotations that you do not want to delete, select them in the Delete quotations form and press ALT+F9. This removes the quotations from the list of quotations to be deleted. 4. Click OK to delete the quotations that are listed in the Delete quotations form.';
	IF(OBJECT_ID('tempdb..#tempProjJournalsSizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempBOMTablesSizes
	END

	CREATE TABLE #tempProjQuotationSizes
	(
	 SavingInKBSalesQuotationTable REAL,
	 SavingInKBSalesQuotationLine REAL,
	 TotalEstimatedSavingInMB REAL
	)

	INSERT into #tempProjQuotationSizes (SavingInKBSalesQuotationTable)
	SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='SALESQUOTATIONTABLE'
	GROUP BY t.Name,p.Rows),0) * count(SALESQUOTATIONTABLE.recID)
	FROM SALESQUOTATIONTABLE
	WHERE SALESQUOTATIONTABLE.QUOTATIONTYPE = 1
	and SALESQUOTATIONTABLE.QUOTATIONSTATUS in (0,2,3,4)

	UPDATE #tempProjQuotationSizes
	SET SavingInKBSalesQuotationLine =  
	(SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='SALESQUOTATIONLINE'
	GROUP BY t.Name,p.Rows),0) * count(SALESQUOTATIONLINE.recID)
	FROM SALESQUOTATIONTABLE, SALESQUOTATIONLINE
	WHERE SALESQUOTATIONTABLE.QUOTATIONTYPE = 1
	and SALESQUOTATIONTABLE.QUOTATIONSTATUS in (0,2,3,4)
	and SALESQUOTATIONTABLE.QUOTATIONID = SALESQUOTATIONLINE.QUOTATIONID)

	UPDATE #tempProjQuotationSizes
	SET TotalEstimatedSavingInMB = (SavingInKBSalesQuotationTable + SavingInKBSalesQuotationLine) /1024

	DECLARE @SavingInKBSalesQuotationTable AS REAL;
	DECLARE @SavingInKBSalesQuotationLine AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempProjQuotationSizes);
	SET @SavingInKBSalesQuotationTable = (SELECT SavingInKBSalesQuotationTable FROM #tempProjQuotationSizes);
	SET @SavingInKBSalesQuotationLine = (SELECT SavingInKBSalesQuotationLine FROM #tempProjQuotationSizes);
	DROP TABLE #tempProjQuotationSizes
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB SalesQuotationTable: ' + CAST(@SavingInKBSalesQuotationTable AS NVARCHAR) + ', Saving In KB SalesQuotationLine: ' + CAST(@SavingInKBSalesQuotationLine AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Inventory settlement cleanup
	--
	SET @RuleID = 455
	SET @RuleName = 'Upgrade Inventory settlement cleanup';
	SET @Observation  = 'Use the Inventory settlements clean up process to delete old and cancelled inventory settlements.  The INVENTSETTLEMENT table can become quite large if you’ve cancelled inventory closes.  This rule has identified records over 1 year old';
	SET @Recommendation  = 'Click Inventory management > Periodic > Clean up > Inventory settlements cleanup. Use this form to group closed inventory transactions or delete canceled inventory settlements. Cleaning up closed or deleted inventory settlements can help free system resources. Do not group or delete inventory settlements too close to the current date or fiscal year, because part of the transaction information for the settlements is lost.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='inventsettlement'
											GROUP BY t.Name,p.Rows),0) * COUNT(recID))/1024 as TotalEstimatedSavingInMB
											FROM inventsettlement (nolock)
											WHERE cancelled = 1 and -- (1 = Yes)
											settlemodel <> 7  and -- (7 = PhysicalValue)
											settletype <> 4  -- (4 = Conversion)
											AND DateDiff(year, transbegintime, GETDATE()) > 1)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Master plan log clean up
	--
	SET @RuleID = 460
	SET @RuleName = 'Upgrade Master plan log clean up';
	SET @Observation  = 'Master scheduling logic keeps a log table of inventory transactions. This is automatically cleaned up when master scheduling is run. If master scheduling is not run these records continue to grow larger over time and are not cleaned up. A large amount of rows over 3 months old have been found in your database.';
	SET @Recommendation  = 'Execute the following SQL statement to clean up records: DELETE INVENTSUMLOGTTS WHERE ISCOMMITTED =1 ';
	SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='InventSumLogTTS'
											GROUP BY t.Name,p.Rows),0) * count(recID))/1024 as TotalEstimatedSavingInMB
											FROM InventSumLogTTS (nolock)
											WHERE DateDiff(month, UTCCREATEDDATETIME, GetDate()) > 3)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Production journal clean up
	--
	SET @RuleID = 465
	SET @RuleName = 'Upgrade Production journal clean up';
	SET @Observation  = 'Clean up production journals for "Ended" production orders. it is useful to delete old or unused journals to reduce demand on system resources. This process is related to the "Production orders clean up" process. Executing the "production orders clean up" will also delete the related production journals - then this process is not required. However if it is not possible for you to delete production orders, then you may wish you use this option to delete just production journals instead.';
	SET @Recommendation  = '1. Click Production control > Periodic > Clean up > Production journals cleanup. 2. Click the Clean up list. 3. Select whether you want to delete all posted journals or only journals that are posted on finished production orders. 4. Click OK to delete the journals, or click the Batch tab, and then define parameters to schedule old journals to be deleted regularly.';
	IF(OBJECT_ID('tempdb..#tempProjJournalsSizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempBOMTablesSizes
	END

	CREATE TABLE #tempProdJournalSizes
	(
	 SavingInKBProdJournalTable REAL,
	 SavingInKBProdJournalBOM REAL,
	 SavingInKBProdJournalProd REAL,
	 SavingInKBProdJournalRoute REAL,
	 TotalEstimatedSavingInMB REAL
	)

	INSERT into #tempProdJournalSizes (SavingInKBProdJournalTable)
	SELECT 
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALTABLE'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALTABLE.recID)
	FROM PRODTABLE, PRODJOURNALTABLE
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1

	UPDATE #tempProdJournalSizes
	SET SavingInKBProdJournalBOM = 
	 (SELECT 
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALBOM'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALBOM.recID)
	FROM PRODTABLE, PRODJOURNALTABLE, PRODJOURNALBOM
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1
	and PRODJOURNALBOM.JOURNALID = PRODJOURNALTABLE.JOURNALID)

	UPDATE #tempProdJournalSizes
	SET SavingInKBProdJournalProd = 
	 (SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALPROD'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALPROD.recID)
	FROM PRODTABLE, PRODJOURNALTABLE, PRODJOURNALPROD
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1
	and PRODJOURNALTABLE.JOURNALID = PRODJOURNALPROD.JOURNALID)


	UPDATE #tempProdJournalSizes
	SET SavingInKBProdJournalRoute = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALROUTE'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALROUTE.recID)
	FROM PRODTABLE, PRODJOURNALTABLE, PRODJOURNALROUTE
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1
	and PRODJOURNALTABLE.JOURNALID = PRODJOURNALROUTE.JOURNALID)

	UPDATE #tempProdJournalSizes
	SET TotalEstimatedSavingInMB = (SavingInKBProdJournalRoute + SavingInKBProdJournalProd + SavingInKBProdJournalBOM + SavingInKBProdJournalTable) /1024
	DECLARE @SavingInKBProdJournalRoute AS REAL;
	DECLARE @SavingInKBProdJournalProd AS REAL;
	DECLARE @SavingInKBProdJournalBOM AS REAL;
	DECLARE @SavingInKBProdJournalTable AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempProdJournalSizes);
	SET @SavingInKBProdJournalRoute = (SELECT SavingInKBProdJournalRoute FROM #tempProdJournalSizes);
	SET @SavingInKBProdJournalProd = (SELECT SavingInKBProdJournalProd FROM #tempProdJournalSizes);
	SET @SavingInKBProdJournalBOM = (SELECT SavingInKBProdJournalBOM FROM #tempProdJournalSizes);
	SET @SavingInKBProdJournalTable = (SELECT SavingInKBProdJournalTable FROM #tempProdJournalSizes);
	DROP TABLE #tempProdJournalSizes
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB ProdJournalRoute: ' + CAST(@SavingInKBProdJournalRoute AS NVARCHAR) + ', Saving In KB ProdJournalProd: ' + CAST(@SavingInKBProdJournalProd AS NVARCHAR) + ', Saving In KB ProdJournalBOM: ' + CAST(@SavingInKBProdJournalBOM AS NVARCHAR) + ', Saving In KB ProdJournalTable: ' + CAST(@SavingInKBProdJournalTable AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Production order clean up
	--
	SET @RuleID = 470
	SET @RuleName = 'Upgrade Production order clean up';
	SET @Observation  = 'Many "Ended" status production orders exist in the system which are over 1 year old. These can be cleaned up to release space';
	SET @Recommendation  = '1. Click Production control > Periodic > Clean up > Production orders cleanup. 2. On the General tab, in the Ended before field, select the last date that you want production orders to be included for deletion. 3. Click OK, or use the Batch tab to set parameters for cleaning up production orders automatically at set intervals.';
	IF(OBJECT_ID('tempdb..#tempProdOrderSizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempProdOrderSizes
	END

	
	CREATE TABLE #tempProdOrderSizes
	(
	 SavingInKBProdTable REAL,
	 SavingInKBProdBOM REAL,
	 SavingInKBProdRoute REAL,
	 SavingInKBProdRouteJob REAL,
	 SavingInKBWrkCtrCapRes REAL,
	 SavingInKBProdCalcTrans REAL,
	 SavingInKBProdJournalTable REAL,
	 SavingInKBProdJournalBOM REAL,
	 SavingInKBProdJournalProd REAL,
	 SavingInKBProdJournalProd2 REAL,
	 SavingInKBProdJournalRoute REAL,
	 TotalEstimatedSavingInMB REAL
	)

	INSERT INTO #tempProdOrderSizes(SavingInKBProdTable) 
	SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODTABLE'
	GROUP BY t.Name,p.Rows),0) * count(recID) AS SavingInKB
	FROM PRODTABLE 
	WHERE PRODSTATUS=7 --ended
	and DateDiff(year, RealDate, getDate()) > 1 --over a year

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdBOM = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODBOM'
	GROUP BY t.Name,p.Rows),0) * count(PRODBOM.recID)
	FROM PRODTABLE, PRODBOM
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODBOM.DATAAREAID
	and PRODTABLE.PRODID = PRODBOM.PRODID)

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdRoute = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODROUTE'
	GROUP BY t.Name,p.Rows),0) * count(PRODROUTE.recID)
	FROM PRODTABLE, PRODROUTE
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODROUTE.DATAAREAID
	and PRODTABLE.PRODID = PRODROUTE.PRODID)

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdRouteJob = 
	 (SELECT 
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODROUTEJOB'
	GROUP BY t.Name,p.Rows),0) * count(PRODROUTEJOB.recID)
	FROM PRODTABLE, PRODROUTEJOB
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODROUTEJOB.DATAAREAID
	and PRODTABLE.PRODID = PRODROUTEJOB.PRODID)

	UPDATE #tempProdOrderSizes
	SET SavingInKBWrkCtrCapRes = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='WRKCTRCAPRES'
	GROUP BY t.Name,p.Rows),0) * count(WRKCTRCAPRES.recID)
	FROM PRODTABLE, WRKCTRCAPRES
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = WRKCTRCAPRES.DATAAREAID
	and PRODTABLE.PRODID = WRKCTRCAPRES.REFID
	and WRKCTRCAPRES.REFTYPE = 1) --production

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdCalcTrans = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODCALCTRANS'
	GROUP BY t.Name,p.Rows),0) * count(PRODCALCTRANS.recID)
	FROM PRODTABLE, PRODCALCTRANS
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODCALCTRANS.DATAAREAID
	and PRODTABLE.PRODID = PRODCALCTRANS.TRANSREFID
	and PRODCALCTRANS.TRANSREFTYPE = 0) --production

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdJournalTable = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALTABLE'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALTABLE.recID)
	FROM PRODTABLE, PRODJOURNALTABLE
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1)

	UPDATE #tempProdOrderSizes
	set SavingInKBProdJournalBOM = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALBOM'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALBOM.recID)
	FROM PRODTABLE, PRODJOURNALTABLE, PRODJOURNALBOM
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1
	and PRODJOURNALBOM.JOURNALID = PRODJOURNALTABLE.JOURNALID)

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdJournalProd = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALPROD'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALPROD.recID)
	FROM PRODTABLE, PRODJOURNALPROD
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODJOURNALPROD.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALPROD.PRODID)

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdJournalProd2 = 
	 (SELECT 
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALPROD'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALPROD.recID)
	FROM PRODTABLE, PRODJOURNALTABLE, PRODJOURNALPROD
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1
	and PRODJOURNALTABLE.JOURNALID = PRODJOURNALPROD.JOURNALID)

	UPDATE #tempProdOrderSizes
	SET SavingInKBProdJournalRoute = 
	 (SELECT 
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='PRODJOURNALROUTE'
	GROUP BY t.Name,p.Rows),0) * count(PRODJOURNALROUTE.recID)
	FROM PRODTABLE, PRODJOURNALTABLE, PRODJOURNALROUTE
	WHERE PRODTABLE.PRODSTATUS=7 --ended
	and DateDiff(year, PRODTABLE.RealDate, getDate()) > 1 --over a year
	and PRODTABLE.DATAAREAID = PRODJOURNALTABLE.DATAAREAID
	and PRODTABLE.PRODID = PRODJOURNALTABLE.PRODID
	and PRODJOURNALTABLE.PRODID != ''
	and PRODJOURNALTABLE.POSTED = 1
	and PRODJOURNALTABLE.JOURNALID = PRODJOURNALROUTE.JOURNALID)

	UPDATE #tempProdOrderSizes
	SET TotalEstimatedSavingInMB = (SavingInKBProdJournalRoute + SavingInKBProdJournalProd2 + SavingInKBProdJournalProd + SavingInKBProdJournalBOM + SavingInKBProdJournalTable + 
			SavingInKBProdCalcTrans + SavingInKBWrkCtrCapRes + SavingInKBProdRouteJob + SavingInKBProdRoute + SavingInKBProdBOM + SavingInKBProdTable) /1024

	DECLARE @SavingInKBProdJournalProd2 AS REAL;
	DECLARE @SavingInKBProdCalcTrans AS REAL;
	DECLARE @SavingInKBWrkCtrCapRes AS REAL;
	DECLARE @SavingInKBProdRouteJob AS REAL;
	DECLARE @SavingInKBProdRoute AS REAL;
	DECLARE @SavingInKBProdBOM AS REAL;
	DECLARE @SavingInKBProdTable AS REAL;

	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempProdOrderSizes);
	SET @SavingInKBProdJournalRoute = (SELECT SavingInKBProdJournalRoute FROM #tempProdOrderSizes);
	SET @SavingInKBProdJournalProd2 = (SELECT SavingInKBProdJournalProd2 FROM #tempProdOrderSizes);
	SET @SavingInKBProdJournalProd = (SELECT SavingInKBProdJournalProd FROM #tempProdOrderSizes);
	SET @SavingInKBProdJournalBOM = (SELECT SavingInKBProdJournalBOM FROM #tempProdOrderSizes);
	SET @SavingInKBProdJournalTable = (SELECT SavingInKBProdJournalTable FROM #tempProdOrderSizes);
	SET @SavingInKBProdCalcTrans = (SELECT SavingInKBProdCalcTrans FROM #tempProdOrderSizes);
	SET @SavingInKBWrkCtrCapRes = (SELECT SavingInKBWrkCtrCapRes FROM #tempProdOrderSizes);
	SET @SavingInKBProdRouteJob = (SELECT SavingInKBProdRouteJob FROM #tempProdOrderSizes);
	SET @SavingInKBProdRoute = (SELECT SavingInKBProdRoute FROM #tempProdOrderSizes);
	SET @SavingInKBProdBOM = (SELECT SavingInKBProdBOM FROM #tempProdOrderSizes);
	SET @SavingInKBProdTable = (SELECT SavingInKBProdTable FROM #tempProdOrderSizes);

	DROP TABLE #tempProdOrderSizes
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB ProdJournalRoute: ' + CAST(@SavingInKBProdJournalRoute AS NVARCHAR) + ', Saving In KB ProdJournalProd2: ' + CAST(@SavingInKBProdJournalProd2 AS NVARCHAR) + ', Saving In KB ProdJournalProd: ' + CAST(@SavingInKBProdJournalProd AS NVARCHAR) + ', Saving In KB ProdJournalBOM: ' + CAST(@SavingInKBProdJournalBOM AS NVARCHAR) + ', Saving In KB ProdJournalTable: ' + CAST(@SavingInKBProdJournalTable AS NVARCHAR) + ', Saving In KB ProdCalcTrans: ' + CAST(@SavingInKBProdCalcTrans AS NVARCHAR) + ', Saving In KB WrkCtrCapRes: ' + CAST(@SavingInKBWrkCtrCapRes AS NVARCHAR) + ', Saving In KB ProdRouteJob: ' + CAST(@SavingInKBProdRouteJob AS NVARCHAR) + ', Saving In KB ProdRoute: ' + CAST(@SavingInKBProdRoute AS NVARCHAR) + ', Saving In KB ProdBOM: ' + CAST(@SavingInKBProdBOM AS NVARCHAR) + ', Saving In KB ProdTable: ' + CAST(@SavingInKBProdTable AS NVARCHAR)
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Purchase update history cleanup
	--
	SET @RuleID = 475
	SET @RuleName = 'Upgrade Purchase update history cleanup';
	SET @Observation  = 'When a purchase order is updated such as a confirmation, receipts list, or invoice, information is stored and tracked in the PURCHPARMTABLE, PURCHPARMUPDATE, PURCHPARMSUBTABLE, PURCHPARMSUBLINE, and PURCHPARMLINE tables. Once a record is marked with a status of EXECUTED, the information is no longer necessary to retain. The purchase update cleanup process removes old purchase update history records and should be scheduled to execute on a regular basis.';
	SET @Recommendation  = 'Use the Delete history of update form to delete the update history. 1. Click Procurement and sourcing > Periodic > Clean up > Purchase update history cleanup. 2. In the Clean up field, select the status of the update history to be deleted as Executed. 3. In the Created until field, select the date up to which the update history is to be deleted. 4. Click OK to delete the update history and close the form.';
	IF(OBJECT_ID('tempdb..#tempPurchUpdateHistorySizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempPurchUpdateHistorySizes
	END


	CREATE TABLE #tempPurchUpdateHistorySizes
	(
	 SavingInKBPurchParmTable real,
	 SavingInKBPurchParmLine real,
	 SavingInKBPurchParmSubTable real,
	 SavingInKBPurchParmUpdate real,
	 TotalEstimatedSavingInMB real

	)
	INSERT INTO #tempPurchUpdateHistorySizes(SavingInKBPurchParmTable)
	SELECT
	ISNULL((
	 SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	 FROM sys.tables t
	 INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	 INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	 INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	 WHERE t.NAME ='PURCHPARMTABLE'
	 GROUP BY t.Name,p.Rows),0) * count(recID) AS SavingInKB

	FROM PurchPARMTABLE 
	WHERE PARMJOBSTATUS=0

	UPDATE #tempPurchUpdateHistorySizes
	SET SavingInKBPurchParmLine = 
	 ( SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	  FROM sys.tables t
	  INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	  INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	  INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	  WHERE t.NAME ='PURCHPARMLINE'
	  GROUP BY t.Name,p.Rows),0) * count(PURCHPARMLINE.recID)
	FROM PURCHPARMTABLE, PURCHPARMLINE
	WHERE PURCHPARMTABLE.PARMJOBSTATUS=0
	and PURCHPARMTABLE.DATAAREAID = PURCHPARMLINE.DATAAREAID
	and PURCHPARMTABLE.PARMID = PURCHPARMLINE.PARMID)

	UPDATE #tempPurchUpdateHistorySizes
	SET SavingInKBPurchParmSubTable = 
	 ( SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	  FROM sys.tables t
	  INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	  INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	  INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	  WHERE t.NAME ='PURCHPARMSUBTABLE'
	  GROUP BY t.Name,p.Rows),0) * count(PURCHPARMSUBTABLE.recID)
	 FROM PURCHPARMTABLE, PURCHPARMSUBTABLE 
	 WHERE PURCHPARMTABLE.PARMJOBSTATUS=0
	 and PURCHPARMTABLE.DATAAREAID = PURCHPARMSUBTABLE.DATAAREAID
	 and PURCHPARMTABLE.PARMID = PURCHPARMSUBTABLE.PARMID)

	UPDATE #tempPurchUpdateHistorySizes
	SET SavingInKBPurchParmUpdate = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	  FROM sys.tables t
	  INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	  INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	  INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	  WHERE t.NAME ='PURCHPARMUPDATE'
	  GROUP BY t.Name,p.Rows),0) * count(PURCHPARMUPDATE.recID)
	 FROM PURCHPARMTABLE, PURCHPARMUPDATE  
	 WHERE PURCHPARMTABLE.PARMJOBSTATUS=0
	 and PURCHPARMTABLE.DATAAREAID = PURCHPARMUPDATE.DATAAREAID
	 and PURCHPARMTABLE.PARMID = PURCHPARMUPDATE.PARMID)

	UPDATE #tempPurchUpdateHistorySizes
	SET TotalEstimatedSavingInMB = (SavingInKBPurchParmUpdate + SavingInKBPurchParmSubTable + SavingInKBPurchParmLine + SavingInKBPurchParmTable) /1024

	DECLARE @SavingInKBPurchParmUpdate AS REAL;
	DECLARE @SavingInKBPurchParmSubTable AS REAL;
	DECLARE @SavingInKBPurchParmLine AS REAL;
	DECLARE @SavingInKBPurchParmTable AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempPurchUpdateHistorySizes);
	SET @SavingInKBPurchParmUpdate = (SELECT SavingInKBPurchParmUpdate FROM #tempPurchUpdateHistorySizes);
	SET @SavingInKBPurchParmSubTable = (SELECT SavingInKBPurchParmSubTable FROM #tempPurchUpdateHistorySizes);
	SET @SavingInKBPurchParmLine = (SELECT SavingInKBPurchParmLine FROM #tempPurchUpdateHistorySizes);
	SET @SavingInKBPurchParmTable = (SELECT SavingInKBPurchParmTable FROM #tempPurchUpdateHistorySizes);
	DROP TABLE #tempPurchUpdateHistorySizes
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB PurchParmUpdate: ' + CAST(@SavingInKBPurchParmUpdate AS NVARCHAR) + ', Saving In KB PurchParmSubTable: ' + CAST(@SavingInKBPurchParmSubTable AS NVARCHAR) + ', Saving In KB PurchParmLine: ' + CAST(@SavingInKBPurchParmLine AS NVARCHAR) + ', Saving In KB PurchParmTable: ' + CAST(@SavingInKBPurchParmTable AS NVARCHAR)
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Sales and marketing transaction log clean up
	--
	SET @RuleID = 480
	SET @RuleName = 'Upgrade Sales and marketing transaction log clean up';
	SET @Observation  = 'The sales and marketing module contains a feature to trans the creation, deletion and update of various types of transaction, this feature is turned on by default but can generate a large amount of data over time. This rule has detected a significant amount of data within this log which could be cleaned up.';
	SET @Recommendation  = 'Delete rows older than a certain date via TSQL. Note that the logic in this query to delete rows in chunks of 1 million rows is to prevent the database log growing very large if the table has many rows. DECLARE @COUNT INT, @LOOPS INT, @DATAAREAID VARCHAR(10), @NUMBEROFYEARSTOKEEP INT, @DATEBEFORE DATETIME -- SET THE VALUES BELOW FOR YEARS TO KEEP AND DATAAREAID set @NUMBEROFYEARSTOKEEP = 1 set @DATAAREAID = ''usrt'' set @DATEBEFORE = DATEADD(year, @NUMBEROFYEARSTOKEEP * -1, GETDATE()) set @LOOPS = ((select count(recid) from SMMTRANSLOG WHERE DATAAREAID = @DATAAREAID AND LOGDATETIME < @DATEBEFORE)/1000)+1 set @COUNT = 1 WHILE @COUNT <= @LOOPS BEGIN delete SMMTRANSLOG WHERE RECID IN  (SELECT TOP 1000000 X.RECID  FROM SMMTRANSLOG X  WHERE X.DATAAREAID = @DATAAREAID  AND X.LOGDATETIME < @DATEBEFORE)set @COUNT = @COUNT+1 END';
	SET @TotalEstimatedSavingInMBReal = (SELECT( ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='SMMTRANSLOG'
											GROUP BY t.Name,p.Rows
											) * COUNT(SMMTRANSLOG.RECID),0)
											)/1024 AS TotalEstimatedSavingInMB
											FROM SMMTRANSLOG
											WHERE DateDiff(year,SMMTRANSLOG.LOGDATETIME, GetDate()) > 1)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Sales order entry statistics clean up
	--
	SET @RuleID = 485
	SET @RuleName = 'Upgrade Sales order entry statistics clean up';
	SET @Observation  = 'Localization - Sweden: Tracking sales order entry statistics increases the amount of space required for data storage. It is a good idea to periodically remove sales order entry statistics that you no longer need to keep. This is only applicable for legal entities whose primary address is in Sweden';
	SET @Recommendation  = 'Use the “Order entry statistics clean up” process to delete order entry statistics that are no longer needed. 1. Click Sales and marketing > Periodic > Clean up > Order entry statistics clean up. 2. In the Created until field, select the last date on which statistic lines should be deleted. 3. Click OK.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='salesOrderEntryStatistics'
											GROUP BY t.Name,p.Rows),0) * count(recID)
											)/1024 as TotalEstimatedSavingInMB
											FROM salesOrderEntryStatistics)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Sales update history cleanup
	--
	SET @RuleID = 490
	SET @RuleName = 'Upgrade Sales update history cleanup';
	SET @Observation  = 'When a sales order is updated such as a confirmation, receipts list, or invoice, information is stored and tracked in the SALESPARMTABLE, SALESPARMUPDATE, SALESPARMSUBTABLE, SALESPARMSUBLINE, and SALESPARMLINE tables. Once a record is marked with a status of EXECUTED, the information is no longer necessary to retain. The sales update cleanup process removes old sales update history records and should be scheduled to execute on a regular basis.';
	SET @Recommendation  = 'Use the Delete history of update form to delete the update history. 1. Click Sales and marketing > Periodic > Clean up > Sales update history cleanup. 2. In the Clean up field, select the status of the update history to be deleted as Executed. 3. In the Created until field, select the date up to which the update history is to be deleted. 4. Click OK to delete the update history and close the form.';
	IF(OBJECT_ID('tempdb..#tempSalesUpdateHistorySizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempSalesUpdateHistorySizes
	END

	CREATE TABLE #tempSalesUpdateHistorySizes
	(
		SavingInKBSalesParmTable REAL,
		SavingInKBSalesParmLine REAL,
		SavingInKBSalesParmSubTable REAL,
		SavingInKBSalesParmUpdate REAL,
		TotalEstimatedSavingInMB REAL
	)
	INSERT INTO #tempSalesUpdateHistorySizes(SavingInKBSalesParmTable)
	SELECT
	 ISNULL((
	  SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real),0)
	  FROM sys.tables t
	  INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	  INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	  INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	  WHERE t.NAME ='SALESPARMTABLE'
	  GROUP BY t.Name,p.Rows
	 ),0) * COUNT(recID) AS SavingInKB
	FROM SALESPARMTABLE 
	WHERE PARMJOBSTATUS=0

	UPDATE #tempSalesUpdateHistorySizes
	SET SavingInKBSalesParmLine = 
	 ISNULL((SELECT (SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real),0) 
	  FROM sys.tables t
	  INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	  INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	  INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	  WHERE t.NAME ='SALESPARMLINE'
	  GROUP BY t.Name,p.Rows) * count(SALESPARMLINE.recID)
	  FROM SALESPARMTABLE, SALESPARMLINE
	  WHERE SALESPARMTABLE.PARMJOBSTATUS=0
	  and SALESPARMTABLE.DATAAREAID = SALESPARMLINE.DATAAREAID
	  and SALESPARMTABLE.PARMID = SALESPARMLINE.PARMID
	  ),0)

	UPDATE #tempSalesUpdateHistorySizes
	SET SavingInKBSalesParmSubTable = 
	 (
	  SELECT 
	   ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real),0)
	   FROM sys.tables t
	   INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	   INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	   INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	   WHERE t.NAME ='SALESPARMSUBTABLE'
	   GROUP BY t.Name,p.Rows),0) * count(SALESPARMSUBTABLE.recID)
	  FROM SALESPARMTABLE, SALESPARMSUBTABLE 
	  WHERE SALESPARMTABLE.PARMJOBSTATUS=0
	  and SALESPARMTABLE.DATAAREAID = SALESPARMSUBTABLE.DATAAREAID
	  and SALESPARMTABLE.PARMID = SALESPARMSUBTABLE.PARMID
	 )

	UPDATE #tempSalesUpdateHistorySizes
	set SavingInKBSalesParmUpdate = 
	 (
	  SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real),0)
	   FROM sys.tables t
	   INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	   INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	   INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	   WHERE t.NAME ='SALESPARMUPDATE'
	   GROUP BY t.Name,p.Rows),0) * count(SALESPARMUPDATE.recID)
	  FROM SALESPARMTABLE, SALESPARMUPDATE  
	  WHERE SALESPARMTABLE.PARMJOBSTATUS=0
	  and SALESPARMTABLE.DATAAREAID = SALESPARMUPDATE.DATAAREAID
	  and SALESPARMTABLE.PARMID = SALESPARMUPDATE.PARMID)

	UPDATE #tempSalesUpdateHistorySizes
	SET TotalEstimatedSavingInMB = (SavingInKBSalesParmUpdate + SavingInKBSalesParmSubTable + SavingInKBSalesParmLine + SavingInKBSalesParmTable) /1024

	DECLARE @SavingInKBSalesParmUpdate AS REAL;
	DECLARE @SavingInKBSalesParmSubTable AS REAL;
	DECLARE @SavingInKBSalesParmLine AS REAL;
	DECLARE @SavingInKBSalesParmTable AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempSalesUpdateHistorySizes);
	SET @SavingInKBSalesParmUpdate = (SELECT SavingInKBSalesParmUpdate FROM #tempSalesUpdateHistorySizes);
	SET @SavingInKBSalesParmSubTable = (SELECT SavingInKBSalesParmSubTable FROM #tempSalesUpdateHistorySizes);
	SET @SavingInKBSalesParmLine = (SELECT SavingInKBSalesParmLine FROM #tempSalesUpdateHistorySizes);
	SET @SavingInKBSalesParmTable = (SELECT SavingInKBSalesParmTable FROM #tempSalesUpdateHistorySizes);
	DROP TABLE #tempSalesUpdateHistorySizes
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB SalesParmUpdate: ' + CAST(@SavingInKBSalesParmUpdate AS NVARCHAR) + ', Saving In KB SalesParmSubTable: ' + CAST(@SavingInKBSalesParmSubTable AS NVARCHAR) + ', Saving In KB SalesParmLine: ' + CAST(@SavingInKBSalesParmLine AS NVARCHAR) + ', Saving In KB SalesParmTable: ' + CAST(@SavingInKBSalesParmTable AS NVARCHAR)
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade SQL statement trace log cleanup
	--
	SET @RuleID = 495
	SET @RuleName = 'Upgrade SQL statement trace log cleanup';
	SET @Observation  = 'Delete the SQL statement trace log to recover database space. This is an all or nothing option. You can export the log before deleting to refer to later. This log is a record of queries over a certain time threshold or SQL errors used for troubleshooting purposes.';
	SET @Recommendation  = 'Click System administration > Inquiries > Database > SQL statement trace log Click the Functions > Clear log button Click yes to the prompt Note: you can export the log before deleting to allow you to retain a copy, by selecting Functions > Export to';
	IF(OBJECT_ID('tempdb..#tempSQLStatementSizes') IS NOT NULL)
	BEGIN 
		DROP TABLE #tempSQLStatementSizes
	END

	CREATE TABLE #tempSQLStatementSizes
	(
		SavingInKBSysTraceTableSQL REAL,
		SavingInKBSysTraceTableSQLExecPlan REAL,
		SavingInKBSysTraceTableSQLTabRef REAL,
		TotalEstimatedSavingInMB REAL
	)

	INSERT into #tempSQLStatementSizes (SavingInKBSysTraceTableSQL)
	SELECT ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='SYSTRACETABLESQL'
	GROUP BY t.Name,p.Rows),0) * count(SYSTRACETABLESQL.recID)
	FROM SYSTRACETABLESQL

	UPDATE #tempSQLStatementSizes
	set SavingInKBSysTraceTableSQLExecPlan = 
	 (SELECT 
	  ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='SYSTRACETABLESQLEXECPLAN'
	GROUP BY t.Name,p.Rows),0) * count(SYSTRACETABLESQLEXECPLAN.recID)
	FROM SYSTRACETABLESQLEXECPLAN)

	UPDATE #tempSQLStatementSizes
	set SavingInKBSysTraceTableSQLTabRef = 
	 (SELECT 
	 ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
	FROM sys.tables t
	INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
	INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
	WHERE t.NAME ='SYSTRACETABLESQLTABREF'
	GROUP BY t.Name,p.Rows),0) * count(SYSTRACETABLESQLTABREF.recID)
	FROM SYSTRACETABLESQLTABREF)

	UPDATE #tempSQLStatementSizes
	SET TotalEstimatedSavingInMB = (SavingInKBSysTraceTableSQLExecPlan + SavingInKBSysTraceTableSQLTabRef + SavingInKBSysTraceTableSQL) /1024

	DECLARE @SavingInKBSysTraceTableSQLExecPlan AS REAL;
	DECLARE @SavingInKBSysTraceTableSQLTabRef AS REAL;
	DECLARE @SavingInKBSysTraceTableSQL AS REAL;
	SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempSQLStatementSizes);
	SET @SavingInKBSysTraceTableSQLExecPlan = (SELECT SavingInKBSysTraceTableSQLExecPlan FROM #tempSQLStatementSizes);
	SET @SavingInKBSysTraceTableSQLTabRef = (SELECT SavingInKBSysTraceTableSQLTabRef FROM #tempSQLStatementSizes);
	SET @SavingInKBSysTraceTableSQL = (SELECT SavingInKBSysTraceTableSQL FROM #tempSQLStatementSizes);
	DROP TABLE #tempSQLStatementSizes
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB SysTraceTableSQLExecPlan: ' + CAST(@SavingInKBSysTraceTableSQLExecPlan AS NVARCHAR) + ', Saving In KB SysTraceTableSQLTabRef: ' + CAST(@SavingInKBSysTraceTableSQLTabRef AS NVARCHAR) + ', Saving In KB SysTraceTableSQL: ' + CAST(@SavingInKBSysTraceTableSQL AS NVARCHAR)
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Time registrations archive cleanup
	--
	SET @RuleID = 500
	SET @RuleName = 'Upgrade Time registrations archive cleanup';
	SET @Observation  = 'Previously archived time registrations can be cleaned up. You can remove archived registrations by deleting them or exporting them to a file.';
	SET @Recommendation  = '1. Click Production control > Inquiries > Registrations > Raw registrations archive. 2. On the toolbar click the Clean up registrations button. 3. In the Cleanup mode field, select how you want to handle the old registrations: ◦ Select To file to move the registrations to an external file. ◦ Select Delete to permanently delete the registrations. 4. In the Maximum age field, enter the maximum age, in days, of registrations that are kept in the raw registrations table. For example, if you enter the number 20, all registrations that are more than 20 days old are archived according to your selection in the Cleanup mode field. 5. If you select To file in the Cleanup mode field, enter a file name, or select an existing file, in the File name field.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='JMGTERMREGARCHIVE'
											GROUP BY t.Name,p.Rows),0) * count(JMGTERMREGARCHIVE.recID)) /1024 as TotalEstimatedSavingInMB
											FROM JMGTERMREGARCHIVE
											WHERE  DateDiff(month, JMGTERMREGARCHIVE.REGDATETIME, GetDate()) > 2)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade Time registrations cleanup
	--
	SET @RuleID = 505
	SET @RuleName = 'Upgrade Time registrations cleanup';
	SET @Observation  = 'Registrations can accumulate in Microsoft Dynamics AX over time, and can reduce the performance of the application. Therefore, we recommend that you clean up old registrations periodically. You can remove old registrations in the following ways: • You can delete them. • You can export them to a file.';
	SET @Recommendation  = '1. Click Human resources > Periodic > Time and attendance > Update > Clean up registrations. –or– Click Production control > Periodic > Clean up > Clean up registrations. -or– Click Production control > Inquiries > Registrations > Raw registrations archive. On the toolbar, click Clean up registrations. 2. In the Cleanup mode field, select how you want to handle the old registrations: ◦ Select To table to move the registrations to another table in Microsoft Dynamics AX. The registrations are transferred to the Raw registrations archive form. ◦ Select To file to move the registrations to an external file. ◦ Select Delete to permanently delete the registrations. 3. In the Maximum age field, enter the maximum age, in days, of registrations that are kept in the raw registrations table. For example, if you enter the number 20, all registrations that are more than 20 days old are archived according to your selection in the Cleanup mode field. 4. If you select To file in the Cleanup mode field, enter a file name, or select an existing file, in the File name field.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (
											ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='JMGTERMREG'
											GROUP BY t.Name,p.Rows),0) * count(JMGTERMREG.recID)) /1024 as TotalEstimatedSavingInMB
											FROM JMGTERMREG
											WHERE  DateDiff(month, JMGTERMREG.REGDATETIME, GetDate()) > 2)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

	--
	-- Rule: Upgrade User log cleanup
	--
	SET @RuleID = 510
	SET @RuleName = 'Upgrade User log cleanup';
	SET @Observation  = 'Delete user logs older than a certain date. This rule has checked for logs over 3 month old. This log is a record of users logging in and out of the system.';
	SET @Recommendation  = '1. Click System administration > Inquiries > Users > User log. Click Clean up. 2. Enter a value in the History limit (days) field to define a limit for the deletion. Only log information that is older than the given number of days is deleted. 3. Click Select to open the Select log cleanup criteria form, which is a version of the Inquiry form. 4. Select your cleanup criteria. Select a user or a range of users and, optionally, additional user information, such as date and time. for more information, see Inquiry (form). 5. Click OK to return to the User log cleanup form. 6. Click OK to perform the cleanup once, or click the Batch tab to define parameters to clean up the user log regularly.';
	SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
											FROM sys.tables t
											INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
											INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
											INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
											WHERE t.NAME ='SYSUSERLOG'
											GROUP BY t.Name,p.Rows),0) * count(SYSUSERLOG.recID))/1024 as TotalEstimatedSavingInMB
											FROM SYSUSERLOG
											WHERE DateDiff(month,SYSUSERLOG.LOGOUTDATETIME, GetDate()) > 3)
	SET @AdditionalComments  = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
	IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END

--
-- Additional Rule Code Template Section
--

/*
	--
	-- Rule: XXXXX
	--
	SET @RuleID = 0
	SET @RuleName = '';
	SET @Observation  = '';
	SET @Recommendation  = '';
	SET @AdditionalComments  = '';
	IF(1=0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
*/

-- 
-- Output Results
--
SELECT RuleID AS 'Rule ID',RuleSection AS 'Rule Section', RuleName AS 'Rule Name', Observation, Recommendation, AdditionalComments AS 'Additional Comments'
FROM #D365UpgradeAnalysisReport
ORDER BY 1;

-- Clean up
DROP TABLE #D365UpgradeAnalysisReport;
