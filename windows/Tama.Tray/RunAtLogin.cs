using System.IO;
using System.Runtime.Versioning;
using Microsoft.Win32;
using Tama.Core.Ui;

namespace Tama.Tray;

/// <summary>
/// Registry-backed <see cref="IRunAtLogin"/>: writes/deletes a value named "Tama" (the quoted exe
/// path) under <c>HKCU\Software\Microsoft\Windows\CurrentVersion\Run</c> (planc-ui-spec.md §7
/// note 3 / task-6-brief.md). Off by default (no value present until the user opts in). All
/// registry access in this file — never touched anywhere else in Tama.Tray except Palette.cs's
/// own read-only theme probe (Palette.IsSystemDark).
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class RunAtLogin : IRunAtLogin
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Tama";

    public bool IsEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
            return key?.GetValue(ValueName) is string;
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException)
        { return false; }
    }

    public void SetEnabled(bool enabled)
    {
        try
        {
            if (enabled)
            {
                var exePath = Environment.ProcessPath;
                if (string.IsNullOrEmpty(exePath)) return;
                using var key = Registry.CurrentUser.CreateSubKey(KeyPath, writable: true);
                key?.SetValue(ValueName, $"\"{exePath}\"");
            }
            else
            {
                using var key = Registry.CurrentUser.OpenSubKey(KeyPath, writable: true);
                key?.DeleteValue(ValueName, throwOnMissingValue: false);
            }
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException)
        { /* best-effort; launch-at-login preference is not critical to app function */ }
    }
}
