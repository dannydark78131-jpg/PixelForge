#Requires -Version 5.1
<#
.SYNOPSIS
    ImageTools - PowerShell image manipulation module (System.Drawing engine).
.DESCRIPTION
    Provides cmdlets for converting, resizing, cropping, rotating, applying color
    effects, adding text watermarks and borders, generating thumbnails, and batch
    processing images. Runs on Windows PowerShell 5.1+ and PowerShell 7 on Windows.
.NOTES
    Author: PowerShell Image Manipulation App
    Engine: System.Drawing (GDI+). No external downloads required on Windows.
#>

$ErrorActionPreference = "Stop"

# --- Load the imaging engine -------------------------------------------------
function Test-ImageEngine {
    <# .SYNOPSIS Verify System.Drawing is available and throw a helpful error if not. #>
    if ($null -ne $script:EngineAvailable) { return }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $script:EngineAvailable = $true
    }
    catch {
        $script:EngineAvailable = $false
        $msg = @(
            "System.Drawing could not be loaded. This module uses the Windows GDI+ engine."
            "  - On Windows: run with Windows PowerShell 5.1 (powershell.exe) or PowerShell 7 (pwsh.exe)."
            "  - On Linux/macOS: System.Drawing is not supported. Run this module on Windows, or"
            "    re-host the operations on a cross-platform library such as SixLabors.ImageSharp."
        ) -join [Environment]::NewLine
        throw $msg
    }
}

# --- Private helpers ---------------------------------------------------------
function Get-ImageInternal {
    <#
    .SYNOPSIS Load an image from a file and return a self-contained 32bpp ARGB bitmap.
    .DESCRIPTION Reads bytes into a MemoryStream, decodes, draws into a fresh bitmap,
                 then disposes the stream and original. The returned bitmap has no
                 stream dependency and the source file is never locked.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    $ms = [System.IO.MemoryStream]::new($bytes)
    try {
        $orig = [System.Drawing.Image]::FromStream($ms)
        try {
            $bmp = New-Object System.Drawing.Bitmap($orig.Width, $orig.Height,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $bmp.SetResolution($orig.HorizontalResolution, $orig.VerticalResolution)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.DrawImage($orig, 0, 0, $orig.Width, $orig.Height)
            }
            finally { $g.Dispose() }
            return $bmp
        }
        finally { $orig.Dispose() }
    }
    catch {
        throw "Could not read image file '$Path': $_"
    }
    finally { $ms.Dispose() }
}

function Get-ImageInfoInternal {
    <# .SYNOPSIS Short-lived decode for reading true metadata (pixel format, dimensions, DPI). #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][scriptblock]$Body)
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    $ms = [System.IO.MemoryStream]::new($bytes)
    try {
        $img = [System.Drawing.Image]::FromStream($ms)
        try { & $Body $img } finally { $img.Dispose() }
    }
    finally { $ms.Dispose() }
}

function New-HighQualityGraphics {
    <# .SYNOPSIS Create a Graphics object with high-quality render settings. #>
    param([Parameter(Mandatory)][System.Drawing.Image]$OnImage)
    $g = [System.Drawing.Graphics]::FromImage($OnImage)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality= [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    return $g
}

function Get-ImageFormatFromExtension {
    param([Parameter(Mandatory)][string]$Path)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".jpg"  { return [System.Drawing.Imaging.ImageFormat]::Jpeg }
        ".jpeg" { return [System.Drawing.Imaging.ImageFormat]::Jpeg }
        ".png"  { return [System.Drawing.Imaging.ImageFormat]::Png }
        ".bmp"  { return [System.Drawing.Imaging.ImageFormat]::Bmp }
        ".gif"  { return [System.Drawing.Imaging.ImageFormat]::Gif }
        ".tif"  { return [System.Drawing.Imaging.ImageFormat]::Tiff }
        ".tiff" { return [System.Drawing.Imaging.ImageFormat]::Tiff }
        default { return $null }
    }
}

function Get-JpegCodec {
    return [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } | Select-Object -First 1
}

