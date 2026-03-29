param(
    [string]$SourceUrl = 'https://ffxiv.consolegameswiki.com/wiki/Aether_Currents',
    [string]$JsonTarget = 'data/aether-currents.json',
    [string]$TempHtmlPath = '.tmp-aether-currents.html'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WikiBaseUrl = 'https://ffxiv.consolegameswiki.com'

function Normalize-Whitespace {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $Text = $Text -replace '&nbsp;', ' '
    $Text = $Text -replace [char]0xA0, ' '
    $Text = $Text -replace "`r", ''
    return $Text
}

function Convert-WikiHref {
    param([string]$Href)

    if (-not $Href) {
        return ''
    }

    if ($Href -match '^https?://') {
        return $Href
    }

    return "$WikiBaseUrl$Href"
}

function Get-UniqueItems {
    param([object[]]$Items, [string]$KeyProperty = 'key')

    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $result = New-Object System.Collections.Generic.List[object]

    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        $key = [string]$item.$KeyProperty
        if (-not $key) {
            continue
        }

        if ($seen.Add($key)) {
            $result.Add($item)
        }
    }

    return $result
}

function Get-PlainTextFromHtml {
    param([string]$Html)

    $withoutTags = $Html -replace '(?is)<[^>]+>', ''
    $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
    return ((Normalize-Whitespace $decoded) -replace '\s+', ' ').Trim()
}

function Get-NormalizedTextFragment {
    param(
        [string]$Html,
        [bool]$Trim = $true
    )

    $withoutTags = $Html -replace '(?is)<[^>]+>', ''
    $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
    $normalized = (Normalize-Whitespace $decoded) -replace '\s+', ' '
    if ($Trim) {
        return $normalized.Trim()
    }

    return $normalized
}

function Get-FirstHrefFromHtml {
    param([string]$Html)

    $match = [regex]::Match($Html, '(?is)<a\b[^>]*href="([^"]+)"[^>]*>')
    if (-not $match.Success) {
        return ''
    }

    return Convert-WikiHref $match.Groups[1].Value
}

function Convert-HtmlFragmentToSafeHtml {
    param([string]$Html)

    $builder = New-Object System.Text.StringBuilder
    $pattern = '(?is)<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>'
    $matches = [regex]::Matches($Html, $pattern)
    $cursor = 0

    foreach ($match in $matches) {
        $before = $Html.Substring($cursor, $match.Index - $cursor)
        $beforeText = Get-NormalizedTextFragment -Html $before -Trim:$false
        if ($beforeText) {
            [void]$builder.Append([System.Net.WebUtility]::HtmlEncode($beforeText))
        }

        $url = Convert-WikiHref $match.Groups[1].Value
        $text = Get-NormalizedTextFragment -Html $match.Groups[2].Value
        if ($text) {
            $safeUrl = [System.Net.WebUtility]::HtmlEncode($url)
            $safeText = [System.Net.WebUtility]::HtmlEncode($text)
            [void]$builder.Append("<a href=""$safeUrl"" target=""_blank"" rel=""noopener noreferrer"">$safeText</a>")
        }

        $cursor = $match.Index + $match.Length
    }

    $after = $Html.Substring($cursor)
    $afterText = Get-NormalizedTextFragment -Html $after -Trim:$false
    if ($afterText) {
        [void]$builder.Append([System.Net.WebUtility]::HtmlEncode($afterText))
    }

    return $builder.ToString().Trim()
}

function Get-SafeCellHtml {
    param($Cell)

    if ($null -eq $Cell) {
        return ''
    }

    $html = [string]$Cell.innerHTML
    $html = $html -replace '(?is)<br\s*/?>', '<br>'
    $html = $html -replace '(?is)<sup[^>]*>.*?</sup>', ''

    $parts = @($html -split '(?i)<br\s*/?>' | ForEach-Object {
        Convert-HtmlFragmentToSafeHtml -Html $_
    } | Where-Object { $_ })

    return ($parts -join '<br>')
}

function Get-TextParts {
    param($Cell)

    $items = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Cell) {
        return @()
    }

    $html = [string]$Cell.innerHTML
    $html = $html -replace '(?is)<sup[^>]*>.*?</sup>', ''

    foreach ($segmentHtml in @($html -split '(?i)<br\s*/?>')) {
        $text = Get-PlainTextFromHtml $segmentHtml
        if (-not $text) {
            continue
        }

        $url = Get-FirstHrefFromHtml $segmentHtml
        $items.Add([pscustomobject]@{
            text = $text
            url = $url
            key = "$text|$url"
        })
    }

    return @(Get-UniqueItems -Items $items)
}

