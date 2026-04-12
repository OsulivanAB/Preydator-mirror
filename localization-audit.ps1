param(
	[switch]$Apply,
	[string[]]$Files = @(
		"issues/achievements.md",
		"issues/quest_list.md",
		"issues/questrewards.md",
		"issues/currencies.md"
	)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Sanitize-Lines {
	param(
		[string[]]$Lines
	)

	$result = New-Object System.Collections.Generic.List[string]
	$removedDnt = 0
	$fixedKorean = 0

	foreach ($line in $Lines) {
		if ($line -match "\[DNT\]\s*\[PH\]") {
			$removedDnt++
			continue
		}

		$updated = $line
		$updated = [regex]::Replace($updated, "\tKorian\t", "`tKorean`t")
		$updated = [regex]::Replace($updated, "\tKorian$", "`tKorean")

		if ($updated -ne $line) {
			$fixedKorean++
		}

		$result.Add($updated)
	}

	return [pscustomobject]@{
		Lines       = $result
		RemovedDnt  = $removedDnt
		FixedKorean = $fixedKorean
	}
}

$summaries = New-Object System.Collections.Generic.List[object]

foreach ($relative in $Files) {
	$path = Join-Path $root $relative
	if (-not (Test-Path -LiteralPath $path)) {
		Write-Warning "Skipped missing file: $relative"
		continue
	}

	$original = Get-Content -LiteralPath $path -Encoding UTF8
	$sanitized = Sanitize-Lines -Lines $original
	$newLines = @($sanitized.Lines)

	$changed = ($sanitized.RemovedDnt -gt 0) -or ($sanitized.FixedKorean -gt 0)

	if ($Apply -and $changed) {
		Set-Content -LiteralPath $path -Value $newLines -Encoding UTF8
	}

	$summaries.Add([pscustomobject]@{
		File        = $relative
		RemovedDnt  = $sanitized.RemovedDnt
		FixedKorean = $sanitized.FixedKorean
		Changed     = $changed
	})
}

Write-Host "Localization data sanitizer summary" -ForegroundColor Cyan
foreach ($s in $summaries) {
	$status = if ($s.Changed) { "changes detected" } else { "no changes" }
	Write-Host ("- {0}: removed DNT rows={1}, fixed Korean labels={2} ({3})" -f $s.File, $s.RemovedDnt, $s.FixedKorean, $status)
}

if (-not $Apply) {
	Write-Host "Dry run only. Re-run with -Apply to write changes." -ForegroundColor Yellow
}
