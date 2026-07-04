namespace Tama.Tray;

// UseWPF + UseWindowsForms both contribute an implicit global "using" for their
// respective Application type (System.Windows.Application vs
// System.Windows.Forms.Application), so the bare name is ambiguous (CS0104).
// Fully qualify instead of "using System.Windows;".
public partial class App : System.Windows.Application
{
    public App()
    {
        // Tray widget must not die to a stray UI exception — swallow and log. Trace.WriteLine (not
        // Debug.WriteLine) so this is visible in Release builds too, not compiled out.
        DispatcherUnhandledException += (_, e) =>
        {
            System.Diagnostics.Trace.WriteLine(e.Exception);
            e.Handled = true;
        };
    }
}