function Join-TextParts {
    param(
        [object[]]$Parts,
        [string]$Separator = ' / '
    )

    return ((@($Parts | ForEach-Object { $_.text }) | Where-Object { $_ }) -join $Separator)
}

function Normalize-Coordinates {
    param([string]$Text)

    $numbers = @([regex]::Matches($Text, '-?\d+(?:\.\d+)?') | ForEach-Object { $_.Value })
    if ($numbers.Count -ge 2) {
        $parts = @("X:$($numbers[0])", "Y:$($numbers[1])")
        if ($numbers.Count -ge 3) {
            $parts += "Z:$($numbers[2])"
        }

        return ($parts -join ', ')
    }

    return ((Normalize-Whitespace $Text) -replace '\s+', ' ').Trim()
}

function Normalize-LocationCoordinates {
    param([string]$Text)

    $text = ((Normalize-Whitespace $Text) -replace '\s+', ' ').Trim()
    if (-not $text) {
        return ''
    }

    $match = [regex]::Match($text, '^(?<place>.+?)\s*\((?<coords>[^)]+)\)$')
    if ($match.Success) {
        $place = $match.Groups['place'].Value.Trim()
        $coords = Normalize-Coordinates $match.Groups['coords'].Value
        if ($place) {
            return "$place - $coords"
        }

        return $coords
    }

    return Normalize-Coordinates $text
}

function Get-CellTexts {
    param($Row)

    return @($Row.cells | ForEach-Object {
        Get-PlainTextFromHtml ([string]$_.innerHTML)
    })
}

function Parse-FieldTable {
    param(
        $Table,
        [string]$Expansion,
        [string]$Zone,
        [int]$ExpansionOrder,
        [int]$ZoneOrder,
        [ref]$ItemOrder
    )

    $items = New-Object System.Collections.Generic.List[object]
    $rows = @($Table.rows)
    for ($i = 1; $i -lt $rows.Length; $i++) {
        $cells = @($rows[$i].cells)
        if ($cells.Length -lt 2) {
            continue
        }

        $cellTexts = Get-CellTexts -Row $rows[$i]
        $number = ''
        $mapNumber = ''
        if ($cells.Length -ge 3) {
            $number = $cellTexts[2]
        }
        if ($cells.Length -ge 4) {
            $mapNumber = $cellTexts[3]
        }

        $currentNumber = if ($number) { $number } else { [string]$i }
        $primary = "Field Current #$currentNumber"
        $id = "$Expansion|$Zone|Field|$currentNumber"

        $ItemOrder.Value++
        $items.Add([pscustomobject]@{
            id = $id
            expansion = $Expansion
            expansion_order = $ExpansionOrder
            zone = $Zone
            zone_order = $ZoneOrder
            section = $Zone
            item_order = $ItemOrder.Value
            entry_type = 'Field'
            type = 'Field'
            number = $currentNumber
            map_number = $mapNumber
            primary = $primary
            coordinates = Normalize-LocationCoordinates $cellTexts[0]
            description = $cellTexts[1]
            description_html = Get-SafeCellHtml $cells[1]
            quest = ''
            quest_parts = @()
            level = ''
            additional_information = ''
            additional_information_html = ''
        })
    }

    return $items
}

function Parse-QuestTable {
    param(
        $Table,
        [string]$Expansion,
        [string]$Zone,
        [int]$ExpansionOrder,
        [int]$ZoneOrder,
        [ref]$ItemOrder
    )

    $items = New-Object System.Collections.Generic.List[object]
    $rows = @($Table.rows)
    for ($i = 1; $i -lt $rows.Length; $i++) {
        $cells = @($rows[$i].cells)
        if ($cells.Length -lt 4) {
            continue
        }

        $cellTexts = Get-CellTexts -Row $rows[$i]
        $questParts = @(Get-TextParts $cells[0])
        $quest = if ($questParts.Count -gt 0) { Join-TextParts -Parts $questParts } else { $cellTexts[0] }
        $id = "$Expansion|$Zone|Quest|$quest"

        $ItemOrder.Value++
        $items.Add([pscustomobject]@{
            id = $id
            expansion = $Expansion
            expansion_order = $ExpansionOrder
            zone = $Zone
            zone_order = $ZoneOrder
            section = $Zone
            item_order = $ItemOrder.Value
            entry_type = 'Quest'
            type = 'Quest'
            number = ''
            map_number = ''
            primary = $quest
            coordinates = Normalize-LocationCoordinates $cellTexts[2]
            description = ''
            description_html = ''
            quest = $quest
            quest_parts = @($questParts | ForEach-Object { [pscustomobject]@{ text = $_.text; url = $_.url } })
            level = $cellTexts[1]
            additional_information = $cellTexts[3]
            additional_information_html = Get-SafeCellHtml $cells[3]
        })
    }

    return $items
}

