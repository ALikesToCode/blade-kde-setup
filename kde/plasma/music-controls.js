// Add the Blade Music widget to existing application panels, once.
var added = [];
panels().forEach(function (panel) {
    var widgets = panel.widgets();
    if (!widgets.some(function (widget) {
        return ["org.kde.plasma.kickoff", "org.kde.plasma.kicker", "org.kde.plasma.icontasks"].indexOf(widget.type) >= 0;
    })) {
        return;
    }
    if (!widgets.some(function (widget) { return widget.type === "org.mysterious.blademusic"; })) {
        var widget = panel.addWidget("org.mysterious.blademusic");
        if (!widget) { throw new Error("Could not add org.mysterious.blademusic"); }
        added.push({panel: panel.id, type: widget.type});
    }
});
print(JSON.stringify({added: added}));
