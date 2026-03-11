This notebook tracks and compares schema changes across managed tables in Microsoft Fabric OneLake. It helps data engineers and platform teams detect and audit structural drift—such as added or removed columns, data type changes, and nullability shifts—between snapshots over time.

## 🚀 Purpose

Schema drift can introduce silent failures, break downstream pipelines, or corrupt analytics. This notebook provides a lightweight, automated way to:

- Capture schema snapshots with versioned timestamps
- Compare the latest schema against the previous version
- Identify changes in columns, data types, and nullability
- Log and summarize drift events for audit and remediation

## 📦 Features

- ✅ Supports manual or dynamic table selection
- 🕒 Timestamped versioning for historical tracking
- 🔍 Full outer join comparison to detect drift
- 📁 Persists snapshots and drift logs to Lakehouse tables
- 📊 Summarizes drift by table and change type

## 📌 How It Works

1. **Setup & Configuration**  
   Define the list of tables to monitor. Optionally, pull all managed tables dynamically.

2. **Snapshot Capture**  
   For each table, extract schema metadata including:
   - Table name
   - Column name
   - Data type
   - Nullability  
   The snapshot is tagged with a version string and timestamp.

3. **Snapshot Storage**  
   Schema snapshots are appended to a Lakehouse table:  
   `lakehouse_schema_snapshots`

4. **Version Comparison**  
   The notebook identifies the two most recent snapshot versions and compares them.

5. **Drift Detection**  
   A full outer join highlights:
   - Added columns
   - Removed columns
   - Data type changes
   - Nullability changes  
   Results are saved to:  
   `lakehouse_schema_drift_log`

6. **Drift Summary**  
   A grouped summary shows the count of changes per table and change type.

## 📂 Output Tables

| Table Name                     | Description                              |
|-------------------------------|------------------------------------------|
| `lakehouse_schema_snapshots`  | Historical schema snapshots               |
| `lakehouse_schema_drift_log`  | Detailed drift comparison between versions |

## 🛠️ Extensibility

This notebook can be extended to:
- Track string length changes for `StringType` columns
- Integrate declared types from SQL endpoints (e.g., `nvarchar(20)`)
- Trigger alerts or notifications on critical drift
- Visualize drift trends over time

## 🧠 Requirements

- Microsoft Fabric OneLake environment
- PySpark runtime
- Lakehouse tables enabled for schema tracking
<img width="922" height="1683" alt="image" src="https://github.com/user-attachments/assets/361ccbb5-9d7a-4470-89a3-016dfa1ea162" />
