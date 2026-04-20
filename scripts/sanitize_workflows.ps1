param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Paths
)

$ErrorActionPreference = "Stop"

function Sanitize-WorkflowHashtable {
  param(
    [hashtable]$Root
  )

  if ($Root.ContainsKey("active")) {
    $Root["active"] = $false
  }

  $null = $Root.Remove("id")
  $null = $Root.Remove("versionId")
  $null = $Root.Remove("meta")

  if ($Root.ContainsKey("settings") -and $Root["settings"] -is [hashtable]) {
    # Это ссылка на другой workflow в конкретной инстанции n8n.
    $null = $Root["settings"].Remove("errorWorkflow")
  }

  if ($Root.ContainsKey("nodes") -and $Root["nodes"] -is [object[]]) {
    foreach ($node in $Root["nodes"]) {
      if ($node -isnot [hashtable]) { continue }

      $null = $node.Remove("id")
      $null = $node.Remove("webhookId")

      if ($node.ContainsKey("credentials") -and $node["credentials"] -is [hashtable]) {
        foreach ($credType in @($node["credentials"].Keys)) {
          $credVal = $node["credentials"][$credType]
          if ($credVal -is [hashtable]) {
            $null = $credVal.Remove("id")
          }
        }
      }
    }
  }
}

function Should-SkipFile {
  param(
    [string]$RelativePath,
    [long]$Length
  )

  if ($Length -eq 0) { return $true }

  # Заглушки: пользователь попросил не трогать "первый шаг".
  switch ($RelativePath.Replace("\\", "/")) {
    "pisec/Pisec_Log_Workflows.json" { return $true }
    "voron/Voron_Check_RSS.json" { return $true }
    "pozdravlyator/Pozdravlyator_Generate_Greeting.json" { return $true }
    default { return $false }
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$files = @()
if ($Paths -and $Paths.Count -gt 0) {
  foreach ($p in $Paths) {
    $files += Get-ChildItem -LiteralPath $p -File
  }
} else {
  $files = Get-ChildItem -Path $repoRoot -Recurse -Filter *.json -File | Where-Object { $_.FullName -notmatch "\\.git\\" }
}

foreach ($file in $files) {
  $rel = $file.FullName.Substring($repoRoot.Length + 1)
  if (Should-SkipFile -RelativePath $rel -Length $file.Length) {
    Write-Host "SKIP  $rel"
    continue
  }

  Write-Host "EDIT  $rel"
  $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
  $obj = $raw | ConvertFrom-Json -AsHashtable -Depth 100
  if ($obj -isnot [hashtable]) {
    throw "Unexpected JSON root type in $rel"
  }

  Sanitize-WorkflowHashtable -Root $obj

  $json = $obj | ConvertTo-Json -Depth 100
  # ConvertTo-Json не гарантирует завершающий перевод строки.
  if (-not $json.EndsWith("`n")) { $json += "`n" }
  Set-Content -LiteralPath $file.FullName -Value $json -Encoding UTF8
}