function Save-ImageInternal {
    <# .SYNOPSIS Save a bitmap to $Path, honoring JPEG -Quality (1-100). #>
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Image,
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1,100)][int]$Quality = 90
    )
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $fmt = Get-ImageFormatFromExtension $Path
    if ($null -eq $fmt) {
        # Unknown extension -> save as PNG but warn by appending .png
        $Path = "$Path.png"
        $fmt = [System.Drawing.Imaging.ImageFormat]::Png
    }
    if ($fmt -eq [System.Drawing.Imaging.ImageFormat]::Jpeg) {
        # JPEG has no alpha channel; flatten onto white so transparent areas don't turn black.
        $saveImg = $Image
        $flat = New-Object System.Drawing.Bitmap($Image.Width, $Image.Height,
            [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $gFlat = [System.Drawing.Graphics]::FromImage($flat)
        try {
            $gFlat.Clear([System.Drawing.Color]::White)
            $gFlat.DrawImage($Image, 0, 0, $Image.Width, $Image.Height)
        }
        finally { $gFlat.Dispose() }
        $saveImg = $flat
        try {
            $codec = Get-JpegCodec
            $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)
            $saveImg.Save($Path, $codec, $encParams)
            $encParams.Dispose()
        }
        finally { if ($saveImg -ne $Image) { $saveImg.Dispose() } }
    }
    else {
        $Image.Save($Path, $fmt)
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function New-ColorMatrix {
    <# .SYNOPSIS Build a 5x5 ColorMatrix from a jagged float array. #>
    param([Parameter(Mandatory)][float[][]]$Rows)
    return [System.Drawing.Imaging.ColorMatrix]::new($Rows)
}

function Get-EffectMatrix {
    param(
        [Parameter(Mandatory)][ValidateSet("Grayscale","Sepia","Invert","Brightness","Contrast")][string]$Effect,
        [float]$Value = 0
    )
    $id = [float[]]@(1,0,0,0,0)
    switch ($Effect) {
        "Grayscale" {
            $r0 = [float[]]@(0.299, 0.299, 0.299, 0, 0)
            $r1 = [float[]]@(0.587, 0.587, 0.587, 0, 0)
            $r2 = [float[]]@(0.114, 0.114, 0.114, 0, 0)
            $r3 = [float[]]@(0, 0, 0, 1, 0)
            $r4 = [float[]]@(0, 0, 0, 0, 1)
        }
        "Sepia" {
            $r0 = [float[]]@(0.393, 0.349, 0.272, 0, 0)
            $r1 = [float[]]@(0.769, 0.686, 0.534, 0, 0)
            $r2 = [float[]]@(0.189, 0.168, 0.131, 0, 0)
            $r3 = [float[]]@(0, 0, 0, 1, 0)
            $r4 = [float[]]@(0, 0, 0, 0, 1)
        }
        "Invert" {
            $r0 = [float[]]@(-1, 0, 0, 0, 0)
            $r1 = [float[]]@(0, -1, 0, 0, 0)
            $r2 = [float[]]@(0, 0, -1, 0, 0)
            $r3 = [float[]]@(0, 0, 0, 1, 0)
            $r4 = [float[]]@(1, 1, 1, 0, 1)
        }
        "Brightness" {
            # Value expected -1..1; clamp.
            $b = [Math]::Max(-1.0, [Math]::Min(1.0, $Value))
            $r0 = [float[]]@(1, 0, 0, 0, 0)
            $r1 = [float[]]@(0, 1, 0, 0, 0)
            $r2 = [float[]]@(0, 0, 1, 0, 0)
            $r3 = [float[]]@(0, 0, 0, 1, 0)
            $r4 = [float[]]@($b, $b, $b, 0, 1)
        }
        "Contrast" {
            # Value expected 0..3 (1 = no change).
            $c = [Math]::Max(0.0, [Math]::Min(3.0, $Value))
            $t = (1.0 - $c) / 2.0
            $r0 = [float[]]@($c, 0, 0, 0, 0)
            $r1 = [float[]]@(0, $c, 0, 0, 0)
            $r2 = [float[]]@(0, 0, $c, 0, 0)
            $r3 = [float[]]@(0, 0, 0, 1, 0)
            $r4 = [float[]]@($t, $t, $t, 0, 1)
        }
    }
    return [float[][]]@($r0, $r1, $r2, $r3, $r4)
}

function Resolve-OutputPath {
    <# .SYNOPSIS Build an output path: explicit $OutputPath, or input dir + suffix + same ext. #>
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [string]$OutputPath,
        [Parameter(Mandatory)][string]$Suffix
    )
    if ($OutputPath) {
        if ([System.IO.Path]::IsPathRooted($OutputPath)) { return $OutputPath }
        return [System.IO.Path]::Combine($PWD.Path, $OutputPath)
    }
    $dir  = [System.IO.Path]::GetDirectoryName($InputPath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $ext  = [System.IO.Path]::GetExtension($InputPath)
    return (Join-Path $dir ("{0}{1}{2}" -f $name, $Suffix, $ext))
}

# --- Public cmdlets ----------------------------------------------------------
function Get-ImageInfo {
    <#
    .SYNOPSIS Read dimensions, resolution, pixel format and file size of an image.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path)
    begin { Test-ImageEngine }
    process {
        $fi = Get-Item -LiteralPath $Path
        Get-ImageInfoInternal -Path $Path -Body {
            param($img)
            [PSCustomObject]@{
                FileName        = $fi.Name
                FullPath        = $fi.FullName
                Width           = $img.Width
                Height          = $img.Height
                PixelFormat     = $img.PixelFormat.ToString()
                HorizontalDpi   = [Math]::Round($img.HorizontalResolution, 1)
                VerticalDpi     = [Math]::Round($img.VerticalResolution, 1)
                FrameCount      = $img.GetFrameCount([System.Drawing.Imaging.FrameDimension]::Page)
                SizeKB          = [Math]::Round($fi.Length / 1KB, 1)
                Modified        = $fi.LastWriteTime
            }
        }
    }
}

function Convert-Image {
    <#
    .SYNOPSIS Convert an image to another format and/or recompress (JPEG quality).
    .PARAMETER Format Target extension without dot: jpg, png, bmp, gif, tiff.
    .PARAMETER Quality JPEG quality 1-100 (default 90).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [Parameter(Mandatory)][ValidateSet("jpg","png","bmp","gif","tiff")][string]$Format,
        [ValidateRange(1,100)][int]$Quality = 90,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix ("_$Format")
        $out = [System.IO.Path]::ChangeExtension($out, ".$Format")
        $img = Get-ImageInternal $Path
        try {
            $saved = Save-ImageInternal -Image $img -Path $out -Quality $Quality
            [PSCustomObject]@{ Operation = "Convert"; Input = $Path; Output = $saved; Format = $Format; Quality = $Quality }
        }
        finally { $img.Dispose() }
    }
}

