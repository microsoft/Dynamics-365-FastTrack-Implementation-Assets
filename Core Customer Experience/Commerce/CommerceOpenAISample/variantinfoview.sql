SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE VIEW [dbo].[VARIANTINFOVIEW]
AS
    (SELECT T1.product                AS PRODUCT,
        T2.distinctproductvariant AS DISTINCTPRODUCTVARIANT,
        T3.inventcolorid          AS INVENTCOLORID,
        T3.configid               AS INVENTCONFIGID,
        T3.inventsizeid           AS INVENTSIZEID,
        T3.inventstyleid          AS INVENTSTYLEID,
        T4.displayproductnumber   AS DISPLAYPRODUCTNUMBER,
        T5.displayproductnumber   AS DISPLAYPRODUCTVARIANTNUMBER
    FROM inventtable T1
        LEFT OUTER JOIN inventdimcombination T2
        ON( ( ( ( T1.itemid = T2.itemid )
            AND ( T1.dataareaid = T2.dataareaid ) )
            AND ( T1.partition = T2.partition ) )
            AND ( ( ( T1.dataareaid = T2.dataareaid )
            AND ( T1.dataareaid = T2.dataareaid ) )
            AND ( T1.partition = T2.partition ) ) )
        LEFT OUTER JOIN inventdim T3
        ON( ( ( ( T2.inventdimid = T3.inventdimid )
            AND ( T2.dataareaid = T3.dataareaid ) )
            AND ( T2.partition = T3.partition ) )
            AND ( ( ( T2.dataareaid = T3.dataareaid )
            AND ( T2.dataareaid = T3.dataareaid ) )
            AND ( T2.partition = T3.partition ) ) )
         CROSS JOIN ecoresproduct T4
        LEFT OUTER JOIN ecoresproduct T5
        ON( ( T2.distinctproductvariant = T5.recid )
            AND ( T2.partition = T5.partition ) )
        LEFT OUTER JOIN ecorescolor T6
        ON( ( T3.inventcolorid = T6.name )
            AND ( T3.partition = T6.partition ) )
        LEFT OUTER JOIN ecoresconfiguration T7
        ON( ( T3.configid = T7.name )
            AND ( T3.partition = T7.partition ) )
        LEFT OUTER JOIN ecoressize T8
        ON( ( T3.inventsizeid = T8.name )
            AND ( T3.partition = T8.partition ) )
        LEFT OUTER JOIN ecoresstyle T9
        ON( ( T3.inventstyleid = T9.name )
            AND ( T3.partition = T9.partition ) )
        LEFT OUTER JOIN ecoresproduct T10
        ON( ( T2.distinctproductvariant = T10.recid )
            AND ( T2.partition = T10.partition ) )
        LEFT OUTER JOIN ecoresproduct T11
        ON( ( T2.distinctproductvariant = T11.recid )
            AND ( T2.partition = T11.partition ) )
    WHERE ( ( T1.product = T4.recid )
        AND ( T1.partition = T4.partition ) ))

GO

