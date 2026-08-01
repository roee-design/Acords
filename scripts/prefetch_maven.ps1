# Prefetch Maven artifacts via PowerShell (uses Windows cert store) into local-plugin-repo.
param(
    [string]$RepoRoot = "$PSScriptRoot\..\android\local-plugin-repo"
)

$extraArtifacts = @(
    "org/jetbrains/kotlin/kotlin-compiler-runner/2.2.20",
    "org/jetbrains/kotlin/kotlin-util-klib-metadata/2.2.20",
    "org/jetbrains/abi-tools-api/2.2.20",
    "org/jetbrains/kotlin/kotlin-stdlib/2.2.0",
    "org/jetbrains/kotlin/kotlin-stdlib/2.2.20",
    "org/jetbrains/kotlin/kotlin-reflect/2.2.20",
    "org/jetbrains/kotlin/kotlin-build-tools-api/2.2.20",
    "org/jetbrains/kotlin/kotlin-build-common/2.2.20",
    "org/jetbrains/kotlin/kotlin-daemon-client/2.2.20",
    "org/jetbrains/kotlin/kotlin-scripting-common/2.2.20",
    "org/jetbrains/kotlin/kotlin-scripting-jvm/2.2.20",
    "org/jetbrains/kotlin/kotlin-scripting-compiler-embeddable/2.2.20",
    "org/jetbrains/kotlin/kotlin-scripting-compiler-impl-embeddable/2.2.20",
    "org/jetbrains/kotlin/kotlin-compiler-embeddable/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugin-idea/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugin-idea-proto/2.2.20",
    "org/jetbrains/kotlin/kotlin-klib-commonizer-api/2.2.20",
    "org/jetbrains/kotlin/kotlin-util-io/2.2.20",
    "org/jetbrains/kotlin/kotlin-util-klib/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugin-model/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugin-annotations/2.2.20",
    "org/jetbrains/kotlin/kotlin-native-utils/2.2.20",
    "org/jetbrains/kotlin/kotlin-tooling-core/2.2.20",
    "org/jetbrains/kotlin/fus-statistics-gradle-plugin/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-ecosystem-plugin/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugin-api/2.2.0",
    "org/jetbrains/kotlin/kotlin-sam-with-receiver/2.2.0",
    "org/jetbrains/kotlin/kotlin-assignment/2.2.0",
    "org/jetbrains/kotlin/kotlin-gradle-plugin-api/2.2.20",
    "org/jetbrains/kotlin/kotlin-sam-with-receiver/2.2.20",
    "org/jetbrains/kotlin/kotlin-assignment/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugins-bom/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugin/2.2.20",
    "org/jetbrains/kotlin/kotlin-gradle-plugin/2.2.0",
    "org/jetbrains/kotlin/kotlin-stdlib-common/2.2.0",
    "org/jetbrains/kotlin/kotlin-stdlib-jdk7/2.2.0",
    "org/jetbrains/kotlin/kotlin-stdlib-jdk8/2.2.0",
    "org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.8.1",
    "org/jetbrains/kotlinx/kotlinx-coroutines-core/1.8.1"
)

function Download-Artifact {
    param([string]$Path)
    $base = "https://repo.maven.apache.org/maven2/$Path"
    foreach ($ext in @("pom", "jar")) {
        $parts = $Path -split '/'
        $file = "$($parts[-1])-$ext" -replace '^([^-]+)-pom$', '$1.pom'
        if ($ext -eq "pom") { $file = "$($parts[-1]).pom" }
        else { $file = "$($parts[-1]).jar" }
        $url = "$base/$file"
        $dest = Join-Path $RepoRoot ($Path -replace '/', '\')
        $destFile = Join-Path $dest $file
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        if (Test-Path $destFile) { continue }
        try {
            Invoke-WebRequest -Uri $url -OutFile $destFile -UseBasicParsing -ErrorAction Stop
            Write-Host "OK $file"
        } catch {
            if ($ext -eq "jar") { Write-Host "skip $url" }
        }
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null
foreach ($path in $extraArtifacts) {
    Download-Artifact $path
}
Copy-Item -Recurse -Force $RepoRoot "D:\flutter\packages\flutter_tools\gradle\local-plugin-repo"
Write-Host "Done. Repo at $RepoRoot"