function Resize-Image {
    <#
    .SYNOPSIS Resize an image by exact dimensions or by percentage, preserving aspect ratio by default.
    .PARAMETER Width Target width in pixels.
    .PARAMETER Height Target height in pixels.
    .PARAMETER Percent Scale factor percent (e.g. 50 = half size). Ignored if Width/Height given.
    .PARAMETER NoMaintainAspect Allow distortion when both Width and Height are given.
    #>
    [CmdletBinding(DefaultParameterSetName="Dimensions")]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [Parameter(ParameterSetName="Dimensions")][int]$Width,
        [Parameter(ParameterSetName="Dimensions")][int]$Height,
        [Parameter(ParameterSetName="Percent", Mandatory)][ValidateRange(1,1000)][int]$Percent,
        [switch]$NoMaintainAspect,
        [ValidateRange(1,100)][int]$Quality = 90,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $img = Get-ImageInternal $Path
        try {
            $srcW = $img.Width; $srcH = $img.Height
            if ($PSCmdlet.ParameterSetName -eq "Percent") {
                $targetW = [int][Math]::Max(1, [Math]::Round($srcW * $Percent / 100))
                $targetH = [int][Math]::Max(1, [Math]::Round($srcH * $Percent / 100))
            }
            else {
                if ($Width -le 0 -and $Height -le 0) { throw "Specify at least one of -Width or -Height (greater than 0)." }
                $targetW = if ($Width -gt 0) { $Width } else { $srcW }
                $targetH = if ($Height -gt 0) { $Height } else { $srcH }
                if (-not $NoMaintainAspect) {
                    $ratioW = $targetW / $srcW
                    $ratioH = $targetH / $srcH
                    $ratio = [Math]::Min($ratioW, $ratioH)
                    # If only one dimension given, that dimension drives the ratio.
                    if ($Width -le 0) { $ratio = $ratioH }
                    if ($Height -le 0) { $ratio = $ratioW }
                    $targetW = [int][Math]::Max(1, [Math]::Round($srcW * $ratio))
                    $targetH = [int][Math]::Max(1, [Math]::Round($srcH * $ratio))
                }
            }
            $bmp = New-Object System.Drawing.Bitmap($targetW, $targetH)
            try {
                $g = New-HighQualityGraphics $bmp
                try { $g.DrawImage($img, 0, 0, $targetW, $targetH) } finally { $g.Dispose() }
                $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix ("_{0}x{1}" -f $targetW, $targetH)
                $saved = Save-ImageInternal -Image $bmp -Path $out -Quality $Quality
                [PSCustomObject]@{ Operation = "Resize"; Input = $Path; Output = $saved; Width = $targetW; Height = $targetH }
            }
            finally { $bmp.Dispose() }
        }
        finally { $img.Dispose() }
    }
}

