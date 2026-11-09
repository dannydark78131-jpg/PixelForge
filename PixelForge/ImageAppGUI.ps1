#Requires -Version 5.1
<#
.SYNOPSIS
    PixelForge Image Toolkit — WPF GUI front-end for ImageTools.psm1.
.DESCRIPTION
    Loads ImageTools.psm1 from the same folder and exposes all 10 operations
    through a tabbed dark-themed GUI. Settings persist to
    %APPDATA%\PixelForge\settings.json.
.NOTES
    Run hidden: powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ImageAppGUI.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# --- Load WPF / WinForms / Drawing ------------------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms, System.Xaml | Out-Null

# --- Locate and import the module -------------------------------------------
$modulePath = Join-Path $PSScriptRoot "ImageTools.psm1"
if (-not (Test-Path -LiteralPath $modulePath)) {
    [System.Windows.MessageBox]::Show(
        "ImageTools.psm1 was not found next to this script.`nExpected at: $modulePath",
        "PixelForge — Missing module", "OK", "Error") | Out-Null
    exit 1
}
try {
    Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
}
catch {
    [System.Windows.MessageBox]::Show("Failed to load ImageTools module: $_", "PixelForge — Load error", "OK", "Error") | Out-Null
    exit 1
}

# --- Settings persistence ----------------------------------------------------
$settingsDir  = Join-Path $env:APPDATA "PixelForge"
$settingsFile = Join-Path $settingsDir "settings.json"
$script:Settings = [ordered]@{
    OutputDir          = ""
    DefaultQuality     = 90
    AutoChain          = $true
    WmText             = "© PixelForge"
    WmFontSize         = 24
    WmColor            = "White"
    WmPosition         = "BottomRight"
    WmOpacity          = 160
    BorderWidth        = 20
    BorderColor        = "Black"
    ThumbnailSize      = 200
    LastImage          = ""
}
function Save-Settings {
    if (-not (Test-Path -LiteralPath $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
    $script:Settings | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $settingsFile -Encoding utf8 -Force
}
if (Test-Path -LiteralPath $settingsFile) {
    try {
        $loaded = Get-Content -LiteralPath $settingsFile -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($k in @($script:Settings.Keys)) {
            if ($null -ne $loaded.$k) { $script:Settings[$k] = $loaded.$k }
        }
    } catch { }
}

$script:WorkingImage = $null

# --- XAML --------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PixelForge — Image Toolkit" Height="700" Width="1000" MinWidth="900" MinHeight="620"
        Background="#1e1e2e" Foreground="#e0e0e0" FontFamily="Segoe UI" FontSize="12"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#00b4d8"/>
            <Setter Property="Foreground" Value="#0d1b2a"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="4,2"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#48cae4"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Background" Value="#3a3a4e"/>
                                <Setter Property="Foreground" Value="#777"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2a2a3e"/>
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="BorderBrush" Value="#3a3a55"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="4,2"/>
            <Setter Property="Margin" Value="2"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#2a2a3e"/>
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="Margin" Value="2"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="Margin" Value="2,4"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="Background" Value="#252536"/>
            <Setter Property="Padding" Value="10,4"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#c0c0d0"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="2"/>
        </Style>
        <Style TargetType="Slider">
            <Setter Property="Margin" Value="2"/>
            <Setter Property="Foreground" Value="#00b4d8"/>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="46"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="30"/>
        </Grid.RowDefinitions>

        <!-- Toolbar -->
        <Border Grid.Row="0" Background="#252536" BorderBrush="#3a3a55" BorderThickness="0,0,0,1">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="8,0">
                <Button Name="btnLoad"    Content="Load Image" Width="110"/>
                <Button Name="btnOutDir"  Content="Output Folder" Width="110" Background="#2ec4b6"/>
                <Button Name="btnSettings" Content="Settings" Width="90" Background="#3a3a55" Foreground="#e0e0e0"/>
                <Button Name="btnReload"  Content="Reload Module" Width="110" Background="#3a3a55" Foreground="#e0e0e0"/>
                <TextBlock Name="tbWorking" Text="No image loaded" Margin="14,0,0,0" Foreground="#888" VerticalAlignment="Center"/>
            </StackPanel>
        </Border>

        <!-- Main -->
        <Grid Grid.Row="1" Margin="8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="470"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <TabControl Name="tabs" Background="#1e1e2e" BorderThickness="0" Margin="0,0,8,0">
                <!-- INFO -->
                <TabItem Header="Info">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#1e1e2e">
                        <StackPanel Margin="10">
                            <TextBlock Text="Image information" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                            <TextBlock Name="tbInfo" Text="Load an image to see details." TextWrapping="Wrap" Margin="0,8"/>
                            <Button Name="btnInfo" Content="Refresh info" HorizontalAlignment="Left" Margin="0,10"/>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <!-- CONVERT -->
                <TabItem Header="Convert">
                    <StackPanel Margin="10">
                        <TextBlock Text="Convert format / compress" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Target format"/>
                            <ComboBox Name="cboConvFormat" Grid.Column="1"/>
                        </Grid>
                        <Grid Margin="0,6"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="JPEG quality (1-100)"/>
                            <Slider Name="sldConvQuality" Grid.Column="1" Minimum="1" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" Value="90"/>
                        </Grid>
                        <TextBlock Name="tbConvQ" Text="90" Margin="140,0,0,0"/>
                        <CheckBox Name="chkConvChain" Content="Set result as new working image" IsChecked="True" Margin="0,10"/>
                        <Button Name="btnConvert" Content="Convert image" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- RESIZE -->
                <TabItem Header="Resize">
                    <StackPanel Margin="10">
                        <TextBlock Text="Resize image" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Mode"/>
                            <ComboBox Name="cboResizeMode" Grid.Column="1"/>
                        </Grid>
                        <Grid Name="gridPct" Margin="0,6"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Percent (50 = half)"/>
                            <Slider Name="sldPct" Grid.Column="1" Minimum="1" Maximum="1000" TickFrequency="5" IsSnapToTickEnabled="True" Value="50"/>
                        </Grid>
                        <TextBlock Name="tbPct" Text="50 %" Margin="140,0,0,6"/>
                        <Grid Name="gridDim" Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Width px (0=auto)"/><TextBox Name="txtW" Grid.Column="1" Text="0"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Height px (0=auto)"/><TextBox Name="txtH" Grid.Column="1" Text="0"/>
                        </Grid>
                        <CheckBox Name="chkAspect" Content="Maintain aspect ratio" IsChecked="True" Margin="0,6"/>
                        <CheckBox Name="chkResizeChain" Content="Set result as new working image" IsChecked="True"/>
                        <Button Name="btnResize" Content="Resize image" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- CROP -->
                <TabItem Header="Crop">
                    <StackPanel Margin="10">
                        <TextBlock Text="Crop rectangle" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <TextBlock Name="tbCropSize" Text="Load an image first." Margin="0,6"/>
                        <Grid Margin="0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="X (left offset)"/><TextBox Name="txtCropX" Grid.Column="1" Text="0"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Y (top offset)"/><TextBox Name="txtCropY" Grid.Column="1" Text="0"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Crop width"/><TextBox Name="txtCropW" Grid.Column="1" Text="0"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Crop height"/><TextBox Name="txtCropH" Grid.Column="1" Text="0"/>
                        </Grid>
                        <CheckBox Name="chkCropChain" Content="Set result as new working image" IsChecked="True" Margin="0,10"/>
                        <Button Name="btnCrop" Content="Crop image" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- ROTATE -->
                <TabItem Header="Rotate">
                    <StackPanel Margin="10">
                        <TextBlock Text="Rotate / flip" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Rotation angle"/><ComboBox Name="cboAngle" Grid.Column="1"/>
                        </Grid>
                        <Grid Margin="0,6"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Flip"/><ComboBox Name="cboFlip" Grid.Column="1"/>
                        </Grid>
                        <CheckBox Name="chkRotateChain" Content="Set result as new working image" IsChecked="True" Margin="0,10"/>
                        <Button Name="btnRotate" Content="Rotate / flip" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- EFFECTS -->
                <TabItem Header="Effects">
                    <StackPanel Margin="10">
                        <TextBlock Text="Apply effect" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Effect"/><ComboBox Name="cboEffect" Grid.Column="1"/>
                        </Grid>
                        <Grid Name="gridEffectVal" Margin="0,6"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Name="tbEffectVal" Grid.Column="0" Text="Value"/><Slider Name="sldEffectVal" Grid.Column="1" Minimum="-1" Maximum="3" TickFrequency="0.1" IsSnapToTickEnabled="True" Value="0.2"/>
                        </Grid>
                        <TextBlock Name="tbEffectValShow" Text="0.2" Margin="140,0,0,0"/>
                        <CheckBox Name="chkEffectChain" Content="Set result as new working image" IsChecked="True" Margin="0,10"/>
                        <Button Name="btnEffect" Content="Apply effect" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- WATERMARK -->
                <TabItem Header="Watermark">
                    <StackPanel Margin="10">
                        <TextBlock Text="Text watermark" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Text"/><TextBox Name="txtWmText" Grid.Column="1" Text="© PixelForge"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Font size"/><TextBox Name="txtWmSize" Grid.Column="1" Text="24"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Color"/><ComboBox Name="cboWmColor" Grid.Column="1"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Position"/><ComboBox Name="cboWmPos" Grid.Column="1"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Opacity (0-255)"/><TextBox Name="txtWmOpacity" Grid.Column="1" Text="160"/>
                        </Grid>
                        <CheckBox Name="chkWmChain" Content="Set result as new working image" IsChecked="True" Margin="0,10"/>
                        <Button Name="btnWm" Content="Add watermark" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- BORDER -->
                <TabItem Header="Border">
                    <StackPanel Margin="10">
                        <TextBlock Text="Add border / frame" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Border width px"/><TextBox Name="txtBorderW" Grid.Column="1" Text="20"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Color (name or #hex)"/><TextBox Name="txtBorderColor" Grid.Column="1" Text="Black"/>
                        </Grid>
                        <CheckBox Name="chkBorderChain" Content="Set result as new working image" IsChecked="True" Margin="0,10"/>
                        <Button Name="btnBorder" Content="Add border" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- THUMBNAIL -->
                <TabItem Header="Thumbnail">
                    <StackPanel Margin="10">
                        <TextBlock Text="Create thumbnail" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Max dimension px"/><TextBox Name="txtThumbSize" Grid.Column="1" Text="200"/>
                        </Grid>
                        <CheckBox Name="chkThumbChain" Content="Set result as new working image" IsChecked="False" Margin="0,10"/>
                        <Button Name="btnThumb" Content="Create thumbnail" HorizontalAlignment="Left" Margin="0,12"/>
                    </StackPanel>
                </TabItem>

                <!-- BATCH -->
                <TabItem Header="Batch">
                    <StackPanel Margin="10">
                        <TextBlock Text="Process a whole folder" FontSize="14" Foreground="#00b4d8" FontWeight="Bold"/>
                        <Grid Margin="0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Input folder"/><TextBox Name="txtBatchIn" Grid.Column="1" IsReadOnly="True"/><Button Name="btnBatchIn" Grid.Column="2" Content="…" Width="32" Padding="0"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Output folder"/><TextBox Name="txtBatchOut" Grid.Column="1" IsReadOnly="True"/><Button Name="btnBatchOut" Grid.Column="2" Content="…" Width="32" Padding="0"/>
                        </Grid>
                        <Grid Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Operation"/><ComboBox Name="cboBatchOp" Grid.Column="1"/>
                        </Grid>
                        <Grid Name="gridBatchWm" Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Watermark text"/><TextBox Name="txtBatchWm" Grid.Column="1" Text="© PixelForge"/>
                        </Grid>
                        <Button Name="btnBatch" Content="Run batch process" HorizontalAlignment="Left" Margin="0,12"/>
                        <TextBlock Name="tbBatchResult" Text="" TextWrapping="Wrap" Margin="0,10" Foreground="#2ec4b6"/>
                    </StackPanel>
                </TabItem>
            </TabControl>

            <!-- Preview pane -->
            <Border Grid.Column="1" Background="#12121c" CornerRadius="8" BorderBrush="#3a3a55" BorderThickness="1">
                <Grid Margin="8">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Viewbox Grid.Row="0" Stretch="Uniform">
                        <Image Name="imgPreview" Stretch="Uniform"/>
                    </Viewbox>
                    <TextBlock Name="tbPreviewInfo" Grid.Row="1" Text="No preview" TextWrapping="Wrap" Foreground="#888" Margin="0,6,0,0"/>
                </Grid>
            </Border>
        </Grid>

        <!-- Status bar -->
        <Border Grid.Row="2" Background="#252536" BorderBrush="#3a3a55" BorderThickness="0,1,0,0">
            <TextBlock Name="tbStatus" Text="Ready." VerticalAlignment="Center" Margin="10,0" Foreground="#00b4d8"/>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# --- Helper: find named control ----------------------------------------------
function N([string]$name) { $window.FindName($name) }

# --- Populate comboboxes ------------------------------------------------------
@("jpg","png","bmp","gif","tiff") | ForEach-Object { (N cboConvFormat).Items.Add($_) | Out-Null }
(N cboConvFormat).SelectedIndex = 0
@("Percent","Exact dimensions") | ForEach-Object { (N cboResizeMode).Items.Add($_) | Out-Null }
(N cboResizeMode).SelectedIndex = 0
@("0","90","180","270") | ForEach-Object { (N cboAngle).Items.Add($_) | Out-Null }
(N cboAngle).SelectedIndex = 1
@("None","X","Y","Both") | ForEach-Object { (N cboFlip).Items.Add($_) | Out-Null }
(N cboFlip).SelectedIndex = 0
@("Grayscale","Sepia","Invert","Brightness","Contrast") | ForEach-Object { (N cboEffect).Items.Add($_) | Out-Null }
(N cboEffect).SelectedIndex = 0
@("White","Black","Red","Green","Blue","Yellow") | ForEach-Object { (N cboWmColor).Items.Add($_) | Out-Null }
(N cboWmColor).SelectedIndex = 0
@("TopLeft","TopRight","BottomLeft","BottomRight","Center") | ForEach-Object { (N cboWmPos).Items.Add($_) | Out-Null }
(N cboWmPos).SelectedIndex = 3
@("Resize to 50%","Convert to JPG q85","Grayscale","Thumbnail 200px","Watermark") | ForEach-Object { (N cboBatchOp).Items.Add($_) | Out-Null }
(N cboBatchOp).SelectedIndex = 0

# Apply saved defaults to UI
(N sldConvQuality).Value = [int]$script:Settings.DefaultQuality
(N tbConvQ).Text = [string]$script:Settings.DefaultQuality
(N txtWmText).Text    = [string]$script:Settings.WmText
(N txtWmSize).Text    = [string]$script:Settings.WmFontSize
(N cboWmColor).SelectedItem = [string]$script:Settings.WmColor
(N cboWmPos).SelectedItem   = [string]$script:Settings.WmPosition
(N txtWmOpacity).Text = [string]$script:Settings.WmOpacity
(N txtBorderW).Text     = [string]$script:Settings.BorderWidth
(N txtBorderColor).Text = [string]$script:Settings.BorderColor
(N txtThumbSize).Text   = [string]$script:Settings.ThumbnailSize

# --- Status + preview helpers -------------------------------------------------
function Set-Status([string]$msg, [string]$color = "#00b4d8") {
    (N tbStatus).Text = $msg
    (N tbStatus).Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
}
function Update-Preview([string]$path) {
    try {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.UriSource = [Uri]$path
        $bi.EndInit()
        $bi.Freeze()
        (N imgPreview).Source = $bi
        $info = Get-ImageInfo -Path $path -ErrorAction Stop
        (N tbPreviewInfo).Text = "{0}`n{1} x {2} px  ·  {3} KB  ·  {4}" -f $path, $info.Width, $info.Height, $info.SizeKB, $info.PixelFormat
        (N tbInfo).Text = ("Path: {0}`nWidth: {1} px`nHeight: {2} px`nSize: {3} KB`nPixel format: {4}" -f $path, $info.Width, $info.Height, $info.SizeKB, $info.PixelFormat)
        (N tbCropSize).Text = ("Image is {0} x {1} px." -f $info.Width, $info.Height)
        if ((N txtCropW).Text -eq "0") { (N txtCropW).Text = [string]$info.Width }
        if ((N txtCropH).Text -eq "0") { (N txtCropH).Text = [string]$info.Height }
    } catch {
        (N tbPreviewInfo).Text = $path
    }
}
function Build-OutputPath([string]$suggestedName) {
    if ($script:Settings.OutputDir -and (Test-Path -LiteralPath $script:Settings.OutputDir)) {
        return Join-Path $script:Settings.OutputDir $suggestedName
    }
    return $null
}
function Require-WorkingImage {
    if (-not $script:WorkingImage) {
        Set-Status "Load an image first." "#ff6b6b"
        return $false
    }
    return $true
}
function After-Apply($result, $chainCheckbox) {
    Set-Status ("Saved -> {0}" -f $result.Output) "#2ec4b6"
    Update-Publish $result.Output
    if ($chainCheckbox -and $chainCheckbox.IsChecked) {
        $script:WorkingImage = $result.Output
        (N tbWorking).Text = [System.IO.Path]::GetFileName($result.Output)
        $script:Settings.LastImage = $result.Output
        Save-Settings
    }
}
function Update-Publish([string]$path) { Update-Preview $path }

# --- Toolbar handlers ---------------------------------------------------------
(N btnLoad).Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "Images|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tiff;*.tif|All files|*.*"
    $dlg.Title = "Load an image"
    if ($dlg.ShowDialog() -eq $true) {
        $script:WorkingImage = $dlg.FileName
        (N tbWorking).Text = [System.IO.Path]::GetFileName($dlg.FileName)
        $script:Settings.LastImage = $dlg.FileName
        Save-Settings
        Update-Preview $dlg.FileName
        Set-Status "Loaded: $($dlg.FileName)"
    }
})
(N btnOutDir).Add_Click({
    if ($script:Settings.OutputDir -and (Test-Path -LiteralPath $script:Settings.OutputDir)) {
        Start-Process explorer.exe -ArgumentList $script:Settings.OutputDir
    } else {
        Set-Status "No output folder set — open Settings to choose one." "#ffd166"
    }
})
(N btnReload).Add_Click({
    try {
        Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
        Set-Status "ImageTools module reloaded." "#2ec4b6"
    } catch { Set-Status "Reload failed: $_" "#ff6b6b" }
})

