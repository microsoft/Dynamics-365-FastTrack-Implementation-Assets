-- With the synapse link derived tables such as DirPartyTable, EcoResProduct may have missing fields as compared to database or Export to data lake feature
-- The reason is Synapse link goes through application layer and only extract field that are available in the table
-- the workaround to solve missing columns is to add applicable child tables to synapse link and create view joining the derived tables on target system
-- this script identifies all derived parent tables and related child  table and also the join statement that can be used to represent the final data   
-- Step: Run this script on D365 sandbox environment database (Use LCS JIT access process to obtain connection string) or Cloud hosted environment (Dev environment) 
-- Output : Script will provide output following for each parent table 
-- parenttable	childtables	synapselinkjoinstatement
--DirPartyTable	CompanyInfo,DirOrganization,DirOrganizationBase,DirPerson,OMInternalOrganization,OMOperatingUnit,OMTeam	select [DirPartyTable].[AddressBookNames],[DirPartyTable].[InstanceRelationType],[DirPartyTable].[KnownAs],[DirPartyTable].[LanguageId],[DirPartyTable].[LegacyInstanceRelationType],[DirPartyTable].[Name],[DirPartyTable].[NameAlias],[DirPartyTable].[PartyNumber],[DirPartyTable].[PrimaryAddressLocation],[DirPartyTable].[PrimaryContactEmail],[DirPartyTable].[PrimaryContactFacebook],[DirPartyTable].[PrimaryContactFax],[DirPartyTable].[PrimaryContactLinkedIn],[DirPartyTable].[PrimaryContactPhone],[DirPartyTable].[PrimaryContactTelex],[DirPartyTable].[PrimaryContactTwitter],[DirPartyTable].[PrimaryContactURL],[CompanyInfo].[Accountant_LT],[CompanyInfo].[AccountingPersonnel_JP],[CompanyInfo].[AccountOfficeRefNum],[CompanyInfo].[ActivityCode],[CompanyInfo].[AddrFormat],[CompanyInfo].[Bank],[CompanyInfo].[BankAcctUsedFor1099],[CompanyInfo].[BankCentralBankPurposeCode],[CompanyInfo].[BankCentralBankPurposeText],[CompanyInfo].[BranchId],[CompanyInfo].[BusinessActivity_SA],[CompanyInfo].[BusinessActivityDesc_SA],[CompanyInfo].[BusinessCommencedDate_JP],[CompanyInfo].[BusinessInitialCapital_JP],[CompanyInfo].[BusinessItem_JP],[CompanyInfo].[BusinessNumber_CA],[CompanyInfo].[CertifiedTaxAccountant_JP],[CompanyInfo].[CNAE_BR],[CompanyInfo].[CombinedFedStateFiler],[CompanyInfo].[CompanyInitialCapital_FR],[CompanyInfo].[CompanyNAFCode],[CompanyInfo].[CompanyRegComFR],[CompanyInfo].[CompanyRepresentative_JP],[CompanyInfo].[CompanyType_MX],[CompanyInfo].[ConversionDate],[CompanyInfo].[CoRegNum],[CompanyInfo].[CUC_IT],[CompanyInfo].[Curp_MX],[CompanyInfo].[DashboardImageType],[CompanyInfo].[DataArea],[CompanyInfo].[DBA],[CompanyInfo].[DeclarantName_AE],[CompanyInfo].[DVRid],[CompanyInfo].[EeEnablePersonalDataReadLog],[CompanyInfo].[EeEnableRoleChangeLog],[CompanyInfo].[EnterpriseCode],[CompanyInfo].[FICreditorID_DK],[CompanyInfo].[FileNumber_SA],[CompanyInfo].[FiscalCode_IT],[CompanyInfo].[ForeignEntityIndicator],[CompanyInfo].[FSS_RU],[CompanyInfo].[FSSAccount_RU],[CompanyInfo].[Giro],[CompanyInfo].[GiroContract],[CompanyInfo].[GiroContractAccount],[CompanyInfo].[Head_LT],[CompanyInfo].[ImportVATNum],[CompanyInfo].[ImportVATNumBranchId],[CompanyInfo].[IntrastatCode],[CompanyInfo].[IsConsolidationCompany],[CompanyInfo].[IsEliminationCompany],[CompanyInfo].[IssuingSignature],[CompanyInfo].[Key],[CompanyInfo].[LastFilingIndicator],[CompanyInfo].[LegalFormFR],[CompanyInfo].[LegalNature_IT],[CompanyInfo].[LegalRepresentative_JP],[CompanyInfo].[LegalRepresentativeCurp_MX],[CompanyInfo].[LegalRepresentativeName_MX],[CompanyInfo].[LegalRepresentativeRfc_MX],[CompanyInfo].[LocalizationCountryRegionCode],[CompanyInfo].[NAICS],[CompanyInfo].[NameControl],[CompanyInfo].[OrganizationLegalForm_RU],[CompanyInfo].[OrgId],[CompanyInfo].[PackMaterialFeeLicenseNum],[CompanyInfo].[PaymInstruction1],[CompanyInfo].[PaymInstruction2],[CompanyInfo].[PaymInstruction3],[CompanyInfo].[PaymInstruction4],[CompanyInfo].[PaymRoutingDNB],[CompanyInfo].[PaymTraderNumber],[CompanyInfo].[PersonInCharge_JP],[CompanyInfo].[PFRegNum_RU],[CompanyInfo].[PlanningCompany],[CompanyInfo].[PrintCorrInvoiceLabel_DE],[CompanyInfo].[PrintCorrInvoiceLabelEffDate_DE],[CompanyInfo].[PrintEnterpriseregister_NO],[CompanyInfo].[PrintINNKPPInAddress_RU],[CompanyInfo].[PrivacyConsent_DK],[CompanyInfo].[ProfitMarginScheme_AE],[CompanyInfo].[RAlienCorpCountry],[CompanyInfo].[RAlienCorpName],[CompanyInfo].[RegNum],[CompanyInfo].[Resident_W],[CompanyInfo].[Rfc_MX],[CompanyInfo].[RFullName],[CompanyInfo].[ShippingCalendarId],[CompanyInfo].[SiaCode],[CompanyInfo].[SoftwareIdentificationCode_CA],[CompanyInfo].[StateInscription_MX],[CompanyInfo].[SubordinateCode],[CompanyInfo].[Tax1099RegNum],[CompanyInfo].[TaxableAgencyName_AE],[CompanyInfo].[TaxableAgentName_AE],[CompanyInfo].[TaxablePersonName_AE],[CompanyInfo].[TaxAuthority_RU],[CompanyInfo].[TaxGSTHSTAccountId_CA],[CompanyInfo].[TaxRegimeCode_MX],[CompanyInfo].[TaxRepresentative],[CompanyInfo].[TCC],[CompanyInfo].[TemplateFolder_W],[CompanyInfo].[UPSNum],[CompanyInfo].[validate1099OnEntry],[CompanyInfo].[VATNum],[CompanyInfo].[VATNumBranchId],[CompanyInfo].[VATOnCustomerBehalf_AE],[CompanyInfo].[VATRefund_AE],[DirOrganization].[ABC],[DirOrganization].[NumberOfEmployees],[DirOrganization].[OrgNumber],[DirOrganizationBase].[DunsNumberRecId],[DirOrganizationBase].[PhoneticName],[DirPerson].[AnniversaryDay],[DirPerson].[AnniversaryMonth],[DirPerson].[AnniversaryYear],[DirPerson].[BirthDay],[DirPerson].[BirthMonth],[DirPerson].[BirthYear],[DirPerson].[ChildrenNames],[DirPerson].[CommunicatorSignIn],[DirPerson].[Gender],[DirPerson].[Hobbies],[DirPerson].[Initials],[DirPerson].[MaritalStatus],[DirPerson].[NameSequence],[DirPerson].[PersonalSuffix],[DirPerson].[PersonalTitle],[DirPerson].[PhoneticFirstName],[DirPerson].[PhoneticLastName],[DirPerson].[PhoneticMiddleName],[DirPerson].[ProfessionalSuffix],[DirPerson].[ProfessionalTitle],[OMInternalOrganization].[OrganizationType],[OMOperatingUnit].[HcmWorker],[OMOperatingUnit].[OMOperatingUnitNumber],[OMOperatingUnit].[OMOperatingUnitType],[OMTeam].[Description],[OMTeam].[IsActive],[OMTeam].[TeamAdministrator],[OMTeam].[TeamMembershipCriterion] FROM DirPartyTable AS DirPartyTable LEFT OUTER JOIN CompanyInfo AS CompanyInfo ON DirPartyTable.recid = CompanyInfo.recid LEFT OUTER JOIN DirOrganization AS DirOrganization ON DirPartyTable.recid = DirOrganization.recid LEFT OUTER JOIN DirOrganizationBase AS DirOrganizationBase ON DirPartyTable.recid = DirOrganizationBase.recid LEFT OUTER JOIN DirPerson AS DirPerson ON DirPartyTable.recid = DirPerson.recid LEFT OUTER JOIN OMInternalOrganization AS OMInternalOrganization ON DirPartyTable.recid = OMInternalOrganization.recid LEFT OUTER JOIN OMOperatingUnit AS OMOperatingUnit ON DirPartyTable.recid = OMOperatingUnit.recid LEFT OUTER JOIN OMTeam AS OMTeam ON DirPartyTable.recid = OMTeam.recid
--EcoResProduct	EcoResDistinctProduct,EcoResDistinctProductVariant,EcoResProductMaster	select [EcoResProduct].[DisplayProductNumber],[EcoResProduct].[EngChgProductCategoryDetails],[EcoResProduct].[EngChgProductOwnerId],[EcoResProduct].[EngChgProductReadinessPolicy],[EcoResProduct].[EngChgProductReleasePolicy],[EcoResProduct].[InstanceRelationType],[EcoResProduct].[PdsCWProduct],[EcoResProduct].[ProductType],[EcoResProduct].[SearchName],[EcoResProduct].[ServiceType],[EcoResDistinctProductVariant].[ProductMaster],[EcoResDistinctProductVariant].[RetaiTotalWeight],[EcoResProductMaster].[IsProductVariantUnitConversionEnabled],[EcoResProductMaster].[RetailColorGroupId],[EcoResProductMaster].[RetailSizeGroupId],[EcoResProductMaster].[RetailStyleGroupId],[EcoResProductMaster].[VariantConfigurationTechnology] FROM EcoResProduct AS EcoResProduct LEFT OUTER JOIN EcoResDistinctProduct AS EcoResDistinctProduct ON EcoResProduct.recid = EcoResDistinctProduct.recid LEFT OUTER JOIN EcoResDistinctProductVariant AS EcoResDistinctProductVariant ON EcoResProduct.recid = EcoResDistinctProductVariant.recid LEFT OUTER JOIN EcoResProductMaster AS EcoResProductMaster ON EcoResProduct.recid = EcoResProductMaster.recidwith parenttable as 
-- Identify the parent table and child tables- Add all parent and child tables to synapse link profile example for dirpartytable add DirPartyTable,CompanyInfo,DirOrganization,DirOrganizationBase,DirPerson,OMInternalOrganization,OMOperatingUnit,OMTeam to fabric/synapse link
-- synapselinkjoinstatement - this presets the joined statement to represent all the columns how they were present when using export to data lake 
-- this can be represented as view on the target database link Synapse serverless, Azure SQL or Spark notebooks or dedicated pool to represent final table
with parenttable as 
(
select t.NAME as ParentTableName, string_agg(convert(nvarchar(max),'['+ T.Name + '].[' + s.Name + ']'), ',') as parenttablecolumns
	from TABLEIDTABLE T
	left outer join TABLEFIELDIDTABLE s on s.TableId = T.ID and s.NAME not like 'DEL_%'
	-- add addtional parent tables as applicable
	where t.NAME in (
select distinct P.NAME as Parent
from SYSINHERITANCERELATIONS H
left outer join TABLEIDTABLE as C on H.MAINTABLEID = C.ID
left outer join TABLEIDTABLE as P on H.RELATEDTABLEID = P.ID
Where P.NAME not like  'Aif%' and  P.NAME not like  'Sys%' and  P.NAME not like  'FND%' 
and  P.NAME not like  'FND%' and  P.NAME not like  'BFT%' and  P.NAME not like  'XPP%' and  P.NAME not like  '%Test%'  
and P.NAME not like  'SVC%'  and P.NAME not like  'SRV%'  and P.NAME not like  'FM%'  and P.NAME not like  'PC%' and P.NAME not like  'DPT%'   and P.NAME not like  'CLI%'  )
	group by T.NAME
),
DerivedTables AS
(
SELECT
      DerivedTable.Name as derivedTable,
	  DerivedTable.ID as derivedTableId,
      BaseTable.NAME as BaseTable,
	  BaseTable.ID as BaseTableId
FROM dbo.TableIdTable DerivedTable
 JOIN dbo.SYSANCESTORSTABLE TableInheritance on TableInheritance.TableId = DerivedTable.ID
LEFT JOIN dbo.TableIdTable BaseTable on BaseTable.ID = TableInheritance.ParentId
where TableInheritance.ParentId != TableInheritance.TableId
and BaseTable.NAME in (select ParentTableName from  parenttable)
),
RecursiveCTE AS (
    -- Base case: Get derived tables for the top base tables
    SELECT 
        basetable AS TopBaseTable, 
		basetableId AS TopBaseTableId, 
        derivedtable AS LeafTable,
        derivedtableId AS LeafTableId
    FROM 
        DerivedTables
    WHERE 
        basetable NOT IN (SELECT derivedtable FROM DerivedTables)
    UNION ALL

    SELECT 
        r.TopBaseTable, 
		r.TopBaseTableId,
        t.derivedtable AS LeafTable,
		t.derivedTableId
    FROM 
        DerivedTables t
    INNER JOIN 
        RecursiveCTE r ON t.basetable = r.LeafTable
    WHERE 
        t.derivedtable NOT IN (SELECT basetable FROM DerivedTables)
)