function Crop-Image {
    <# .SYNOPSIS Crop a rectangle (X,Y,Width,Height) from an image. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [ValidateRange(1,100)][int]$Quality = 90,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $img = Get-ImageInternal $Path
        try {
            if ($X -lt 0 -or $Y -lt 0 -or $X + $Width -gt $img.Width -or $Y + $Height -gt $img.Height -or $Width -le 0 -or $Height -le 0) {
                throw "Crop rectangle ($X,$Y,$Width,$Height) is outside image $($img.Width)x$($img.Height)."
            }
            $rect = New-Object System.Drawing.Rectangle($X, $Y, $Width, $Height)
            $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
            try {
                $g = New-HighQualityGraphics $bmp
                try { $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0,0,$Width,$Height)), $rect, [System.Drawing.GraphicsUnit]::Pixel) }
                finally { $g.Dispose() }
                $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix "_crop"
                $saved = Save-ImageInternal -Image $bmp -Path $out -Quality $Quality
                [PSCustomObject]@{ Operation = "Crop"; Input = $Path; Output = $saved; X = $X; Y = $Y; Width = $Width; Height = $Height }
            }
            finally { $bmp.Dispose() }
        }
        finally { $img.Dispose() }
    }
}

function Rotate-Image {
    <# .SYNOPSIS Rotate (90/180/270) and/or flip (None/X/Y/Both) an image. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [ValidateSet(0,90,180,270)][int]$Angle = 0,
        [ValidateSet("None","X","Y","Both")][string]$Flip = "None",
        [ValidateRange(1,100)][int]$Quality = 90,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $img = Get-ImageInternal $Path
        try {
            $type = switch ("$Angle$Flip") {
                "0None"   { [System.Drawing.RotateFlipType]::RotateNoneFlipNone }
                "90None"  { [System.Drawing.RotateFlipType]::Rotate90FlipNone }
                "180None" { [System.Drawing.RotateFlipType]::Rotate180FlipNone }
                "270None" { [System.Drawing.RotateFlipType]::Rotate270FlipNone }
                "0X"      { [System.Drawing.RotateFlipType]::RotateNoneFlipX }
                "90X"     { [System.Drawing.RotateFlipType]::Rotate90FlipX }
                "180X"    { [System.Drawing.RotateFlipType]::Rotate180FlipX }
                "270X"    { [System.Drawing.RotateFlipType]::Rotate270FlipX }
                "0Y"      { [System.Drawing.RotateFlipType]::RotateNoneFlipY }
                "90Y"     { [System.Drawing.RotateFlipType]::Rotate90FlipY }
                "180Y"    { [System.Drawing.RotateFlipType]::Rotate180FlipY }
                "270Y"    { [System.Drawing.RotateFlipType]::Rotate270FlipY }
                "0Both"   { [System.Drawing.RotateFlipType]::RotateNoneFlipXY }
                "90Both"  { [System.Drawing.RotateFlipType]::Rotate90FlipXY }
                "180Both" { [System.Drawing.RotateFlipType]::Rotate180FlipXY }
                "270Both" { [System.Drawing.RotateFlipType]::Rotate270FlipXY }
                default   { [System.Drawing.RotateFlipType]::RotateNoneFlipNone }
            }
            $img.RotateFlip($type)
            $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix "_rot"
            $saved = Save-ImageInternal -Image $img -Path $out -Quality $Quality
            [PSCustomObject]@{ Operation = "Rotate"; Input = $Path; Output = $saved; Angle = $Angle; Flip = $Flip }
        }
        finally { $img.Dispose() }
    }
}

