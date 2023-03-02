USE msdb;
GO

BEGIN TRANSACTION;

-- Set the variables for the audit log location and the destination path.
DECLARE @auditLogLocation NVARCHAR(500) = N'C:\AuditLogs';
DECLARE @destinationPath NVARCHAR(500) = N'\\RemoteServer\AuditLogs';

-- Get the name of the active audit log file.
DECLARE @activeAuditLogName NVARCHAR(500);
SELECT TOP 1 @activeAuditLogName = audit_file_path
FROM sys.dm_server_audit_status
WHERE audit_file_path IS NOT NULL
ORDER BY audit_start_time DESC;

-- Create a new SQL Server Agent job.
DECLARE @jobId BINARY(16);
EXEC msdb.dbo.sp_add_job
  @job_name = N'Compress and Offload Audit Logs',
  @enabled = 1,
  @description = N'Compress and offload audit logs to remote server',
  @job_id = @jobId OUTPUT;

-- Add a job step to compress the audit logs.
EXEC msdb.dbo.sp_add_jobstep
  @job_id = @jobId,
  @step_name = N'Compress Logs',
  @subsystem = N'CmdExec',
  @command = N'powershell.exe Compress-Archive -Path "' + @auditLogLocation + '\*" -DestinationPath "' + @auditLogLocation + '\Archive.zip" -Exclude "' + @activeAuditLogName + '"',
  @on_success_action = 1,
  @retry_attempts = 0,
  @retry_interval = 0;

-- Add a job step to offload the compressed audit logs.
EXEC msdb.dbo.sp_add_jobstep
  @job_id = @jobId,
  @step_name = N'Offload Logs',
  @subsystem = N'CmdExec',
  @command = N'powershell.exe Copy-Item -Path "' + @auditLogLocation + '\Archive.zip" -Destination "' + @destinationPath + '"',
  @on_success_action = 1,
  @retry_attempts = 0,
  @retry_interval = 0;

-- Create a new schedule to run the job daily.
EXEC msdb.dbo.sp_add_schedule
  @schedule_name = N'Daily',
  @enabled = 1,
  @freq_type = 4,
  @freq_interval = 1,
  @freq_subday_type = 1,
  @freq_subday_interval = 0,
  @freq_relative_interval = 0,
  @freq_recurrence_factor = 1,
  @active_start_date = 20220301,
  @active_end_date = 99991231,
  @active_start_time = 010000,
  @active_end_time = 235959;

-- Attach the new schedule to the job.
EXEC msdb.dbo.sp_attach_schedule
  @job_id = @jobId,
  @schedule_name = N'Daily';

-- Assign the job to the local SQL Server Agent.
EXEC msdb.dbo.sp_add_jobserver
  @job_id = @jobId,
  @server_name = N'(local)';

COMMIT TRANSACTION;
