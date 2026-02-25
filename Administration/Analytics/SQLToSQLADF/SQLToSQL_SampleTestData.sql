
CREATE TABLE [dbo].[Student](
	[ID] [int] NOT NULL,
	[Name] [varchar](10) NOT NULL,
	[Marks] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC,
	[Name] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


insert into dbo.Student (ID, Name, Marks) values (1, 'David', 80), (2, 'Mark', 85), (3, 'Rohit', 80)

-- Run full export pipeline

update Student 
set Marks = 90
where id = 1 ;
-- run incremental export pipeline 
