/****** Object:  StoredProcedure [dbo].[UL_CreateJournal]    Script Date: 3/14/2022 10:01:59 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateJournal]
AS

TRUNCATE TABLE UL_Journal
INSERT INTO
   UL_Journal
SELECT
    distinct JournalName as Description,
	192350000 as JournalType, --Entry
	CAST (NULL as uniqueIdentifier) as Id
FROM
    CU_JournalLine
GO