# --- Slider live labels -------------------------------------------------------
(N sldConvQuality).Add_ValueChanged({ (N tbConvQ).Text = [string][int]((N sldConvQuality).Value); $script:Settings.DefaultQuality = [int]((N sldConvQuality).Value) })
(N sldPct).Add_ValueChanged({ (N tbPct).Text = "{0} %" -f [int]((N sldPct).Value) })
(N sldEffectVal).Add_ValueChanged({ (N tbEffectValShow).Text = [string]([math]::Round((N sldEffectVal).Value, 2)) })

# --- Resize mode toggle -------------------------------------------------------
(N cboResizeMode).Add_SelectionChanged({
    $pct = ((N cboResizeMode).SelectedItem -eq "Percent")
    (N gridPct).Visibility = if ($pct) { "Visible" } else { "Collapsed" }
    (N tbPct).Visibility   = if ($pct) { "Visible" } else { "Collapsed" }
    (N gridDim).IsEnabled = -not $pct
})

# --- Effect value toggle ------------------------------------------------------
(N cboEffect).Add_SelectionChanged({
    $eff = (N cboEffect).SelectedItem
    $show = ($eff -eq "Brightness" -or $eff -eq "Contrast")
    (N gridEffectVal).Visibility = if ($show) { "Visible" } else { "Collapsed" }
    (N tbEffectValShow).Visibility = if ($show) { "Visible" } else { "Collapsed" }
    if ($eff -eq "Brightness") { (N tbEffectVal).Text = "Brightness (-1..1)"; (N sldEffectVal).Minimum = -1; (N sldEffectVal).Maximum = 1; (N sldEffectVal).Value = 0.2 }
    if ($eff -eq "Contrast")   { (N tbEffectVal).Text = "Contrast (0..3)";    (N sldEffectVal).Minimum = 0;  (N sldEffectVal).Maximum = 3; (N sldEffectVal).Value = 1.3 }
})

