param(
  [ValidateSet('create','start','stop','status','verify')][string]$Action = 'status',
  [string]$PostgresBin = 'C:\laragon\bin\postgresql\postgresql-14.5-1\bin'
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LocalRoot = Join-Path $ProjectRoot '.local'
$DataPath = Join-Path $LocalRoot 'postgres'
$PasswordFile = Join-Path $LocalRoot 'postgres-password.local'
$PortNumber = 55432
$DatabaseName = 'juniormark'
$ControlExe = Join-Path $PostgresBin 'pg_ctl.exe'
if (-not (Test-Path -LiteralPath $ControlExe)) { throw 'PostgreSQL binaries not found. Pass -PostgresBin with the installed bin folder.' }

function Start-Database {
  & $ControlExe status -D $DataPath *> $null
  if ($LASTEXITCODE -eq 0) { return }
  # Chỉ đợi pg_ctl kết thúc; -Wait của Start-Process còn đợi cả server con chạy dài hạn.
  $ServerProcess = Start-Process -FilePath $ControlExe -ArgumentList @('start','-D', ('"'+$DataPath+'"'),'-l',('"'+(Join-Path $LocalRoot 'postgres.log')+'"'),'-w') -WindowStyle Hidden -PassThru
  $ServerProcess.WaitForExit()
  if ($ServerProcess.ExitCode -ne 0) { throw 'Could not start PostgreSQL. Check .local/postgres.log.' }
}
if ($Action -eq 'status') { & $ControlExe status -D $DataPath; exit $LASTEXITCODE }
if ($Action -eq 'stop') { & $ControlExe stop -D $DataPath -m fast -w; exit $LASTEXITCODE }
if ($Action -eq 'start') { Start-Database; Write-Output 'PostgreSQL ready: 127.0.0.1:55432 / juniormark'; exit 0 }

New-Item -ItemType Directory -Path $LocalRoot -Force | Out-Null
if ($Action -eq 'verify' -and -not (Test-Path -LiteralPath (Join-Path $DataPath 'PG_VERSION'))) { throw 'Create the local database first.' }
if (-not (Test-Path -LiteralPath (Join-Path $DataPath 'PG_VERSION'))) {
  if (Test-Path -LiteralPath $DataPath) { throw 'Data directory exists without PG_VERSION. Inspect it manually; no files were removed.' }
  $RandomBytes = New-Object byte[] 32
  $RandomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $RandomGenerator.GetBytes($RandomBytes)
  $RandomGenerator.Dispose()
  [System.IO.File]::WriteAllText($PasswordFile, [Convert]::ToBase64String($RandomBytes))
  & (Join-Path $PostgresBin 'initdb.exe') -D $DataPath -U postgres -A scram-sha-256 --pwfile=$PasswordFile --encoding=UTF8 --locale=C
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed.' }
  Add-Content -LiteralPath (Join-Path $DataPath 'postgresql.conf') -Value "`nlisten_addresses = '127.0.0.1'`nport = $PortNumber`ntimezone = 'Asia/Ho_Chi_Minh'"
}
Start-Database
if (-not (Test-Path -LiteralPath $PasswordFile)) { throw 'Local password file missing; no credential was reset.' }
$PreviousPassword = $env:PGPASSWORD
$env:PGPASSWORD = [System.IO.File]::ReadAllText($PasswordFile).Trim()
$PsqlExe = Join-Path $PostgresBin 'psql.exe'
$ConnectionArgs = @('-X','-h','127.0.0.1','-p',"$PortNumber",'-U','postgres','-v','ON_ERROR_STOP=1')
try {
  if ($Action -eq 'verify') {
    & $PsqlExe @ConnectionArgs -d $DatabaseName -c "select current_database() as database_name,version()" -c "select count(*) as public_tables from information_schema.tables where table_schema='public' and table_type='BASE TABLE'" -c 'set role anon' -c "select jsonb_array_length(public.get_catalog()->'artists') as artists, jsonb_array_length(public.get_catalog()->'media_items') as photos, jsonb_array_length(public.get_catalog()->'jummo_fortunes') as fortunes" -c 'reset role'
    if ($LASTEXITCODE -ne 0) { throw 'Verification failed.' }
    & $PsqlExe @ConnectionArgs -d $DatabaseName -tA -o (Join-Path $ProjectRoot 'docs/database-schema.json') -c "select jsonb_agg(jsonb_build_object('schema',table_schema,'table',table_name,'column',column_name,'type',coalesce(domain_name,udt_name),'nullable',is_nullable,'default',column_default) order by table_schema,table_name,ordinal_position) from information_schema.columns where table_schema in ('public','private');"
    if ($LASTEXITCODE -ne 0) { throw 'Schema export failed.' }
    exit 0
  }
  $ExistingDatabase = & $PsqlExe @ConnectionArgs -d postgres -tAc "select 1 from pg_database where datname='juniormark'"
  if ($LASTEXITCODE -ne 0) { throw 'Cannot connect to local PostgreSQL.' }
  if ($ExistingDatabase -eq '1') { Write-Output 'Database juniormark already exists; no migrations or data were overwritten.'; exit 0 }
  & $PsqlExe @ConnectionArgs -d postgres -c 'create database juniormark'
  if ($LASTEXITCODE -ne 0) { throw 'CREATE DATABASE failed.' }
  & $PsqlExe @ConnectionArgs -d $DatabaseName -f (Join-Path $ProjectRoot 'database/local-bootstrap.sql')
  if ($LASTEXITCODE -ne 0) { throw 'Local compatibility setup failed.' }
  $MigrationFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'database/migrations') -Filter '0*.sql' | Sort-Object Name
  foreach ($MigrationFile in $MigrationFiles) {
    & $PsqlExe @ConnectionArgs -d $DatabaseName -f $MigrationFile.FullName
    if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($MigrationFile.Name). Inspect before retrying; database is preserved." }
  }
  & $PsqlExe @ConnectionArgs -d $DatabaseName -f (Join-Path $ProjectRoot 'database/seed/catalog.sql')
  if ($LASTEXITCODE -ne 0) { throw 'Seed failed.' }
  Write-Output 'Created PostgreSQL database: juniormark at 127.0.0.1:55432. Password: .local/postgres-password.local (not committed).'
} finally { $env:PGPASSWORD = $PreviousPassword }
