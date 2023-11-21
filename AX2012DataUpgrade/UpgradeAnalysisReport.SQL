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

-- Revision History
-- 1.0 Initial release of report
-- 1.1 Additional rules added for: Partitoin Validation, Application Version, Document Attchement Checks, Use of an ISV model, Database Collation
-- 1.2 New rule sections - SCM Enhancements, Finance Enhancements
-- 1.3 Modified all rules so variables are declared per rule. Allows for rules to be moved \ added\ deleted without impact to others. 
-- 1.4 Additional parameter added to allow for comments if rule condition isn't met. Set parameter @ShowWhenUnobserved to enable output. 



--
-- Tuning Parameters
--
	DECLARE @LargeTableThreshold INT = 10000 -- Threshold for large table analysis (in MB)
	DECLARE @EstimatedSavingThreshold INT = 100 -- Threshold for data cleanup operations (in MB)
	DECLARE @CleanupRecordCountThreshold INT = 1000 -- Threshold for large Inventory Cleanup 

--
-- Report Parameters
--
	DECLARE @ShowWhenUnobserved BIT = 0;
	DECLARE @RequestedDate DATETIME = GETDATE();


--
-- Report Temp Tables
--
	SET NOCOUNT ON;
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

	IF(OBJECT_ID('tempdb..#D365UpgradeAnalysisReportGlobalVariables') IS NOT NULL)
	BEGIN 
		DROP TABLE #D365UpgradeAnalysisReportGlobalVariables
	END
	CREATE TABLE #D365UpgradeAnalysisReportGlobalVariables (
		LargeTableThreshold INT,
		EstimatedSavingThreshold INT,
		CleanupRecordCountThreshold INT,
		ShowWhenUnobserved BIT,
		RequestedDate DATETIME
	)
	
	INSERT INTO #D365UpgradeAnalysisReportGlobalVariables (LargeTableThreshold, EstimatedSavingThreshold, CleanupRecordCountThreshold, ShowWhenUnobserved, RequestedDate)
		VALUES (@LargeTableThreshold, @EstimatedSavingThreshold, @CleanupRecordCountThreshold, @ShowWhenUnobserved, @RequestedDate);
	GO

--
-- Rule Section: Deprecated Features 
--

	--
	-- Rule: Upgrade Deprecated feature Virtual companies
	--
	-- TODO - add note for single record sharing 
		DECLARE @RuleID INT = 1000;
		DECLARE @RuleSection NVARCHAR(100) = 'Deprecated Features';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Deprecated feature Virtual companies';
		DECLARE @Observation NVARCHAR(MAX) = 'The virtual companies feature is deprecated in Dynamics 365 for Operations. This rule has identified that virtual companies exist in the AX2012 environment. This configuration will not function in Dynamics 365 for Operations.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Look at the cross company data sharing feature in Dynamics 365 for Operations: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/sysadmin/cross-company-data-sharing';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((SELECT COUNT(*) AS TotalActiveVirtualCompanies FROM DataArea WHERE IsVirtual = 1) > 0)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO


	--
	-- Rule: Upgrade Deprecated tables
	--
		DECLARE @RuleID INT = 1010;
		DECLARE @RuleSection NVARCHAR(100) = 'Deprecated Features';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Deprecated tables';
		DECLARE @Observation NVARCHAR(MAX) = 'The tables listed are deprecated in Dynamics 365 for Operations. This rule has identifed data exists in one or more of these tables, please ensure either this data is not required or write a customization  to move the data. Tables: ';
		DECLARE @Recommendation NVARCHAR(MAX) = 'A developer should review the output of this rule to determine whether data is required and write custom code to retain the data is necessary.';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
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
		GO
	

	--
	-- Rule: Upgrade Partition validation
	--
		DECLARE @RuleID INT = 1020;
		DECLARE @RuleSection NVARCHAR(100) = 'Deprecated Features';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Partition validation';
		DECLARE @Observation NVARCHAR(MAX) = 'Dynamics 365 for Operations does not support multiple partitions. This rule has identified multiple partitions exist in the AX2012 environment. This means that upgrade to Dynamics 365 for Operations is not possible.';
		DECLARE @Recommendation NVARCHAR(MAX) = '';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((SELECT COUNT(*) AS TotalPartitions FROM Partitions) > 1)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

	--
	-- Rule: Enterprise portal use
	--
		DECLARE @RuleID INT = 1030;
		DECLARE @RuleSection NVARCHAR(100) = 'Deprecated Features';
		DECLARE @RuleName NVARCHAR(500) = 'Enterprise Portal';
		DECLARE @Observation NVARCHAR(MAX) = 'Based on the parameter setup, we have identified that you are probably using Enterprise portal.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Dynamics 365 comes with modern browser based interface and simplify the use cases around enterprise portal. In Dynamics 365 enterprise portal has been deprecated.';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF ((SELECT COUNT(RECID) FROM EPWEBSITEPARAMETERS WHERE INTERNALURL <>'') > 0)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO


--
-- Rule Section: Environment Settings
--

	--
	-- Rule: Application Version
	--
		DECLARE @RuleID INT = 2000;
		DECLARE @RuleSection NVARCHAR(100) = 'Environment Settings';
		DECLARE @RuleName NVARCHAR(500) = 'Application Version';
		DECLARE @Observation NVARCHAR(MAX) = '';
		DECLARE @Recommendation NVARCHAR(MAX) = '';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';

		DECLARE @ModelDatabase AS VARCHAR(100) = DB_NAME() + '_Model';
		DECLARE @Count AS INT
		DECLARE @VersionMajorMinor DECIMAL(2,1);
		DECLARE @VersionBuildRevision DECIMAL(8,4);
		DECLARE @sql NVARCHAR(MAX);
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
			SET @Observation = 'AX 2012 RTM (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is NOT a supported upgrade path ';
			SET @Recommendation = 'Only AX 2012 R2 CU9 and AX 2012 R3 CU13 are supported upgrade paths';	
		END
		IF(@VersionMajorMinor = 6.2) 
		BEGIN 
			IF(@VersionBuildRevision < 3000.110)
			BEGIN
				SET @Observation = 'AX 2012 R2 CU8 or lower (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is NOT a supported upgrade path ';
				SET @Recommendation = 'Only AX 2012 R2 CU9 or higher is a supported upgrade path';	
			END
			ELSE
			BEGIN
				SET @Observation = 'AX 2012 R2 CU9 or higher (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is a supported upgrade path ';
				SET @Recommendation = 'Validate version to ensure you are on a valid supported version of AX 2012 R2 CU9 or higher. ';	
			END
		END
		IF(@VersionMajorMinor = 6.3) 
		BEGIN 
			IF(@VersionBuildRevision < 6000.149)
			BEGIN
				SET @Observation = 'AX 2012 R3 CU12 or lower (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is NOT a supported upgrade path ';
				SET @Recommendation = 'Only AX 2012 R3 CU13 or higher is a supported upgrade path';	
			END
			ELSE
			BEGIN
				SET @Observation = 'AX 2012 R3 CU13 or higher (Application version ' + CAST(@VersionMajorMinor AS VARCHAR(3)) + '.' + CAST(@VersionBuildRevision AS VARCHAR(9)) + ') has been detected. This is a supported upgrade path ';
				SET @Recommendation = 'Validate version to ensure you are on a valid supported version of AX 2012 R3 CU13 or higher. ';	
			END
		END

		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

	--
	-- Rule: Alert Rules
	--
		DECLARE @RuleID INT = 2010;
		DECLARE @RuleSection NVARCHAR(100) = 'Environment Settings';
		DECLARE @RuleName NVARCHAR(500) = 'Alert Rules';
		DECLARE @Observation NVARCHAR(MAX) = 'This rule has identified that alerts exist in the AX2012 environment.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Alerts may not upgrade, and may need to be recreated. For details on alerts see: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/fin-ops/get-started/create-alerts';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((SELECT COUNT(*) AS TotalActiveAlertRules FROM EventRule) > 0)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

	--
	-- Rule: Document Attachments File Share
	--
		DECLARE @RuleID INT = 2020;
		DECLARE @RuleSection NVARCHAR(100) = 'Environment Settings';
		DECLARE @RuleName NVARCHAR(500) = 'Document Attachments File Share';
		DECLARE @Observation NVARCHAR(MAX) = 'This rule has identified that you have document attachments on a file share';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Attachments on a file share need to be migrated into the database to get upgraded, see: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/migration-upgrade/migrate-doc-attachments-ax-2012';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((SELECT COUNT(T1.RECID) FROM DOCUREF T1 JOIN DOCUTYPE T2 ON T1.TYPEID = T2.TYPEID AND T1.PARTITION = T2.PARTITION AND T1.REFCOMPANYID = T2.DATAAREAID WHERE T2.FILEPLACE = 0) > 0)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

	--
	-- Rule: Document Attachments SharePoint
	--
		DECLARE @RuleID INT = 2030;
		DECLARE @RuleSection NVARCHAR(100) = 'Environment Settings';
		DECLARE @RuleName NVARCHAR(500) = 'Document Attachments SharePoint';
		DECLARE @Observation NVARCHAR(MAX) = 'This rule has identified that you have document attachments in SharePoint';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Migration of attachments in SharePoint is not currently supported. You will need to manually migrate these as needed';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((SELECT COUNT(T1.RECID) FROM DOCUREF T1 JOIN DOCUTYPE T2 ON T1.TYPEID = T2.TYPEID AND T1.PARTITION = T2.PARTITION AND T1.REFCOMPANYID = T2.DATAAREAID WHERE T2.FILEPLACE = 3) > 0)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO


	--TODO - Add in Database, and add comments for migration and upgrades. 

	--
	-- Rule: Development ISV VAR Models
	--
		DECLARE @RuleID INT = 2040;
		DECLARE @RuleSection NVARCHAR(100) = 'Environment Settings';
		DECLARE @RuleName NVARCHAR(500) = 'Development ISV VAR Models';
		DECLARE @Observation NVARCHAR(MAX) = 'It has been identified that you may have modules and models (customization) from an ISV or Microsoft Partner (VAR)';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Work with you ISV and\or VAR to ensure any modules and models you continue to need are available for D365. Certain ISV models are also idetified in this report, see secrtion later for further details on these';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		DECLARE @ModelDatabase AS VARCHAR(100);
		DECLARE @sql NVARCHAR(MAX);
		DECLARE @Count AS INT;
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
		GO
	

--
-- Rule Section: Database Settings
--

	--
	-- Rule: Database Collation
	--
		DECLARE @RuleID INT = 3000;
		DECLARE @RuleSection NVARCHAR(100) = 'Database Settings';
		DECLARE @RuleName NVARCHAR(500) = 'Database Collation';
		DECLARE @Observation NVARCHAR(MAX) = 'Database Collation is not SQL_Latin1_General_CP1_CI_AS';
		DECLARE @Recommendation NVARCHAR(MAX) = 'In order to upgrade a Tier 1 Development Cloud Hosted Environment or VHD, the collation of the database needs to be changed to SQL_Latin1_General_CP1_CI_AS. [NOTE!!]: The change in collation is handled automatically by the Data Migration Toolkit for Tier 2 Self-Service Environments';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((select collation_name from sys.databases where name = DB_NAME()) != 'SQL_Latin1_General_CP1_CI_AS')
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	
	--
	-- Rule: Database Size
	--
		DECLARE @RuleID INT = 3010;
		DECLARE @RuleSection NVARCHAR(100) = 'Database Settings';
		DECLARE @RuleName NVARCHAR(500) = 'Database Size';
		DECLARE @Observation NVARCHAR(MAX) = 'Database size is over 250GB';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Upgrading larger databases may require more planning, testing and tuning of the upgrade process, especially for the Self-Service (Tier 2+) upgrade process where replication is used';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((SELECT SUM(size * 8 / 1024 / 1024) AS 'Database_Size' FROM sys.master_files WHERE DB_NAME(database_id) = DB_NAME() AND TYPE = 0) >= 250)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

	--
	-- Rule: RCSI not configured
	--
		DECLARE @RuleID INT = 3020;
		DECLARE @RuleSection NVARCHAR(100) = 'Database Settings';
		DECLARE @RuleName NVARCHAR(500) = 'RCSI not configured';
		DECLARE @Observation NVARCHAR(MAX) = 'Read Committed Snapshot Isolation (RCSI) is not configured on the database';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Enable RSCI on this database with the following (Edit database name as needed): ALTER DATABASE MicrosoftDynamicsAX SET READ_COMMITTED_SNAPSHOT ON';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		IF((SELECT is_read_committed_snapshot_on FROM sys.databases WHERE [name] = DB_NAME()) = 0)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