# --- Batch watermark toggle ---------------------------------------------------
(N cboBatchOp).Add_SelectionChanged({
    $show = ((N cboBatchOp).SelectedItem -eq "Watermark")
    (N gridBatchWm).Visibility = if ($show) { "Visible" } else { "Collapsed" }
})

# --- Operation handlers -------------------------------------------------------
function Invoke-Op([scriptblock]$body, $chainCheckbox) {
    try {
        $result = & $body
        After-Apply $result $chainCheckbox
    } catch {
        Set-Status ("ERROR: {0}" -f $_.Exception.Message) "#ff6b6b"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Operation failed", "OK", "Warning") | Out-Null
    }
}

(N btnInfo).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    Update-Preview $script:WorkingImage
    Set-Status "Info refreshed."
})

(N btnConvert).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $fmt = (N cboConvFormat).SelectedItem
    $q   = [int]((N sldConvQuality).Value)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($script:WorkingImage) + ".$fmt"
    Invoke-Op { Convert-Image -Path $script:WorkingImage -Format $fmt -Quality $q -OutputPath (Build-OutputPath $name) } (N chkConvChain)
})

(N btnResize).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $name = [System.IO.Path]::GetFileName($script:WorkingImage)
    if ((N cboResizeMode).SelectedItem -eq "Percent") {
        $pct = [int]((N sldPct).Value)
        Invoke-Op { Resize-Image -Path $script:WorkingImage -Percent $pct -OutputPath (Build-OutputPath $name) } (N chkResizeChain)
    } else {
        $w = [int]((N txtW).Text); $h = [int]((N txtH).Text)
        $params = @{ Path = $script:WorkingImage; OutputPath = (Build-OutputPath $name) }
        if ($w -gt 0) { $params.Width = $w }
        if ($h -gt 0) { $params.Height = $h }
        if (-not (N chkAspect).IsChecked) { $params.NoMaintainAspect = $true }
        Invoke-Op { Resize-Image @params } (N chkResizeChain)
    }
})

