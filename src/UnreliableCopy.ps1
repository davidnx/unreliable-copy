<#
Example source tree:

    Path                                  Cursor
    ---------------------------------------------
    C:\src                                0
        C:\src\dir1                       0.0
            C:\src\dir1\1.txt             0.0.0
            C:\src\dir1\2.txt             0.0.1
        C:\src\dir2                       0.1
            C:\src\dir2\3.txt             0.1.0
        C:\src\4.txt                      0.2
        C:\src\5.txt                      0.3

Copying always starts from 0.0
#>


param (
    [Parameter(Mandatory = $true)]
    $src,

    [Parameter(Mandatory = $true)]
    $dest,

    $exclude
)

$ErrorActionPreference = "Stop"

function GetItems {
    param (
        $path
    )

    $items = Get-ChildItem $path
    $items | ForEach-Object {
        Write-Output $_.FullName
    }
}

function PrintTree {
    param(
        $tree
    )

    for ($i = 0; $i -lt $tree.Items.Length; $i++) {
        Write-Host "  $($tree.Level).$i    $($tree.Items[$i])"
    }

    Write-Host ""
    If ($tree.Parent) {
        PrintTree -tree $tree.Parent
    }
}

function HydrateCursor {
    param(
        $cursorPath
    )

    $cursor = $null
    if (Test-Path $cursorPath -PathType Leaf) {
        $cursor = Get-Content -Path $cursorPath -Raw
    }
    
    if ($cursor) {
        Write-Host "Found cursor '$cursor'"
    
        # Try to expand next level
        $levels = $cursor -split "\."
        $parentLevels = $levels[0..($levels.Length - 2)]
        $leafIndex = $levels[$levels.Length - 1]
    
        $parentLevelsString = $parentLevels -join "."
        $plan = Get-Content -Path "$tmp\$parentLevelsString.txt"
        $nextItem = $plan[$leafIndex]
    
        If ($nextItem) {
            if (Test-Path $nextItem -PathType Container) {
                Write-Host "Expanding into '$nextItem'..."
                $expandedItems = GetItems -Path $nextItem
                Set-Content -Path "$tmp\$cursor.txt" -Value $expandedItems
                $cursor = "$cursor.0"
            }
        }
    }
    else {
        Write-Host "No cursor found, starting fresh"
    
        $items = GetItems -Path $src
        Set-Content -Path "$tmp\0.txt" -Value $items
        $cursor = "0.0"
        Set-Content -Path $cursorPath -Value $cursor -NoNewline
    }

    return $cursor
}

$tmp = "$dest\.unreliablecopy"
New-Item -Path $tmp -ItemType Directory -Force | Out-Null

$srcRoot = (Get-Item $src).FullName
$destRoot = (Get-Item $dest).FullName

$fullExcludes = $exclude | ForEach-Object {
    (Get-Item $_).FullName
}
$robocopyExclusions = ($fullExcludes | ForEach-Object {
        "/XD ""$_"""
    }) -join " "

$excludesDict = @{}
$fullExcludes | ForEach-Object {
    $excludesDict.Add($_, $true)
}

Write-Host "Copying '$src' to '$dest'"

$cursorPath = "$tmp\cursor.txt"
$cursor = HydrateCursor -cursorPath $cursorPath

Write-Host "Copying starting at cursor '$cursor'"

$levels = $cursor -split "\."
$parentLevels = $levels[0..($levels.Length - 2)]
$leafIndex = [convert]::ToInt32($levels[$levels.Length - 1])

$tree = $null
$level = ""
for ($i = 0; $i -lt $parentLevels.Length; $i++) {
    $index = $parentLevels[$i]
    if ($level.Length -gt 0) {
        $level += "."
    }
    $level += "$index"
    $tree = @{
        Level  = $level;
        Items  = Get-Content -Path "$tmp\$level.txt";
        Parent = $tree
    }
}

Write-Host "Current tree (current index: $leafIndex):"
PrintTree -tree $tree

while ($tree) {
    for ($i = $leafIndex; $i -lt $tree.Items.Length; $i++) {
        $item = $tree.Items[$i]
        if ($item) {
            if (!$excludesDict.Contains($item)) {
                if (-not $item.StartsWith($srcRoot)) {
                    throw "Expected srcRoot beginning '$srcRoot', found '$item'"
                }

                $afterRoot = $item.Substring($srcRoot.Length)
                $destItem = $destRoot + $afterRoot
                If (Test-Path $item -PathType Leaf) {
                    Write-Host "Copying file '$item' to '$destItem'..."

                    # Make sure destination path strucure exists...
                    New-Item -ItemType File -Path $destItem -Force | Out-Null
                    Copy-Item $item $destItem | Out-Null
                }
                else {
                    $afterRoot = $item.Substring($srcRoot.Length)
                    $destItem = $destRoot + $afterRoot
                    Write-Host "robocopy ""$item"" ""$destItem"" ""/MT:4"" $robocopyExclusions"
                    robocopy $item $destItem "/MT:4" $robocopyExclusions
                    $err = $LastExitCode
                    if ($err -gt 7) {
                        throw "Robocopy failed with $err"
                    }
                }
            }
            else {
                Write-Host "Skipping '$item' (excluded via -exclude)..."
            }

            $cursor = "$($tree.Level).$($i + 1)"
            Write-Host "Updating cursor to '$cursor'..."
            Set-Content -Path $cursorPath -Value $cursor -NoNewline
        }
    }

    $levels = $tree.Level -split "\."
    $leafIndex = [convert]::ToInt32($levels[$levels.Length - 1]) + 1
    $tree = $tree.Parent

    if ($tree) {
        $cursor = "$($tree.Level).$leafIndex"
        Write-Host "Updating cursor to '$cursor'..."
        Set-Content -Path $cursorPath -Value $cursor -NoNewline
    }
}

Write-Host "Done!"