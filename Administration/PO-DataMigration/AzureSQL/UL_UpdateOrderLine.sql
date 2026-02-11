/****** Object:  StoredProcedure [dbo].[UL_UpdateOrderLine]    Script Date: 3/8/2022 7:51:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [dbo].[UL_UpdateOrderLine]
AS

UPDATE UL_OrderLine
SET
   Id = dl.Id
FROM
   UL_OrderLine ul
JOIN
   DL_OrderLine dl
ON
   ul.name = dl.name and
   ul.[Order] = dl.[Order]
GO