(N btnCrop).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $x = [int]((N txtCropX).Text); $y = [int]((N txtCropY).Text)
    $cw = [int]((N txtCropW).Text); $ch = [int]((N txtCropH).Text)
    $name = [System.IO.Path]::GetFileName($script:WorkingImage)
    Invoke-Op { Crop-Image -Path $script:WorkingImage -X $x -Y $y -Width $cw -Height $ch -OutputPath (Build-OutputPath $name) } (N chkCropChain)
})

(N btnRotate).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $angle = [int]((N cboAngle).SelectedItem); $flip = (N cboFlip).SelectedItem
    $name = [System.IO.Path]::GetFileName($script:WorkingImage)
    Invoke-Op { Rotate-Image -Path $script:WorkingImage -Angle $angle -Flip $flip -OutputPath (Build-OutputPath $name) } (N chkRotateChain)
})

(N btnEffect).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $eff = (N cboEffect).SelectedItem
    $params = @{ Path = $script:WorkingImage; Effect = $eff; OutputPath = (Build-OutputPath ([System.IO.Path]::GetFileName($script:WorkingImage))) }
    if ($eff -eq "Brightness" -or $eff -eq "Contrast") { $params.Value = [double]([math]::Round((N sldEffectVal).Value, 2)) }
    Invoke-Op { Set-ImageEffect @params } (N chkEffectChain)
})

