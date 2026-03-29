param(
    [string]$SourceUrl = 'https://ffxiv.consolegameswiki.com/wiki/Wondrous_Tails',
    [string]$JsonTarget = 'data/wondrous-tails.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WikiBaseUrl = 'https://ffxiv.consolegameswiki.com'

function Convert-WikiUrl {
    param([string]$Path)

    if (-not $Path) {
        return ''
    }

    if ($Path -match '^https?://') {
        return $Path
    }

    return "$WikiBaseUrl$Path"
}

function New-LinkPart {
    param([string]$Text, [string]$Path)

    return [pscustomobject]@{
        text = $Text
        url = Convert-WikiUrl $Path
    }
}

function Join-LinkPartsHtml {
    param(
        [object[]]$Parts,
        [string]$Separator = ' | '
    )

    $segments = foreach ($part in @($Parts)) {
        if (-not $part.text) {
            continue
        }

        $safeText = [System.Net.WebUtility]::HtmlEncode($part.text)
        if ($part.url) {
            $safeUrl = [System.Net.WebUtility]::HtmlEncode($part.url)
            "<a href=""$safeUrl"" target=""_blank"" rel=""noopener noreferrer"">$safeText</a>"
        }
        else {
            $safeText
        }
    }

    return ($segments -join $Separator)
}

function New-WondrousItem {
    param(
        [string]$Id,
        [string]$GroupTitle,
        [string]$GroupMeta,
        [int]$GroupOrder,
        [int]$ItemOrder,
        [string]$Primary,
        [string]$Type,
        [string]$Subtype,
        [string]$Level = '',
        [string]$Location = '',
        [string]$SecondaryLabel = '',
        [string]$SecondaryHtml = '',
        [string]$Information = '',
        [string]$InformationHtml = '',
        [object[]]$PrimaryParts = @()
    )

    return [pscustomobject]@{
        id = $Id
        group_title = $GroupTitle
        group_meta = $GroupMeta
        group_order = $GroupOrder
        item_order = $ItemOrder
        primary = $Primary
        primary_parts = @($PrimaryParts)
        type = $Type
        subtype = $Subtype
        level = $Level
        location = $Location
        secondary_label = $SecondaryLabel
        secondary_html = $SecondaryHtml
        information = $Information
        information_html = $InformationHtml
    }
}

Write-Host "Checking source page: $SourceUrl"
$null = Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl

$items = @(
    (New-WondrousItem -Id 'unlock' -GroupTitle 'Unlock' -GroupMeta 'Quest and NPC' -GroupOrder 1 -ItemOrder 1 -Primary 'Unlock Wondrous Tails' -Type 'Wondrous Tails' -Subtype 'Unlock' -Level '60' -Location 'X:5.7, Y:6.0:Idyllshire' -SecondaryLabel 'Quest' -SecondaryHtml (Join-LinkPartsHtml @(
        New-LinkPart 'Keeping Up with the Aliapohs' '/wiki/Keeping_Up_with_the_Aliapohs'
    ) '') -Information 'NPC: Unctuous Adventurer (X:7.0, Y:5.9).' -InformationHtml ('NPC: ' + (Join-LinkPartsHtml @(
        New-LinkPart 'Unctuous Adventurer' '/wiki/Unctuous_Adventurer'
    ) '') + ' (X:7.0, Y:5.9).'))

    (New-WondrousItem -Id 'receive_journal' -GroupTitle 'Weekly Flow' -GroupMeta 'How the journal works each week' -GroupOrder 2 -ItemOrder 1 -Primary '1. Receive a Wondrous Tails Journal' -Type 'Wondrous Tails' -Subtype 'Weekly Flow' -Location 'X:5.7, Y:6.1:Idyllshire' -SecondaryLabel 'NPC' -SecondaryHtml (Join-LinkPartsHtml @(
        New-LinkPart 'Khloe Aliapoh' '/wiki/Khloe_Aliapoh'
    ) '') -Information 'Pick up a journal with sixteen randomized objectives. A new journal appears every Tuesday at 1:00 a.m. PDT.' -InformationHtml ('Pick up a journal with sixteen randomized objectives from ' + (Join-LinkPartsHtml @(
        New-LinkPart 'Khloe Aliapoh' '/wiki/Khloe_Aliapoh'
    ) '') + '.<br>A new journal appears every Tuesday at 1:00 a.m. PDT.<br>Your journal is stored in Key Items and you must resolve the previous one before taking another.'))

    (New-WondrousItem -Id 'complete_objectives' -GroupTitle 'Weekly Flow' -GroupMeta 'How the journal works each week' -GroupOrder 2 -ItemOrder 2 -Primary '2. Complete Objectives to Obtain Seals' -Type 'Wondrous Tails' -Subtype 'Weekly Flow' -Information 'Complete journal duties to earn up to 9 seals, one seal per objective.' -InformationHtml ('Complete journal duties to earn up to 9 seals, one seal per objective.<br>Older duties can be cleared unsynced with ' + (Join-LinkPartsHtml @(
        New-LinkPart 'Unrestricted Party' '/wiki/Unrestricted_Party'
    ) '') + '.<br>Party Finder groups often use "WT" to mean one unsynced clear for Wondrous Tails.'))

    (New-WondrousItem -Id 'hand_in' -GroupTitle 'Weekly Flow' -GroupMeta 'How the journal works each week' -GroupOrder 2 -ItemOrder 3 -Primary '3. Hand in the Wondrous Tails Journal' -Type 'Wondrous Tails' -Subtype 'Weekly Flow' -Location 'X:5.7, Y:6.1:Idyllshire' -SecondaryLabel 'Turn in to' -SecondaryHtml (Join-LinkPartsHtml @(
        New-LinkPart 'Khloe Aliapoh' '/wiki/Khloe_Aliapoh'
    ) '') -Information 'Turn it in after 9 seals for the base reward plus line rewards. A journal lasts two weeks.' -InformationHtml ('Turn it in after 9 seals for the base reward plus any completed horizontal, vertical, or diagonal lines.<br>A journal lasts two weeks from the Tuesday it was issued.<br>' + (Join-LinkPartsHtml @(
        New-LinkPart 'Limited Jobs' '/wiki/Limited_Jobs'
    ) '') + ' cannot turn in Wondrous Tails journals.'))

    (New-WondrousItem -Id 'journal_states' -GroupTitle 'Journal States' -GroupMeta 'Pool and reward variants' -GroupOrder 3 -ItemOrder 1 -Primary 'Low-level and High-level states' -Type 'Wondrous Tails' -Subtype 'Journal State' -Information 'Low-level is the default 1-60 journal. High-level expands to 1-100, excludes level 50 trials, and unlocks after finishing Dawntrail.' -InformationHtml ('Low-level is the default journal and includes duties from level 1 to 60.<br>High-level includes duties from level 1 to 100, excludes level 50 trials, and gives 3 reward options per tier.<br>As of Patch 7.0, high-level unlocks after completing ' + (Join-LinkPartsHtml @(
        New-LinkPart 'Dawntrail' '/wiki/Dawntrail'
    ) '') + '.'))

    (New-WondrousItem -Id 'duty_pools_low' -GroupTitle 'Duty Pools' -GroupMeta 'Low-level state' -GroupOrder 4 -ItemOrder 1 -Primary 'Low-level duty pools' -Type 'Wondrous Tails' -Subtype 'Duty Pool' -Information 'Covers dungeon groups, Crystal Tower, Void Ark, Alexander, Bahamut, ARR/Heavensward extremes, bonus duties and PvP.' -InformationHtml ('Low-level journal pools include:<br>' +
        'Dungeons (Lv. 1-49, 50, 51-59, 60)<br>' +
        'Crystal Tower: ' + (Join-LinkPartsHtml @(
            New-LinkPart 'The Labyrinth of the Ancients' '/wiki/The_Labyrinth_of_the_Ancients'
            New-LinkPart 'Syrcus Tower' '/wiki/Syrcus_Tower'
            New-LinkPart 'The World of Darkness' '/wiki/The_World_of_Darkness'
        )) + '<br>' +
        'Shadow of Mhach: ' + (Join-LinkPartsHtml @(
            New-LinkPart 'The Void Ark' '/wiki/The_Void_Ark'
            New-LinkPart 'The Weeping City of Mhach' '/wiki/The_Weeping_City_of_Mhach'
            New-LinkPart 'Dun Scaith' '/wiki/Dun_Scaith'
        )) + '<br>' +
        'Alexander, Bahamut coils, ARR extremes, Heavensward extremes, Treasure Hunt / Deep Dungeons, and PvP objectives.'))

    (New-WondrousItem -Id 'duty_pools_high' -GroupTitle 'Duty Pools' -GroupMeta 'High-level state' -GroupOrder 4 -ItemOrder 2 -Primary 'High-level duty pools' -Type 'Wondrous Tails' -Subtype 'Duty Pool' -Information 'Covers leveling/high-level dungeons, level 100 dungeons, alliance raid sets, raid series, recent extreme trial groups, bonus duties and PvP.' -InformationHtml ('High-level journal pools include:<br>' +
        'Leveling and high-level dungeon groups plus ' + (Join-LinkPartsHtml @(
            New-LinkPart 'Dungeons (Lv. 100)' '/wiki/Dungeon'
        ) '') + '<br>' +
        'Alliance raid sets from ARR through Endwalker plus ' + (Join-LinkPartsHtml @(
            New-LinkPart 'Jeuno: The First Walk' '/wiki/Jeuno:_The_First_Walk'
            New-LinkPart 'San d''Oria: The Second Walk' '/wiki/San_d%27Oria:_The_Second_Walk'
        )) + '<br>' +
        'Raid series from Bahamut through AAC, Heavensward / Stormblood / Shadowbringers / Endwalker extreme pools, Treasure Hunt / Deep Dungeons, and PvP objectives.<br>' +
        (Join-LinkPartsHtml @(
            New-LinkPart 'Castrum Meridianum' '/wiki/Castrum_Meridianum'
            New-LinkPart 'The Praetorium' '/wiki/The_Praetorium'
        )) + ' do not count for the High-level Dungeons (Lv. 50 & 60) objective.'))

    (New-WondrousItem -Id 'rewards' -GroupTitle 'Rewards' -GroupMeta '9 Seals to 3 Lines' -GroupOrder 5 -ItemOrder 1 -Primary 'Reward tiers' -Type 'Wondrous Tails' -Subtype 'Reward' -Information 'Rewards are cumulative across 9 Seals, 1 Line, 2 Lines and 3 Lines.' -InformationHtml ('Reward tiers are cumulative.<br>' +
        '9 Seals: 50% combat EXP plus one of ' + (Join-LinkPartsHtml @(
            New-LinkPart 'Allagan Platinum Piece' '/wiki/Allagan_Platinum_Piece'
            New-LinkPart 'Allagan Tomestones of Poetics' '/wiki/Allagan_Tomestones_of_Poetics'
            New-LinkPart 'Timeworn Gargantuaskin Map' '/wiki/Timeworn_Gargantuaskin_Map'
        )) + '<br>' +
        '1 Line: ' + (Join-LinkPartsHtml @(
            New-LinkPart 'MGP Gold Card' '/wiki/MGP_Gold_Card'
            New-LinkPart 'Khloe''s Bronze Certificate of Commendation' '/wiki/Khloe%27s_Bronze_Certificate_of_Commendation'
            New-LinkPart 'Allagan Tomestones of Mnemonics' '/wiki/Allagan_Tomestones_of_Mnemonics'
        )) + '<br>' +
        '2 Lines: ' + (Join-LinkPartsHtml @(
            New-LinkPart 'MGP Platinum Card' '/wiki/MGP_Platinum_Card'
            New-LinkPart 'Khloe''s Silver Certificate of Commendation' '/wiki/Khloe%27s_Silver_Certificate_of_Commendation'
            New-LinkPart 'Allagan Tomestones of Mathematics' '/wiki/Allagan_Tomestones_of_Mathematics'
        )) + '<br>' +
        '3 Lines: ' + (Join-LinkPartsHtml @(
            New-LinkPart 'MGP Platinum Card' '/wiki/MGP_Platinum_Card'
            New-LinkPart 'Khloe''s Gold Certificate of Commendation' '/wiki/Khloe%27s_Gold_Certificate_of_Commendation'
            New-LinkPart 'Khloe''s Silver Certificate of Commendation' '/wiki/Khloe%27s_Silver_Certificate_of_Commendation'
        ))))

    (New-WondrousItem -Id 'second_chance' -GroupTitle 'Second Chance' -GroupMeta 'Bonus sticker tools' -GroupOrder 6 -ItemOrder 1 -Primary 'Second Chance points' -Type 'Wondrous Tails' -Subtype 'Second Chance' -Information 'Earn up to 9 points from first-timer clears. Retry costs 1 point and Shuffle costs 2 points.' -InformationHtml 'Earn up to 9 Second Chance points by clearing objectives with party members who are new to the duty.<br>Retry costs 1 point and lets you rerun a completed duty for another sticker.<br>Shuffle costs 2 points and rearranges seals; it is only available between 3 and 7 stickers.<br>Guildhests are ineligible for Second Chance points.')

    (New-WondrousItem -Id 'achievements' -GroupTitle 'Achievements' -GroupMeta 'Series completion milestones' -GroupOrder 7 -ItemOrder 1 -Primary 'Wondrous Tails achievements' -Type 'Wondrous Tails' -Subtype 'Achievement' -Information 'Seven achievements track completed series from 1 to 50. Notable rewards are Khloe''s Friend at 5 and Khloe''s Best Friend at 50.' -InformationHtml ('The achievement series runs from ' + (Join-LinkPartsHtml @(
        New-LinkPart 'And Khloe Was Her Name-o I' '/wiki/And_Khloe_Was_Her_Name-o_I'
        New-LinkPart 'And Khloe Was Her Name-o VII' '/wiki/And_Khloe_Was_Her_Name-o_VII'
    )) + '.<br>Notable rewards are ' + (Join-LinkPartsHtml @(
        New-LinkPart 'Khloe''s Friend' '/wiki/Khloe%27s_Friend'
        New-LinkPart 'Khloe''s Best Friend' '/wiki/Khloe%27s_Best_Friend'
    )) + '.<br>For achievement credit, only the 9 seals are required; lines are not needed.'))
)

$parentDir = Split-Path -Parent $JsonTarget
if ($parentDir -and -not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

$json = $items | ConvertTo-Json -Depth 6 -Compress
Set-Content -Path $JsonTarget -Value $json -Encoding UTF8

Write-Host "Updated $JsonTarget"
Write-Host ("Total entries: {0}" -f $items.Count)
$items | Group-Object group_title | Sort-Object Name | ForEach-Object {
    Write-Host ("{0}: {1}" -f $_.Name, $_.Count)
}
