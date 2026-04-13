

-- CREATE DATABASE


IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'capex')
    CREATE DATABASE capex;
GO

USE capex;
GO


-- CREATE TABLES


DROP TABLE IF EXISTS ProjectPlantMap;
DROP TABLE IF EXISTS OpsKPI;
DROP TABLE IF EXISTS Milestones;
DROP TABLE IF EXISTS CapexPostings;
DROP TABLE IF EXISTS Projects;

CREATE TABLE Projects (
    ProjectID             VARCHAR(10)   PRIMARY KEY,
    ProjectName           VARCHAR(100),
    Sponsor               VARCHAR(50),
    StartDate             DATE,
    PlannedGoLiveDate     DATE,
    BudgetAmount          BIGINT,
    ExpectedAnnualBenefit BIGINT,
    BenefitType           VARCHAR(50)
);

CREATE TABLE CapexPostings (
    PostingID      VARCHAR(10)  PRIMARY KEY,
    ProjectID      VARCHAR(10)  REFERENCES Projects(ProjectID),
    PostingDate    DATE,
    Amount         BIGINT,
    NatureOfCost   VARCHAR(50),
    Vendor         VARCHAR(50),
    CapitalizeFlag VARCHAR(3)
);

CREATE TABLE Milestones (
    ProjectID     VARCHAR(10)  REFERENCES Projects(ProjectID),
    MilestoneName VARCHAR(50),
    PlannedDate   DATE,
    ActualDate    DATE,
    Status        VARCHAR(20)
);

CREATE TABLE OpsKPI (
    PlantID        VARCHAR(10),
    MonthStartDate DATE,
    UnitsProduced  INT,
    DowntimeHours  INT,
    ScrapRate      DECIMAL(5,4)
);

CREATE TABLE ProjectPlantMap (
    ProjectID VARCHAR(10) REFERENCES Projects(ProjectID),
    PlantID   VARCHAR(10)
);

PRINT 'Tables created.';
GO



--INSERT DATA



INSERT INTO Projects VALUES
('PR01','Automation Line',   'COO',        '2023-10-01','2024-06-01',50000000,12000000,'Cost Reduction'),
('PR02','Capacity Expansion','Plant Head',  '2023-12-01','2024-08-01',80000000,20000000,'Revenue Growth');


INSERT INTO CapexPostings VALUES
('CP01','PR01','2024-01-10',10000000,'Machinery',   'Vendor A','Yes'),
('CP02','PR01','2024-03-15', 8000000,'Installation','Vendor B','Yes'),
('CP03','PR02','2024-02-20',15000000,'Civil',        'Vendor C','Yes');


INSERT INTO Milestones VALUES
('PR01','Design','2023-11-15','2023-11-20','Completed'),
('PR01','GoLive','2024-06-01','2024-06-20','Delayed'),
('PR02','GoLive','2024-08-01', NULL,        'Planned');


INSERT INTO OpsKPI VALUES
('PL01','2023-12-01',10000,120,0.05),
('PL01','2024-07-01',11500, 80,0.03);


INSERT INTO ProjectPlantMap VALUES
('PR01','PL01'),
('PR02','PL02');

PRINT 'Data inserted.';
GO



-- ANALYTICAL QUERIES



--Q1: Budget vs Spend + Budget Variance per project

SELECT
    p.ProjectID,
    p.ProjectName,
    p.BudgetAmount,
    ISNULL(SUM(c.Amount),0)                                   AS TotalSpend,
    p.BudgetAmount - ISNULL(SUM(c.Amount),0)                  AS BudgetVariance,
    ROUND(ISNULL(SUM(c.Amount),0)*100.0/p.BudgetAmount,1)     AS PctBudgetUsed,
    CASE
        WHEN ISNULL(SUM(c.Amount),0) > p.BudgetAmount          THEN 'RED'
        WHEN ISNULL(SUM(c.Amount),0)*100.0/p.BudgetAmount > 80 THEN 'AMBER'
        ELSE 'GREEN'
    END                                                        AS RAGStatus