(N btnWm).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $text = (N txtWmText).Text; if ([string]::IsNullOrWhiteSpace($text)) { Set-Status "Watermark text is empty." "#ffd166"; return }
    $params = @{
        Path = $script:WorkingImage
        Text = $text
        FontSize = [int]((N txtWmSize).Text)
        Color = (N cboWmColor).SelectedItem
        Position = (N cboWmPos).SelectedItem
        Opacity = [int]((N txtWmOpacity).Text)
        OutputPath = (Build-OutputPath ([System.IO.Path]::GetFileName($script:WorkingImage)))
    }
    $script:Settings.WmText = $text; $script:Settings.WmFontSize = $params.FontSize
    $script:Settings.WmColor = $params.Color; $script:Settings.WmPosition = $params.Position
    $script:Settings.WmOpacity = $params.Opacity; Save-Settings
    Invoke-Op { Add-ImageWatermark @params } (N chkWmChain)
})

(N btnBorder).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $bw = [int]((N txtBorderW).Text); $col = (N txtBorderColor).Text
    $script:Settings.BorderWidth = $bw; $script:Settings.BorderColor = $col; Save-Settings
    $name = [System.IO.Path]::GetFileName($script:WorkingImage)
    Invoke-Op { Add-ImageBorder -Path $script:WorkingImage -Width $bw -ColorName $col -OutputPath (Build-OutputPath $name) } (N chkBorderChain)
})

