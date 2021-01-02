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
function EnsureSameSource {
    $srcPathFilePath = "$tmp\src.txt"
    if (Test-Path $srcPathFilePath -PathType Leaf) {
        $lastSrc = Get-Content -Path $srcPathFilePath -Raw -Encoding UTF8
        if ($lastSrc -ne $srcRoot) {
            throw "There is a copy in progress from a different source path '$lastSrc'." +
            " You can manually delete '$tmp' to start fresh.";
        }
    }

    Set-Content -Path $srcPathFilePath -Value $srcRoot -NoNewline -Encoding UTF8
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
        if ($cursor -eq "done") {
            return "done"
        }
    
        # Try to expand next level
        $levels = $cursor -split "\."
        $parentLevels = $levels[0..($levels.Length - 2)]
        $leafIndex = $levels[$levels.Length - 1]
    
        $parentLevelsString = $parentLevels -join "."
        $plan = @(Get-Content -Path "$tmp\$parentLevelsString.txt" -Encoding UTF8)
        $nextItem = $plan[$leafIndex]
    
        If ($nextItem) {
            if (Test-Path $nextItem -PathType Container) {
                Write-Host "Expanding into '$nextItem'..."
                $expandedItems = GetItems -Path $nextItem
                Set-Content -Path "$tmp\$cursor.txt" -Value $expandedItems -Encoding UTF8
                $cursor = "$cursor.0"
            }
        }
    }
    else {
        Write-Host "No cursor found, starting fresh"
    
        $items = GetItems -Path $src
        Set-Content -Path "$tmp\0.txt" -Value $items -Encoding UTF8
        $cursor = "0.0"
        Set-Content -Path $cursorPath -Value $cursor -NoNewline
    }

    return $cursor
}

$tmp = "$dest\.unreliablecopy"
New-Item -Path $tmp -ItemType Directory -Force | Out-Null

$srcRoot = (Get-Item $src).FullName
$destRoot = (Get-Item $dest).FullName

EnsureSameSource

if ($null -eq $exclude) {
    $exclude = @()
}
$fullExcludes = $exclude | ForEach-Object {
    $item = Get-Item $_
    Write-Output @{
        FullName    = $item.FullName;
        IsDirectory = $item.PSIsContainer
    }
}

$excludesDict = @{}
$fullExcludes | ForEach-Object {
    $excludesDict.Add($_.FullName, $true)
}

Write-Host "Copying '$src' to '$dest'"

$cursorPath = "$tmp\cursor.txt"
$cursor = HydrateCursor -cursorPath $cursorPath
if ($cursor -eq "done") {
    Write-Host "Copying already completed on a previous run. To start a new copy, you can manually delete '$tmp'."
    exit 0
}

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
        Items  = @(Get-Content -Path "$tmp\$level.txt" -Encoding UTF8);
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

                    # Make sure destination path structure exists...
                    New-Item -ItemType File -Path $destItem -Force | Out-Null
                    Copy-Item $item $destItem | Out-Null
                }
                else {
                    $argList = @(
                        $item,
                        $destItem,
                        "/e",
                        "/MT:4",
                        "/NJH", # No Job Header.
                        "/NJS"  # No Job Summary.
                    )
                    $fullExcludes | ForEach-Object {
                        $argList += If ($_.IsDirectory) { "/XD" } else { "/XF" }
                        $argList += $_.FullName
                    }

                    Write-Host "robocopy $argList"
                    & robocopy $argList
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

    $treeToDelete = $tree.Level
    $levels = $tree.Level -split "\."
    $leafIndex = [convert]::ToInt32($levels[$levels.Length - 1]) + 1
    $tree = $tree.Parent

    if ($tree) {
        $cursor = "$($tree.Level).$leafIndex"
    }
    else {
        $cursor = "done"
    }

    Write-Host "Updating cursor to '$cursor'..."
    Set-Content -Path $cursorPath -Value $cursor -NoNewline

    # Delete the file containing the contents of the tree level we just finished copying
    Remove-Item -Path "$tmp\$treeToDelete.txt" -Force | Out-Null
}

Write-Host "Done!"