function Build-DataSet {
    param([string]$HtmlContent)

    $document = New-Object -ComObject 'HTMLFile'
    $document.IHTMLDocument2_write($HtmlContent)

    $contentRoot = $document.getElementById('mw-content-text')
    if (-not $contentRoot) {
        throw 'Unable to find #mw-content-text in the downloaded wiki page.'
    }

    $allTables = @($contentRoot.getElementsByTagName('table'))
    $expansionHeadings = @($contentRoot.getElementsByTagName('h2')) | Where-Object {
        $_.innerText -match 'Aether Currents$'
    }

    $items = New-Object System.Collections.Generic.List[object]
    $itemOrder = 0

    for ($expansionIndex = 0; $expansionIndex -lt $expansionHeadings.Count; $expansionIndex++) {
        $expansionHeading = $expansionHeadings[$expansionIndex]
        $expansion = ($expansionHeading.innerText -replace ' Aether Currents$', '').Trim()
        $expansionStart = $expansionHeading.sourceIndex
        $nextExpansionStart = if ($expansionIndex + 1 -lt $expansionHeadings.Count) {
            $expansionHeadings[$expansionIndex + 1].sourceIndex
        }
        else {
            [int]::MaxValue
        }

        $zoneHeadings = @($contentRoot.getElementsByTagName('h3')) | Where-Object {
            $_.sourceIndex -gt $expansionStart -and $_.sourceIndex -lt $nextExpansionStart
        }

        for ($zoneIndex = 0; $zoneIndex -lt $zoneHeadings.Count; $zoneIndex++) {
            $zoneHeading = $zoneHeadings[$zoneIndex]
            $zone = ($zoneHeading.innerText -replace '\[edit\]', '').Trim()
            if (-not $zone) {
                continue
            }

            $zoneStart = $zoneHeading.sourceIndex
            $nextZoneStart = if ($zoneIndex + 1 -lt $zoneHeadings.Count) {
                $zoneHeadings[$zoneIndex + 1].sourceIndex
            }
            else {
                $nextExpansionStart
            }

            $zoneTables = @($allTables | Where-Object {
                $_.sourceIndex -gt $zoneStart -and $_.sourceIndex -lt $nextZoneStart
            })

            foreach ($table in $zoneTables) {
                $headerTexts = @($table.rows[0].cells | ForEach-Object {
                    Get-PlainTextFromHtml ([string]$_.innerHTML)
                })
                $headerLine = ($headerTexts -join ' | ')

                if ($headerLine -match '^Coordinates \| Description') {
                    foreach ($item in Parse-FieldTable -Table $table -Expansion $expansion -Zone $zone -ExpansionOrder ($expansionIndex + 1) -ZoneOrder ($zoneIndex + 1) -ItemOrder ([ref]$itemOrder)) {
                        $items.Add($item)
                    }
                }
                elseif ($headerLine -match '^Quest \| Level \| Coordinates \| Additional Information$') {
                    foreach ($item in Parse-QuestTable -Table $table -Expansion $expansion -Zone $zone -ExpansionOrder ($expansionIndex + 1) -ZoneOrder ($zoneIndex + 1) -ItemOrder ([ref]$itemOrder)) {
                        $items.Add($item)
                    }
                }
            }
        }
    }

    return $items
}

Write-Host "Downloading latest Aether Currents page from $SourceUrl"
Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl | Select-Object -ExpandProperty Content | Set-Content -Path $TempHtmlPath -Encoding UTF8

$htmlContent = Get-Content -Raw -Path $TempHtmlPath
$items = Build-DataSet -HtmlContent $htmlContent
$json = $items | ConvertTo-Json -Depth 6 -Compress

$parentDir = Split-Path -Parent $JsonTarget
if ($parentDir -and -not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

Set-Content -Path $JsonTarget -Value $json -Encoding UTF8
Write-Host "Updated $JsonTarget"

if (Test-Path $TempHtmlPath) {
    Remove-Item -Path $TempHtmlPath -Force
}

$items | Group-Object expansion | Sort-Object Name | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Name, $_.Count) }
Write-Host ("Total entries: {0}" -f $items.Count)