function Set-ImageEffect {
    <#
    .SYNOPSIS Apply a color-matrix effect: Grayscale, Sepia, Invert, Brightness or Contrast.
    .PARAMETER Value Brightness -1..1 (0 = none); Contrast 0..3 (1 = none).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [Parameter(Mandatory)][ValidateSet("Grayscale","Sepia","Invert","Brightness","Contrast")][string]$Effect,
        [float]$Value = 0,
        [ValidateRange(1,100)][int]$Quality = 90,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $img = Get-ImageInternal $Path
        try {
            $rows = Get-EffectMatrix -Effect $Effect -Value $Value
            $matrix = [System.Drawing.Imaging.ColorMatrix]::new($rows)
            $attr = New-Object System.Drawing.Imaging.ImageAttributes
            $attr.SetColorMatrix($matrix)
            $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
            try {
                $g = New-HighQualityGraphics $bmp
                try {
                    $dest = New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)
                    $g.DrawImage($img, $dest, 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
                }
                finally { $g.Dispose() }
                $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix ("_$Effect").ToLower()
                $saved = Save-ImageInternal -Image $bmp -Path $out -Quality $Quality
                [PSCustomObject]@{ Operation = "Effect"; Input = $Path; Output = $saved; Effect = $Effect; Value = $Value }
            }
            finally { $bmp.Dispose(); $attr.Dispose() }
        }
        finally { $img.Dispose() }
    }
}

function Add-ImageWatermark {
    <# .SYNOPSIS Draw a semi-transparent text watermark on an image. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [Parameter(Mandatory)][string]$Text,
        [string]$FontFamily = "Arial",
        [int]$FontSize = 24,
        [ValidateSet("Black","White","Red","Green","Blue","Yellow")][string]$Color = "White",
        [ValidateRange(0,255)][int]$Opacity = 160,
        [ValidateSet("TopLeft","TopRight","BottomLeft","BottomRight","Center")][string]$Position = "BottomRight",
        [int]$Margin = 20,
        [ValidateRange(1,100)][int]$Quality = 90,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $img = Get-ImageInternal $Path
        try {
            $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
            try {
                $g = New-HighQualityGraphics $bmp
                try {
                    $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
                    $font = New-Object System.Drawing.Font($FontFamily, $FontSize, [System.Drawing.FontStyle]::Bold)
                    $brushColor = [System.Drawing.Color]::FromArgb($Opacity, [System.Drawing.Color]::$Color)
                    $brush = New-Object System.Drawing.SolidBrush($brushColor)
                    $measured = $g.MeasureString($Text, $font)
                    $tw = $measured.Width; $th = $measured.Height
                    $pt = switch ($Position) {
                        "TopLeft"     { New-Object System.Drawing.PointF($Margin, $Margin) }
                        "TopRight"    { New-Object System.Drawing.PointF($img.Width - $tw - $Margin, $Margin) }
                        "BottomLeft"  { New-Object System.Drawing.PointF($Margin, $img.Height - $th - $Margin) }
                        "BottomRight" { New-Object System.Drawing.PointF($img.Width - $tw - $Margin, $img.Height - $th - $Margin) }
                        "Center"      { New-Object System.Drawing.PointF(($img.Width - $tw)/2, ($img.Height - $th)/2) }
                    }
                    $g.DrawString($Text, $font, $brush, $pt)
                    $font.Dispose(); $brush.Dispose()
                }
                finally { $g.Dispose() }
                $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix "_wm"
                $saved = Save-ImageInternal -Image $bmp -Path $out -Quality $Quality
                [PSCustomObject]@{ Operation = "Watermark"; Input = $Path; Output = $saved; Text = $Text; Position = $Position }
            }
            finally { $bmp.Dispose() }
        }
        finally { $img.Dispose() }
    }
}

