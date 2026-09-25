# Chỉ thêm dữ liệu chưa tồn tại; không ghi đè nội dung đã sửa trong PostgreSQL.
$ErrorActionPreference = 'Stop'
$BackendRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$OldPassword = $env:PGPASSWORD
try {
 $env:PGPASSWORD = [IO.File]::ReadAllText((Join-Path $BackendRoot '.local/postgres-password.local')).Trim()
 & 'C:\laragon\bin\postgresql\postgresql-14.5-1\bin\psql.exe' -X -h 127.0.0.1 -p 55432 -U postgres -d juniormark -v ON_ERROR_STOP=1 -f (Join-Path $BackendRoot 'database/seed/catalog.sql')
 if ($LASTEXITCODE -ne 0) { throw 'Import failed; inspect database before retrying.' }
} finally { $env:PGPASSWORD = $OldPassword }
