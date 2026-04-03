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

function Convert-TitleToWikiHref {
    param([string]$Title)

    if (-not $Title) {
        return ''
    }

    $path = $Title -replace ' ', '_'
    $encodedPath = [System.Uri]::EscapeDataString($path) -replace '%2F', '/'
    return "/wiki/$encodedPath"
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

    $alexanderChainEntries = @(
        @{
            quest = 'Steel and Steam'
            unlock = 'Alexander - The Cuff of the Father'
            unlockHref = '/wiki/Alexander_-_The_Cuff_of_the_Father'
            giver = 'Biggs'
            giverHref = '/wiki/Biggs'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21, Y:18'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'Disarmed'
            previousHref = '/wiki/Disarmed'
        },
        @{
            quest = 'Tinker, Seeker, Soldier, Spy'
            unlock = 'Alexander - The Arm of the Father'
            unlockHref = '/wiki/Alexander_-_The_Arm_of_the_Father'
            giver = 'Biggs'
            giverHref = '/wiki/Biggs'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21, Y:18'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'Steel and Steam'
            previousHref = '/wiki/Steel_and_Steam'
        },
        @{
            quest = 'The Pulsing Heart'
            unlock = 'Alexander - The Burden of the Father'
            unlockHref = '/wiki/Alexander_-_The_Burden_of_the_Father'
            giver = 'Mide'
            giverHref = '/wiki/Mide'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21.7, Y:18.8'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'Tinker, Seeker, Soldier, Spy'
            previousHref = '/wiki/Tinker,_Seeker,_Soldier,_Spy'
        },
        @{
            quest = 'Enigma'
            unlock = 'Awake the Metal'
            unlockHref = '/wiki/Awake_the_Metal'
            giver = 'Redbrix'
            giverHref = '/wiki/Redbrix'
            place = 'The Dravanian Hinterlands'
            coords = 'X:23.9, Y:26.5'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'The Pulsing Heart'
            previousHref = '/wiki/The_Pulsing_Heart'
        },
        @{
            quest = 'The Folly of Youth'
            unlock = 'Alexander - The Cuff of the Son'
            unlockHref = '/wiki/Alexander_-_The_Cuff_of_the_Son'
            giver = 'Biggs'
            giverHref = '/wiki/Biggs'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21.7, Y:18.8'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'Rearmed'
            previousHref = '/wiki/Rearmed'
        },
        @{
            quest = 'Toppling the Tyrant'
            unlock = 'Alexander - The Arm of the Son'
            unlockHref = '/wiki/Alexander_-_The_Arm_of_the_Son'
            giver = 'Mide'
            giverHref = '/wiki/Mide'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21.7, Y:18.8'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'The Folly of Youth'
            previousHref = '/wiki/The_Folly_of_Youth'
        },
        @{
            quest = 'One Step Behind'
            unlock = 'Alexander - The Burden of the Son'
            unlockHref = '/wiki/Alexander_-_The_Burden_of_the_Son'
            giver = 'Backrix'
            giverHref = '/wiki/Backrix'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21, Y:18'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'Toppling the Tyrant'
            previousHref = '/wiki/Toppling_the_Tyrant'
        },
        @{
            quest = 'A Gob in the Machine'
            unlock = 'The Midas Touch'
            unlockHref = '/wiki/The_Midas_Touch'
            giver = 'Backrix'
            giverHref = '/wiki/Backrix'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21, Y:18'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'One Step Behind'
            previousHref = '/wiki/One_Step_Behind'
        },
        @{
            quest = "Biggs and Wedge's Excellent Adventure"
            unlock = 'Alexander - The Breath of the Creator'
            unlockHref = '/wiki/Alexander_-_The_Breath_of_the_Creator'
            giver = 'Biggs'
            giverHref = '/wiki/Biggs'
            place = 'The Dravanian Hinterlands'
            coords = 'X:23.5, Y:23.9'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'The Coeurl and the Colossus'
            previousHref = '/wiki/The_Coeurl_and_the_Colossus'
        },
        @{
            quest = 'Thus Spake Quickthinx'
            unlock = 'Alexander - The Heart of the Creator'
            unlockHref = '/wiki/Alexander_-_The_Heart_of_the_Creator'
            giver = 'Biggs'
            giverHref = '/wiki/Biggs'
            place = 'The Dravanian Hinterlands'
            coords = 'X:23.5, Y:23.9'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = "Biggs and Wedge's Excellent Adventure"
            previousHref = "/wiki/Biggs_and_Wedge's_Excellent_Adventure"
        },
        @{
            quest = 'Judgment Day'
            unlock = 'Alexander - The Soul of the Creator'
            unlockHref = '/wiki/Alexander_-_The_Soul_of_the_Creator'
            giver = 'Biggs'
            giverHref = '/wiki/Biggs'
            place = 'The Dravanian Hinterlands'
            coords = 'X:21, Y:18'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'Thus Spake Quickthinx'
            previousHref = '/wiki/Thus_Spake_Quickthinx'
        },
        @{
            quest = 'Of Endings and Beginnings'
            unlock = 'Back in Time'
            unlockHref = '/wiki/Back_in_Time'
            giver = 'Biggs'
            giverHref = '/wiki/Biggs'
            place = 'The Dravanian Hinterlands'
            coords = 'X:17, Y:22'
            placeHref = '/wiki/The_Dravanian_Hinterlands'
            previous = 'Judgment Day'
            previousHref = '/wiki/Judgment_Day'
        }
    )

    foreach ($entry in $alexanderChainEntries) {
        $existingAlexanderEntry = $null
        foreach ($candidate in $enhancedItems) {
            if ($candidate.quest -eq $entry.quest -or $candidate.unlock -eq $entry.unlock) {
                $existingAlexanderEntry = $candidate
                break
            }
        }

        if ($existingAlexanderEntry) {
            continue
        }

        $unlockParts = @(
            New-TextPart -Text $entry.unlock -Href $entry.unlockHref
        )
        $questParts = @(
            New-TextPart -Text $entry.quest -Href ("/wiki/" + (($entry.quest -replace ' ', '_')))
        )
        $locationParts = @(
            New-LocationPart -Place $entry.place -Coords $entry.coords -Href $entry.placeHref
        )

        $information = "Talk to $($entry.giver) in $($entry.place) after $($entry.previous) to continue the Alexander quest line and unlock $($entry.unlock)."
        $informationHtml = (
            'Talk to <a href="' + (Convert-WikiHref $entry.giverHref) + '" target="_blank" rel="noopener noreferrer">' + $entry.giver + '</a> in ' +
            '<a href="' + (Convert-WikiHref $entry.placeHref) + '" target="_blank" rel="noopener noreferrer">' + $entry.place + '</a> ' +
            "($($entry.coords)) after " +
            '<a href="' + (Convert-WikiHref $entry.previousHref) + '" target="_blank" rel="noopener noreferrer">' + $entry.previous + '</a> ' +
            'to continue the Alexander quest line and unlock ' +
            '<a href="' + (Convert-WikiHref $entry.unlockHref) + '" target="_blank" rel="noopener noreferrer">' + $entry.unlock + '</a>.'
        )

        $enhancedItems.Add([pscustomobject]@{
            section = 'Level 60'
            ilevel = ''
            unlock = $entry.unlock
            unlock_parts = @($unlockParts)
            type = 'Raid'
            quest = $entry.quest
            quest_parts = @($questParts)
            location = "$($entry.coords):$($entry.place)"
            location_parts = @($locationParts)
            information = $information
            information_html = $informationHtml
            raw = @('Level 60', '', $entry.unlock, 'Raid', $entry.quest, "$($entry.coords):$($entry.place)", $information) -join ' | '
            id = "Level 60||$($entry.unlock)|$($entry.quest)"
            primary = $entry.quest
            secondary_unlock = $entry.unlock
        })
    }

    for ($i = 0; $i -lt $enhancedItems.Count; $i++) {
        $candidate = $enhancedItems[$i]

        if (
            $candidate.quest -ne 'Game Mechanic' -or
            $candidate.unlock -ne '-' -or
            -not $candidate.type -or
            -not $candidate.location
        ) {
            continue
        }

        $questTitle = $candidate.location
        $unlockTitle = $candidate.type
        $locationText = $candidate.information
        $locationHref = ''
        if ($candidate.information_html) {
            $locationHref = Get-FirstHrefFromHtml $candidate.information_html
        }
        if (-not $locationHref) {
            $locationHref = Convert-WikiHref (Convert-TitleToWikiHref (($locationText -replace '\s*\(.*$', '').Trim()))
        }

        $place = $locationText
        $coords = ''
        $locationMatch = [regex]::Match($locationText, '^(?<place>.+?)\s*\((?<coords>[^)]+)\)$')
        if ($locationMatch.Success) {
            $place = $locationMatch.Groups['place'].Value.Trim()
            $coords = Normalize-Coordinates $locationMatch.Groups['coords'].Value
            $candidate.location = "$coords`:$place"
            $candidate.location_parts = @(
                New-LocationPart -Place $place -Coords $coords -Href $locationHref
            )
        }
        else {
            $candidate.location = $locationText
            $candidate.location_parts = @(
                [pscustomobject]@{
                    place = $locationText
                    coords = ''
                    display = $locationText
                    url = $locationHref
                }
            )
        }

        $questHref = ''
        if ($candidate.location_parts -and $candidate.location_parts.Count -gt 0) {
            $questHref = $candidate.location_parts[0].url
        }
        if (-not $questHref) {
            $questHref = Convert-WikiHref (Convert-TitleToWikiHref $questTitle)
        }

        $candidate.unlock = $unlockTitle
        $candidate.unlock_parts = @(
            New-TextPart -Text $unlockTitle -Href (Convert-TitleToWikiHref $unlockTitle)
        )
        $candidate.type = 'Game Mechanic'
        $candidate.quest = $questTitle
        $candidate.quest_parts = @(
            New-TextPart -Text $questTitle -Href $questHref
        )
        $candidate.information = ''
        $candidate.information_html = ''
        $candidate.primary = $questTitle
        $candidate.secondary_unlock = $unlockTitle
        $candidate.id = @($candidate.section, $candidate.ilevel, $candidate.unlock, $candidate.quest) -join '|'
        $candidate.raw = @($candidate.section, $candidate.ilevel, $candidate.unlock, $candidate.type, $candidate.quest, $candidate.location, $candidate.information) -join ' | '
        $enhancedItems[$i] = $candidate
    }

    $malformedStrikingUnlocks = @(
        'The Circles of Answering',
        'The Lawns'
    )

    for ($i = $enhancedItems.Count - 1; $i -ge 0; $i--) {
        $candidate = $enhancedItems[$i]
        if (
            $candidate.quest -eq 'Game Mechanic' -and
            $candidate.unlock -eq '-' -and
            $malformedStrikingUnlocks -contains $candidate.type
        ) {
            $enhancedItems.RemoveAt($i)
        }
    }

    $strikingOpportunityEntries = @(
        @{
            section = 'Level 61 - 70'
            ilevel = '70'
            unlock = 'The Circles of Answering'
            unlockHref = '/wiki/The_Circles_of_Answering'
            quest = 'Another Striking Opportunity'
            questHref = '/wiki/Another_Striking_Opportunity'
            giver = 'Starry-eyed Ala Mhigan'
            giverHref = '/wiki/Starry-eyed_Ala_Mhigan'
            place = "Rhalgr's Reach"
            coords = 'X:12.3, Y:13.1'
            placeHref = '/wiki/Rhalgr%27s_Reach'
            previous = 'A Striking Opportunity'
            previousHref = '/wiki/A_Striking_Opportunity'
        },
        @{
            section = 'Level 71 - 80'
            ilevel = '80'
            unlock = 'The Lawns'
            unlockHref = '/wiki/The_Lawns'
            quest = 'Yet Another Striking Opportunity'
            questHref = '/wiki/Yet_Another_Striking_Opportunity'
            giver = 'Weary Dockworker'
            giverHref = '/wiki/Weary_Dockworker'
            place = 'Eulmore'
            coords = 'X:9.2, Y:9.9'
            placeHref = '/wiki/Eulmore'
            previous = 'A Striking Opportunity'
            previousHref = '/wiki/A_Striking_Opportunity'
        }
    )

    foreach ($entry in $strikingOpportunityEntries) {
        $existingEntry = $null
        foreach ($candidate in $enhancedItems) {
            if ($candidate.quest -eq $entry.quest -or $candidate.unlock -eq $entry.unlock) {
                $existingEntry = $candidate
                break
            }
        }

        $unlockParts = @(
            New-TextPart -Text $entry.unlock -Href $entry.unlockHref
        )
        $questParts = @(
            New-TextPart -Text $entry.quest -Href $entry.questHref
        )
        $locationParts = @(
            New-LocationPart -Place $entry.place -Coords $entry.coords -Href $entry.placeHref
        )

        $information = "Requires $($entry.previous). DPS Check for various Raids and Trials"
        $informationHtml = (
            'Requires <a href="' + (Convert-WikiHref $entry.previousHref) + '" target="_blank" rel="noopener noreferrer">' + $entry.previous + '</a>. ' +
            'DPS Check for various <a href="https://ffxiv.consolegameswiki.com/wiki/Raid" target="_blank" rel="noopener noreferrer">Raids</a> and ' +
            '<a href="https://ffxiv.consolegameswiki.com/wiki/Trial" target="_blank" rel="noopener noreferrer">Trials</a>'
        )

        if ($existingEntry) {
            $existingEntry.section = $entry.section
            $existingEntry.ilevel = $entry.ilevel
            $existingEntry.unlock = $entry.unlock
            $existingEntry.unlock_parts = @($unlockParts)
            $existingEntry.type = 'Game Mechanic'
            $existingEntry.quest = $entry.quest
            $existingEntry.quest_parts = @($questParts)
            $existingEntry.location = "$($entry.coords):$($entry.place)"
            $existingEntry.location_parts = @($locationParts)
            $existingEntry.information = $information
            $existingEntry.information_html = $informationHtml
            $existingEntry.raw = @($entry.section, $entry.ilevel, $entry.unlock, 'Game Mechanic', $entry.quest, "$($entry.coords):$($entry.place)", $information) -join ' | '
            $existingEntry.id = "$($entry.section)|$($entry.ilevel)|$($entry.unlock)|$($entry.quest)"
            $existingEntry.primary = $entry.quest
            $existingEntry.secondary_unlock = $entry.unlock
            continue
        }

        $enhancedItems.Add([pscustomobject]@{
            section = $entry.section
            ilevel = $entry.ilevel
            unlock = $entry.unlock
            unlock_parts = @($unlockParts)
            type = 'Game Mechanic'
            quest = $entry.quest
            quest_parts = @($questParts)
            location = "$($entry.coords):$($entry.place)"
            location_parts = @($locationParts)
            information = $information
            information_html = $informationHtml
            raw = @($entry.section, $entry.ilevel, $entry.unlock, 'Game Mechanic', $entry.quest, "$($entry.coords):$($entry.place)", $information) -join ' | '
            id = "$($entry.section)|$($entry.ilevel)|$($entry.unlock)|$($entry.quest)"
            primary = $entry.quest
            secondary_unlock = $entry.unlock
        })
    }

    $idyllshireMissingUnlocks = @(
        @{
            section = 'Level 51 - 60'
            ilevel = '1'
            unlock = 'Just Like Fire'
            unlockHref = '/wiki/Just_Like_Fire'
            quest = 'Fiery Wings, Fiery Hearts'
            questHref = '/wiki/Fiery_Wings,_Fiery_Hearts'
            place = 'Idyllshire'
            coords = 'X:7.5, Y:6.1'
            placeHref = '/wiki/Idyllshire'
            information = 'Requires the Firebird Whistle. This quest becomes available after collecting all seven Heavensward Lanner mounts and unlocks the Firebird mount questline finale.'
            informationHtml = (
                'Requires the <a href="https://ffxiv.consolegameswiki.com/wiki/Firebird_Whistle" target="_blank" rel="noopener noreferrer">Firebird Whistle</a>. ' +
                'This quest becomes available after collecting all seven Heavensward Lanner mounts and unlocks the Firebird mount questline finale.'
            )
        },
        @{
            section = 'Level 61 - 70'
            ilevel = '66'
            unlock = 'Custom Deliveries (Adkiragh)'
            unlockHref = '/wiki/Custom_Deliveries'
            quest = 'Between a Rock and the Hard Place'
            questHref = '/wiki/Between_a_Rock_and_the_Hard_Place'
            place = 'Idyllshire'
            coords = 'X:5.7, Y:6.9'
            placeHref = '/wiki/Idyllshire'
            information = 'Requires Stormblood, Arms Wide Open, and Purbol Rain. Unlocks Adkiragh custom deliveries.'
            informationHtml = (
                'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/Stormblood_(Quest)" target="_blank" rel="noopener noreferrer">Stormblood</a>, ' +
                '<a href="https://ffxiv.consolegameswiki.com/wiki/Arms_Wide_Open" target="_blank" rel="noopener noreferrer">Arms Wide Open</a>, and ' +
                '<a href="https://ffxiv.consolegameswiki.com/wiki/Purbol_Rain" target="_blank" rel="noopener noreferrer">Purbol Rain</a>. ' +
                'Unlocks Adkiragh custom deliveries.'
            )
        }
    )

    foreach ($entry in $idyllshireMissingUnlocks) {
        $existingEntry = $null
        foreach ($candidate in $enhancedItems) {
            if ($candidate.quest -eq $entry.quest -or $candidate.unlock -eq $entry.unlock) {
                $existingEntry = $candidate
                break
            }
        }

        if ($existingEntry) {
            continue
        }

        $unlockParts = @(
            New-TextPart -Text $entry.unlock -Href $entry.unlockHref
        )
        $questParts = @(
            New-TextPart -Text $entry.quest -Href $entry.questHref
        )
        $locationParts = @(
            New-LocationPart -Place $entry.place -Coords $entry.coords -Href $entry.placeHref
        )

        $enhancedItems.Add([pscustomobject]@{
            section = $entry.section
            ilevel = $entry.ilevel
            unlock = $entry.unlock
            unlock_parts = @($unlockParts)
            type = 'Game Mechanic'
            quest = $entry.quest
            quest_parts = @($questParts)
            location = "$($entry.coords):$($entry.place)"
            location_parts = @($locationParts)
            information = $entry.information
            information_html = $entry.informationHtml
            raw = @($entry.section, $entry.ilevel, $entry.unlock, 'Game Mechanic', $entry.quest, "$($entry.coords):$($entry.place)", $entry.information) -join ' | '
            id = "$($entry.section)|$($entry.ilevel)|$($entry.unlock)|$($entry.quest)"
            primary = $entry.quest
            secondary_unlock = $entry.unlock
        })
    }

    $sylphChainEntries = @(
        @{
            unlock = 'Sylph Daily Quests'
            unlockHref = '/wiki/Sylph_Daily_Quests'
            quest = 'Voyce of Concern'
            questHref = '/wiki/Voyce_of_Concern'
            place = 'East Shroud'
            coords = 'X:22, Y:26'
            placeHref = '/wiki/East_Shroud'
            previous = 'Seeking Solace'
            previousHref = '/wiki/Seeking_Solace'
        },
        @{
            unlock = 'Sylph Daily Quests'
            unlockHref = '/wiki/Sylph_Daily_Quests'
            quest = 'Pilfered Podlings'
            questHref = '/wiki/Pilfered_Podlings'
            place = 'East Shroud'
            coords = 'X:21, Y:26'
            placeHref = '/wiki/East_Shroud'
            previous = 'Voyce of Concern'
            previousHref = '/wiki/Voyce_of_Concern'
        },
        @{
            unlock = 'Sylph Daily Quests'
            unlockHref = '/wiki/Sylph_Daily_Quests'
            quest = 'Idle Hands'
            questHref = '/wiki/Idle_Hands'
            place = 'East Shroud'
            coords = 'X:22, Y:26'
            placeHref = '/wiki/East_Shroud'
            previous = 'Pilfered Podlings'
            previousHref = '/wiki/Pilfered_Podlings'
        },
        @{
            unlock = 'Sylph Daily Quests'
            unlockHref = '/wiki/Sylph_Daily_Quests'
            quest = 'Feathers and Folly'
            questHref = '/wiki/Feathers_and_Folly'
            place = 'East Shroud'
            coords = 'X:22.4, Y:26.4'
            placeHref = '/wiki/East_Shroud'
            previous = 'Idle Hands'
            previousHref = '/wiki/Idle_Hands'
        },
        @{
            unlock = 'Intersocietal Quests'
            unlockHref = '/wiki/Intersocietal_Quests'
            quest = 'Little Sylphs Lost'
            questHref = '/wiki/Little_Sylphs_Lost'
            place = 'New Gridania'
            coords = 'X:10, Y:11'
            placeHref = '/wiki/New_Gridania'
            previous = 'Call of the Wild (Immortal Flames)'
            previousHref = '/wiki/Call_of_the_Wild_(Immortal_Flames)'
        },
        @{
            unlock = 'Intersocietal Quests'
            unlockHref = '/wiki/Intersocietal_Quests'
            quest = 'Clutching at Straws'
            questHref = '/wiki/Clutching_at_Straws'
            place = 'East Shroud'
            coords = 'X:21, Y:26'
            placeHref = '/wiki/East_Shroud'
            previous = 'Little Sylphs Lost'
            previousHref = '/wiki/Little_Sylphs_Lost'
        },
        @{
            unlock = 'Intersocietal Quests'
            unlockHref = '/wiki/Intersocietal_Quests'
            quest = 'Digging for Answers'
            questHref = '/wiki/Digging_for_Answers'
            place = 'Western La Noscea'
            coords = 'X:16, Y:22'
            placeHref = '/wiki/Western_La_Noscea'
            previous = 'Clutching at Straws'
            previousHref = '/wiki/Clutching_at_Straws'
        },
        @{
            unlock = 'Intersocietal Quests'
            unlockHref = '/wiki/Intersocietal_Quests'
            quest = 'Rattled in Ehcatl'
            questHref = '/wiki/Rattled_in_Ehcatl'
            place = 'Outer La Noscea'
            coords = 'X:21, Y:17'
            placeHref = '/wiki/Outer_La_Noscea'
            previous = 'Digging for Answers'
            previousHref = '/wiki/Digging_for_Answers'
        },
        @{
            unlock = 'Intersocietal Quests'
            unlockHref = '/wiki/Intersocietal_Quests'
            quest = 'Ash Not What Your Brotherhood Can Do for You'
            questHref = '/wiki/Ash_Not_What_Your_Brotherhood_Can_Do_for_You'
            place = 'North Shroud'
            coords = 'X:24, Y:23'
            placeHref = '/wiki/North_Shroud'
            previous = 'Rattled in Ehcatl'
            previousHref = '/wiki/Rattled_in_Ehcatl'
        },
        @{
            unlock = "Intersocietal Quests / Amalj'aa Daily Quests"
            unlockHref = '/wiki/Amalj%27aa_Daily_Quests'
            quest = 'Friends Forever'
            questHref = '/wiki/Friends_Forever'
            place = 'Southern Thanalan'
            coords = 'X:23, Y:14'
            placeHref = '/wiki/Southern_Thanalan'
            previous = 'Ash Not What Your Brotherhood Can Do for You'
            previousHref = '/wiki/Ash_Not_What_Your_Brotherhood_Can_Do_for_You'
        }
    )

    foreach ($entry in $sylphChainEntries) {
        $existingEntry = $null
        foreach ($candidate in $enhancedItems) {
            if ($candidate.quest -eq $entry.quest) {
                $existingEntry = $candidate
                break
            }
        }

        if ($existingEntry) {
            continue
        }

        $unlockParts = @()
        foreach ($unlockText in @($entry.unlock -split ' / ' | Where-Object { $_ })) {
            $href = $entry.unlockHref
            if ($unlockText -eq "Intersocietal Quests") {
                $href = '/wiki/Intersocietal_Quests'
            }
            elseif ($unlockText -eq "Amalj''aa Daily Quests" -or $unlockText -eq "Amalj'aa Daily Quests") {
                $href = '/wiki/Amalj%27aa_Daily_Quests'
            }
            $unlockParts += New-TextPart -Text $unlockText -Href $href
        }

        $questParts = @(
            New-TextPart -Text $entry.quest -Href $entry.questHref
        )
        $locationParts = @(
            New-LocationPart -Place $entry.place -Coords $entry.coords -Href $entry.placeHref
        )
        $information = "Requires $($entry.previous)."
        $informationHtml = 'Requires <a href="' + (Convert-WikiHref $entry.previousHref) + '" target="_blank" rel="noopener noreferrer">' + $entry.previous + '</a>.'

        $enhancedItems.Add([pscustomobject]@{
            section = 'Level 1 - 50'
            ilevel = '41'
            unlock = $entry.unlock
            unlock_parts = @($unlockParts)
            type = 'Allied Society Quests'
            quest = $entry.quest
            quest_parts = @($questParts)
            location = "$($entry.coords):$($entry.place)"
            location_parts = @($locationParts)
            information = $information
            information_html = $informationHtml
            raw = @('Level 1 - 50', '41', $entry.unlock, 'Allied Society Quests', $entry.quest, "$($entry.coords):$($entry.place)", $information) -join ' | '
            id = "Level 1 - 50|41|$($entry.unlock)|$($entry.quest)"
            primary = $entry.quest
            secondary_unlock = $entry.unlock
        })
    }

    $customDeliveryEntries = @(
        @{
            section = 'Level 51 - 60'
            ilevel = '56'
            unlock = 'Aetherial Reduction'
            unlockHref = '/wiki/Aetherial_Reduction'
            quest = 'No Longer a Collectable'
            questHref = '/wiki/No_Longer_a_Collectable'
            place = 'Mor Dhona'
            coords = 'X:22.3, Y:6.8'
            placeHref = '/wiki/Mor_Dhona'
            information = 'Disciple of the Land requirement. Part of the collectables and custom deliveries progression.'
            informationHtml = 'Disciple of the Land requirement. Part of the collectables and custom deliveries progression.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 60'
            ilevel = '60'
            unlock = 'Collectable Appraiser (Idyllshire) / Scrip Exchange (Idyllshire) / Splendors Vendor (Idyllshire)'
            unlockHref = '/wiki/Collectable_Appraiser_(Idyllshire)'
            quest = 'Go West, Craftsman'
            questHref = '/wiki/Go_West,_Craftsman'
            place = 'Mor Dhona'
            coords = 'X:22.3, Y:6.8'
            placeHref = '/wiki/Mor_Dhona'
            information = 'Requires Inscrutable Tastes. Unlocks the Idyllshire collectable and scrip NPC suite.'
            informationHtml = 'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/Inscrutable_Tastes" target="_blank" rel="noopener noreferrer">Inscrutable Tastes</a>. Unlocks the Idyllshire collectable and scrip NPC suite.'
            type = 'Game Mechanic'
            unlockParts = @(
                @{ text = 'Collectable Appraiser (Idyllshire)'; href = '/wiki/Collectable_Appraiser_(Idyllshire)' },
                @{ text = 'Scrip Exchange (Idyllshire)'; href = '/wiki/Scrip_Exchange_(Idyllshire)' },
                @{ text = 'Splendors Vendor (Idyllshire)'; href = '/wiki/Splendors_Vendor_(Idyllshire)' }
            )
        },
        @{
            section = 'Level 60'
            ilevel = '60'
            unlock = "Collectable Appraiser (Rhalgr's Reach) / Scrip Exchange (Rhalgr's Reach) / Splendors Vendor (Rhalgr's Reach)"
            unlockHref = '/wiki/Collectable_Appraiser_(Rhalgr%27s_Reach)'
            quest = 'Reach Long and Prosper'
            questHref = '/wiki/Reach_Long_and_Prosper'
            place = "Rhalgr's Reach"
            coords = 'X:9.8, Y:12.5'
            placeHref = '/wiki/Rhalgr%27s_Reach'
            information = "Unlocks the Rhalgr's Reach collectable and scrip NPC suite."
            informationHtml = "Unlocks the Rhalgr&#39;s Reach collectable and scrip NPC suite."
            type = 'Game Mechanic'
            unlockParts = @(
                @{ text = "Collectable Appraiser (Rhalgr's Reach)"; href = '/wiki/Collectable_Appraiser_(Rhalgr%27s_Reach)' },
                @{ text = "Scrip Exchange (Rhalgr's Reach)"; href = '/wiki/Scrip_Exchange_(Rhalgr%27s_Reach)' },
                @{ text = "Splendors Vendor (Rhalgr's Reach)"; href = '/wiki/Splendors_Vendor_(Rhalgr%27s_Reach)' }
            )
        },
        @{
            section = 'Level 70'
            ilevel = '70'
            unlock = 'Collectable Appraiser (Eulmore) / Scrip Exchange (Eulmore) / Splendors Vendor (Eulmore)'
            unlockHref = '/wiki/Collectable_Appraiser_(Eulmore)'
            quest = 'The Boutique Always Wins'
            questHref = '/wiki/The_Boutique_Always_Wins'
            place = 'Eulmore'
            coords = 'X:11.4, Y:10.7'
            placeHref = '/wiki/Eulmore'
            information = 'Unlocks the Eulmore collectable and scrip NPC suite.'
            informationHtml = 'Unlocks the Eulmore collectable and scrip NPC suite.'
            type = 'Game Mechanic'
            unlockParts = @(
                @{ text = 'Collectable Appraiser (Eulmore)'; href = '/wiki/Collectable_Appraiser_(Eulmore)' },
                @{ text = 'Scrip Exchange (Eulmore)'; href = '/wiki/Scrip_Exchange_(Eulmore)' },
                @{ text = 'Splendors Vendor (Eulmore)'; href = '/wiki/Splendors_Vendor_(Eulmore)' }
            )
        },
        @{
            section = 'Level 80'
            ilevel = '80'
            unlock = 'Collectable Appraiser (Radz-at-Han) / Scrip Exchange (Radz-at-Han) / Splendors Vendor (Radz-at-Han)'
            unlockHref = '/wiki/Collectable_Appraiser_(Radz-at-Han)'
            quest = 'Expanding House of Splendors'
            questHref = '/wiki/Expanding_House_of_Splendors'
            place = 'Radz-at-Han'
            coords = 'X:11.7, Y:9.6'
            placeHref = '/wiki/Radz-at-Han'
            information = 'Unlocks the Radz-at-Han collectable and scrip NPC suite.'
            informationHtml = 'Unlocks the Radz-at-Han collectable and scrip NPC suite.'
            type = 'Game Mechanic'
            unlockParts = @(
                @{ text = 'Collectable Appraiser (Radz-at-Han)'; href = '/wiki/Collectable_Appraiser_(Radz-at-Han)' },
                @{ text = 'Scrip Exchange (Radz-at-Han)'; href = '/wiki/Scrip_Exchange_(Radz-at-Han)' },
                @{ text = 'Splendors Vendor (Radz-at-Han)'; href = '/wiki/Splendors_Vendor_(Radz-at-Han)' }
            )
        },
        @{
            section = 'Level 90'
            ilevel = '90'
            unlock = 'Collectable Appraiser (Solution Nine) / Scrip Exchange (Solution Nine) / Splendors Vendor (Solution Nine)'
            unlockHref = '/wiki/Collectable_Appraiser_(Solution_Nine)'
            quest = 'Dawn of a New Deal'
            questHref = '/wiki/Dawn_of_a_New_Deal'
            place = 'Solution Nine'
            coords = 'X:9.2, Y:13.4'
            placeHref = '/wiki/Solution_Nine'
            information = 'Requires Go West, Craftsman. Unlocks the Solution Nine collectable and scrip NPC suite.'
            informationHtml = 'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/Go_West,_Craftsman" target="_blank" rel="noopener noreferrer">Go West, Craftsman</a>. Unlocks the Solution Nine collectable and scrip NPC suite.'
            type = 'Game Mechanic'
            unlockParts = @(
                @{ text = 'Collectable Appraiser (Solution Nine)'; href = '/wiki/Collectable_Appraiser_(Solution_Nine)' },
                @{ text = 'Scrip Exchange (Solution Nine)'; href = '/wiki/Scrip_Exchange_(Solution_Nine)' },
                @{ text = 'Splendors Vendor (Solution Nine)'; href = '/wiki/Splendors_Vendor_(Solution_Nine)' }
            )
        },
        @{
            section = 'Level 60'
            ilevel = '60'
            unlock = "Custom Deliveries (M'naago)"
            unlockHref = '/wiki/Custom_Deliveries_(M%27naago)'
            quest = 'None Forgotten, None Forsaken'
            questHref = '/wiki/None_Forgotten,_None_Forsaken'
            place = "Rhalgr's Reach"
            coords = 'X:9.8, Y:12.5'
            placeHref = '/wiki/Rhalgr%27s_Reach'
            information = "Requires Reach Long and Prosper. Unlocks M'naago custom deliveries."
            informationHtml = 'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/Reach_Long_and_Prosper" target="_blank" rel="noopener noreferrer">Reach Long and Prosper</a>. Unlocks M&#39;naago custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 61 - 70'
            ilevel = '62'
            unlock = 'Custom Deliveries (Kurenai)'
            unlockHref = '/wiki/Custom_Deliveries_(Kurenai)'
            quest = 'The Seaweed Is Always Greener'
            questHref = '/wiki/The_Seaweed_Is_Always_Greener'
            place = 'Kugane'
            coords = 'X:10.1, Y:9.9'
            placeHref = '/wiki/Kugane'
            information = 'Requires None Forgotten, None Forsaken. Unlocks Kurenai custom deliveries.'
            informationHtml = 'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/None_Forgotten,_None_Forsaken" target="_blank" rel="noopener noreferrer">None Forgotten, None Forsaken</a>. Unlocks Kurenai custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 70'
            ilevel = '70'
            unlock = 'Custom Deliveries (Kai-Shirr)'
            unlockHref = '/wiki/Custom_Deliveries_(Kai-Shirr)'
            quest = 'Oh, Beehive Yourself'
            questHref = '/wiki/Oh,_Beehive_Yourself'
            place = 'Eulmore'
            coords = 'X:11.7, Y:11.7'
            placeHref = '/wiki/Eulmore'
            information = 'Unlocks Kai-Shirr custom deliveries.'
            informationHtml = 'Unlocks Kai-Shirr custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 70'
            ilevel = '70'
            unlock = 'Custom Deliveries (Ehll Tou)'
            unlockHref = '/wiki/Custom_Deliveries_(Ehll_Tou)'
            quest = 'O Crafter, My Crafter'
            questHref = '/wiki/O_Crafter,_My_Crafter'
            place = 'The Firmament'
            coords = 'X:13.5, Y:11.2'
            placeHref = '/wiki/The_Firmament'
            information = 'Requires If Songs Had Wings and Shadowbringers. Unlocks Ehll Tou custom deliveries.'
            informationHtml = 'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/If_Songs_Had_Wings" target="_blank" rel="noopener noreferrer">If Songs Had Wings</a> and <a href="https://ffxiv.consolegameswiki.com/wiki/Shadowbringers_(Quest)" target="_blank" rel="noopener noreferrer">Shadowbringers</a>. Unlocks Ehll Tou custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 70'
            ilevel = '70'
            unlock = 'Custom Deliveries (Count Charlemend de Durendaire)'
            unlockHref = '/wiki/Custom_Deliveries_(Count_Charlemend_de_Durendaire)'
            quest = 'You Can Count on It'
            questHref = '/wiki/You_Can_Count_on_It'
            place = 'The Firmament'
            coords = 'X:11.0, Y:14.5'
            placeHref = '/wiki/The_Firmament'
            information = 'Requires Smiles Cross the Sky and Shadowbringers. Unlocks Count Charlemend custom deliveries.'
            informationHtml = 'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/Smiles_Cross_the_Sky" target="_blank" rel="noopener noreferrer">Smiles Cross the Sky</a> and <a href="https://ffxiv.consolegameswiki.com/wiki/Shadowbringers_(Quest)" target="_blank" rel="noopener noreferrer">Shadowbringers</a>. Unlocks Count Charlemend custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 80'
            ilevel = '80'
            unlock = 'Custom Deliveries (Ameliance Leveilleur)'
            unlockHref = '/wiki/Custom_Deliveries_(Ameliance_Leveilleur)'
            quest = 'Of Mothers and Merchants'
            questHref = '/wiki/Of_Mothers_and_Merchants'
            place = 'Old Sharlayan'
            coords = 'X:12.6, Y:9.7'
            placeHref = '/wiki/Old_Sharlayan'
            information = 'Unlocks Ameliance custom deliveries.'
            informationHtml = 'Unlocks Ameliance custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 80'
            ilevel = '80'
            unlock = 'Custom Deliveries (Anden)'
            unlockHref = '/wiki/Custom_Deliveries_(Anden)'
            quest = "That's So Anden"
            questHref = '/wiki/That%27s_So_Anden'
            place = 'The Crystarium'
            coords = 'X:9.3, Y:11.3'
            placeHref = '/wiki/The_Crystarium'
            information = 'Unlocks Anden custom deliveries.'
            informationHtml = 'Unlocks Anden custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 80'
            ilevel = '80'
            unlock = 'Custom Deliveries (Margrat)'
            unlockHref = '/wiki/Custom_Deliveries_(Margrat)'
            quest = "A Request of One's Own"
            questHref = '/wiki/A_Request_of_One%27s_Own'
            place = 'Old Sharlayan'
            coords = 'X:13.8, Y:15.0'
            placeHref = '/wiki/Old_Sharlayan'
            information = 'Unlocks Margrat custom deliveries.'
            informationHtml = 'Unlocks Margrat custom deliveries.'
            type = 'Game Mechanic'
        },
        @{
            section = 'Level 90'
            ilevel = '90'
            unlock = 'Custom Deliveries (Nitowikwe)'
            unlockHref = '/wiki/Custom_Deliveries_(Nitowikwe)'
            quest = 'Laying New Tracks'
            questHref = '/wiki/Laying_New_Tracks'
            place = 'Tuliyollal'
            coords = 'X:14.1, Y:12.1'
            placeHref = '/wiki/Tuliyollal'
            information = 'Unlocks Nitowikwe custom deliveries.'
            informationHtml = 'Unlocks Nitowikwe custom deliveries.'
            type = 'Game Mechanic'
        }
    )

    foreach ($entry in $customDeliveryEntries) {
        $existingEntry = $null
        foreach ($candidate in $enhancedItems) {
            if ($candidate.quest -eq $entry.quest -or $candidate.unlock -eq $entry.unlock) {
                $existingEntry = $candidate
                break
            }
        }

        if ($existingEntry) {
            continue
        }

        $unlockParts = @()
        if ($entry.ContainsKey('unlockParts') -and $entry.unlockParts) {
            foreach ($part in $entry.unlockParts) {
                $unlockParts += New-TextPart -Text $part.text -Href $part.href
            }
        }
        else {
            $unlockParts = @(
                New-TextPart -Text $entry.unlock -Href $entry.unlockHref
            )
        }

        $questParts = @(
            New-TextPart -Text $entry.quest -Href $entry.questHref
        )
        $locationParts = @(
            New-LocationPart -Place $entry.place -Coords $entry.coords -Href $entry.placeHref
        )

        $enhancedItems.Add([pscustomobject]@{
            section = $entry.section
            ilevel = $entry.ilevel
            unlock = $entry.unlock
            unlock_parts = @($unlockParts)
            type = $entry.type
            quest = $entry.quest
            quest_parts = @($questParts)
            location = "$($entry.coords):$($entry.place)"
            location_parts = @($locationParts)
            information = $entry.information
            information_html = $entry.informationHtml
            raw = @($entry.section, $entry.ilevel, $entry.unlock, $entry.type, $entry.quest, "$($entry.coords):$($entry.place)", $entry.information) -join ' | '
            id = "$($entry.section)|$($entry.ilevel)|$($entry.unlock)|$($entry.quest)"
            primary = $entry.quest
            secondary_unlock = $entry.unlock
        })
    }

    $importantSystemEntries = @(
        @{
            section = 'Level 1 - 50'
            ilevel = '1'
            unlock = 'Ocean Fishing'
            unlockHref = '/wiki/Ocean_Fishing'
            type = 'Gathering'
            quest = 'All the Fish in the Sea'
            questHref = '/wiki/All_the_Fish_in_the_Sea'
            place = 'Limsa Lominsa Lower Decks'
            coords = 'X:7.8, Y:14.5'
            placeHref = '/wiki/Limsa_Lominsa_Lower_Decks'
            information = 'Requires My First Fishing Rod. Unlocks Ocean Fishing from the ferry docks in Limsa Lominsa.'
            informationHtml = 'Requires <a href="https://ffxiv.consolegameswiki.com/wiki/My_First_Fishing_Rod" target="_blank" rel="noopener noreferrer">My First Fishing Rod</a>. Unlocks Ocean Fishing from the ferry docks in Limsa Lominsa.'
        },
        @{
            section = 'Level 71 - 80'
            ilevel = '70'
            unlock = 'Crystarium Deliveries'
            unlockHref = '/wiki/Crystarium_Deliveries'
            type = 'Side Quests'
            quest = 'The Crystalline Mean'
            questHref = '/wiki/The_Crystalline_Mean'
            place = 'The Crystarium'
            coords = 'X:11.0, Y:8.5'
            placeHref = '/wiki/The_Crystarium'
            information = 'Unlocks the Shadowbringers crafting and gathering role quest hub.'
            informationHtml = 'Unlocks the Shadowbringers crafting and gathering role quest hub.'
        },
        @{
            section = 'Level 81 - 90'
            ilevel = '80'
            unlock = 'Studium Deliveries'
            unlockHref = '/wiki/Studium_Deliveries'
            type = 'Side Quests'
            quest = 'The Faculty'
            questHref = '/wiki/The_Faculty'
            place = 'Old Sharlayan'
            coords = 'X:4.1, Y:9.4'
            placeHref = '/wiki/Old_Sharlayan'
            information = 'Unlocks the Endwalker crafting and gathering role quest hub.'
            informationHtml = 'Unlocks the Endwalker crafting and gathering role quest hub.'
        }
    )

    foreach ($entry in $importantSystemEntries) {
        $existingEntry = $null
        foreach ($candidate in $enhancedItems) {
            if ($candidate.quest -eq $entry.quest -or $candidate.unlock -eq $entry.unlock) {
                $existingEntry = $candidate
                break
            }
        }

        if ($existingEntry) {
            continue
        }

        $unlockParts = @(
            New-TextPart -Text $entry.unlock -Href $entry.unlockHref
        )
        $questParts = @(
            New-TextPart -Text $entry.quest -Href $entry.questHref
        )
        $locationParts = @(
            New-LocationPart -Place $entry.place -Coords $entry.coords -Href $entry.placeHref
        )

        $enhancedItems.Add([pscustomobject]@{
            section = $entry.section
            ilevel = $entry.ilevel
            unlock = $entry.unlock
            unlock_parts = @($unlockParts)
            type = $entry.type
            quest = $entry.quest
            quest_parts = @($questParts)
            location = "$($entry.coords):$($entry.place)"
            location_parts = @($locationParts)
            information = $entry.information
            information_html = $entry.informationHtml
            raw = @($entry.section, $entry.ilevel, $entry.unlock, $entry.type, $entry.quest, "$($entry.coords):$($entry.place)", $entry.information) -join ' | '
            id = "$($entry.section)|$($entry.ilevel)|$($entry.unlock)|$($entry.quest)"
            primary = $entry.quest
            secondary_unlock = $entry.unlock
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