--
-- Rule Section: SCM Enhancements
--

	--
	-- Rule: Supply and Demand Planning
	--
		DECLARE @RuleID INT = 4000;
		DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
		DECLARE @RuleName NVARCHAR(500) = 'Supply and Demand Planning';
		DECLARE @Observation NVARCHAR(MAX) = '';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Microsoft has changed Master Planning executiion in Dynamics 365 F&O. Microsoft has released new Planning Optimization service that is much more performant and scalable. New capabilities are available in Demand planning.';
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'See: https://learn.microsoft.com/en-us/dynamics365/supply-chain/master-planning/master-planning-home-page'
		
		DECLARE @ReqPlanId NVARCHAR(10);
		DECLARE @ReqLogId NVARCHAR(10);
		DECLARE @MaxDuration NUMERIC(32,2);
		DECLARE @DataArea NVARCHAR(4);
		DECLARE @SQL NVARCHAR(MAX);

		SET @ReqPlanId = '';
		SET @ReqLogId = '';
		SET @SQL = N'SELECT @MaxDuration = DATEDIFF(SECOND, STARTDATETIME, ENDDATETIME), @ReqPlanId = REQPLANID, @ReqLogId = REQLOGID,  @DataArea = DATAAREAID FROM REQLOG WHERE DATEDIFF(SECOND, STARTDATETIME, ENDDATETIME) = (SELECT MAX(DATEDIFF(SECOND,STARTDATETIME, ENDDATETIME)) FROM REQLOG)';

		EXEC sp_executesql @SQL, N'@MaxDuration NUMERIC(32,2) OUTPUT, @ReqPlanId NVARCHAR(10) OUTPUT, @ReqLogId NVARCHAR(10) OUTPUT, @DataArea NVARCHAR(4) OUTPUT',@MaxDuration OUTPUT, @ReqPlanId OUTPUT, @ReqLogId OUTPUT, @DataArea OUTPUT
		SET @MaxDuration = @MaxDuration/60;
		--TODO  - IF CONDITION HERE?
		SET @Observation = 'Based on the batch jobs history we have identified that you are using MRP. Master planning batch process takes maximum '+ CONVERT(NVARCHAR(MAX), @MaxDuration) + ' mins (max. time) Batch job id: ' + @ReqLogId + ' Company: ' + @DataArea;
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		GO
	

	--
	-- Rule: Inventory closing duration
	--
		DECLARE @RuleID INT = 4010;
		DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
		DECLARE @RuleName NVARCHAR(500) = 'Inventory closing duration';
		DECLARE @Observation NVARCHAR(MAX) = '';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Microsoft has optimized the performance of inventory closing process to make it much more performmant and scalable. Customers moving to the cloud are taking advantage of these new optimization in inventory closting duration.';
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Refer this link https://learn.microsoft.com/en-us/dynamics365/supply-chain/cost-management/inventory-close';
		
		DECLARE @SQL NVARCHAR(MAX);
		DECLARE @MaxDuration NUMERIC(32,2);
		DECLARE @TimeUnit VARCHAR(4) = 'sec';
		SET @SQL = N'SELECT @MaxDuration = END_ - START_ FROM INVENTCLOSING WHERE END_ - START_ = (SELECT MAX(END_ - START_) FROM INVENTCLOSING) AND EXECUTED >= GETDATE()-90';
		EXEC sp_executesql @SQL, N'@MaxDuration INT OUTPUT', @MaxDuration OUTPUT;

		IF (@MaxDuration > 3600)
			BEGIN
			SET @Observation = 'Based on the batch jobs history we have identified that inventory closing batch process is taking long time. Inventory closing process take maximum  '+ CAST(@MaxDuration/60 AS NVARCHAR(MAX))  + ' mins (max. time) in last 90 days.';
			
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO


	--
	-- Rule: Advance Warehouse management
	--
	DECLARE @RuleID INT = 4020;
	DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Advance warehouse management';
	DECLARE @Observation NVARCHAR(MAX) = 'Not enabled';  
	DECLARE @Recommendation NVARCHAR(MAX) = 'Microsoft has introduced warehouse-specific inventory transations. These transactions are optimized for warehouse operations, with important benefits for system performance and efficiency.';								
	DECLARE @AdditionalComments NVARCHAR(MAX) = 'See: https://cloudblogs.microsoft.com/dynamics365/it/2023/02/07/introducing-warehouse-specific-inventory-transactions/';

	DECLARE @InventLocationId NVARCHAR(10);
	DECLARE @LocationName NVARCHAR(60);
	DECLARE @DataArea NVARCHAR(4)
	DECLARE @WHSInfo NVARCHAR(MAX);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	SET @WHSInfo = '';

	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM INVENTLOCATION WHERE WHSENABLED = 1';
	
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;

	IF (@Count > 0)
	BEGIN
		SET @WHSInfo = 'Based on the warehouse setup, we have identified that following warehouses have advance warehouse management enabled.'
		DECLARE WarehouseCursor CURSOR FOR
		SELECT DATAAREAID, INVENTLOCATIONID, NAME FROM INVENTLOCATION WHERE WHSENABLED = 1;

		OPEN WarehouseCursor
		FETCH NEXT FROM WarehouseCursor INTO @DataArea, @InventLocationId, @LocationName;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @WHSInfo = @WHSInfo + @DataArea + ' - ' + @InventLocationId + ' - ' + @LocationName + ', ';
		FETCH NEXT FROM WarehouseCursor INTO @DataArea, @InventLocationId, @LocationName;
		END
		CLOSE WarehouseCursor;
		DEALLOCATE WarehouseCursor;
	
		IF (LEN(@WHSInfo) > 0)
		BEGIN
			SET @Observation = REVERSE(SUBSTRING(REVERSE(@WHSInfo), 3, 9999));	
		END
		
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO
	

	--
	-- Rule: Warehouse mobile app usage
	--
	DECLARE @RuleID INT = 4030;
	DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Warehouse mobile app usage';
	DECLARE @Observation NVARCHAR(MAX) = '';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';
	DECLARE @DataArea NVARCHAR(4);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM WHSRFMENUITEMTABLE';
	
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;

	IF (@Count > 0)
	BEGIN
		DECLARE WHMobileUseCompCursor CURSOR FOR
		SELECT DISTINCT DATAAREAID FROM WHSRFMENUITEMTABLE;

		OPEN WHMobileUseCompCursor
		FETCH NEXT FROM WHMobileUseCompCursor INTO @DataArea;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @Observation = @Observation + @DataArea + ', ';
		FETCH NEXT FROM WHMobileUseCompCursor INTO @DataArea;
		END
		CLOSE WHMobileUseCompCursor;
		DEALLOCATE WHMobileUseCompCursor;

		SET @Observation = 'We have identified that warehouse mobile device menu item setup  is present in your application for legal entities (' + REVERSE(SUBSTRING(REVERSE(@Observation), 3, 9999)) + '), which indicates that you are probably using AX 2012 Warehouse mobile portal.';
		SET @Recommendation = 'Microsoft has introduced Warehouse Management Moible app and enhanced many features, supporting Android and iOS platform.';
		SET @AdditionalComments = 'Refer this link https://learn.microsoft.com/en-us/dynamics365/supply-chain/warehousing/whats-new-wma';

		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Intercompany PO/SO
	--
	DECLARE @RuleID INT = 4040;
	DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';	
	DECLARE @RuleName NVARCHAR(500) = 'Intercompany Purchase Orders and\or Sales Orders';
	DECLARE @Observation NVARCHAR(MAX) = 'Intercompany setup has been detected';	
	DECLARE @Recommendation NVARCHAR(MAX) = 'There have been multiple enhancements in intercompany trade functionality in Dynamics 365 Finance and Operations, please review the provided resources.';
	DECLARE @AdditionalComments NVARCHAR(MAX) = 'Refer this link https://learn.microsoft.com/en-us/dynamics365/supply-chain/sales-marketing/intercompany-trade-set-up';
	IF ((SELECT COUNT(RECID) FROM INTERCOMPANYTRADINGRELATION WHERE ACTIVE = 1) > 0)
	BEGIN
	INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Warehouse mobile app usage
	--
	DECLARE @RuleID INT = 4050;
	DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Warehouse mobile app usage';
	DECLARE @Observation NVARCHAR(MAX) = '';
	DECLARE @Recommendation NVARCHAR(MAX) = 'Microsoft has introduced Warehouse Management Moible app and enhanced many features, supporting Android and iOS platform.';
	DECLARE @AdditionalComments NVARCHAR(MAX) = 'Refer this link https://learn.microsoft.com/en-us/dynamics365/supply-chain/warehousing/whats-new-wma';
	DECLARE @DataArea NVARCHAR(4)
	IF ((SELECT COUNT(RECID) FROM WHSRFMENUITEMTABLE) > 0)
	BEGIN
		DECLARE WHMobileUseCompCursor CURSOR FOR
		SELECT DISTINCT DATAAREAID FROM WHSRFMENUITEMTABLE;

		OPEN WHMobileUseCompCursor
		FETCH NEXT FROM WHMobileUseCompCursor INTO @DataArea;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @Observation = @Observation + @DataArea + ', ';
			FETCH NEXT FROM WHMobileUseCompCursor INTO @DataArea;
		END
		CLOSE WHMobileUseCompCursor;
		DEALLOCATE WHMobileUseCompCursor;

		SET @Observation = 'We have identified that warehouse mobile device menu item setup  is present in your application for legal entities (' + REVERSE(SUBSTRING(REVERSE(@Observation), 3, 9999)) + '), which indicates that you are probably using AX 2012 Warehouse mobile portal.';
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		 VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Inventory dimension (custom)
	--
	DECLARE @RuleID INT = 4060;
	DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Inventory Dimension (Custom)';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = 'Microsoft provides a finite set of unused dimension fields in Dynamics 365 Finance and Operations. We recommend you to review the use of custom inventory dimension in AX2012 and move this to new framework using extension.';
	DECLARE @AdditionalComments NVARCHAR(MAX) = 'Refer this link https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/extensibility/inventory-dimensions';

	DECLARE @DimName NVARCHAR(40)
	SET @DimName = '';

	DECLARE DimCursor CURSOR FOR
	SELECT NAME FROM SQLDICTIONARY
		WHERE TABLEID IN (SELECT TABLEID FROM SQLDICTIONARY
			WHERE NAME = 'INVENTDIM' AND FIELDID = 0)
			AND FIELDTYPE = 0
			AND NAME NOT IN ('INVENTDIM', 'INVENTDIMID', 'INVENTGTDID_RU', 'INVENTPROFILEID_RU', 'INVENTOWNERID_RU', 'MODIFIEDBY', 'DATAAREAID', 'INVENTBATCHID',  'WMSLOCATIONID', 'WMSPALLETID', 'INVENTSERIALID', 'INVENTLOCATIONID', 'CONFIGID', 'INVENTSIZEID', 'INVENTCOLORID', 'INVENTSITEID', 'INVENTSTYLEID', 'LICENSEPLATEID', 'INVENTSTATUSID');

	OPEN DimCursor
	FETCH NEXT FROM DimCursor INTO @DimName;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @Observation = @Observation + @DimName + ', ';
		FETCH NEXT FROM DimCursor INTO @DimName;
	END
	CLOSE DimCursor;
	DEALLOCATE DimCursor;

	IF (LEN(@Observation) > 0)
	BEGIN
		SET @Observation = 'The custom inventory dimention being used in AX2012: ' + REVERSE(SUBSTRING(REVERSE(@Observation), 3, 9999));
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Load planning workbench
	--
	DECLARE @RuleID INT = 4070;
	DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Load planning workbench';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = 'Microsoft has enhanced the experience of existing load planning workbench in Dynamics 365 F&O to have two separate forms. e.g. Inbound load planning workbench and Outbound load planning workbench with other performance enhancements.';
	DECLARE @AdditionalComments NVARCHAR(MAX) = 'Refer this link https://learn.microsoft.com/en-us/dynamics365/supply-chain/get-started/whats-new-scm-10-0-24#feature-enhancements-included-in-this-release';
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	IF ((SELECT COUNT(RECID) FROM WHSLOADTABLE) > 0)
	BEGIN
		SET @Observation = 'You are using Load planning workbench.';	
		SET @SQL = N'SELECT @Count = COUNT(RECID) FROM WHSLOADTABLE WHERE LOADDIRECTION = 1';	
		EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
		SET @Observation = @Observation + ' Inbound: ' + CONVERT(NVARCHAR(MAX), @Count);
		SET @SQL = N'SELECT @Count = COUNT(RECID) FROM WHSLOADTABLE WHERE LOADDIRECTION = 2';	
		EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
		SET @Observation = @Observation + ' Outbound: ' + CONVERT(NVARCHAR(MAX), @Count);
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


