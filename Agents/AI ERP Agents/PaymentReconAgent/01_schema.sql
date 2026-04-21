/****** Object:  Table [dbo].[ReconciliationRules]    Script Date: 3/24/2026 11:03:33 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[ReconciliationRules](
    [Stage]            [nvarchar](100)  NOT NULL,
    [RuleCode]         [nvarchar](50)   NOT NULL,
    [RuleDescription]  [nvarchar](max)  NOT NULL,
    [CreatedAt]        [datetime]       NOT NULL,
    [ModifiedAt]       [datetime]       NOT NULL,
    [IsSystemRule]     [bit]            NOT NULL,
    [PolicyDriven]     [bit]            NULL,
    [ExecutionOrder]   [int]            NOT NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

/****** Object:  Index [CX_ReconciliationRules_ExecutionOrder]    Script Date: 3/24/2026 11:03:33 PM ******/
CREATE CLUSTERED INDEX [CX_ReconciliationRules_ExecutionOrder] 
ON [dbo].[ReconciliationRules] ([ExecutionOrder] ASC)
GO

/****** Object:  Table [dbo].[ReconciliationExecution]    Script Date: 2/25/2026 9:01:09 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[ReconciliationExecution](
	[ReconciliationId] [nvarchar](50) NOT NULL,
	[ReconciliationDate] [datetime2](3) NOT NULL,
	[RequestedBy] [nvarchar](256) NULL,
	[Status] [nvarchar](30) NOT NULL,
	[Notes] [nvarchar](max) NULL,
	[CommerceRecords] [int] NULL,
	[PaymentRecords] [int] NULL,
 CONSTRAINT [PK_ReconciliationExecution] PRIMARY KEY CLUSTERED 
(
	[ReconciliationId] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[ReconciliationExecution] ADD  CONSTRAINT [DF_RE_ReconciliationId]  DEFAULT (N'') FOR [ReconciliationId]
GO

ALTER TABLE [dbo].[ReconciliationExecution] ADD  CONSTRAINT [DF_RE_ReconciliationDate]  DEFAULT (sysutcdatetime()) FOR [ReconciliationDate]
GO

ALTER TABLE [dbo].[ReconciliationExecution] ADD  CONSTRAINT [DF_RE_RequestedBy]  DEFAULT (N'') FOR [RequestedBy]
GO

ALTER TABLE [dbo].[ReconciliationExecution] ADD  CONSTRAINT [DF_RE_Status]  DEFAULT (N'Pending') FOR [Status]
GO

ALTER TABLE [dbo].[ReconciliationExecution] ADD  CONSTRAINT [DF_RE_Notes]  DEFAULT (N'') FOR [Notes]
GO

ALTER TABLE [dbo].[ReconciliationExecution] ADD  CONSTRAINT [DF_RE_CommerceRecords]  DEFAULT ((0)) FOR [CommerceRecords]
GO

ALTER TABLE [dbo].[ReconciliationExecution] ADD  CONSTRAINT [DF_RE_PaymentRecords]  DEFAULT ((0)) FOR [PaymentRecords]
GO

/****** Object:  Table [dbo].[CommercePaymentTransactionsStaging]    Script Date: 2/25/2026 9:02:06 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CommercePaymentTransactionsStaging](
	[TransactionId] [nvarchar](50) NOT NULL,
	[PaymentReferenceId] [nvarchar](50) NULL,
	[PaymentMethod] [nvarchar](50) NULL,
	[StoreId] [nvarchar](20) NULL,
	[TerminalId] [nvarchar](20) NULL,
	[TransactionDate] [date] NULL,
	[CreationDate] [datetime2](3) NULL,
	[Currency] [nvarchar](10) NULL,
	[Tendered] [numeric](32, 2) NOT NULL,
	[FileImportedDateTime] [datetime2](3) NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_TransactionId]  DEFAULT (N'') FOR [TransactionId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_PaymentReferenceId]  DEFAULT (N'') FOR [PaymentReferenceId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_StoreId]  DEFAULT (N'') FOR [StoreId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_TerminalId]  DEFAULT (N'') FOR [TerminalId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_TransactionDate]  DEFAULT ('1900-01-01') FOR [TransactionDate]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_CreationDate]  DEFAULT (sysutcdatetime()) FOR [CreationDate]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_Currency]  DEFAULT (N'') FOR [Currency]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsStaging] ADD  CONSTRAINT [DF_CPTS_FileImportedDateTime]  DEFAULT (sysutcdatetime()) FOR [FileImportedDateTime]
GO


/****** Object:  Table [dbo].[CommercePaymentTransactions]    Script Date: 2/25/2026 9:03:09 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CommercePaymentTransactions](
	[TransactionId] [nvarchar](50) NOT NULL,
	[PaymentReferenceId] [nvarchar](50) NOT NULL,
	[PaymentMethod] [nvarchar](50) NULL,
	[StoreId] [nvarchar](20) NULL,
	[TerminalId] [nvarchar](20) NULL,
	[TransactionDate] [date] NULL,
	[CreationDate] [datetime2](3) NULL,
	[Currency] [nvarchar](10) NULL,
	[Tendered] [numeric](32, 2) NOT NULL,
	[ReconciliationId] [nvarchar](50) NULL,
	[Remarks] [nvarchar](max) NULL,
	[FileImportedDateTime] [datetime2](3) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_TransactionId]  DEFAULT (N'') FOR [TransactionId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_PaymentReferenceId]  DEFAULT (N'') FOR [PaymentReferenceId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_StoreId]  DEFAULT (N'') FOR [StoreId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_TerminalId]  DEFAULT (N'') FOR [TerminalId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_TransactionDate]  DEFAULT ('1900-01-01') FOR [TransactionDate]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_CreationDate]  DEFAULT (sysutcdatetime()) FOR [CreationDate]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_Currency]  DEFAULT (N'') FOR [Currency]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_ReconciliationId]  DEFAULT (N'') FOR [ReconciliationId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_Remarks]  DEFAULT (N'') FOR [Remarks]
GO

ALTER TABLE [dbo].[CommercePaymentTransactions] ADD  CONSTRAINT [DF_CPT_FileImportedDateTime]  DEFAULT ('1900-01-01') FOR [FileImportedDateTime]
GO


/****** Object:  Table [dbo].[CommercePaymentTransactionsHistory]    Script Date: 2/25/2026 9:04:08 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CommercePaymentTransactionsHistory](
	[TransactionId] [nvarchar](50) NOT NULL,
	[PaymentReferenceId] [nvarchar](50) NULL,
	[PaymentMethod] [nvarchar](50) NULL,
	[StoreId] [nvarchar](20) NULL,
	[TerminalId] [nvarchar](20) NULL,
	[TransactionDate] [date] NULL,
	[CreationDate] [datetime2](3) NULL,
	[Currency] [nvarchar](10) NULL,
	[Tendered] [numeric](32, 2) NOT NULL,
	[ReconciliationId] [nvarchar](50) NOT NULL,
	[Remarks] [nvarchar](max) NULL,
	[FileImportedDateTime] [datetime2](3) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_TransactionId]  DEFAULT (N'') FOR [TransactionId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_PaymentReferenceId]  DEFAULT (N'') FOR [PaymentReferenceId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_StoreId]  DEFAULT (N'') FOR [StoreId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_TerminalId]  DEFAULT (N'') FOR [TerminalId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_TransactionDate]  DEFAULT ('1900-01-01') FOR [TransactionDate]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_CreationDate]  DEFAULT (sysutcdatetime()) FOR [CreationDate]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_Currency]  DEFAULT (N'') FOR [Currency]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_ReconciliationId]  DEFAULT (N'') FOR [ReconciliationId]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_Remarks]  DEFAULT (N'') FOR [Remarks]
GO

ALTER TABLE [dbo].[CommercePaymentTransactionsHistory] ADD  CONSTRAINT [DF_CPTH_FileImportedDateTime]  DEFAULT ('1900-01-01') FOR [FileImportedDateTime]
GO

/****** Object:  Table [dbo].[PaymentProcessorTransactionsStaging]    Script Date: 2/25/2026 9:05:20 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[PaymentProcessorTransactionsStaging](
	[MerchantAccount] [nvarchar](100) NULL,
	[PaymentReferenceId] [nvarchar](50) NULL,
	[MerchantReference] [nvarchar](200) NULL,
	[PaymentMethod] [nvarchar](50) NULL,
	[CreationDate] [datetime2](3) NULL,
	[TimeZone] [nvarchar](10) NULL,
	[Status] [nvarchar](50) NULL,
	[ModificationReference] [nvarchar](50) NULL,
	[GrossCurrency] [nvarchar](10) NULL,
	[GrossDebit] [numeric](32, 2) NULL,
	[GrossCredit] [numeric](32, 2) NULL,
	[ExchangeRate] [numeric](18, 6) NULL,
	[BatchNumber] [nvarchar](50) NULL,
	[ModificationMerchantReference] [nvarchar](200) NULL,
	[ARN] [nvarchar](100) NULL,
	[Currency] [nvarchar](10) NULL,
	[Authorised] [numeric](32, 2) NULL,
	[Commission] [numeric](32, 2) NULL,
	[Interchange] [numeric](32, 2) NULL,
	[Received] [numeric](32, 2) NULL,
	[Markup] [numeric](32, 2) NULL,
	[Captured] [numeric](32, 2) NULL,
	[Payable] [numeric](32, 2) NULL,
	[SchemeFees] [numeric](32, 2) NULL,
	[FileImportedDateTime] [datetime2](3) NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_MerchantAccount]  DEFAULT (N'') FOR [MerchantAccount]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_PaymentReferenceId]  DEFAULT (N'') FOR [PaymentReferenceId]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_MerchantReference]  DEFAULT (N'') FOR [MerchantReference]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_PaymentMethod]  DEFAULT (N'') FOR [PaymentMethod]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_CreationDate]  DEFAULT ('1900-01-01') FOR [CreationDate]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_TimeZone]  DEFAULT (N'') FOR [TimeZone]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Status]  DEFAULT (N'') FOR [Status]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_ModificationReference]  DEFAULT (N'') FOR [ModificationReference]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_GrossCurrency]  DEFAULT (N'') FOR [GrossCurrency]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_GrossDebit]  DEFAULT ((0.00)) FOR [GrossDebit]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_GrossCredit]  DEFAULT ((0.00)) FOR [GrossCredit]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_ExchangeRate]  DEFAULT ((1.000000)) FOR [ExchangeRate]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_BatchNumber]  DEFAULT (N'') FOR [BatchNumber]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_ModificationMerchantReference]  DEFAULT (N'') FOR [ModificationMerchantReference]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_ARN]  DEFAULT (N'') FOR [ARN]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Currency]  DEFAULT (N'') FOR [Currency]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Authorised]  DEFAULT ((0.00)) FOR [Authorised]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Commission]  DEFAULT ((0.00)) FOR [Commission]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Interchange]  DEFAULT ((0.00)) FOR [Interchange]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Received]  DEFAULT ((0.00)) FOR [Received]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Markup]  DEFAULT ((0.00)) FOR [Markup]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Captured]  DEFAULT ((0.00)) FOR [Captured]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_Payable]  DEFAULT ((0.00)) FOR [Payable]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_SchemeFees]  DEFAULT ((0.00)) FOR [SchemeFees]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsStaging] ADD  CONSTRAINT [DF_PPTS_FileImportedDateTime]  DEFAULT (sysutcdatetime()) FOR [FileImportedDateTime]
GO


/****** Object:  Table [dbo].[PaymentProcessorTransactions]    Script Date: 2/25/2026 9:06:35 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[PaymentProcessorTransactions](
	[PaymentReferenceId] [nvarchar](50) NOT NULL,
	[Currency] [nvarchar](10) NULL,
	[PaymentMethod] [nvarchar](50) NULL,
	[Authorised] [numeric](32, 2) NULL,
	[Commission] [numeric](32, 2) NULL,
	[Interchange] [numeric](32, 2) NULL,
	[Received] [numeric](32, 2) NULL,
	[Markup] [numeric](32, 2) NULL,
	[Captured] [numeric](32, 2) NULL,
	[Payable] [numeric](32, 2) NULL,
	[SchemeFees] [numeric](32, 2) NULL,
	[Status] [nvarchar](30) NULL,
	[ReconciliationId] [nvarchar](50) NULL,
	[BookingDate] [date] NULL,
	[CreationDate] [datetime2](3) NULL,
	[Remarks] [nvarchar](max) NULL,
	[FileImportedDateTime] [datetime2](3) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_PaymentReferenceId]  DEFAULT (N'') FOR [PaymentReferenceId]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Currency]  DEFAULT (N'') FOR [Currency]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_PaymentMethod]  DEFAULT (N'') FOR [PaymentMethod]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Authorised]  DEFAULT ((0.00)) FOR [Authorised]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Commission]  DEFAULT ((0.00)) FOR [Commission]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Interchange]  DEFAULT ((0.00)) FOR [Interchange]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Received]  DEFAULT ((0.00)) FOR [Received]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Markup]  DEFAULT ((0.00)) FOR [Markup]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Captured]  DEFAULT ((0.00)) FOR [Captured]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Payable]  DEFAULT ((0.00)) FOR [Payable]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_SchemeFees]  DEFAULT ((0.00)) FOR [SchemeFees]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Status]  DEFAULT (N'') FOR [Status]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_ReconciliationId]  DEFAULT (N'') FOR [ReconciliationId]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_BookingDate]  DEFAULT ('1900-01-01') FOR [BookingDate]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_CreationDate]  DEFAULT (sysutcdatetime()) FOR [CreationDate]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_Remarks]  DEFAULT (N'') FOR [Remarks]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactions] ADD  CONSTRAINT [DF_PPT_FileImportedDateTime]  DEFAULT ('1900-01-01') FOR [FileImportedDateTime]
GO



/****** Object:  Table [dbo].[PaymentProcessorTransactionsHistory]    Script Date: 2/5/2026 8:42:57 PM ******/
/****** Object:  Table [dbo].[PaymentProcessorTransactionsHistory]    Script Date: 2/25/2026 9:07:44 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[PaymentProcessorTransactionsHistory](
	[PaymentReferenceId] [nvarchar](50) NULL,
	[Currency] [nvarchar](10) NOT NULL,
	[PaymentMethod] [nvarchar](50) NULL,
	[Authorised] [numeric](32, 2) NULL,
	[Commission] [numeric](32, 2) NULL,
	[Interchange] [numeric](32, 2) NULL,
	[Received] [numeric](32, 2) NULL,
	[Markup] [numeric](32, 2) NULL,
	[Captured] [numeric](32, 2) NULL,
	[Payable] [numeric](32, 2) NULL,
	[SchemeFees] [numeric](32, 2) NULL,
	[Status] [nvarchar](30) NULL,
	[ReconciliationId] [nvarchar](50) NULL,
	[BookingDate] [date] NULL,
	[CreationDate] [datetime2](3) NULL,
	[Remarks] [nvarchar](max) NULL,
	[FileImportedDateTime] [datetime2](3) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_PaymentReferenceId]  DEFAULT (N'') FOR [PaymentReferenceId]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Currency]  DEFAULT (N'') FOR [Currency]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_PaymentMethod]  DEFAULT (N'') FOR [PaymentMethod]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Authorised]  DEFAULT ((0.00)) FOR [Authorised]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Commission]  DEFAULT ((0.00)) FOR [Commission]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Interchange]  DEFAULT ((0.00)) FOR [Interchange]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Received]  DEFAULT ((0.00)) FOR [Received]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Markup]  DEFAULT ((0.00)) FOR [Markup]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Captured]  DEFAULT ((0.00)) FOR [Captured]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Payable]  DEFAULT ((0.00)) FOR [Payable]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_SchemeFees]  DEFAULT ((0.00)) FOR [SchemeFees]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Status]  DEFAULT (N'') FOR [Status]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_ReconciliationId]  DEFAULT (N'') FOR [ReconciliationId]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_BookingDate]  DEFAULT ('1900-01-01') FOR [BookingDate]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_CreatedDate]  DEFAULT (sysutcdatetime()) FOR [CreationDate]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_Remarks]  DEFAULT (N'') FOR [Remarks]
GO

ALTER TABLE [dbo].[PaymentProcessorTransactionsHistory] ADD  CONSTRAINT [DF_PPTH_FileImportedDateTime]  DEFAULT ('1900-01-01') FOR [FileImportedDateTime]
GO

/****** Object:  View [dbo].[PayRecon_UnreconciledCommerceTransactions]    Script Date: 2/6/2026 6:00:01 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[PayRecon_UnreconciledCommerceTransactions] AS
SELECT *
FROM CommercePaymentTransactions
WHERE ReconciliationId IS NULL OR ReconciliationId = '';
GO

/****** Object:  View [dbo].[PayRecon_UnreconciledPaymentProcessorTransactions]    Script Date: 2/6/2026 6:00:33 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[PayRecon_UnreconciledPaymentProcessorTransactions] AS
SELECT *
FROM PaymentProcessorTransactions
WHERE ReconciliationId IS NULL OR ReconciliationId = '';
GO

/****** Object:  View [dbo].[PayRecon_PolicyDrivenRules]    Script Date: 3/24/2026 11:20:11 PM ******/
CREATE VIEW [dbo].[PayRecon_PolicyDrivenRules] AS
SELECT 
    [ExecutionOrder],
    [Stage],
    [RuleCode],
    [RuleDescription],
    [CreatedAt],
    [ModifiedAt],
    [IsSystemRule],
    [PolicyDriven]
FROM [dbo].[ReconciliationRules]
WHERE [PolicyDriven] = 1;