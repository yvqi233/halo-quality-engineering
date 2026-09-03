$ErrorActionPreference = 'Stop'

function Get-JUnitCases {
    param([string]$Path)

    $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { throw "No JUnit XML files found at $Path." }
    $cases = [Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        [xml]$document = Get-Content -Raw -LiteralPath $file.FullName
        foreach ($testcase in @($document.SelectNodes('//testcase'))) {
            $outcomes = @(
                if ($null -ne $testcase.SelectSingleNode('./skipped')) { 'SKIPPED' }
                if ($null -ne $testcase.SelectSingleNode('./failure')) { 'FAILURE' }
                if ($null -ne $testcase.SelectSingleNode('./error')) { 'ERROR' }
            )
            if ($outcomes.Count -gt 1) {
                throw "JUnit testcase '$($testcase.name)' has multiple terminal outcomes."
            }
            [void]$cases.Add([pscustomobject]@{
                name = [string]$testcase.name
                classname = [string]$testcase.classname
                outcome = if ($outcomes.Count -eq 0) { 'PASS' } else { $outcomes[0] }
            })
        }
    }
    return @($cases)
}

function Assert-AllCasesPassed {
    param([object[]]$Cases, [string]$Description)

    $nonPassing = @($Cases | Where-Object { $_.outcome -ne 'PASS' })
    if ($nonPassing.Count -gt 0) {
        $details = @($nonPassing | ForEach-Object { "$($_.classname)::$($_.name)=$($_.outcome)" }) -join ', '
        throw "$Description contains $($nonPassing.Count) non-passing testcase record(s): $details"
    }
}

function Assert-ExactIds {
    param([object[]]$Cases, [string[]]$ExpectedIds, [string]$PrefixPattern, [string]$Description)

    Assert-AllCasesPassed -Cases $Cases -Description $Description
    $actualIds = @($Cases | ForEach-Object {
        $match = [regex]::Match($_.name, "^($PrefixPattern)\s")
        if ($match.Success) { $match.Groups[1].Value }
    })
    $difference = if ($ExpectedIds.Count -eq 0 -and $actualIds.Count -eq 0) {
        @()
    } else {
        @(Compare-Object @($ExpectedIds | Sort-Object) @($actualIds | Sort-Object))
    }
    if ($difference.Count -gt 0 -or $actualIds.Count -ne $ExpectedIds.Count) {
        throw "$Description inventory mismatch. Expected $($ExpectedIds.Count), observed $($actualIds.Count)."
    }
}

function Assert-ExactCaseInventory {
    param([object[]]$Cases, [string[]]$ExpectedIds, [string]$PrefixPattern, [string]$Description)

    Assert-AllCasesPassed -Cases $Cases -Description $Description
    $actualIds = [Collections.Generic.List[string]]::new()
    $unclassified = [Collections.Generic.List[string]]::new()
    foreach ($case in $Cases) {
        $match = [regex]::Match($case.name, "^($PrefixPattern)\s")
        if ($match.Success) {
            [void]$actualIds.Add($match.Groups[1].Value)
        } else {
            [void]$unclassified.Add($case.name)
        }
    }
    $difference = if ($ExpectedIds.Count -eq 0 -and $actualIds.Count -eq 0) {
        @()
    } else {
        @(Compare-Object @($ExpectedIds | Sort-Object) @($actualIds | Sort-Object))
    }
    if ($unclassified.Count -gt 0 -or $difference.Count -gt 0 -or $Cases.Count -ne $ExpectedIds.Count) {
        $unclassifiedText = if ($unclassified.Count -eq 0) { 'none' } else { $unclassified -join ', ' }
        throw "$Description inventory mismatch. Expected $($ExpectedIds.Count) exact records, observed $($Cases.Count); unclassified: $unclassifiedText."
    }
}