FROM Projects p
LEFT JOIN CapexPostings c ON c.ProjectID = p.ProjectID
GROUP BY p.ProjectID, p.ProjectName, p.BudgetAmount;


-- Q2: Capitalisation Rate per project 

SELECT
    ProjectID,
    SUM(Amount)                                                AS TotalSpend,
    SUM(CASE WHEN CapitalizeFlag='Yes' THEN Amount ELSE 0 END) AS Capitalised,
    SUM(CASE WHEN CapitalizeFlag='No'  THEN Amount ELSE 0 END) AS Expensed,
    ROUND(
        SUM(CASE WHEN CapitalizeFlag='Yes' THEN Amount ELSE 0 END)*100.0
        / NULLIF(SUM(Amount),0), 1)                           AS CapRate_Pct
FROM CapexPostings
GROUP BY ProjectID;


-- Q3: Spend by Nature of Cost + Vendor

SELECT
    c.ProjectID,
    c.NatureOfCost,
    c.Vendor,
    c.CapitalizeFlag,
    SUM(c.Amount)                                              AS Amount,
    ROUND(SUM(c.Amount)*100.0/SUM(SUM(c.Amount))
          OVER (PARTITION BY c.ProjectID),1)                  AS PctOfProject
FROM CapexPostings c
GROUP BY c.ProjectID, c.NatureOfCost, c.Vendor, c.CapitalizeFlag
ORDER BY c.ProjectID, Amount DESC;


-- Q4: Milestone schedule slippage (days)

SELECT
    ProjectID,
    MilestoneName,
    PlannedDate,
    ActualDate,
    Status,
    DATEDIFF(DAY, PlannedDate, ActualDate)                    AS SlippageDays,
    CASE
        WHEN ActualDate > PlannedDate THEN 'DELAYED'
        WHEN ActualDate IS NULL       THEN 'PENDING'
        ELSE 'ON TIME'
    END                                                        AS SlippageFlag
FROM Milestones
ORDER BY ProjectID, PlannedDate;


-- Q5: Average & max schedule variance per project 
SELECT
    ProjectID,
    COUNT(*)                                                   AS TotalMilestones,
    SUM(CASE WHEN ActualDate > PlannedDate THEN 1 ELSE 0 END) AS Delayed,
    AVG(DATEDIFF(DAY, PlannedDate, ActualDate))                AS AvgSlippageDays,
    MAX(DATEDIFF(DAY, PlannedDate, ActualDate))                AS MaxSlippageDays
FROM Milestones
WHERE ActualDate IS NOT NULL
GROUP BY ProjectID;


--Q6: Pre vs Post GoLive OpsKPI comparison

SELECT
    ppm.ProjectID,
    k.PlantID,
    p.PlannedGoLiveDate,

    AVG(CASE WHEN k.MonthStartDate <  p.PlannedGoLiveDate THEN k.UnitsProduced END) AS Units_Pre,
    AVG(CASE WHEN k.MonthStartDate >= p.PlannedGoLiveDate THEN k.UnitsProduced END) AS Units_Post,

    AVG(CASE WHEN k.MonthStartDate <  p.PlannedGoLiveDate THEN k.DowntimeHours END) AS Downtime_Pre,
    AVG(CASE WHEN k.MonthStartDate >= p.PlannedGoLiveDate THEN k.DowntimeHours END) AS Downtime_Post,

    AVG(CASE WHEN k.MonthStartDate <  p.PlannedGoLiveDate THEN k.ScrapRate END)     AS Scrap_Pre,
    AVG(CASE WHEN k.MonthStartDate >= p.PlannedGoLiveDate THEN k.ScrapRate END)     AS Scrap_Post

FROM ProjectPlantMap ppm
JOIN Projects p ON p.ProjectID = ppm.ProjectID
JOIN OpsKPI   k ON k.PlantID   = ppm.PlantID
GROUP BY ppm.ProjectID, k.PlantID, p.PlannedGoLiveDate;


