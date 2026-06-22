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
    internal const string NpcCommandName = "/npc";
    internal const string BellCommandName = "/bell";
    internal const string InnCommandName = "/inn";
    internal const string MarketBoardCommandName = "/mb";
    internal const string JumboBuyCommandName = "/jumbobuy";

    [PluginService] internal static IDalamudPluginInterface PluginInterface { get; private set; } = null!;
    [PluginService] internal static ICommandManager CommandManager { get; private set; } = null!;
    [PluginService] internal static IClientState ClientState { get; private set; } = null!;
    [PluginService] internal static IFramework Framework { get; private set; } = null!;
    [PluginService] internal static IDataManager DataManager { get; private set; } = null!;
    [PluginService] internal static IGameGui GameGui { get; private set; } = null!;
    [PluginService] internal static IChatGui ChatGui { get; private set; } = null!;
    [PluginService] internal static IObjectTable ObjectTable { get; private set; } = null!;
    [PluginService] internal static IPlayerState PlayerState { get; private set; } = null!;
    [PluginService] internal static IUnlockState UnlockState { get; private set; } = null!;
    [PluginService] internal static IPluginLog Log { get; private set; } = null!;

    internal Configuration Configuration { get; }

    internal UnlockDataService UnlockData { get; }

    internal NpcNavigationService NpcNavigation { get; }

    internal BellNavigationService BellNavigation { get; }

    internal WindowSystem WindowSystem { get; } = new("VaelarisUnlockList");

    private readonly MainWindow mainWindow;

    public Plugin()
    {
        Configuration = PluginInterface.GetPluginConfig() as Configuration ?? new Configuration();
        Configuration.LoadLocalManualCompletedIds();
        Configuration.Save();

        UnlockData = new UnlockDataService(DataManager, GameGui, PlayerState, UnlockState, Log, Configuration);
        UnlockData.Load();
        NpcNavigation = new NpcNavigationService(DataManager, GameGui, ClientState, CommandManager, Framework, ChatGui, Log);
        BellNavigation = new BellNavigationService(DataManager, GameGui, ClientState, ObjectTable, CommandManager, Framework, ChatGui, Log);

        mainWindow = new MainWindow(this);
        WindowSystem.AddWindow(mainWindow);

        CommandManager.AddHandler(CommandName, new CommandInfo(OnCommand)
        {
            HelpMessage = "Open the Vaelaris unlockables checklist.",
        });
        CommandManager.AddHandler(NpcCommandName, new CommandInfo(OnNpcCommand)
        {
            HelpMessage = "Mark an NPC on the map and run /gtf. Usage: /npc <npc name>",
        });
        CommandManager.AddHandler(BellCommandName, new CommandInfo(OnBellCommand)
        {
            HelpMessage = "Mark the nearest retainer bell on the map and run /gtf.",
        });
        CommandManager.AddHandler(InnCommandName, new CommandInfo(OnInnCommand)
        {
            HelpMessage = "Run /li inn.",
        });
        CommandManager.AddHandler(MarketBoardCommandName, new CommandInfo(OnMarketBoardCommand)
        {
            HelpMessage = "Run /li mb.",
        });
        CommandManager.AddHandler(JumboBuyCommandName, new CommandInfo(OnJumboBuyCommand)
        {
            HelpMessage = "Mark the Jumbo Cactpot Broker in the Gold Saucer and run /gtf.",
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
        CommandManager.RemoveHandler(NpcCommandName);
        CommandManager.RemoveHandler(BellCommandName);
        CommandManager.RemoveHandler(InnCommandName);
        CommandManager.RemoveHandler(MarketBoardCommandName);
        CommandManager.RemoveHandler(JumboBuyCommandName);
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

    private void OnNpcCommand(string command, string args)
    {
        NpcNavigation.Navigate(args);
    }

    private void OnBellCommand(string command, string args)
    {
        BellNavigation.Navigate();
    }

    private void OnInnCommand(string command, string args)
    {
        if (!CommandManager.ProcessCommand("/li inn"))
        {
            ChatGui.PrintError("/li inn was not found. Install/enable Lifestream or run /li inn manually.");
        }
    }

    private void OnMarketBoardCommand(string command, string args)
    {
        if (!CommandManager.ProcessCommand("/li mb"))
        {
            ChatGui.PrintError("/li mb was not found. Install/enable Lifestream or run /li mb manually.");
        }
    }

    private void OnJumboBuyCommand(string command, string args)
    {
        var destination = UnlockData.Items.FirstOrDefault(item =>
            item.Locations.Any(location =>
                string.Equals(location.Place, "The Gold Saucer", StringComparison.OrdinalIgnoreCase)
                && location.X == 8.5f
                && location.Y == 5.9f));

        if (destination is null || !UnlockData.OpenMap(UnlockData.Resolve(destination)))
        {
            ChatGui.PrintError("Could not open the Jumbo Cactpot map location.");
            return;
        }

        Framework.RunOnTick(() =>
        {
            if (!CommandManager.ProcessCommand("/gtf"))
            {
                ChatGui.PrintError("Map flag opened, but /gtf was not found. Install/enable your goto-flag plugin or run /gtf manually.");
            }
        }, TimeSpan.FromMilliseconds(250));
    }
}
