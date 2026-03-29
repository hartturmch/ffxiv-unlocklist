param(
    [string]$SourceUrl = 'https://ffxiv.consolegameswiki.com/wiki/Content_Unlock',
    [string]$JsonTarget = 'data/content-unlock.json',
    [string]$TempHtmlPath = '.tmp-content-unlock.html'
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

    foreach ($item in $Items) {
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

function Join-StringParts {
    param(
        [string[]]$Parts,
        [ValidateSet('space', 'slash', 'semi')]
        [string]$Mode = 'space'
    )

    $parts = @($Parts | Where-Object { $_ })
    if ($Mode -eq 'slash') {
        return ($parts -join ' / ')
    }

    if ($Mode -eq 'semi') {
        return ($parts -join '; ')
    }

    return ($parts -join ' ')
}

function Get-SegmentHtmlList {
    param($Cell)

    if ($null -eq $Cell) {
        return @()
    }

    $html = [string]$Cell.innerHTML
    $html = $html -replace '(?is)<br\s*/?>', "`n"
    $html = $html -replace '(?is)</li\s*>', "`n"
    $html = $html -replace '(?is)<li[^>]*>', ''
    $html = $html -replace '(?is)</p\s*>', "`n"
    $html = $html -replace '(?is)<p[^>]*>', ''
    $html = $html -replace '(?is)<sup[^>]*>.*?</sup>', ''

    return @($html -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
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

function Convert-TextPartsToSafeHtml {
    param(
        [object[]]$Parts,
        [string]$Separator = ' / '
    )

    $chunks = New-Object System.Collections.Generic.List[string]

    foreach ($part in @($Parts)) {
        if ($null -eq $part -or -not $part.text) {
            continue
        }

        $safeText = [System.Net.WebUtility]::HtmlEncode([string]$part.text)
        if ($part.url) {
            $safeUrl = [System.Net.WebUtility]::HtmlEncode([string]$part.url)
            $chunks.Add("<a href=""$safeUrl"" target=""_blank"" rel=""noopener noreferrer"">$safeText</a>")
        }
        else {
            $chunks.Add($safeText)
        }
    }

    return ($chunks -join $Separator)
}

function Get-SafeCellHtml {
    param($Cell)

    $segments = New-Object System.Collections.Generic.List[string]

    foreach ($segmentHtml in Get-SegmentHtmlList -Cell $Cell) {
        $safeHtml = Convert-HtmlFragmentToSafeHtml -Html $segmentHtml
        if ($safeHtml) {
            $segments.Add($safeHtml)
        }
    }

    return ($segments -join '<br>')
}

function Get-TextParts {
    param($Cell)

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($segmentHtml in Get-SegmentHtmlList -Cell $Cell) {
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

function Normalize-Coordinates {
    param([string]$Coords)

    $nums = @([regex]::Matches($Coords, '\d+(?:\.\d+)?') | ForEach-Object { $_.Value })
    if ($nums.Count -ge 2) {
        return "X:$($nums[0]), Y:$($nums[1])"
    }

    return ((Normalize-Whitespace $Coords) -replace '\s+', ' ').Trim()
}

function Get-LocationParts {
    param($Cell)

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($segmentHtml in Get-SegmentHtmlList -Cell $Cell) {
        $text = Get-PlainTextFromHtml $segmentHtml
        if (-not $text) {
            continue
        }

        $url = Get-FirstHrefFromHtml $segmentHtml
        $place = $text
        $coords = ''
        $display = $text

        $match = [regex]::Match($text, '^(?<place>.+?)\s*\((?<coords>[^)]+)\)$')
        if ($match.Success) {
            $place = $match.Groups['place'].Value.Trim()
            $coords = Normalize-Coordinates $match.Groups['coords'].Value
            $display = "$coords`:$place"
        }

        $items.Add([pscustomobject]@{
            place = $place
            coords = $coords
            display = $display
            url = $url
            key = "$display|$url"
        })
    }

    return @(Get-UniqueItems -Items $items)
}

function Normalize-Type {
    param([string]$Type)

    switch -Regex ($Type) {
        '^Field Operations / ' { return 'Field Operations' }
        '^PvP / ' { return 'PvP' }
        '^Materia / Crafting$' { return 'Crafting' }
        '^Variant Dungeon / ' { return 'Variant Dungeon' }
        default { return $Type }
    }
}

function Normalize-Info {
    param([string]$Info)

    return ((Normalize-Whitespace $Info) -replace '\s+', ' ').Trim()
}

function Is-InstructionText {
    param([string]$Text)

    if (-not $Text) {
        return $false
    }

    return $Text -match '^(You need|Requires|Required|Available after|After reaching|After clearing|Must have)'
}

function Get-NextTable {
    param($Heading)

    $node = $Heading.parentElement.nextSibling
    while ($node -and $node.tagName -ne 'TABLE') {
        $node = $node.nextSibling
    }

    return $node
}

function Get-PrimaryValue {
    param([string]$Unlock, [string]$Quest)

    if ($Quest -and $Quest -ne '-' -and $Quest -ne $Unlock) {
        return $Quest
    }

    return $Unlock
}

function Get-SecondaryUnlock {
    param([string]$Unlock, [string]$Quest)

    if ($Quest -and $Quest -ne '-' -and $Quest -ne $Unlock) {
        return $Unlock
    }

    return ''
}

function New-TextPart {
    param(
        [string]$Text,
        [string]$Href
    )

    return [pscustomobject]@{
        text = $Text
        url = Convert-WikiHref $Href
    }
}

function New-LocationPart {
    param(
        [string]$Place,
        [string]$Coords,
        [string]$Href
    )

    return [pscustomobject]@{
        place = $Place
        coords = $Coords
        display = "$Coords`:$Place"
        url = Convert-WikiHref $Href
    }
}

function Apply-ManualEnhancements {
    param([object[]]$Items)

    $enhancedItems = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Items)) {
        $enhancedItems.Add($item)
    }

    $goldSaucer = $null
    foreach ($candidate in $enhancedItems) {
        if ($candidate.unlock -eq 'The Gold Saucer' -and $candidate.quest -eq 'It Could Happen to You') {
            $goldSaucer = $candidate
            break
        }
    }

    if ($goldSaucer) {
        $goldSaucer.location = "X:9.6, Y:9.0:Ul'dah - Steps of Nald"
        $goldSaucer.location_parts = @(
            New-LocationPart -Place "Ul'dah - Steps of Nald" -Coords 'X:9.6, Y:9.0' -Href "/wiki/Ul%27dah_-_Steps_of_Nald"
        )
        $goldSaucer.information = "Talk to Well-heeled Youth in Ul'dah - Steps of Nald to start It Could Happen to You and unlock the Gold Saucer. If the quest is not available, you likely have not reached the level 15 MSQ step that opens this content yet."
        $goldSaucer.information_html = (
            'Talk to <a href="https://ffxiv.consolegameswiki.com/wiki/Well-heeled_Youth" target="_blank" rel="noopener noreferrer">Well-heeled Youth</a> in ' +
            '<a href="https://ffxiv.consolegameswiki.com/wiki/Ul%27dah_-_Steps_of_Nald" target="_blank" rel="noopener noreferrer">Ul&#39;dah - Steps of Nald</a> ' +
            '(X:9.6, Y:9.0) to start <a href="https://ffxiv.consolegameswiki.com/wiki/It_Could_Happen_to_You" target="_blank" rel="noopener noreferrer">It Could Happen to You</a> and unlock the Gold Saucer.<br>' +
            'If the quest is not available, you likely have not reached the level 15 MSQ step that opens this content yet.<br>' +
            '<a href="https://na.finalfantasyxiv.com/lodestone/playguide/contentsguide/goldsaucer/?utm_source=chatgpt.com" target="_blank" rel="noopener noreferrer">Official Gold Saucer guide</a>'
        )
        $goldSaucer.raw = @($goldSaucer.section, $goldSaucer.ilevel, $goldSaucer.unlock, $goldSaucer.type, $goldSaucer.quest, $goldSaucer.location, $goldSaucer.information) -join ' | '
    }

    $jumboEntry = $null
    foreach ($candidate in $enhancedItems) {
        if ($candidate.unlock -eq 'Jumbo Cactpot' -or $candidate.quest -eq 'Hitting the Cactpot') {
            $jumboEntry = $candidate
            break
        }
    }

    if (-not $jumboEntry) {
        $unlockParts = @(
            New-TextPart -Text 'Jumbo Cactpot' -Href '/wiki/Jumbo_Cactpot'
        )
        $questParts = @(
            New-TextPart -Text 'Hitting the Cactpot' -Href '/wiki/Hitting_the_Cactpot'
        )
        $locationParts = @(
            New-LocationPart -Place 'The Gold Saucer' -Coords 'X:8.5, Y:5.9' -Href '/wiki/Gold_Saucer'
        )
        $information = 'Speak with Jumbo Cactpot Broker at the Gold Saucer after unlocking the Gold Saucer. Hitting the Cactpot has no steps; talking to the NPC accepts and completes the quasi-quest immediately, unlocking Jumbo Cactpot on the spot.'
        $informationHtml = (
            'Speak with <a href="https://ffxiv.consolegameswiki.com/wiki/Jumbo_Cactpot_Broker" target="_blank" rel="noopener noreferrer">Jumbo Cactpot Broker</a> at ' +
            '<a href="https://ffxiv.consolegameswiki.com/wiki/Gold_Saucer" target="_blank" rel="noopener noreferrer">The Gold Saucer</a> (X:8.5, Y:5.9) after unlocking the Gold Saucer.<br>' +
            '<a href="https://ffxiv.consolegameswiki.com/wiki/Hitting_the_Cactpot?utm_source=chatgpt.com" target="_blank" rel="noopener noreferrer">Hitting the Cactpot</a> has no steps; talking to the NPC accepts and completes the quasi-quest immediately, unlocking Jumbo Cactpot on the spot.<br>' +
            'Prerequisite: complete <a href="https://ffxiv.consolegameswiki.com/wiki/It_Could_Happen_to_You" target="_blank" rel="noopener noreferrer">It Could Happen to You</a> first.<br>' +
            '<a href="https://na.finalfantasyxiv.com/lodestone/playguide/contentsguide/goldsaucer/cactpot/?utm_source=chatgpt.com" target="_blank" rel="noopener noreferrer">Official Cactpot guide</a>'
        )

        $enhancedItems.Add([pscustomobject]@{
            section = 'Level 1 - 50'
            ilevel = '15'
            unlock = 'Jumbo Cactpot'
            unlock_parts = @($unlockParts)
            type = 'Game Extra'
            quest = 'Hitting the Cactpot'
            quest_parts = @($questParts)
            location = 'X:8.5, Y:5.9:The Gold Saucer'
            location_parts = @($locationParts)
            information = $information
            information_html = $informationHtml
            raw = @('Level 1 - 50', '15', 'Jumbo Cactpot', 'Game Extra', 'Hitting the Cactpot', 'X:8.5, Y:5.9:The Gold Saucer', $information) -join ' | '
            id = 'Level 1 - 50|15|Jumbo Cactpot|Hitting the Cactpot'
            primary = 'Hitting the Cactpot'
            secondary_unlock = 'Jumbo Cactpot'
        })
    }

    return $enhancedItems
}

function Build-DataSet {
    param([string]$HtmlContent)

    $document = New-Object -ComObject 'HTMLFile'
    $document.IHTMLDocument2_write($HtmlContent)

    $contentRoot = $document.getElementById('mw-content-text')
    if (-not $contentRoot) {
        throw 'Unable to find #mw-content-text in the downloaded wiki page.'
    }

    $headings = @($contentRoot.getElementsByTagName('h2')) | Where-Object { $_.innerText -match '^Level' }
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($heading in $headings) {
        $section = (Normalize-Whitespace $heading.innerText).Trim()
        $table = Get-NextTable -Heading $heading
        if (-not $table) {
            continue
        }

        $rows = @($table.rows)
        for ($i = 1; $i -lt $rows.Length; $i++) {
            $cells = @($rows[$i].cells)
            if ($cells.Length -lt 6) {
                continue
            }

            $ilevel = Get-PlainTextFromHtml ([string]$cells[0].innerHTML)
            $unlockParts = Get-TextParts $cells[1]
            $questParts = Get-TextParts $cells[3]
            $locationParts = Get-LocationParts $cells[4]
            $type = Normalize-Type (Join-StringParts -Parts ($cells[2].innerText -split "`n" | ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_ }) -Mode 'slash')
            $unlock = Join-StringParts -Parts ($unlockParts | ForEach-Object { $_.text }) -Mode 'slash'
            $quest = Join-StringParts -Parts ($questParts | ForEach-Object { $_.text }) -Mode 'slash'
            $location = Join-StringParts -Parts ($locationParts | ForEach-Object { $_.display }) -Mode 'semi'
            $information = Normalize-Info (Get-PlainTextFromHtml ([string]$cells[5].innerHTML))
            $informationHtml = Get-SafeCellHtml $cells[5]

            if (Is-InstructionText $quest) {
                $information = Join-StringParts -Parts @($quest, $information) -Mode 'space'
                $questHtml = Convert-TextPartsToSafeHtml -Parts $questParts
                $informationHtml = (@($questHtml, $informationHtml) | Where-Object { $_ }) -join ' '
                $quest = ''
                $questParts = @()
            }

            $primary = Get-PrimaryValue -Unlock $unlock -Quest $quest
            $secondaryUnlock = Get-SecondaryUnlock -Unlock $unlock -Quest $quest
            $raw = @($section, $ilevel, $unlock, $type, $quest, $location, $information) -join ' | '
            $id = @($section, $ilevel, $unlock, $quest) -join '|'

            $items.Add([pscustomobject]@{
                section = $section
                ilevel = $ilevel
                unlock = $unlock
                unlock_parts = @($unlockParts | ForEach-Object { [pscustomobject]@{ text = $_.text; url = $_.url } })
                type = $type
                quest = $quest
                quest_parts = @($questParts | ForEach-Object { [pscustomobject]@{ text = $_.text; url = $_.url } })
                location = $location
                location_parts = @($locationParts | ForEach-Object { [pscustomobject]@{ place = $_.place; coords = $_.coords; display = $_.display; url = $_.url } })
                information = $information
                information_html = $informationHtml
                raw = $raw
                id = $id
                primary = $primary
                secondary_unlock = $secondaryUnlock
            })
        }
    }

    return $items
}

Write-Host "Downloading latest Content Unlock page from $SourceUrl"
Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl | Select-Object -ExpandProperty Content | Set-Content -Path $TempHtmlPath -Encoding UTF8

$htmlContent = Get-Content -Raw -Path $TempHtmlPath
$items = Build-DataSet -HtmlContent $htmlContent
$items = Apply-ManualEnhancements -Items $items
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

$items | Group-Object section | Sort-Object Name | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Name, $_.Count) }
Write-Host ("Total entries: {0}" -f $items.Count)

