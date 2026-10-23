// Add only the power controls to existing application panels.
var added = [];
panels().forEach(function (panel) {
    var widgets = panel.widgets();
    if (!widgets.some(function (widget) {
        return ["org.kde.plasma.kickoff", "org.kde.plasma.kicker", "org.kde.plasma.icontasks"].indexOf(widget.type) >= 0;
    })) {
        return;
    }
    // A panel with a system tray shows brightness there (blade-panels.js).
    var hasTray = widgets.some(function (widget) { return widget.type === "org.kde.plasma.systemtray"; });
    var types = hasTray ? ["org.mysterious.bladepower"] : ["org.kde.plasma.brightness", "org.mysterious.bladepower"];
    types.forEach(function (type) {
        if (!widgets.some(function (widget) { return widget.type === type; })) {
            var widget = panel.addWidget(type);
            if (!widget) { throw new Error("Could not add " + type); }
            added.push({panel: panel.id, type: type});
        }
    });
});
print(JSON.stringify({added: added}));