--Q7: OpsKPI deltas (benefit realisation proxy)
WITH Pre AS (
    SELECT k.PlantID,
           AVG(k.UnitsProduced) AS Units,
           AVG(k.DowntimeHours) AS Downtime,
           AVG(k.ScrapRate)     AS Scrap
    FROM OpsKPI k
    JOIN ProjectPlantMap ppm ON ppm.PlantID = k.PlantID
    JOIN Projects        p   ON p.ProjectID = ppm.ProjectID
    WHERE k.MonthStartDate < p.PlannedGoLiveDate
    GROUP BY k.PlantID
),
Post AS (
    SELECT k.PlantID,
           AVG(k.UnitsProduced) AS Units,
           AVG(k.DowntimeHours) AS Downtime,
           AVG(k.ScrapRate)     AS Scrap
    FROM OpsKPI k
    JOIN ProjectPlantMap ppm ON ppm.PlantID = k.PlantID
    JOIN Projects        p   ON p.ProjectID = ppm.ProjectID
    WHERE k.MonthStartDate >= p.PlannedGoLiveDate
    GROUP BY k.PlantID
)
SELECT
    Pre.PlantID,
    Post.Units    - Pre.Units                                 AS Units_Delta,
    Post.Downtime - Pre.Downtime                              AS Downtime_Delta,
    Post.Scrap    - Pre.Scrap                                 AS Scrap_Delta,
    ROUND((Post.Units-Pre.Units)*100.0/NULLIF(Pre.Units,0),1) AS Units_Pct_Change
FROM Pre
JOIN Post ON Pre.PlantID = Post.PlantID;


-- Q8: Full portfolio health summary (single view)
SELECT
    p.ProjectID,
    p.ProjectName,
    p.Sponsor,
    p.BudgetAmount,
    ISNULL(SUM(c.Amount),0)                                    AS TotalSpend,
    p.BudgetAmount - ISNULL(SUM(c.Amount),0)                   AS BudgetRemaining,
    ROUND(ISNULL(SUM(c.Amount),0)*100.0/p.BudgetAmount,1)      AS PctUsed,
    ROUND(SUM(CASE WHEN c.CapitalizeFlag='Yes'
                   THEN c.Amount ELSE 0 END)*100.0
          / NULLIF(SUM(c.Amount),0),1)                         AS CapRate_Pct,
    MAX(m.SlippageDays)                                        AS MaxSlippageDays,
    p.ExpectedAnnualBenefit,
    p.BenefitType
FROM Projects p
LEFT JOIN CapexPostings c ON c.ProjectID = p.ProjectID
LEFT JOIN (
    SELECT ProjectID,
           MAX(DATEDIFF(DAY,PlannedDate,ISNULL(ActualDate,PlannedDate))) AS SlippageDays
    FROM Milestones
    GROUP BY ProjectID
) m ON m.ProjectID = p.ProjectID
GROUP BY p.ProjectID, p.ProjectName, p.Sponsor,
         p.BudgetAmount, p.ExpectedAnnualBenefit, p.BenefitType;


-- Q9: Cumulative monthly spend trend
SELECT
    c.ProjectID,
    FORMAT(c.PostingDate,'MMM-yy')                            AS Month,
    SUM(c.Amount)                                              AS MonthlySpend,
    SUM(SUM(c.Amount)) OVER (
        PARTITION BY c.ProjectID
        ORDER BY MIN(c.PostingDate)
        ROWS UNBOUNDED PRECEDING)                             AS CumulativeSpend,
    p.BudgetAmount,
    ROUND(SUM(SUM(c.Amount)) OVER (
        PARTITION BY c.ProjectID
        ORDER BY MIN(c.PostingDate)
        ROWS UNBOUNDED PRECEDING)*100.0/p.BudgetAmount,1)    AS CumPctUsed
FROM CapexPostings c
JOIN Projects p ON p.ProjectID = c.ProjectID
GROUP BY c.ProjectID, FORMAT(c.PostingDate,'MMM-yy'), p.BudgetAmount
ORDER BY c.ProjectID, MIN(c.PostingDate);


PRINT 'All queries executed successfully.';
GO