function Add-ImageBorder {
    <# .SYNOPSIS Add a solid border of given pixel width around an image. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [ValidateRange(1,500)][int]$Width = 20,
        [string]$ColorName = "Black",
        [ValidateRange(1,100)][int]$Quality = 90,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $img = Get-ImageInternal $Path
        try {
            if ($ColorName -match '^#') {
            $borderColor = [System.Drawing.ColorTranslator]::FromHtml($ColorName)
        } else {
            $borderColor = [System.Drawing.Color]::$ColorName
        }
            $newW = $img.Width + 2 * $Width
            $newH = $img.Height + 2 * $Width
            $bmp = New-Object System.Drawing.Bitmap($newW, $newH)
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $g.Clear($borderColor)
                    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $g.DrawImage($img, $Width, $Width, $img.Width, $img.Height)
                }
                finally { $g.Dispose() }
                $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix "_border"
                $saved = Save-ImageInternal -Image $bmp -Path $out -Quality $Quality
                [PSCustomObject]@{ Operation = "Border"; Input = $Path; Output = $saved; BorderWidth = $Width; Color = $ColorName }
            }
            finally { $bmp.Dispose() }
        }
        finally { $img.Dispose() }
    }
}

function New-ImageThumbnail {
    <# .SYNOPSIS Create a thumbnail that fits within -Size pixels, preserving aspect ratio. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$Path,
        [ValidateRange(1,5000)][int]$Size = 200,
        [ValidateRange(1,100)][int]$Quality = 85,
        [string]$OutputPath
    )
    begin { Test-ImageEngine }
    process {
        $img = Get-ImageInternal $Path
        try {
            $ratio = [Math]::Min($Size / $img.Width, $Size / $img.Height)
            $tw = [int][Math]::Max(1, [Math]::Round($img.Width * $ratio))
            $th = [int][Math]::Max(1, [Math]::Round($img.Height * $ratio))
            $bmp = New-Object System.Drawing.Bitmap($tw, $th)
            try {
                $g = New-HighQualityGraphics $bmp
                try { $g.DrawImage($img, 0, 0, $tw, $th) } finally { $g.Dispose() }
                $out = Resolve-OutputPath -InputPath $Path -OutputPath $OutputPath -Suffix ("_thumb{0}" -f $Size)
                $saved = Save-ImageInternal -Image $bmp -Path $out -Quality $Quality
                [PSCustomObject]@{ Operation = "Thumbnail"; Input = $Path; Output = $saved; Width = $tw; Height = $th }
            }
            finally { $bmp.Dispose() }
        }
        finally { $img.Dispose() }
    }
}

function Invoke-BatchImage {
    <#
    .SYNOPSIS Apply an operation to every image in a folder.
    .PARAMETER ScriptBlock Receives -Path (input file) and -OutputDir; must emit the output file path or an object.
    .EXAMPLE
        Invoke-BatchImage -InputDir C:\photos -OutputDir C:\resized -ScriptBlock { param($p,$o) Resize-Image -Path $p -Percent 50 -OutputPath (Join-Path $o ([IO.Path]::GetFileName($p))) }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputDir,
        [Parameter(Mandatory)][string]$OutputDir,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string[]]$IncludeExtensions = @(".jpg",".jpeg",".png",".bmp",".gif",".tif",".tiff")
    )
    if (-not (Test-Path -LiteralPath $InputDir)) { throw "Input directory not found: $InputDir" }
    if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    $files = Get-ChildItem -LiteralPath $InputDir -File | Where-Object { $IncludeExtensions -contains $_.Extension.ToLowerInvariant() }
    $i = 0; $results = @()
    foreach ($f in $files) {
        $i++
        Write-Progress -Activity "Batch processing" -Status ("{0}/{1}: {2}" -f $i, $files.Count, $f.Name) -PercentComplete ([Math]::Round(100 * $i / $files.Count))
        try {
            $results += & $ScriptBlock $f.FullName $OutputDir
        }
        catch {
            Write-Warning "Failed on '$($f.FullName)': $_"
        }
    }
    Write-Progress -Activity "Batch processing" -Completed
    return $results
}

Export-ModuleMember -Function @(
    "Get-ImageInfo","Convert-Image","Resize-Image","Crop-Image","Rotate-Image",
    "Set-ImageEffect","Add-ImageWatermark","Add-ImageBorder","New-ImageThumbnail","Invoke-BatchImage"
)
