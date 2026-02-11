WITH allviews (nodeId, parentNodeId, nodeIdType, rootNode, depth) AS (
        SELECT 
            nv.name AS nodeId,
            CAST(NULL AS NVARCHAR(MAX)) AS parentNodeId,
            CAST('VIEW' AS NVARCHAR(60)) COLLATE DATABASE_DEFAULT AS nodeIdType,
            nv.name AS rootNode,
            0 AS depth
        FROM sys.views nv
        WHERE schema_name(nv.schema_id) = @old_schema
          AND nv.name IN (SELECT value FROM STRING_SPLIT(@entities, ','))
        
        UNION ALL
        
        SELECT 
            o.name AS nodeId,
            CAST(p.name AS NVARCHAR(MAX)) AS parentNodeId,
            o.type_desc COLLATE DATABASE_DEFAULT AS nodeIdType,
            allviews.rootNode AS rootNode,
            allviews.depth + 1 AS depth
        FROM sys.sql_expression_dependencies d
        JOIN sys.objects o ON o.object_id = d.referenced_id
        JOIN sys.objects p ON p.object_id = d.referencing_id
        JOIN allviews ON allviews.nodeId = p.name
        WHERE d.referenced_id IS NOT NULL
          AND p.type_desc = 'VIEW'
          AND schema_name(p.schema_id) = @old_schema
          AND schema_name(o.schema_id) = @old_schema
    )

	--4 inserts the results in a temporary table for ease of use
	Select * into #myEntitiestree from allviews ;

    SELECT 
        rootNode AS rootEntity,
        nodeId AS entityName, 
        nodeIdType AS objectType,  
        MAX(depth) AS depth,
        (
            SELECT TOP 1 replace(replace(replace(m.definition, 'create ', 'CREATE or ALTER '), ' VIEW ['+@old_schema+'].', ' VIEW ['+ @new_schema +'].'), ' '+@old_schema+'.', ' '+ @new_schema +'.')
            FROM sys.sql_modules m
            JOIN sys.objects o ON m.object_id = o.object_id
            WHERE 
                o.schema_id = schema_id(@old_schema)
                AND o.name COLLATE DATABASE_DEFAULT = x.nodeId COLLATE DATABASE_DEFAULT 
                AND o.type_desc COLLATE DATABASE_DEFAULT = nodeIdType COLLATE DATABASE_DEFAULT
        ) AS definition
    FROM #myEntitiestree x
    GROUP BY nodeId, nodeIdType, rootNode
    ORDER BY depth DESC;
    