(N btnThumb).Add_Click({
    if (-not (Require-WorkingImage)) { return }
    $sz = [int]((N txtThumbSize).Text); $script:Settings.ThumbnailSize = $sz; Save-Settings
    $name = [System.IO.Path]::GetFileName($script:WorkingImage)
    Invoke-Op { New-ImageThumbnail -Path $script:WorkingImage -Size $sz -OutputPath (Build-OutputPath $name) } (N chkThumbChain)
})

# --- Batch folder browse + run ------------------------------------------------
function Pick-Folder([string]$desc) {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $desc
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}
(N btnBatchIn).Add_Click({ $p = Pick-Folder "Select input folder"; if ($p) { (N txtBatchIn).Text = $p } })
(N btnBatchOut).Add_Click({ $p = Pick-Folder "Select output folder"; if ($p) { (N txtBatchOut).Text = $p } })

(N btnBatch).Add_Click({
    $inDir = (N txtBatchIn).Text; $outDir = (N txtBatchOut).Text
    if ([string]::IsNullOrWhiteSpace($inDir) -or -not (Test-Path -LiteralPath $inDir)) { Set-Status "Choose a valid input folder." "#ff6b6b"; return }
    if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = Join-Path $inDir "processed" }
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $op = (N cboBatchOp).SelectedItem
    $wmText = (N txtBatchWm).Text
    $scriptBlock = switch ($op) {
        "Resize to 50%"     { [scriptblock]::Create('param($p,$o) Resize-Image -Path $p -Percent 50 -OutputPath (Join-Path $o ([IO.Path]::GetFileName($p)))') }
        "Convert to JPG q85"{ [scriptblock]::Create('param($p,$o) Convert-Image -Path $p -Format jpg -Quality 85 -OutputPath (Join-Path $o ([IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFileName($p)) + ".jpg"))') }
        "Grayscale"         { [scriptblock]::Create('param($p,$o) Set-ImageEffect -Path $p -Effect Grayscale -OutputPath (Join-Path $o ([IO.Path]::GetFileName($p)))') }
        "Thumbnail 200px"   { [scriptblock]::Create('param($p,$o) New-ImageThumbnail -Path $p -Size 200 -OutputPath (Join-Path $o ([IO.Path]::GetFileName($p)))') }
        "Watermark"         { [scriptblock]::Create(('param($p,$o) Add-ImageWatermark -Path $p -Text ''{0}'' -OutputPath (Join-Path $o ([IO.Path]::GetFileName($p)))' -f ($wmText -replace "'","''"))) }
    }
    try {
        Set-Status "Processing folder…"
        (N btnBatch).IsEnabled = $false
        $window.Dispatcher.Invoke([action]{}, "Background")  # let UI paint
        $results = Invoke-BatchImage -InputDir $inDir -OutputDir $outDir -ScriptBlock $scriptBlock
        $count = @($results).Count
        (N tbBatchResult).Text = "Done. $count file(s) processed -> $outDir"
        Set-Status "Batch done: $count files." "#2ec4b6"
    } catch {
        Set-Status ("Batch ERROR: {0}" -f $_.Exception.Message) "#ff6b6b"
    } finally {
        (N btnBatch).IsEnabled = $true
    }
})

