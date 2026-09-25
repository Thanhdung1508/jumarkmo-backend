param([ValidateSet('run','test','verify','package')][string]$Task='run')
$ErrorActionPreference='Stop'
$BackendRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $BackendRoot
# IntelliJ dùng JDK 17. Khi chạy terminal, tự tìm JDK 17 đã cài nếu JAVA_HOME chưa có.
if (!$env:JAVA_HOME) {
 $Jdk=Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.jdks') -Directory -ErrorAction SilentlyContinue | Where-Object Name -Like '*17*' | Select-Object -First 1
 if ($Jdk) { $env:JAVA_HOME=$Jdk.FullName }
}
$MavenCommand=Get-Command mvn.cmd -ErrorAction SilentlyContinue
if ($MavenCommand) { $Maven=$MavenCommand.Source } else {
 $Idea=Get-ChildItem -LiteralPath 'C:\Program Files\JetBrains' -Directory -ErrorAction SilentlyContinue | Where-Object Name -Like 'IntelliJ IDEA*' | Sort-Object Name -Descending | Select-Object -First 1
 $Maven=if($Idea){Join-Path $Idea.FullName 'plugins/maven-plugin/lib/maven3/bin/mvn.cmd'}else{''}
}
if (!(Test-Path -LiteralPath $Maven)) { throw 'Install Maven 3.6.3+ or run Maven from IntelliJ.' }
$Arguments=@('-B',('-Dmaven.repo.local='+(Join-Path $BackendRoot '.local/maven-cache')))
if ($Task -eq 'run') { $Arguments+='spring-boot:run' }
elseif ($Task -eq 'verify') { $env:RUN_DATABASE_TESTS='true';$Arguments+='test' }
else { $Arguments+=$Task }
& $Maven @Arguments
exit $LASTEXITCODE
