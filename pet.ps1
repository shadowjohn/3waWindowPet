Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$window = New-Object Windows.Window
$window.Title = '3WA Capybara'
$window.WindowStyle = 'None'
$window.AllowsTransparency = $true
$window.Background = [Windows.Media.Brushes]::Transparent
$window.Width = 220
$window.Height = 220
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ResizeMode = 'NoResize'
$window.WindowStartupLocation = 'Manual'
$area = [System.Windows.SystemParameters]::WorkArea
$window.Left = $area.Right - $window.Width - 12
$window.Top = $area.Bottom - $window.Height - 12
$image = New-Object Windows.Controls.Image
$bitmap = New-Object Windows.Media.Imaging.BitmapImage
$bitmap.BeginInit()
$bitmap.UriSource = [Uri]::new((Join-Path $PSScriptRoot 'capybara.png'))
$bitmap.CacheOption = 'OnLoad'
$bitmap.EndInit()
$image.Source = $bitmap
$image.Stretch = 'Uniform'
$window.Content = $image
$menu = New-Object Windows.Controls.ContextMenu
$exit = New-Object Windows.Controls.MenuItem
$exit.Header = 'Exit'
$exit.Add_Click({ $window.Close() })
[void]$menu.Items.Add($exit)
$image.ContextMenu = $menu
$image.Add_MouseLeftButtonDown({
    if (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Alt) -ne 0) {
        try { $window.DragMove() } catch [System.InvalidOperationException] { }
    }
})
$scale = New-Object Windows.Media.ScaleTransform
$scale.CenterX = 110
$scale.CenterY = 200
$image.RenderTransform = $scale
$animation = New-Object Windows.Media.Animation.DoubleAnimation
$animation.From = 1.0
$animation.To = 1.025
$animation.Duration = [Windows.Duration]::new([TimeSpan]::FromSeconds(2.2))
$animation.AutoReverse = $true
$animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
$scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $animation)
[void]$window.ShowDialog()