# --- Settings window ----------------------------------------------------------
(N btnSettings).Add_Click({
    [xml]$sx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PixelForge — Settings" Height="460" Width="460" Background="#1e1e2e" Foreground="#e0e0e0"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize" FontFamily="Segoe UI" FontSize="12">
    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Output folder (blank = same as input)" Foreground="#00b4d8" FontWeight="Bold"/>
        <Grid Grid.Row="1" Margin="0,4"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBox Name="sOut" Grid.Column="0" IsReadOnly="True"/>
            <Button Name="sOutBtn" Grid.Column="1" Content="…" Width="36" Padding="0"/>
        </Grid>
        <CheckBox Grid.Row="2" Name="sChain" Content="Set result as new working image after each apply" Margin="0,8"/>
        <TextBlock Grid.Row="3" Text="Default JPEG quality (1-100)" Foreground="#00b4d8" FontWeight="Bold" Margin="0,10,0,0"/>
        <Slider Grid.Row="4" Name="sQuality" Minimum="1" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True"/>
        <TextBlock Grid.Row="5" Name="sQualityLbl" Text="90" Margin="0,0,0,6"/>
        <StackPanel Grid.Row="6" VerticalAlignment="Bottom">
            <TextBlock Text="Settings are saved to %APPDATA%\PixelForge\settings.json" Foreground="#777" FontSize="10" TextWrapping="Wrap"/>
        </StackPanel>
        <StackPanel Grid.Row="7" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="sCancel" Content="Cancel" Width="90" Background="#3a3a55" Foreground="#e0e0e0"/>
            <Button Name="sSave" Content="Save settings" Width="120"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $sr = New-Object System.Xml.XmlNodeReader $sx
    $sw = [Windows.Markup.XamlReader]::Load($sr)
    $sw.Owner = $window
    $sOut = $sw.FindName("sOut"); $sOutBtn = $sw.FindName("sOutBtn")
    $sChain = $sw.FindName("sChain"); $sQuality = $sw.FindName("sQuality"); $sQualityLbl = $sw.FindName("sQualityLbl")
    $sOut.Text = [string]$script:Settings.OutputDir
    $sChain.IsChecked = [bool]$script:Settings.AutoChain
    $sQuality.Value = [int]$script:Settings.DefaultQuality
    $sQualityLbl.Text = [string]$script:Settings.DefaultQuality
    $sQuality.Add_ValueChanged({ $sQualityLbl.Text = [string][int]$sQuality.Value })
    $sOutBtn.Add_Click({ $p = Pick-Folder "Choose default output folder"; if ($p) { $sOut.Text = $p } })
    $sw.FindName("sCancel").Add_Click({ $sw.DialogResult = $false; $sw.Close() })
    $sw.FindName("sSave").Add_Click({
        $script:Settings.OutputDir = $sOut.Text
        $script:Settings.AutoChain = [bool]$sChain.IsChecked
        $script:Settings.DefaultQuality = [int]$sQuality.Value
        Save-Settings
        (N sldConvQuality).Value = [int]$script:Settings.DefaultQuality
        (N tbConvQ).Text = [string]$script:Settings.DefaultQuality
        Set-Status "Settings saved." "#2ec4b6"
        $sw.DialogResult = $true; $sw.Close()
    })
    $sw.ShowDialog() | Out-Null
})

# --- Auto-load last image -----------------------------------------------------
if ($script:Settings.LastImage -and (Test-Path -LiteralPath $script:Settings.LastImage)) {
    $script:WorkingImage = $script:Settings.LastImage
    (N tbWorking).Text = [System.IO.Path]::GetFileName($script:Settings.LastImage)
    Update-Preview $script:Settings.LastImage
    Set-Status "Loaded last image: $([System.IO.Path]::GetFileName($script:Settings.LastImage))"
}

# --- Show window --------------------------------------------------------------
$window.ShowDialog() | Out-Null
