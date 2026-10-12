Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path $PSScriptRoot -Parent
$source = [System.Drawing.Image]::FromFile((Join-Path $projectRoot 'assets/Icon/SAFEROUTE_LOGO.png'))

function Get-IconPng([int]$size, [bool]$maskable = $false) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $stream = [System.IO.MemoryStream]::new()
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scale = 1.0
        if ($maskable) {
            $graphics.Clear([System.Drawing.Color]::White)
            $scale = 0.8
        }
        $side = [int]($size * $scale)
        $offset = [int](($size - $side) / 2)
        $graphics.DrawImage($source, $offset, $offset, $side, $side)
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    } finally {
        $stream.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    $targets = @{
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png' = 48
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png' = 72
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png' = 96
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png' = 144
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png' = 192
        'web/favicon.png' = 32
        'web/icons/Icon-192.png' = 192
        'web/icons/Icon-512.png' = 512
        'web/icons/Icon-maskable-192.png' = 192
        'web/icons/Icon-maskable-512.png' = 512
    }
    foreach ($target in $targets.GetEnumerator()) {
        [System.IO.File]::WriteAllBytes((Join-Path $projectRoot $target.Key), (Get-IconPng $target.Value ($target.Key.Contains('maskable'))))
    }

    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = @($sizes | ForEach-Object { ,(Get-IconPng $_) })
    $iconStream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($iconStream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dimension = $sizes[$i] % 256
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frames[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
        $writer.Flush()
        [System.IO.File]::WriteAllBytes((Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'), $iconStream.ToArray())
    } finally {
        $writer.Dispose()
        $iconStream.Dispose()
    }
    Write-Output 'Generated Android, Windows, and web icons from SAFEROUTE_LOGO.png.'
} finally {
    $source.Dispose()
}
