using Dalamud.Game.Command;
using Dalamud.Interface.Windowing;
using Dalamud.IoC;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using VaelarisUnlockList.Services;
using VaelarisUnlockList.Windows;

namespace VaelarisUnlockList;

public sealed class Plugin : IDalamudPlugin
{
    internal const string CommandName = "/vunlock";

    [PluginService] internal static IDalamudPluginInterface PluginInterface { get; private set; } = null!;
    [PluginService] internal static ICommandManager CommandManager { get; private set; } = null!;
    [PluginService] internal static IClientState ClientState { get; private set; } = null!;
    [PluginService] internal static IDataManager DataManager { get; private set; } = null!;
    [PluginService] internal static IGameGui GameGui { get; private set; } = null!;
    [PluginService] internal static IPlayerState PlayerState { get; private set; } = null!;
    [PluginService] internal static IUnlockState UnlockState { get; private set; } = null!;
    [PluginService] internal static IPluginLog Log { get; private set; } = null!;

    internal Configuration Configuration { get; }

    internal UnlockDataService UnlockData { get; }

    internal WindowSystem WindowSystem { get; } = new("VaelarisUnlockList");

    private readonly MainWindow mainWindow;

    public Plugin()
    {
        Configuration = PluginInterface.GetPluginConfig() as Configuration ?? new Configuration();
        UnlockData = new UnlockDataService(DataManager, GameGui, PlayerState, UnlockState, Log, Configuration);
        UnlockData.Load();

        mainWindow = new MainWindow(this);
        WindowSystem.AddWindow(mainWindow);

        CommandManager.AddHandler(CommandName, new CommandInfo(OnCommand)
        {
            HelpMessage = "Open the Vaelaris unlockables checklist.",
        });

        PluginInterface.UiBuilder.Draw += WindowSystem.Draw;
        PluginInterface.UiBuilder.OpenMainUi += ToggleMainUi;
        PluginInterface.UiBuilder.OpenConfigUi += ToggleMainUi;
    }

    public void Dispose()
    {
        PluginInterface.UiBuilder.Draw -= WindowSystem.Draw;
        PluginInterface.UiBuilder.OpenMainUi -= ToggleMainUi;
        PluginInterface.UiBuilder.OpenConfigUi -= ToggleMainUi;

        CommandManager.RemoveHandler(CommandName);
        WindowSystem.RemoveAllWindows();
        mainWindow.Dispose();
    }

    internal void ToggleMainUi()
    {
        mainWindow.Toggle();
    }

    private void OnCommand(string command, string args)
    {
        ToggleMainUi();
    }
}