--
-- Rule Section: Finance Enhancements
--

	--
	-- Rule: Free text posting performance
	--
	DECLARE @RuleID INT = 5000;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Free text posting performance';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';
	DECLARE @InvoiceId NVARCHAR(20);
	DECLARE @DataArea NVARCHAR(4);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);

	SET @InvoiceId = '';

	SET @SQL = N'SELECT TOP 1 @DataArea = DATAAREAID, @InvoiceId = INVOICEID, @Count = COUNT(INVOICEID) FROM CUSTINVOICETRANS WHERE SALESID = '''' AND ' 
	SET @SQL = @SQL + 'INVOICEDATE BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') AND  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' 	+ 'GROUP BY INVOICEID, DATAAREAID ORDER BY COUNT(INVOICEID) DESC';
	EXEC sp_executesql @SQL, N'@DataArea NVARCHAR(4) OUTPUT, @InvoiceId NVARCHAR(20) OUTPUT, @Count INT OUTPUT', @DataArea OUTPUT, @InvoiceId OUTPUT, @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		SET @Observation = 'Highest number of transactions in the last 30 days are ' + CONVERT(NVARCHAR(MAX), @Count) + ' for invoice: ' + @InvoiceId + ' in ' + @DataArea + ' company.';	
	END

	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM CUSTINVOICETRANS WHERE SALESID = '''' AND INVOICEDATE BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') AND  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''';
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		SET @Observation = @Observation + ' Total number of transactions in the last 30 days: ' + CONVERT(NVARCHAR(MAX), @Count);	
	END

	IF(@Observation != '')
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO
	

	--
	-- Rule: Timesheet usage
	--
	DECLARE @RuleID INT = 5010;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Timesheet usage';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM TSTIMESHEETLINE WHERE MODIFIEDDATETIME BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''';
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		SET @Observation = 'Number of Timesheet transactions in the last 30 days: ' + CONVERT(NVARCHAR(MAX), @Count);	
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Expense Usage 
	--
	DECLARE @RuleID INT = 5020;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Expense Usage';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM TRVEXPTRANS WHERE MODIFIEDDATETIME BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''';
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		SET @Observation = 'Number of Expense transactions in the last 30 days: ' + CONVERT(NVARCHAR(MAX), @Count);	
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO
	

	--
	-- Rule: Project accounting usage 
	--
	DECLARE @RuleID INT = 5030;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Project accounting usage';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM PROJTRANSPOSTING WHERE PROJTRANSDATE BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + ''''; 
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		SET @Observation = 'Number of Project transactions in the last 30 days: ' + CONVERT(NVARCHAR(MAX), @Count);	
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Vendor invoice automation 
	--
	DECLARE @RuleID INT = 5040;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Vendor invoice automation';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @DataArea NVARCHAR(4)
	DECLARE @InvoiceDate DATETIME;
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);
	DECLARE @InvoiceId NVARCHAR(20);
	SET @SQL = N'SELECT TOP 1 @DataArea = DATAAREAID, @InvoiceId = INVOICEID, @Count = COUNT(INVOICEID) FROM VENDINVOICETRANS '
	SET @SQL = @SQL + 'WHERE INVOICEDATE BETWEEN DATEADD(DAY,-30,''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ' GROUP BY DATAAREAID, INVOICEID ORDER BY COUNT(INVOICEID) DESC';
	EXEC sp_executesql @SQL, N'@DataArea NVARCHAR(4) OUTPUT, @InvoiceId NVARCHAR(20) OUTPUT, @Count INT OUTPUT', @DataArea OUTPUT, @InvoiceId OUTPUT, @Count OUTPUT;

	IF (@Count > 0)
	BEGIN
		SET @Observation = @Observation + 'High volume of ' +  CONVERT(NVARCHAR(MAX), @Count) + ' AP invoices are detected for invoice ' +  @InvoiceId + ' in ' + @DataArea + ' company in the last 30 days.';	
	END 

	SET @SQL = N'SELECT TOP 1 @DataArea = DATAAREAID, @InvoiceDate = INVOICEDATE, @Count = COUNT(INVOICEDATE) FROM VENDINVOICETRANS	WHERE INVOICEDATE BETWEEN DATEADD(DAY,-30,' 
	SET @SQL = @SQL + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + 'GROUP BY DATAAREAID, INVOICEDATE ORDER BY COUNT(INVOICEDATE) DESC';
	EXEC sp_executesql @SQL, N'@DataArea NVARCHAR(4) OUTPUT, @InvoiceDate DATETIME OUTPUT, @Count INT OUTPUT', @DataArea OUTPUT, @InvoiceDate OUTPUT, @Count OUTPUT;

	IF (@Count > 0)
	BEGIN
		SET @Observation = @Observation + ' High volume of ' +  CONVERT(NVARCHAR(MAX), @Count) + ' AP invoices are detected for a single day on ' + CONVERT(NVARCHAR(MAX), CONVERT(DATE, @InvoiceDate))  + ' in ' + @DataArea + ' company in the last 30 days.';	
	END

	IF(@Observation != '')
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Huge volume of sales invoice posting 
	--
	DECLARE @RuleID INT = 5050;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Huge volume of sales invoice posting';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = 'Microsoft has optimized the performance of posting sales order and purchase order journals. This requires few parameter configuration to take effect of this enhancements.';
	DECLARE @AdditionalComments NVARCHAR(MAX) = 'Refer this link https://community.dynamics.com/blogs/post/?postid=bc4e25dd-24a9-48ba-af5d-1ccd8e04e95a';

	DECLARE @DataArea NVARCHAR(4);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);
	DECLARE @InvoiceId NVARCHAR(20);
	DECLARE @InvoiceDate DATETIME;
	SET @SQL = N'SELECT TOP 1 @DataArea = DATAAREAID, @InvoiceId = INVOICEID, @Count = COUNT(INVOICEID) FROM CUSTINVOICETRANS WHERE SALESID <> '''' '
	SET @SQL = @SQL + 'AND INVOICEDATE BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') AND  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + 'GROUP BY DATAAREAID, INVOICEID ORDER BY COUNT(INVOICEID) DESC';
	EXEC sp_executesql @SQL, N'@DataArea NVARCHAR(4) OUTPUT, @InvoiceId NVARCHAR(20) OUTPUT, @Count INT OUTPUT', @DataArea OUTPUT, @InvoiceId OUTPUT, @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		SET @Observation = 'You are posting ' + CONVERT(NVARCHAR(MAX), @Count) + ' number of invoice lines in single invoice ' + @InvoiceId + ' in ' + @DataArea + ' company in the last 30 days.';	
	END 

	SET @SQL = N'SELECT TOP 1 @DataArea = DATAAREAID, @InvoiceDate = INVOICEDATE, @Count = COUNT(INVOICEDATE) FROM CUSTINVOICETRANS WHERE SALESID <> '''' '
	SET @SQL = @SQL + 'AND INVOICEDATE BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + 'GROUP BY DATAAREAID, INVOICEDATE ORDER BY COUNT(INVOICEDATE) DESC';
	EXEC sp_executesql @SQL, N'@DataArea NVARCHAR(4) OUTPUT, @InvoiceDate DATETIME OUTPUT, @Count INT OUTPUT', @DataArea OUTPUT, @InvoiceDate OUTPUT, @Count OUTPUT;

	IF (@Count > 0)
	BEGIN
		SET @Observation = @Observation + ' You are posting ' + CONVERT(NVARCHAR(MAX), @Count) + ' number of invoices in peak hours on ' + CONVERT(VARCHAR(MAX), CONVERT(DATE, @InvoiceDate)) + ' in ' + @DataArea + ' company in the last 30 days.';	
	END

	IF (LEN(@Observation) > 0)
	BEGIN
		SET @Observation = @Observation + ' It indicates high volume of sales invoice posting.';
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Ledger journal transactions high daily volume 
	--
	DECLARE @RuleID INT = 5060;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Ledger journal transactions high daily volume';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @DataArea NVARCHAR(4);
	DECLARE @TransDate DATE;
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);
	SET @SQL = N'SELECT TOP 1 @DataArea = DATAAREAID, @TransDate = CAST(TRANSDATE AS DATE), @Count = COUNT(TRANSDATE) FROM LEDGERJOURNALTRANS ' 
	SET @SQL = @SQL + 'WHERE TRANSDATE BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' 	+ 'GROUP BY DATAAREAID, CAST(TRANSDATE AS DATE) '
	SET @SQL = @SQL + 'ORDER BY COUNT(TRANSDATE) DESC';
	EXEC sp_executesql @SQL, N'@DataArea NVARCHAR(4) OUTPUT, @TransDate DATE OUTPUT, @Count INT OUTPUT', @DataArea OUTPUT, @TransDate OUTPUT, @Count OUTPUT;

	IF (@Count > 0)
	BEGIN
		SET @Observation = @Observation + 'High daily volume of ' +  CONVERT(NVARCHAR(MAX), @Count) + ' ledger journal transactions are done on ' +  CONVERT(NVARCHAR(MAX), @TransDate) + ' in ' + @DataArea + ' company in the last 30 days.';	
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	GO


	--
	-- Rule: Ledger journal transactions large number of lines per journal 
	--
	DECLARE @RuleID INT = 5070;
	DECLARE @RuleSection NVARCHAR(100) = 'Finance Enhancements';
	DECLARE @RuleName NVARCHAR(500) = 'Ledger journal transactions large number of lines per journal';
	DECLARE @Observation NVARCHAR(MAX) = '';  
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	DECLARE @DataArea NVARCHAR(4);
	DECLARE @JournalNum NVARCHAR(10);
	DECLARE @RequestedDate DATETIME = (SELECT RequestedDate FROM #D365UpgradeAnalysisReportGlobalVariables);
	SET @SQL = N'SELECT TOP 1 @DataArea = DATAAREAID, @JournalNum = JOURNALNUM, @Count = COUNT(JOURNALNUM) FROM LEDGERJOURNALTRANS '
	SET @SQL = @SQL + 'WHERE TRANSDATE BETWEEN DATEADD(DAY,-30,' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + ') and  ' + '''' + CONVERT(NVARCHAR(MAX), @RequestedDate) + '''' + 'GROUP BY DATAAREAID, JOURNALNUM ORDER BY COUNT(JOURNALNUM) DESC';
	EXEC sp_executesql @SQL, N'@DataArea NVARCHAR(4) OUTPUT, @JournalNum NVARCHAR(10) OUTPUT, @Count INT OUTPUT', @DataArea OUTPUT, @JournalNum OUTPUT, @Count OUTPUT;

	IF (@Count > 0)
	BEGIN
		SET @Observation = @Observation + 'Large number of lines per journal are ' +  CONVERT(NVARCHAR(MAX), @Count) + ' on ' +  @JournalNum + ' in ' + @DataArea + ' company in the last 30 days.';	
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END 
	GO


--
-- Rule Section: Technical Overview
--

	--
	-- Rule: AIF file based outbound adapter
	--
	DECLARE @RuleID INT = 6000;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'AIF file based outbound adapter';
	DECLARE @Observation NVARCHAR(MAX) = 'Yes';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @ModelDatabase AS VARCHAR(100) = DB_NAME() + '_Model';
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM AIFCHANNEL WHERE ADAPTERCLASSID = (SELECT ADP.ADAPTERCLASSID FROM AIFADAPTER ADP '
	SET @SQL = @SQL + 'JOIN [' + @ModelDatabase + '].[DBO].UTILIDELEMENTS UTIL ON UTIL.ID = ADP.ADAPTERCLASSID AND UTIL.NAME = ''AifFileSystemAdapter'') AND DIRECTION = 2';
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	ELSE
	BEGIN
		IF((SELECT ShowWhenUnobserved FROM #D365UpgradeAnalysisReportGlobalVariables) = 1)
		BEGIN
			SET @Observation = 'No';
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
				VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
	END
	GO


	--
	-- Rule: AIF file based inbound adapter
	--
	DECLARE @RuleID INT = 6010;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'AIF file based inbound adapter';
	DECLARE @Observation NVARCHAR(MAX) = 'Yes';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @ModelDatabase AS VARCHAR(100) = DB_NAME() + '_Model';
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM AIFCHANNEL WHERE ADAPTERCLASSID = (SELECT ADP.ADAPTERCLASSID FROM AIFADAPTER ADP ' 
	SET @SQL = @SQL + 'JOIN [' + @ModelDatabase + '].[DBO].UTILIDELEMENTS UTIL ON UTIL.ID = ADP.ADAPTERCLASSID AND UTIL.NAME = ''AifFileSystemAdapter'') AND DIRECTION = 1';
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	ELSE
	BEGIN
		IF((SELECT ShowWhenUnobserved FROM #D365UpgradeAnalysisReportGlobalVariables) = 1)
		BEGIN
			SET @Observation = 'No';
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
				VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
	END
	GO
	

	--
	-- Rule: AIF file based .NET adapter 
	--
	DECLARE @RuleID INT = 6020;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'AIF file based .NET adapter';
	DECLARE @Observation NVARCHAR(MAX) = 'Yes';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @ModelDatabase AS VARCHAR(100) = DB_NAME() + '_Model';
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM AIFCHANNEL WHERE ADAPTERCLASSID = (SELECT ADP.ADAPTERCLASSID FROM AIFADAPTER ADP '
	SET @SQL = @SQL + 'JOIN [' + @ModelDatabase + '].[DBO].UTILIDELEMENTS UTIL ON UTIL.ID = ADP.ADAPTERCLASSID AND UTIL.NAME = ''AifWcfNetTcpAdapter'')';
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	ELSE
	BEGIN
		IF((SELECT ShowWhenUnobserved FROM #D365UpgradeAnalysisReportGlobalVariables) = 1)
		BEGIN
			SET @Observation = 'No';
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
				VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
	END
	GO


	--
	-- Rule: AIF file based MSMQ adapter  
	--
	DECLARE @RuleID INT = 6030;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'AIF file based MSMQ adapter';
	DECLARE @Observation NVARCHAR(MAX) = 'Yes';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @ModelDatabase AS VARCHAR(100) = DB_NAME() + '_Model';
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Count AS INT;
	SET @SQL = N'SELECT @Count = COUNT(RECID) FROM AIFCHANNEL WHERE ADAPTERCLASSID = (SELECT ADP.ADAPTERCLASSID FROM AIFADAPTER ADP '
	SET @SQL = @SQL + 'JOIN [' + @ModelDatabase + '].[DBO].UTILIDELEMENTS UTIL ON UTIL.ID = ADP.ADAPTERCLASSID AND UTIL.NAME = ''AifWcfMsmqAdapter'')';
	EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;
	IF (@Count > 0)
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	ELSE
	BEGIN
		IF((SELECT ShowWhenUnobserved FROM #D365UpgradeAnalysisReportGlobalVariables) = 1)
		BEGIN
			SET @Observation = 'No';
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
				VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
	END
	GO


	--
	-- Rule: DMF Execution History
	--
	DECLARE @RuleID INT = 6040;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'DMF Execution History';
	DECLARE @Observation NVARCHAR(MAX) = '';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	IF ((SELECT COUNT(RECID) FROM DMFSTAGINGLOG) > 0)
	BEGIN
		SET @Observation = 'Yes';
	END
	ELSE
	BEGIN
		IF ((SELECT COUNT(RECID) FROM DMFDEFINITIONGROUPEXECUTION) > 0)
		BEGIN
			SET @Observation = 'Yes';	
		END
		ELSE
		BEGIN
			IF ((SELECT COUNT(RECID) FROM DMFDEFINITIONGROUP) > 0)
			BEGIN
				SET @Observation = 'Yes';	
			END
		END
	END
	IF (@Observation != '')
	BEGIN
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
	END
	ELSE
	BEGIN
		IF((SELECT ShowWhenUnobserved FROM #D365UpgradeAnalysisReportGlobalVariables) = 1)
		BEGIN
			SET @Observation = 'No';
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
				VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
	END

	GO

	--
	-- Rule: Countries implemented
	--
	DECLARE @RuleID INT = 6050;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'Countries Implemented';
	DECLARE @Observation NVARCHAR(MAX) = '';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @CountryRegion NVARCHAR(10)

	DECLARE CountryRegionCursor CURSOR FOR
	SELECT DISTINCT DPAV.COUNTRYREGIONID FROM DIRPARTYTABLE DP
	JOIN DIRPARTYPOSTALADDRESSVIEW DPAV
		ON DPAV.ISPRIMARY =1
		AND DP.RECID = DPAV.PARTY
		AND DP.ORGANIZATIONTYPE = 1
		ORDER BY DPAV.COUNTRYREGIONID

	OPEN CountryRegionCursor;
	FETCH NEXT FROM CountryRegionCursor INTO @CountryRegion;
	WHILE @@FETCH_STATUS = 0
	BEGIN		
		SET @Observation = @Observation + @CountryRegion + ', ';
	FETCH NEXT FROM CountryRegionCursor INTO @CountryRegion;
	END
	CLOSE CountryRegionCursor;
	DEALLOCATE CountryRegionCursor;

	IF (LEN(@Observation) > 0)
	BEGIN
		SET @Observation = REVERSE(SUBSTRING(REVERSE(@Observation), 3, 9999));
	END

	INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);

	GO

	--
	-- Rule: Legal entities
	--
	DECLARE @RuleID INT = 6060;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'Legal Entities';
	DECLARE @Observation NVARCHAR(MAX) = '';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @LegalEntity NVARCHAR(4);
	DECLARE @Count AS INT = 0;
	DECLARE LegalEntityCursor CURSOR FOR
	SELECT ID FROM DATAAREA

	OPEN LegalEntityCursor;
	FETCH NEXT FROM LegalEntityCursor INTO @LegalEntity;
	WHILE @@FETCH_STATUS = 0
	BEGIN		
		SET @Observation = @Observation + @LegalEntity + ', ';
		SET @Count = @Count + 1;
		FETCH NEXT FROM LegalEntityCursor INTO @LegalEntity;
	END
	CLOSE LegalEntityCursor;
	DEALLOCATE LegalEntityCursor;

	IF (LEN(@Observation) > 0)
	BEGIN
		SET @Observation = REVERSE(SUBSTRING(REVERSE(@Observation), 3, 9999));
		SET @Observation = CONVERT(NVARCHAR(MAX), @Count) + ' Operational legal entities (' + @Observation + ')';
	END

	INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);

	GO

	--
	-- Rule: Functional Models used
	--
	DECLARE @RuleID INT = 6070;
	DECLARE @RuleSection NVARCHAR(100) = 'Technical Overview';
	DECLARE @RuleName NVARCHAR(500) = 'Functional Models Used';
	DECLARE @Observation NVARCHAR(MAX) = '';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';

	DECLARE @Count AS INT;
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @tablename NVARCHAR(256);
	IF(OBJECT_ID('tempdb..#TempTable') IS NOT NULL)
	BEGIN 
		DROP TABLE #TempTable
	END
	CREATE TABLE #TempTable
	(TableName VARCHAR(MAX))

	INSERT INTO #TempTable (TableName)
	VALUES ('CUSTTRANS'),('VENDTRANS'),('PROJTABLE'),('INVENTTRANS'),('PRODTABLE'),	('REQTRANS'),('LEDGERJOURNALTRANS'),('BANKACCOUNTTRANS'),('ASSETTRANS'),('RETAILSTATEMENTTRANS');

	DECLARE TableNameCursor CURSOR FOR
	SELECT TableName FROM #TempTable

	OPEN TableNameCursor;
	FETCH NEXT FROM TableNameCursor INTO @TableName;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @SQL = N'SELECT @Count = COUNT(RECID) FROM ' + @TableName;	
		EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count OUTPUT;

		IF (@Count > 0)
		BEGIN
			SET @Observation =  @Observation + CASE @TableName
				WHEN 'CUSTTRANS' THEN 'Accounts receivable'
				WHEN 'VENDTRANS' THEN 'Accounts payable'
				WHEN 'PROJTABLE' THEN 'Project management'
				WHEN 'INVENTTRANS' THEN 'Inventory management'
				WHEN 'PRODTABLE' THEN 'Production'
				WHEN 'REQTRANS' THEN 'Master planning'
				WHEN 'LEDGERJOURNALTRANS' THEN 'General Ledger'
				WHEN 'BANKACCOUNTTRANS' THEN 'Cash and Bank management'
				WHEN 'ASSETTRANS' THEN 'Fixed assets'
				WHEN 'RETAILSTATEMENTTRANS' THEN 'Retail'		
			END
			SET @Observation = @Observation +  + ', ';
		END
	FETCH NEXT FROM TableNameCursor INTO @TableName;
	END
	CLOSE TableNameCursor;
	DEALLOCATE TableNameCursor;

	IF (LEN(@Observation) > 0)
	BEGIN
		SET @Observation = REVERSE(SUBSTRING(REVERSE(@Observation), 3, 9999));
	END

	INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);

	GO


--
-- Rule Section: Database Saving
--

	--
	-- Rule: Backup Database
	--
		DECLARE @RuleID INT = 7000;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Backup Database';
		DECLARE @Observation NVARCHAR(MAX) = 'The following rules may suggest data clean up or data changes';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Before cleaning or making any changes to the environment, please ensure you have a full backup';
		DECLARE @AdditionalComments NVARCHAR(MAX) = ''
		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
		VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		GO
	
	

	--
	-- Rule: Large Tables
	--
		DECLARE @RuleID INT = 7010;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Large Tables';
		DECLARE @Observation NVARCHAR(MAX) =  '';
		DECLARE @Recommendation NVARCHAR(MAX) = '';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';

		DECLARE @LargeTableThreshold INT = (SELECT LargeTableThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
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
			SET @Observation = 'Large tables detected. There is\are ' + CAST((SELECT COUNT(1) FROM #LARGETABLES) AS VARCHAR) + ' table(s) over ' + CAST(@LargeTableThreshold AS VARCHAR) + 'MB in size.';
			SET @Recommendation = 'It may be beneficial to compress large tables prior to the upgrade, see: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/migration-upgrade/compress-tables-ax-2012';
			SET @AdditionalComments = 'Following large tables detected: ' + (SELECT TOP 1 STUFF((SELECT ', ' + TableName + ' - ' + CAST(UsedSpaceMB AS VARCHAR) + 'MB ' FROM #LARGETABLES FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS ConcatenatedString FROM #LARGETABLES)
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade AIF document log cleanup
	--
		DECLARE @RuleID INT = 7020;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade AIF document log cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Delete the XML document history for old AIF messages to recover database space. This rule has found XML documents stored in history which are over 1 year old, the estimate here is for deleting all history over 1 year. Note that the message log remains, this function only deletes the related document XML';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click System administration > Periodic > Services and Application Integration Framework > History. 2. In the Display by field, select Document. 3. Select a document, and then click Clear document XML. 4. To clear all the versions of the XML document that exist in the system, click Clear all versions. 5. To clear all intermediate versions of the XML document, click Clear interim versions. for outbound documents, this action clears all versions except the version that has the highest version number. For inbound documents, this action clears all versions except the first version.';
		
		DECLARE @TotalEstimatedSavingInMB INT;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
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
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB:' + CAST(@TotalEstimatedSavingInMB AS NVARCHAR)
		IF(@TotalEstimatedSavingInMB > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Archive future time registrations
	--
		DECLARE @RuleID INT = 7030;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Archive future time registrations';
		DECLARE @Observation NVARCHAR(MAX) = 'Time registrations which have been accidentally entered with a future date can be archived. Once this process has been executed you need to run the archive cleanup to delete the records from Production control > Inquiries > Registrations > Raw registrations archive';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Click Production control > Periodic > Clean up > Archive future registrations. Click ok, or use batch options to set a recurring job.';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';

		DECLARE @TotalEstimatedSavingInMB INT;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
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
		GO
	
	

	--
	-- Rule: Upgrade Batch cleanup
	--
		DECLARE @RuleID INT = 7040;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Batch cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Delete batch jobs which have ended successfully.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1.Click Home > Inquiries > Batch jobs > My batch jobs. 2. Click Functions, and then select Delete. 3. In the Select batch transactions for deletion dialog box, enter the criteria to use for deleting jobs. for example, to delete all jobs that have ended, for Field select Status, for Criteria, select Ended, and then click OK.';
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempBatchTablesSizes);
		SET @SavingInKBBatchJobAlerts = (SELECT SavingInKBBatchJobAlerts FROM #tempBatchTablesSizes);
		SET @SavingInKBBatch = (SELECT SavingInKBBatch FROM #tempBatchTablesSizes);
		SET @SavingInKBBatchJob = (SELECT SavingInKBBatchJob FROM #tempBatchTablesSizes);
		DROP TABLE #tempBatchTablesSizes

		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB Batch Job Alerts: ' + CAST(@SavingInKBBatchJobAlerts AS NVARCHAR) + ', Saving In KB Batch: ' + CAST(@SavingInKBBatch AS NVARCHAR) + ', Saving In KB Batch Job: ' + CAST(@SavingInKBBatchJob AS NVARCHAR)
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade BOM calculation cleanup
	--
		DECLARE @RuleID INT = 7050;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade BOM calculation cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'If performing BOM calculations the BOMCalcTable and BOMCalcTrans tables can become large. Once calculated this data is not generally needed. The purpose of this old data is to go back and look at old calculations, if this is not part of your business process then you may clean it up. A rule of thumb is that a customer should keep a few months of data and purge the rest.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Step 1 - Purging the BOMCalcTrans Before running the script, replace the following information: # of records to group = A while loop has been implemented to minimize the SQL Transaction Log growth. The while loop will delete records in groups of the number that you enter (example 1 million 1000000). The process will take a significant amount of time to complete on large data sets. Company = Enter the name of the company that you want to delete BOMCalcTrans records Date = Enter a date and the qualifier (example < > or =) of which records you want to delete. Below is an example of deleting the BOMCalcTable records for company dmo with transaction date less than 1/31/2023. DELETE BOMCALCTABLE WHERE TRANSDATE < ''2023-01-31 00:00:00.000'' AND DATAAREAID = ''dmo''';
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempBOMTablesSizes);
		SET @SavingInKBBomCalcTrans = (SELECT SavingInKBBomCalcTrans FROM #tempBOMTablesSizes);
		SET @SavingInKBBomCalcTable = (SELECT SavingInKBBomCalcTable FROM #tempBOMTablesSizes);
		DROP TABLE #tempBOMTablesSizes

		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB Bom Calc Trans: ' + CAST(@SavingInKBBomCalcTrans AS NVARCHAR) + ', Saving In KB Bom Calc Table: ' + CAST(@SavingInKBBomCalcTable AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	
	
	--
	-- Rule: Upgrade Calendar date cleanup
	--
		DECLARE @RuleID INT = 7060;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Calendar date cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Cleanup calendar dates older than a certain date. This rule has found calendar dates over 1 year old. This function will not delete the calendars themselves, but only the dates within the calendar that are older than the date you specify.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Click Organization administration > Periodic > Calendar cleanup. Use this form to specify the end date for deleting old working times. All old working hours up to, but not including, this date are deleted.';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
												FROM sys.tables t
												INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
												INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
												INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
												WHERE t.NAME ='WORKCALENDARDATE'
												GROUP BY t.Name,p.Rows),0) * count(WORKCALENDARDATE.recID))/1024 as TotalEstimatedSavingInMB
												FROM WORKCALENDARDATE
												WHERE DateDiff(year, WORKCALENDARDATE.TRANSDATE, GetDate()) > 1);
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	
	

	--
	-- Rule: Upgrade Database log cleanup
	--
		DECLARE @RuleID INT = 7070;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Database log cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Delete database log records older than a certain date. This rule has checked for logs over 1 year old. You can also delete logs only for a certain table or other specific criteria.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click System administration > Inquiries > Database > Database log. Click Clean up log. 2. Choose a method of selecting logs to delete by entering the table ID that they refer to, or the type of log, or the created date and time. 3. Use the Database log cleanup tab to determine when to run the log cleanup task.';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
												FROM sys.tables t
												INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
												INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
												INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
												WHERE t.NAME ='SYSDATABASELOG'
												GROUP BY t.Name,p.Rows),0) * count(SYSDATABASELOG.recID))/1024 as TotalEstimatedSavingInMB
												FROM SYSDATABASELOG
												WHERE DateDiff(year,SYSDATABASELOG.CREATEDDATETIME, GetDate())  > 1)
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	
	
	--
	-- Rule: Upgrade Delete absence journals
	--
		DECLARE @RuleID INT = 7080;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Delete absence journals';
		DECLARE @Observation NVARCHAR(MAX) = 'Use the “Delete absence journals” process to delete all empty journals that have not been transferred for approval. The exceptions to this rule are empty journals that contain a period that is before a journal that contains planned, or future, absences. if planned absences exist in a future period but you still want to delete the journal, you can cancel approval and then repeat the delete journal procedure.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click Human resources > Periodic > Absence > Delete absence journals. 2. Choose one of the following actions: ◦ Click OK to delete all absence journals. ◦ Click Select to select the employees to delete absence journals for.';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
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
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Delete project journals
	--
		DECLARE @RuleID INT = 7090;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Delete project journals';
		DECLARE @Observation NVARCHAR(MAX) = 'You can delete project journals from which transactions have been posted. By deleting these project journals, you can help make more system resources available.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1.Click Project management and accounting > Periodic > Journals > Delete project journals. 2. In the Delete project journals form, click Select. 3. In the ProjJournalCleanUp form, in the Criteria field, select the journal(s) that you want to delete. 4. Click OK.';
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempProjJournalsSizes);
		SET @SavingInKBProjJournalTable = (SELECT SavingInKBProjJournalTable FROM #tempProjJournalsSizes);
		SET @SavingInKBProjJournalTrans = (SELECT SavingInKBProjJournalTrans FROM #tempProjJournalsSizes);
		SET @SavingInKBProdBegBalJournalTrans_CostSales = (SELECT SavingInKBProdBegBalJournalTrans_CostSales FROM #tempProjJournalsSizes);
		SET @SavingInKBProdBegBalJournalTrans_Fee = (SELECT SavingInKBProdBegBalJournalTrans_Fee FROM #tempProjJournalsSizes);
		SET @SavingInKBProdBegBalJournalTrans_OnAcc = (SELECT SavingInKBProdBegBalJournalTrans_OnAcc FROM #tempProjJournalsSizes);
		DROP TABLE #tempProjJournalsSizes
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB ProjJournalTable: ' + CAST(@SavingInKBProjJournalTable AS NVARCHAR) + ', Saving In KB ProjJournalTrans: ' + CAST(@SavingInKBProjJournalTrans AS NVARCHAR) + ', Saving In KB ProdBegBalJournalTrans_CostSales: ' + CAST(@SavingInKBProdBegBalJournalTrans_CostSales AS NVARCHAR)  + ', Saving In KB ProdBegBalJournalTrans_Fee: ' + CAST(@SavingInKBProdBegBalJournalTrans_Fee AS NVARCHAR)  + ', Saving In KB ProdBegBalJournalTrans_OnAcc: ' + CAST(@SavingInKBProdBegBalJournalTrans_OnAcc AS NVARCHAR)  
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	
	
	--
	-- Rule: Upgrade Delete unsent project quotations
	--
		DECLARE @RuleID INT = 7100;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Delete unsent project quotations';
		DECLARE @Observation NVARCHAR(MAX) = 'Deleting unsent project quotations to recover database space. It is possible to create a filter to delete only selected quotations. note that it is not possible to delete "Sent" quotations, to delete a "Sent" quotation first update it to Lost or Cancelled.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1.Click Project management and accounting > Periodic > Quotations > Delete quotations. 2. In the Delete quotations form, click the Select button. if necessary, customize the query to match your needs. 3. Click OK to transfer the quotations to the Delete quotations form. if the query transfers quotations that you do not want to delete, select them in the Delete quotations form and press ALT+F9. This removes the quotations from the list of quotations to be deleted. 4. Click OK to delete the quotations that are listed in the Delete quotations form.';
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempProjQuotationSizes);
		SET @SavingInKBSalesQuotationTable = (SELECT SavingInKBSalesQuotationTable FROM #tempProjQuotationSizes);
		SET @SavingInKBSalesQuotationLine = (SELECT SavingInKBSalesQuotationLine FROM #tempProjQuotationSizes);
		DROP TABLE #tempProjQuotationSizes
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB SalesQuotationTable: ' + CAST(@SavingInKBSalesQuotationTable AS NVARCHAR) + ', Saving In KB SalesQuotationLine: ' + CAST(@SavingInKBSalesQuotationLine AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Inventory settlement cleanup
	--
		DECLARE @RuleID INT = 7110;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Inventory settlement cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Use the Inventory settlements clean up process to delete old and cancelled inventory settlements.  The INVENTSETTLEMENT table can become quite large if you’ve cancelled inventory closes.  This rule has identified records over 1 year old';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Click Inventory management > Periodic > Clean up > Inventory settlements cleanup. Use this form to group closed inventory transactions or delete canceled inventory settlements. Cleaning up closed or deleted inventory settlements can help free system resources. Do not group or delete inventory settlements too close to the current date or fiscal year, because part of the transaction information for the settlements is lost.';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
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
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

	--
	-- Rule: Upgrade Master plan log clean up
	--
		DECLARE @RuleID INT = 7120;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Master plan log clean up';
		DECLARE @Observation NVARCHAR(MAX) = 'Master scheduling logic keeps a log table of inventory transactions. This is automatically cleaned up when master scheduling is run. If master scheduling is not run these records continue to grow larger over time and are not cleaned up. A large amount of rows over 3 months old have been found in your database.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Execute the following SQL statement to clean up records: DELETE INVENTSUMLOGTTS WHERE ISCOMMITTED =1 ';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
												FROM sys.tables t
												INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
												INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
												INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
												WHERE t.NAME ='InventSumLogTTS'
												GROUP BY t.Name,p.Rows),0) * count(recID))/1024 as TotalEstimatedSavingInMB
												FROM InventSumLogTTS (nolock)
												WHERE DateDiff(month, UTCCREATEDDATETIME, GetDate()) > 3)
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Production journal clean up
	--
		DECLARE @RuleID INT = 7130;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Production journal clean up';
		DECLARE @Observation NVARCHAR(MAX) = 'Clean up production journals for "Ended" production orders. it is useful to delete old or unused journals to reduce demand on system resources. This process is related to the "Production orders clean up" process. Executing the "production orders clean up" will also delete the related production journals - then this process is not required. However if it is not possible for you to delete production orders, then you may wish you use this option to delete just production journals instead.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click Production control > Periodic > Clean up > Production journals cleanup. 2. Click the Clean up list. 3. Select whether you want to delete all posted journals or only journals that are posted on finished production orders. 4. Click OK to delete the journals, or click the Batch tab, and then define parameters to schedule old journals to be deleted regularly.';
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempProdJournalSizes);
		SET @SavingInKBProdJournalRoute = (SELECT SavingInKBProdJournalRoute FROM #tempProdJournalSizes);
		SET @SavingInKBProdJournalProd = (SELECT SavingInKBProdJournalProd FROM #tempProdJournalSizes);
		SET @SavingInKBProdJournalBOM = (SELECT SavingInKBProdJournalBOM FROM #tempProdJournalSizes);
		SET @SavingInKBProdJournalTable = (SELECT SavingInKBProdJournalTable FROM #tempProdJournalSizes);
		DROP TABLE #tempProdJournalSizes
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB ProdJournalRoute: ' + CAST(@SavingInKBProdJournalRoute AS NVARCHAR) + ', Saving In KB ProdJournalProd: ' + CAST(@SavingInKBProdJournalProd AS NVARCHAR) + ', Saving In KB ProdJournalBOM: ' + CAST(@SavingInKBProdJournalBOM AS NVARCHAR) + ', Saving In KB ProdJournalTable: ' + CAST(@SavingInKBProdJournalTable AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO



	--
	-- Rule: Upgrade Production order clean up
	--
		DECLARE @RuleID INT = 7140;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Production order clean up';
		DECLARE @Observation NVARCHAR(MAX) = 'Many "Ended" status production orders exist in the system which are over 1 year old. These can be cleaned up to release space';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click Production control > Periodic > Clean up > Production orders cleanup. 2. On the General tab, in the Ended before field, select the last date that you want production orders to be included for deletion. 3. Click OK, or use the Batch tab to set parameters for cleaning up production orders automatically at set intervals.';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		
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
		DECLARE @SavingInKBProdJournalRoute AS REAL;
		DECLARE @SavingInKBProdJournalProd AS REAL;
		DECLARE @SavingInKBProdJournalBOM AS REAL;
		DECLARE @SavingInKBProdJournalTable AS REAL;
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);

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
		SET @AdditionalComments = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB ProdJournalRoute: ' + CAST(@SavingInKBProdJournalRoute AS NVARCHAR) + ', Saving In KB ProdJournalProd2: ' + CAST(@SavingInKBProdJournalProd2 AS NVARCHAR) + ', Saving In KB ProdJournalProd: ' + CAST(@SavingInKBProdJournalProd AS NVARCHAR) + ', Saving In KB ProdJournalBOM: ' + CAST(@SavingInKBProdJournalBOM AS NVARCHAR) + ', Saving In KB ProdJournalTable: ' + CAST(@SavingInKBProdJournalTable AS NVARCHAR) + ', Saving In KB ProdCalcTrans: ' + CAST(@SavingInKBProdCalcTrans AS NVARCHAR) + ', Saving In KB WrkCtrCapRes: ' + CAST(@SavingInKBWrkCtrCapRes AS NVARCHAR) + ', Saving In KB ProdRouteJob: ' + CAST(@SavingInKBProdRouteJob AS NVARCHAR) + ', Saving In KB ProdRoute: ' + CAST(@SavingInKBProdRoute AS NVARCHAR) + ', Saving In KB ProdBOM: ' + CAST(@SavingInKBProdBOM AS NVARCHAR) + ', Saving In KB ProdTable: ' + CAST(@SavingInKBProdTable AS NVARCHAR)
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Purchase update history cleanup
	--
		DECLARE @RuleID INT = 7150;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Purchase update history cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'When a purchase order is updated such as a confirmation, receipts list, or invoice, information is stored and tracked in the PURCHPARMTABLE, PURCHPARMUPDATE, PURCHPARMSUBTABLE, PURCHPARMSUBLINE, and PURCHPARMLINE tables. Once a record is marked with a status of EXECUTED, the information is no longer necessary to retain. The purchase update cleanup process removes old purchase update history records and should be scheduled to execute on a regular basis.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Use the Delete history of update form to delete the update history. 1. Click Procurement and sourcing > Periodic > Clean up > Purchase update history cleanup. 2. In the Clean up field, select the status of the update history to be deleted as Executed. 3. In the Created until field, select the date up to which the update history is to be deleted. 4. Click OK to delete the update history and close the form.';
		
		
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempPurchUpdateHistorySizes);
		SET @SavingInKBPurchParmUpdate = (SELECT SavingInKBPurchParmUpdate FROM #tempPurchUpdateHistorySizes);
		SET @SavingInKBPurchParmSubTable = (SELECT SavingInKBPurchParmSubTable FROM #tempPurchUpdateHistorySizes);
		SET @SavingInKBPurchParmLine = (SELECT SavingInKBPurchParmLine FROM #tempPurchUpdateHistorySizes);
		SET @SavingInKBPurchParmTable = (SELECT SavingInKBPurchParmTable FROM #tempPurchUpdateHistorySizes);
		DROP TABLE #tempPurchUpdateHistorySizes
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB PurchParmUpdate: ' + CAST(@SavingInKBPurchParmUpdate AS NVARCHAR) + ', Saving In KB PurchParmSubTable: ' + CAST(@SavingInKBPurchParmSubTable AS NVARCHAR) + ', Saving In KB PurchParmLine: ' + CAST(@SavingInKBPurchParmLine AS NVARCHAR) + ', Saving In KB PurchParmTable: ' + CAST(@SavingInKBPurchParmTable AS NVARCHAR)
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Sales and marketing transaction log clean up
	--
		DECLARE @RuleID INT = 7160;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Sales and marketing transaction log clean up';
		DECLARE @Observation NVARCHAR(MAX) = 'The sales and marketing module contains a feature to trans the creation, deletion and update of various types of transaction, this feature is turned on by default but can generate a large amount of data over time. This rule has detected a significant amount of data within this log which could be cleaned up.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Delete rows older than a certain date via TSQL. Note that the logic in this query to delete rows in chunks of 1 million rows is to prevent the database log growing very large if the table has many rows. DECLARE @COUNT INT, @LOOPS INT, @DATAAREAID VARCHAR(10), @NUMBEROFYEARSTOKEEP INT, @DATEBEFORE DATETIME -- SET THE VALUES BELOW FOR YEARS TO KEEP AND DATAAREAID set @NUMBEROFYEARSTOKEEP = 1 set @DATAAREAID = ''usrt'' set @DATEBEFORE = DATEADD(year, @NUMBEROFYEARSTOKEEP * -1, GETDATE()) set @LOOPS = ((select count(recid) from SMMTRANSLOG WHERE DATAAREAID = @DATAAREAID AND LOGDATETIME < @DATEBEFORE)/1000)+1 set @COUNT = 1 WHILE @COUNT <= @LOOPS BEGIN delete SMMTRANSLOG WHERE RECID IN  (SELECT TOP 1000000 X.RECID  FROM SMMTRANSLOG X  WHERE X.DATAAREAID = @DATAAREAID  AND X.LOGDATETIME < @DATEBEFORE)set @COUNT = @COUNT+1 END';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
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
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Sales order entry statistics clean up
	--
		DECLARE @RuleID INT = 7170;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Sales order entry statistics clean up';
		DECLARE @Observation NVARCHAR(MAX) = 'Localization - Sweden: Tracking sales order entry statistics increases the amount of space required for data storage. It is a good idea to periodically remove sales order entry statistics that you no longer need to keep. This is only applicable for legal entities whose primary address is in Sweden';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Use the “Order entry statistics clean up” process to delete order entry statistics that are no longer needed. 1. Click Sales and marketing > Periodic > Clean up > Order entry statistics clean up. 2. In the Created until field, select the last date on which statistic lines should be deleted. 3. Click OK.';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
												FROM sys.tables t
												INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
												INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
												INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
												WHERE t.NAME ='salesOrderEntryStatistics'
												GROUP BY t.Name,p.Rows),0) * count(recID)
												)/1024 as TotalEstimatedSavingInMB
												FROM salesOrderEntryStatistics)
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Sales update history cleanup
	--
		DECLARE @RuleID INT = 7180;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Sales update history cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'When a sales order is updated such as a confirmation, receipts list, or invoice, information is stored and tracked in the SALESPARMTABLE, SALESPARMUPDATE, SALESPARMSUBTABLE, SALESPARMSUBLINE, and SALESPARMLINE tables. Once a record is marked with a status of EXECUTED, the information is no longer necessary to retain. The sales update cleanup process removes old sales update history records and should be scheduled to execute on a regular basis.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Use the Delete history of update form to delete the update history. 1. Click Sales and marketing > Periodic > Clean up > Sales update history cleanup. 2. In the Clean up field, select the status of the update history to be deleted as Executed. 3. In the Created until field, select the date up to which the update history is to be deleted. 4. Click OK to delete the update history and close the form.';
		
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempSalesUpdateHistorySizes);
		SET @SavingInKBSalesParmUpdate = (SELECT SavingInKBSalesParmUpdate FROM #tempSalesUpdateHistorySizes);
		SET @SavingInKBSalesParmSubTable = (SELECT SavingInKBSalesParmSubTable FROM #tempSalesUpdateHistorySizes);
		SET @SavingInKBSalesParmLine = (SELECT SavingInKBSalesParmLine FROM #tempSalesUpdateHistorySizes);
		SET @SavingInKBSalesParmTable = (SELECT SavingInKBSalesParmTable FROM #tempSalesUpdateHistorySizes);
		DROP TABLE #tempSalesUpdateHistorySizes
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB SalesParmUpdate: ' + CAST(@SavingInKBSalesParmUpdate AS NVARCHAR) + ', Saving In KB SalesParmSubTable: ' + CAST(@SavingInKBSalesParmSubTable AS NVARCHAR) + ', Saving In KB SalesParmLine: ' + CAST(@SavingInKBSalesParmLine AS NVARCHAR) + ', Saving In KB SalesParmTable: ' + CAST(@SavingInKBSalesParmTable AS NVARCHAR)
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	

	--
	-- Rule: Upgrade SQL statement trace log cleanup
	--
		DECLARE @RuleID INT = 7190;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade SQL statement trace log cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Delete the SQL statement trace log to recover database space. This is an all or nothing option. You can export the log before deleting to refer to later. This log is a record of queries over a certain time threshold or SQL errors used for troubleshooting purposes.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Click System administration > Inquiries > Database > SQL statement trace log Click the Functions > Clear log button Click yes to the prompt Note: you can export the log before deleting to allow you to retain a copy, by selecting Functions > Export to';
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
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT TotalEstimatedSavingInMB FROM #tempSQLStatementSizes);
		SET @SavingInKBSysTraceTableSQLExecPlan = (SELECT SavingInKBSysTraceTableSQLExecPlan FROM #tempSQLStatementSizes);
		SET @SavingInKBSysTraceTableSQLTabRef = (SELECT SavingInKBSysTraceTableSQLTabRef FROM #tempSQLStatementSizes);
		SET @SavingInKBSysTraceTableSQL = (SELECT SavingInKBSysTraceTableSQL FROM #tempSQLStatementSizes);
		DROP TABLE #tempSQLStatementSizes
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) + ', Saving In KB SysTraceTableSQLExecPlan: ' + CAST(@SavingInKBSysTraceTableSQLExecPlan AS NVARCHAR) + ', Saving In KB SysTraceTableSQLTabRef: ' + CAST(@SavingInKBSysTraceTableSQLTabRef AS NVARCHAR) + ', Saving In KB SysTraceTableSQL: ' + CAST(@SavingInKBSysTraceTableSQL AS NVARCHAR)
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Time registrations archive cleanup
	--
		DECLARE @RuleID INT = 7200;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Time registrations archive cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Previously archived time registrations can be cleaned up. You can remove archived registrations by deleting them or exporting them to a file.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click Production control > Inquiries > Registrations > Raw registrations archive. 2. On the toolbar click the Clean up registrations button. 3. In the Cleanup mode field, select how you want to handle the old registrations: ◦ Select To file to move the registrations to an external file. ◦ Select Delete to permanently delete the registrations. 4. In the Maximum age field, enter the maximum age, in days, of registrations that are kept in the raw registrations table. For example, if you enter the number 20, all registrations that are more than 20 days old are archived according to your selection in the Cleanup mode field. 5. If you select To file in the Cleanup mode field, enter a file name, or select an existing file, in the File name field.';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
												FROM sys.tables t
												INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
												INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
												INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
												WHERE t.NAME ='JMGTERMREGARCHIVE'
												GROUP BY t.Name,p.Rows),0) * count(JMGTERMREGARCHIVE.recID)) /1024 as TotalEstimatedSavingInMB
												FROM JMGTERMREGARCHIVE
												WHERE  DateDiff(month, JMGTERMREGARCHIVE.REGDATETIME, GetDate()) > 2)
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade Time registrations cleanup
		--
		DECLARE @RuleID INT = 7210;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade Time registrations cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Registrations can accumulate in Microsoft Dynamics AX over time, and can reduce the performance of the application. Therefore, we recommend that you clean up old registrations periodically. You can remove old registrations in the following ways: • You can delete them. • You can export them to a file.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click Human resources > Periodic > Time and attendance > Update > Clean up registrations. –or– Click Production control > Periodic > Clean up > Clean up registrations. -or– Click Production control > Inquiries > Registrations > Raw registrations archive. On the toolbar, click Clean up registrations. 2. In the Cleanup mode field, select how you want to handle the old registrations: ◦ Select To table to move the registrations to another table in Microsoft Dynamics AX. The registrations are transferred to the Raw registrations archive form. ◦ Select To file to move the registrations to an external file. ◦ Select Delete to permanently delete the registrations. 3. In the Maximum age field, enter the maximum age, in days, of registrations that are kept in the raw registrations table. For example, if you enter the number 20, all registrations that are more than 20 days old are archived according to your selection in the Cleanup mode field. 4. If you select To file in the Cleanup mode field, enter a file name, or select an existing file, in the File name field.';
		
		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
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
		DECLARE @AdditionalComments NVARCHAR(MAX) = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: Upgrade User log cleanup
	--
		DECLARE @RuleID INT = 7220;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'Upgrade User log cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Delete user logs older than a certain date. This rule has checked for logs over 3 month old. This log is a record of users logging in and out of the system.';
		DECLARE @Recommendation NVARCHAR(MAX) = '1. Click System administration > Inquiries > Users > User log. Click Clean up. 2. Enter a value in the History limit (days) field to define a limit for the deletion. Only log information that is older than the given number of days is deleted. 3. Click Select to open the Select log cleanup criteria form, which is a version of the Inquiry form. 4. Select your cleanup criteria. Select a user or a range of users and, optionally, additional user information, such as date and time. for more information, see Inquiry (form). 5. Click OK to return to the User log cleanup form. 6. Click OK to perform the cleanup once, or click the Batch tab to define parameters to clean up the user log regularly.';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';

		DECLARE @TotalEstimatedSavingInMBReal AS REAL;
		DECLARE @EstimatedSavingThreshold INT = (SELECT EstimatedSavingThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		SET @TotalEstimatedSavingInMBReal = (SELECT (ISNULL((SELECT (SUM(a.used_pages) * 8)/NULLIF(CAST(p.rows as real) ,0)
												FROM sys.tables t
												INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
												INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
												INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
												WHERE t.NAME ='SYSUSERLOG'
												GROUP BY t.Name,p.Rows),0) * count(SYSUSERLOG.recID))/1024 as TotalEstimatedSavingInMB
												FROM SYSUSERLOG
												WHERE DateDiff(month,SYSUSERLOG.LOGOUTDATETIME, GetDate()) > 3)
		SET @Recommendation = 'Total Estimated Saving In MB: ' + CAST(@TotalEstimatedSavingInMBReal AS NVARCHAR) 
		IF(@TotalEstimatedSavingInMBReal > @EstimatedSavingThreshold)
		BEGIN
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: WHSInventReserve - Warehouse management on-hand entries cleanup
	--
		DECLARE @RuleID INT = 7230;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'WHSInventReserve - Warehouse management on-hand entries cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Estimate of WHSInventReserve records eligible for cleanup. This cleanup routine deletes records in the InventSum and WHSInventReserve tables. These tables are used to store on-hand information for items that are enabled for warehouse management processing (that is, WHS items). By cleaning up these records, you can significantly improve the on-hand calculations.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Run cleanup: Inventory Management > Periodic tasks > Clean up > Warehouse management on-hand entries cleanup';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		
		DECLARE @CleanupRecordCountThreshold INT = (SELECT CleanupRecordCountThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		DECLARE @DataArea NVARCHAR(4);
		DECLARE cleanupCursor CURSOR FOR
		WITH WHS_TOTAL_CTE (PARTITION, DATAAREAID, WHS_TOTAL_RECORDS)
		AS (SELECT PARTITION, DATAAREAID, COUNT (DATAAREAID) AS WHS_TOTAL_RECORDS
		FROM WHSINVENTRESERVE
		GROUP BY PARTITION, DATAAREAID)
		, 
		WHS_CLEANUP_CTE (PARTITION, DATAAREAID, WHS_CLEANUP_RECORDS)
		AS (SELECT PARTITION, DATAAREAID, COUNT (DATAAREAID) AS WHS_CLEANUP_RECORDS
		FROM WHSINVENTRESERVE WIR
		WHERE AVAILORDERED=0 AND AVAILPHYSICAL=0 AND RESERVORDERED=0 AND RESERVPHYSICAL=0
		AND EXISTS (SELECT 'x' FROM INVENTDIM ID WHERE WIR.PARTITION = ID.PARTITION AND WIR.DATAAREAID = ID.DATAAREAID AND WIR.INVENTDIMID=ID.INVENTDIMID)
		GROUP BY PARTITION, DATAAREAID)
	 
		SELECT P.NAME, CTE1.DATAAREAID, CAST ((CAST((WHS_CLEANUP_RECORDS) AS DECIMAL(20,2))/(CAST((WHS_TOTAL_RECORDS) AS DECIMAL(20,2))) * 100) AS DECIMAL(5,2)) AS PERCENT_CLEANUP, CTE2.WHS_CLEANUP_RECORDS AS CLEANUP_RECORD_COUNT, CTE1.WHS_TOTAL_RECORDS AS TOTAL_RECORD_COUNT
		FROM WHS_TOTAL_CTE CTE1
		JOIN WHS_CLEANUP_CTE CTE2  ON CTE1.DATAAREAID = CTE2.DATAAREAID
		JOIN PARTITIONS P ON CTE1.PARTITION = P.RECID
		ORDER BY PERCENT_CLEANUP DESC

		DECLARE  @Partition NVARCHAR(MAX), @DataAreaID NVARCHAR(MAX), @PercentCleanup NVARCHAR(MAX), @CleanupRecordCount NVARCHAR(MAX), @TotalRecordCount NVARCHAR(MAX);
		OPEN cleanupCursor;
		FETCH NEXT FROM cleanupCursor INTO @Partition, @DataAreaID, @PercentCleanup, @CleanupRecordCount, @TotalRecordCount;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF(@CleanupRecordCount > @CleanupRecordCountThreshold)
			BEGIN
				SET @AdditionalComments = @AdditionalComments + '[' + @Partition + ', ' +  @DataAreaID + ', ' + @PercentCleanup + '%, ' + @CleanupRecordCount + ', ' + @TotalRecordCount + '] | ';
			END
			FETCH NEXT FROM cleanupCursor INTO  @Partition, @DataAreaID, @PercentCleanup, @CleanupRecordCount, @TotalRecordCount;
		END;
		CLOSE cleanupCursor;
		DEALLOCATE cleanupCursor;

		IF (@AdditionalComments != '')
		BEGIN
			SET @AdditionalComments = 'Cleanup details for table WHSINVENTRESERVE by company (Partition, Company, % Cleanup, Cleanup Records, Total Records): ' + @AdditionalComments
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
		
	

	--
	-- Rule: InventSum - Warehouse management on-hand entries cleanup 
	--
		DECLARE @RuleID INT = 7240;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'InventSum - Warehouse management on-hand entries cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Estimate of InventSum records eligible for cleanup for items that are warehouse enabled. This cleanup routine deletes records in the InventSum and WHSInventReserve tables. These tables are used to store on-hand information for items that are enabled for warehouse management processing (that is, WHS items). By cleaning up these records, you can significantly improve the on-hand calculations.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Run cleanup: Inventory Management > Periodic tasks > Clean up > Warehouse management on-hand entries cleanup';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		
		DECLARE @CleanupRecordCountThreshold INT = (SELECT CleanupRecordCountThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		DECLARE  @Partition NVARCHAR(MAX), @DataAreaID NVARCHAR(MAX), @PercentCleanup NVARCHAR(MAX), @CleanupRecordCount NVARCHAR(MAX), @TotalRecordCount NVARCHAR(MAX);
		DECLARE cleanupCursor CURSOR FOR
		WITH INVENTSUM_TOTAL_CTE (PARTITION, DATAAREAID, INVENTSUM_TOTAL_RECORDS)
		AS (SELECT PARTITION, DATAAREAID, COUNT (DATAAREAID) AS INVENTSUM_TOTAL_RECORDS
		FROM INVENTSUM
		GROUP BY PARTITION, DATAAREAID)
		,
		INVENTSUM_CLEANUP_CTE (PARTITION, DATAAREAID, INVENTSUM_CLEANUP_RECORDS)
		AS (SELECT PARTITION, DATAAREAID, COUNT (DATAAREAID) AS INVENTSUM_CLEANUP_RECORDS
		FROM INVENTSUM IVS
		WHERE CLOSED = 1 AND EXISTS  (SELECT 'x' FROM WHSINVENTRESERVE WIR WHERE AVAILORDERED=0 AND AVAILPHYSICAL=0 AND RESERVORDERED=0 AND RESERVPHYSICAL=0 AND WIR.PARTITION = IVS.PARTITION AND WIR.DATAAREAID = IVS.DATAAREAID AND WIR.INVENTDIMID = IVS.INVENTDIMID)
		GROUP BY PARTITION, DATAAREAID
		)
	 
		SELECT P.NAME, CTE1.DATAAREAID, CAST ((CAST((INVENTSUM_CLEANUP_RECORDS) AS DECIMAL(20,2))/(CAST((INVENTSUM_TOTAL_RECORDS) AS DECIMAL(20,2))) * 100) AS DECIMAL(5,2)) AS PERCENT_CLEANUP, CTE2.INVENTSUM_CLEANUP_RECORDS AS CLEANUP_RECORD_COUNT, CTE1.INVENTSUM_TOTAL_RECORDS AS TOTAL_RECORD_COUNT
		FROM INVENTSUM_TOTAL_CTE CTE1
		JOIN INVENTSUM_CLEANUP_CTE CTE2 ON CTE1.DATAAREAID = CTE2.DATAAREAID
		JOIN PARTITIONS P ON CTE1.PARTITION = P.RECID
		ORDER BY PERCENT_CLEANUP DESC
		
		OPEN cleanupCursor;
		FETCH NEXT FROM cleanupCursor INTO @Partition, @DataAreaID, @PercentCleanup, @CleanupRecordCount, @TotalRecordCount;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF(@CleanupRecordCount > @CleanupRecordCountThreshold)
			BEGIN
				SET @AdditionalComments = @AdditionalComments + '[' + @Partition + ', ' +  @DataAreaID + ', ' + @PercentCleanup + '%, ' + @CleanupRecordCount + ', ' + @TotalRecordCount + '] | ';
			END
			FETCH NEXT FROM cleanupCursor INTO  @Partition, @DataAreaID, @PercentCleanup, @CleanupRecordCount, @TotalRecordCount;
		END;
		CLOSE cleanupCursor;
		DEALLOCATE cleanupCursor;
		IF (@AdditionalComments != '')
		BEGIN
			SET @AdditionalComments = 'Cleanup details for table INVENTSUM by company (Partition, Company, % Cleanup, Cleanup Records, Total Records): ' + @AdditionalComments
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO
	
	

	--
	-- Rule: InventSum - On-hand entries cleanup
	--
		DECLARE @RuleID INT = 7250;
		DECLARE @RuleSection NVARCHAR(100) = 'Data Sizes and Cleanup';
		DECLARE @RuleName NVARCHAR(500) = 'InventSum - On-hand entries cleanup';
		DECLARE @Observation NVARCHAR(MAX) = 'Estimate of InventSum records eligible for cleanup for items that are NOT warehouse enabled. This cleanup routine is used to delete closed and unused entries for on-hand inventory that is assigned to one or more tracking dimensions. Closed transactions contain a value of 0 (zero) for all quantities and cost values, and they are marked as closed. By deleting these transactions, you can help improve the performance of queries for on-hand inventory. Transactions won''t be deleted for on-hand inventory that isn''t assigned to tracking dimensions.';
		DECLARE @Recommendation NVARCHAR(MAX) = 'Run cleanup: Inventory Management > Periodic tasks > Clean up > On-hand entries cleanup';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';
		
		DECLARE @CleanupRecordCountThreshold INT = (SELECT CleanupRecordCountThreshold FROM #D365UpgradeAnalysisReportGlobalVariables);
		DECLARE  @Partition NVARCHAR(MAX), @DataAreaID NVARCHAR(MAX), @PercentCleanup NVARCHAR(MAX), @CleanupRecordCount NVARCHAR(MAX), @TotalRecordCount NVARCHAR(MAX);
		DECLARE cleanupCursor CURSOR FOR
		WITH INVENTSUM_TOTAL_CTE (PARTITION, DATAAREAID, INVENTSUM_TOTAL_RECORDS)
		AS (SELECT PARTITION, DATAAREAID, COUNT (DATAAREAID) AS INVENTSUM_TOTAL_COUNT
		FROM INVENTSUM IVS
		GROUP BY PARTITION, DATAAREAID
		) 
		,
		INVENTSUM_CLEANUP_CTE (PARTITION, DATAAREAID, INVENTSUM_CLEANUP_RECORDS)
		AS (SELECT PARTITION, DATAAREAID, COUNT (DATAAREAID) AS INVENTSUM_CLEANUP_COUNT
		FROM INVENTSUM IVS 
		WHERE CLOSED = 1 
		AND EXISTS (SELECT 'x' FROM INVENTTRANS IVT WHERE STATUSISSUE <> 1 AND STATUSRECEIPT <> 1 AND IVS.PARTITION = IVT.PARTITION AND IVS.DATAAREAID = IVT.DATAAREAID AND IVS.INVENTDIMID = IVT.INVENTDIMID)
		AND NOT EXISTS (SELECT 'x' FROM WHSINVENTENABLED WIE WHERE WIE.PARTITION = IVS.PARTITION AND WIE.DATAAREAID = IVS.DATAAREAID AND WIE.ITEMID = IVS.ITEMID)
		GROUP BY PARTITION, DATAAREAID
		)
	 
		SELECT P.NAME, CTE1.DATAAREAID, CAST ((CAST((INVENTSUM_CLEANUP_RECORDS) AS DECIMAL(20,2))/(CAST((INVENTSUM_TOTAL_RECORDS) AS DECIMAL(20,2))) * 100) AS DECIMAL(5,2)) AS PERCENT_CLEANUP, CTE2.INVENTSUM_CLEANUP_RECORDS AS CLEANUP_RECORD_COUNT, CTE1.INVENTSUM_TOTAL_RECORDS AS TOTAL_RECORD_COUNT
		FROM INVENTSUM_TOTAL_CTE CTE1
		JOIN INVENTSUM_CLEANUP_CTE CTE2 ON CTE1.PARTITION = CTE2.PARTITION AND CTE1.DATAAREAID = CTE2.DATAAREAID
		JOIN PARTITIONS P ON CTE1.PARTITION = P.RECID
		ORDER BY PERCENT_CLEANUP DESC

		OPEN cleanupCursor;
		FETCH NEXT FROM cleanupCursor INTO @Partition, @DataAreaID, @PercentCleanup, @CleanupRecordCount, @TotalRecordCount;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF(@CleanupRecordCount > @CleanupRecordCountThreshold)
			BEGIN
				SET @AdditionalComments = @AdditionalComments + '[' + @Partition + ', ' +  @DataAreaID + ', ' + @PercentCleanup + '%, ' + @CleanupRecordCount + ', ' + @TotalRecordCount + '] | ';
			END
			FETCH NEXT FROM cleanupCursor INTO  @Partition, @DataAreaID, @PercentCleanup, @CleanupRecordCount, @TotalRecordCount;
		END;
		CLOSE cleanupCursor;
		DEALLOCATE cleanupCursor;
		IF (@AdditionalComments != '')
		BEGIN
			SET @AdditionalComments = 'Cleanup details for table INVENTSUM by company (Partition, Company, % Cleanup, Cleanup Records, Total Records): ' + @AdditionalComments
			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		END
		GO


--
-- Rule Section: ISVs
--

	--
	-- Rule: ISV model information
	--

	--  TODO - add in the other two ISVS that were slip into the sub if statements
		DECLARE @RuleID INT = 2000;
		DECLARE @RuleSection NVARCHAR(100) = 'ISVs';
		DECLARE @RuleName NVARCHAR(500) = '';
		DECLARE @Observation NVARCHAR(MAX) = '';
		DECLARE @Recommendation NVARCHAR(MAX) = '';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';

		DECLARE @ModelName NVARCHAR(40);
		DECLARE @ISVModelNameList NVARCHAR(MAX);
		DECLARE @IsDaxEamPresent INT;
		DECLARE @IsFlintFoxPresent INT;
		DECLARE @SQL NVARCHAR(MAX);
		DECLARE @ModelDatabase AS VARCHAR(100) = DB_NAME() + '_Model';
		SET @ISVModelNameList = '';
		SET @SQL = N'DECLARE ISVModelCursor CURSOR FOR '
		SET @SQL = @SQL + N'SELECT T2.NAME FROM [' +  @ModelDatabase + '].DBO.MODEL T1 '
		SET @SQL = @SQL + N'JOIN [' +  @ModelDatabase + '].DBO.MODELMANIFEST T2 '
		SET @SQL = @SQL + N'ON T1.ID = T2.ID '
		SET @SQL = @SQL + N'WHERE T1.LAYERID IN (SELECT ID FROM [' + @ModelDatabase + '].dbo.LAYER WHERE NAME IN (''ISV'',''ISP'',''VAR'',''VAP''))'
		SET @SQL = @SQL + N'AND T2.NAME NOT IN  (''ISV Model'',''ISP Model'',''VAR Model'',''VAP Model'')'

		EXEC (@SQL);

		OPEN ISVModelCursor;
		FETCH NEXT FROM ISVModelCursor INTO @ModelName;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @RuleName = CASE @ModelName
				WHEN 'DemandForecasting' THEN 'Demand forecasting ISV Solution'
				WHEN 'Supply Chain Suite' THEN 'Supply Chain Suite'
				WHEN 'ICON AX' THEN 'ICON AX'
				WHEN 'BT_DPA' THEN 'Document printing ISV Solution'
				WHEN 'BT_DPA_LABELS' THEN 'Document printing labels ISV Solution'
				WHEN 'FPAuditTrail' THEN 'FPAuditTrail'
				WHEN 'SKSAXR3CU13' THEN 'SKSAXR3CU13'
				WHEN 'SKS' THEN 'e-Banking ISV Solution'
				WHEN 'MRO' THEN 'MRO'
				WHEN 'Update for Supply Chain Suite' THEN 'Update for Supply Chain Suite'
				WHEN 'ICON AX Kent fix' THEN 'ICON AX Kent fix'
				WHEN 'MRO Kent changes' THEN 'MRO Kent changes'
				WHEN 'Dynamicweb' THEN 'Dynamicweb'
				WHEN 'BHS_LandedCost' THEN 'BHS_LandedCost'
				WHEN 'JSITH' THEN 'JSITH'
				WHEN 'MFL ITG' THEN 'OCR ISV Solution'
				WHEN 'Kent Model' THEN 'Kent Model'
			END

			SET @Observation = CASE @ModelName
				WHEN 'DemandForecasting' THEN 'You are using ''DemandForecasting'' ISV from ''Farsight Solutions Ltd.'''
				WHEN 'Supply Chain Suite' THEN 'You are using ''Supply Chain Suite'' ISV from ''Blue Horseshoe Solutions, Inc.''.'
				WHEN 'ICON AX' THEN 'You are using ''ICON AX'' ISV from ''ICON AX''.'
				WHEN 'BT_DPA' THEN 'You are using ''BT_DPA'' ISV from ''Bottomline Technologies, Inc.'''
				WHEN 'BT_DPA_LABELS' THEN 'You are using ''BT_DPA_LABELS'' ISV from ''Bottomline Technologies, Inc.'''
				WHEN 'FPAuditTrail' THEN 'You are using ''FPAuditTrail'' ISV from ''Fastpath, Inc.''.'
				WHEN 'SKSAXR3CU13' THEN 'You are using ''SKSAXR3CU13'' ISV from ''SK Global Software''.'
				WHEN 'SKS' THEN 'You are using ''SKS'' ISV from ''SK Global Software''.'
				WHEN 'MRO' THEN 'You are using ''MRO'' ISV from ''Dynaway A/S''.'
				WHEN 'Update for Supply Chain Suite' THEN 'You are using ''Update for Supply Chain Suite'' ISV from ''Blue Horseshoe Solutions, Inc.''.'
				WHEN 'ICON AX Kent fix' THEN 'You are using ''ICON AX Kent fix'' ISV from ''ICON AX''.'
				WHEN 'MRO Kent changes' THEN 'You are using ''MRO Kent changes'' ISV from ''Dynaway A/S''.'
				WHEN 'Dynamicweb' THEN 'You are using ''Dynamicweb'' ISV from ''Dynamicweb''.'
				WHEN 'BHS_LandedCost' THEN 'You are using ''BHS_LandedCost'' ISV from ''Blue Horseshoe Solutions, Inc.''.'
				WHEN 'JSITH' THEN 'You are using ''JSITH'' ISV from ''Junction Solutions''.'
				WHEN 'MFL ITG' THEN 'You are using ''MFL ITG'' ISV from ''Medius RnD''.'
				WHEN 'Kent' THEN 'You are using ''Kent'' ISV from ''Kent Corporation''.'
			END

			SET @Recommendation = CASE @ModelName
				WHEN 'DemandForecasting' THEN 'Microsoft has Demand forecasting using Azure ML.'
				WHEN 'BT_DPA' THEN 'This ISV was used to enhance document printing experience. 
					You can now analyze to replace this ISV with new Dynamics 365 Finance and Operations capability 
						of Electronic Reporting or business document management'
				WHEN 'BHS_LandedCost' THEN 'This ISV was used for Landed cost capabilities, 
					you can evaluate to remove this ISV and use new Dynamics 365 out of the box landed cost module'
				WHEN 'FPAuditTrail' THEN 'FastPath has released new version of FastPath ISV solution, 
					please contact FastPath Inc to get new version of their solution'
				WHEN 'Dynamicweb' THEN 'We recommend you to review the use of this ISV, with new SaaS Dynamics 365 Finance and Operations, this ISV may not be required.'
				WHEN 'SKS' THEN 'SK Global has released new version of e-Banking solution, please contact SK Global Software to get new version of their solution'
				WHEN 'MFL ITG' THEN 'This ISV was used for AP OCR capabilities, you can evaluate to remove this ISV and use new Dynamics 365 OCR capabilities'
			END

			SET @AdditionalComments = CASE @ModelName
				WHEN 'DemandForecasting' THEN 'Refer this lnk https://learn.microsoft.com/en-us/dynamics365/supply-chain/master-planning/introduction-demand-forecasting'
				WHEN 'BT_DPA' THEN 'Refer this link https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/analytics/er-business-document-management'
				WHEN 'BHS_LandedCost' THEN 'Refer this link https://learn.microsoft.com/en-us/dynamics365/supply-chain/landed-cost/landed-cost-overview'
				WHEN 'MFL ITG' THEN 'Refer this link  https://learn.microsoft.com/en-us/dynamics365/finance/accounts-payable/invoice-capture-overview'
			END	

			SET @ISVModelNameList = @ISVModelNameList + @ModelName +  ' - ' + @Recommendation + ', ';

			IF (@ModelName = 'DAXEAM')
			BEGIN
				SET @IsDaxEamPresent = 1;
			END

			IF (@ModelName = 'FlintFox')
			BEGIN
				SET @IsFlintFoxPresent = 1;
			END	

			INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
				VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);

			SET @RuleId = @RuleId + 10;
		
		FETCH NEXT FROM ISVModelCursor INTO @ModelName;
		END
		CLOSE ISVModelCursor;
		DEALLOCATE ISVModelCursor;
		GO
	

	/*-- TODO  - Where should these ones go??
	--
	-- Rule: DAXEAM layer
	--
		DECLARE @RuleID INT = 4000;
		DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
		DECLARE @RuleName NVARCHAR(500) = 'Is DAXEAM being used in AX2012?';
		DECLARE @Observation NVARCHAR(MAX) = 'No';
		DECLARE @Recommendation NVARCHAR(MAX) = '';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';

		IF (@IsDaxEamPresent = 1)
		BEGIN
			SET @Observation = 'Yes';
		END



		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		GO
	
	
	--
	-- Rule: FlintFox layer
	--
		DECLARE @RuleID INT = 4010;
		DECLARE @RuleSection NVARCHAR(100) = 'SCM Enhancements';
		DECLARE @RuleName NVARCHAR(500) = 'FlintFox ISV for pricing?';
		DECLARE @Observation NVARCHAR(MAX) = 'No';
		DECLARE @Recommendation NVARCHAR(MAX) = '';
		DECLARE @AdditionalComments NVARCHAR(MAX) = '';

		IF (@IsFlintFoxPresent = 1)
		BEGIN
			SET @Observation = 'Yes';
		END

		INSERT INTO #D365UpgradeAnalysisReport (RuleID, RuleSection, RuleName, Observation, Recommendation, AdditionalComments)
			VALUES (@RuleId, @RuleSection, @RuleName, @Observation, @Recommendation, @AdditionalComments);
		GO

		*/

--
-- Additional Rule Code Template Section
--

/*
	--
	-- Rule: XXXXX
	--
	DECLARE @RuleID INT = 0;
	DECLARE @RuleName NVARCHAR(500) = '';
	DECLARE @Observation NVARCHAR(MAX) = '';
	DECLARE @Recommendation NVARCHAR(MAX) = '';
	DECLARE @AdditionalComments NVARCHAR(MAX) = '';
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