-- Select results from the CTE
select 
parenttable,
childtables,
'select ' + parenttablecolumns + ',' + derivedTableColumns + ' FROM ' + parenttable +  ' AS ' +  
parenttable + ' ' +  joinclause as synapselinkjoinstatement
from 
(
select 
parentTable,
STRING_AGG(convert(nvarchar(max),childtable), ',') as childtables,
STRING_AGG(convert(nvarchar(max),derivedTableColumns), ',') as derivedTableColumns,
STRING_AGG(convert(nvarchar(max),joinclause), ' ') as joinclause,
parenttablecolumns
from 
(SELECT 
    TopBaseTable AS parenttable,
	TopBaseTableId AS parentTableId,
	LeafTable AS childtable,
    LeafTableId AS LeafTableId,
	string_agg(convert(nvarchar(max),'['+ LeafTable + '].[' + s.Name + ']'), ',')  as derivedTableColumns,
	'LEFT OUTER JOIN ' + LeafTable + ' AS ' + LeafTable + ' ON ' + TopBaseTable +'.recid = ' + LeafTable + '.recid' AS joinclause,
	p.parenttablecolumns
FROM 
    RecursiveCTE r1
	join parenttable p on p.ParentTableName = r1.TopBaseTable 
	left outer join TABLEFIELDIDTABLE s on s.TableId = LeafTableId
	and s.NAME not like 'DEL_%'
	and s.Name not in (select value from string_split('RELATIONTYPE,modifieddatetime,modifiedby,modifiedtransactionid,dataareaid,recversion,partition,sysrowversion,recid,tableid,versionnumber,createdon,modifiedon,isDelete,PartitionId,createddatetime,createdby,createdtransactionid,PartitionId,sysdatastatecode', ','))
GROUP BY 
    TopBaseTable, TopBaseTableId, LeafTable, LeafTableId, parenttablecolumns
) x 
group by  parentTable, parenttablecolumns
) y





