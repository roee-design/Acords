# Downloads Maven artifacts reported missing by Gradle (SSL workaround).
param(
    [string]$RepoRoot = "D:\flutter\packages\flutter_tools\gradle\local-plugin-repo",
    [string]$ProjectDir = "c:\Users\noam1\OneDrive\שולחן העבודה\רועי\Acords",
    [int]$MaxRounds = 80
)

$env:JAVA_HOME = "D:\Program Files\Android\Android Studio\jbr"
$env:Path += ";D:\flutter\bin"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Download-MavenPath {
    param([string]$MavenPath)
    $base = "https://repo.maven.apache.org/maven2/$MavenPath"
    $dest = Join-Path $RepoRoot ($MavenPath -replace '/', '\')
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $name = ($MavenPath -split '/')[-1]
    foreach ($ext in @('pom', 'jar', 'module')) {
        $file = "$name.$ext"
        $out = Join-Path $dest $file
        if (Test-Path $out) { continue }
        $url = "$base/$file"
        try {
            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
            Write-Host "  + $file"
        } catch { }
    }
}

function Download-FromLog {
    param([string]$Log)
    $paths = [regex]::Matches($Log, 'maven2/([^\s''"]+\.(?:pom|jar|module))') |
        ForEach-Object { $_.Groups[1].Value -replace '/[^/]+\.(pom|jar|module)$', '' } |
        Select-Object -Unique
    foreach ($p in $paths) { Download-MavenPath $p }
    $coords = [regex]::Matches($Log, 'Could not resolve ([^:]+):([^:]+):([^\s]+)') |
        ForEach-Object {
            $g = $_.Groups[1].Value -replace '\.', '/'
            "$g/$($_.Groups[2].Value)/$($_.Groups[3].Value)"
        } | Select-Object -Unique
    foreach ($c in $coords) { Download-MavenPath $c }
}

for ($i = 1; $i -le $MaxRounds; $i++) {
    Write-Host "`n=== Round $i ==="
    Push-Location $ProjectDir
    $log = & flutter build apk --debug 2>&1 | Out-String
    Pop-Location
    if ($log -match 'Built build\\app\\outputs' -or (Test-Path (Join-Path $ProjectDir 'build\app\outputs\flutter-apk\app-debug.apk'))) {
        Write-Host "APK built successfully."
        exit 0
    }
    if ($log -notmatch 'Could not resolve|Could not get resource|PKIX|SSL') {
        Write-Host $log
        exit 1
    }
    Download-FromLog $log
    Copy-Item -Recurse -Force $RepoRoot (Join-Path $ProjectDir 'android\local-plugin-repo')
}

Write-Host "Max rounds reached."
exit 1
