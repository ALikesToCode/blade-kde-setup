// Plasma 6 layout applied by scripts/apply-panels.sh.
// Runtime values are injected as BLADE_* globals by the shell wrapper.

var bladeStatusItems = [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.volume",
    "org.kde.plasma.brightness",
    "org.kde.plasma.battery",
    "org.kde.plasma.notifications"
];

// Reachable from the tray arrow, never shown in the bar itself.
var bladeHiddenTrayItems = [
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.clipboard",
    "org.kde.kscreen",
    "org.kde.kdeconnect",
    "org.kde.kupapplet",
    "org.kde.plasma.dwellclicker",
    // Status icons of apps that duplicate Plasma's own audio and Bluetooth applets.
    "KMix",
    "blueman"
];

var bladeExtraTrayItems = bladeStatusItems.concat([
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.clipboard",
    "org.kde.kscreen",
    "org.kde.kdeconnect"
]);

var bladePinnedApplications = [
    "applications:org.kde.konsole.desktop",
    "applications:org.kde.dolphin.desktop",
    "applications:zen.desktop",
    "applications:dev.zed.Zed.desktop",
    "applications:antigravity.desktop",
    "applications:systemsettings.desktop"
];

var bladeEventCalendar = "org.kde.plasma.eventcalendar";
var bladeTelemetry = "org.kde.plasma.systemmonitor";
var bladeSpacer = "org.kde.plasma.panelspacer";

// Installed by their own scripts; placed here only when already present.
var bladeOptionalWidgets = [
    "org.mysterious.blademusic",
    "org.mysterious.bladepower"
];

// Earlier layouts used these; the tray and the combined telemetry replace them.
var bladeRetiredWidgets = [
    "org.kde.plasma.systemmonitor.cpu",
    "org.kde.plasma.systemmonitor.memory",
    "org.kde.plasma.systemmonitor.net",
    "org.kde.plasma.brightness",
    "org.kde.plasma.marginsseparator"
];

// Apps on the left, music centred between two spacers, status on the right.
var bladePrimaryOrder = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.icontasks",
    bladeSpacer,
    "org.kde.plasma.mediacontroller",
    "org.mysterious.blademusic",
    bladeSpacer,
    bladeTelemetry,
    "org.kde.plasma.systemtray",
    "org.mysterious.bladepower",
    bladeEventCalendar,
    "org.kde.plasma.showdesktop"
];

// The auto-hide panel on the large display has room for workspaces.
var bladeSecondaryOrder = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.icontasks",
    bladeSpacer,
    "org.kde.plasma.mediacontroller",
    "org.mysterious.blademusic",
    bladeSpacer,
    "org.kde.plasma.pager",
    bladeTelemetry,
    "org.kde.plasma.systemtray",
    "org.mysterious.bladepower",
    bladeEventCalendar,
    "org.kde.plasma.showdesktop"
];

function bladeWrite(widget, group, values) {
    widget.currentConfigGroup = group;
    Object.keys(values).forEach(function (key) {
        widget.writeConfig(key, values[key]);
    });
    widget.currentConfigGroup = [];
    widget.reloadConfig();
}

function bladeReadList(widget, group, key) {
    widget.currentConfigGroup = group;
    var current = widget.readConfig(key, []);
    widget.currentConfigGroup = [];
    if (Array.isArray(current)) {
        return current;
    }
    if (typeof current !== "string" || current.length === 0) {
        return [];
    }
    if (current.charAt(0) === "[") {
        try {
            var parsed = JSON.parse(current);
            return Array.isArray(parsed) ? parsed : [];
        } catch (error) {
            return [];
        }
    }
    return current.split(",").filter(function (value) {
        return value.length > 0;
    });
}

function bladeMergeList(widget, group, key, wanted) {
    var merged = bladeReadList(widget, group, key);
    wanted.forEach(function (value) {
        if (merged.indexOf(value) === -1) {
            merged.push(value);
        }
    });
    var values = {};
    values[key] = merged;
    bladeWrite(widget, group, values);
}

function bladeWidgetsOfType(panel, type) {
    return panel.widgets().filter(function (widget) {
        return widget.type === type;
    });
}

function bladeAddWidget(panel, type) {
    var before = {};
    panel.widgets().forEach(function (widget) {
        before[widget.id] = true;
    });

    var result = panel.addWidget(type);
    if (result && result.id !== undefined) {
        return result;
    }

    var after = panel.widgets();
    for (var index = 0; index < after.length; ++index) {
        if (!before[after[index].id] && after[index].type === type) {
            return after[index];
        }
    }
    print("Blade panels: unavailable widget " + type);
    return null;
}

function bladeApplyOrder(panel, widgets) {
    var present = {};
    panel.widgets().forEach(function (widget) {
        present[String(widget.id)] = true;
    });

    var ids = [];
    widgets.forEach(function (widget) {
        var id = widget ? String(widget.id) : "";
        if (present[id] && ids.indexOf(id) === -1) {
            ids.push(id);
        }
    });

    // Widgets the user added stay, after the Blade set and in their old order.
    panel.currentConfigGroup = ["General"];
    var storedOrder = panel.readConfig("AppletOrder", "");
    panel.currentConfigGroup = [];
    var stored = typeof storedOrder === "string" ? storedOrder.split(";") : [];
    stored.concat(Object.keys(present)).forEach(function (id) {
        if (present[id] && ids.indexOf(id) === -1) {
            ids.push(id);
        }
    });

    bladeWrite(panel, ["General"], {"AppletOrder": ids.join(";")});
}

function bladeConfigureTelemetry(widget) {
    if (!widget) {
        return;
    }

    var gpu = BLADE_GPU_PREFIX + "/usage";
    // The text face fills two rows column by column, but sizes the panel item
    // from the first two sensors only. Leading with the widest label (RAM) and
    // the widest value (network) keeps every label visible.
    var sensors = ["memory/physical/usedPercent", "network/all/download", "cpu/all/usage", gpu];
    var details = [
        "cpu/all/averageTemperature",
        "memory/physical/used",
        BLADE_GPU_PREFIX + "/temperature",
        BLADE_GPU_PREFIX + "/usedVram",
        "network/all/upload"
    ];

    bladeWrite(widget, [], {
        "CurrentPreset": "org.kde.plasma.systemmonitor",
        "highPrioritySensorIds": JSON.stringify(sensors),
        "lowPrioritySensorIds": JSON.stringify(details),
        "showTitle": false,
        "title": "System",
        "totalSensors": JSON.stringify([]),
        "updateRateLimit": 2000
    });
    bladeWrite(widget, ["Appearance"], {
        "chartFace": "org.kde.ksysguard.textonly",
        "title": "System"
    });
    bladeWrite(widget, ["FaceConfig"], {
        "groupByTotal": false
    });
    var colors = {};
    colors["cpu/all/usage"] = "138,180,248";
    colors["memory/physical/usedPercent"] = "129,201,149";
    colors[gpu] = "84,209,255";
    colors["network/all/download"] = "197,138,249";
    bladeWrite(widget, ["SensorColors"], colors);
    var labels = {};
    labels["cpu/all/usage"] = "CPU";
    labels["memory/physical/usedPercent"] = "RAM";
    labels[gpu] = "GPU";
    labels["network/all/download"] = "NET";
    bladeWrite(widget, ["SensorLabels"], labels);
    bladeWrite(widget, ["Sensors"], {
        "highPrioritySensorIds": JSON.stringify(sensors),
        "lowPrioritySensorIds": JSON.stringify(details),
        "totalSensors": JSON.stringify([])
    });
}

function bladeConfigureTray(widget) {
    bladeMergeList(widget, ["General"], "extraItems", bladeExtraTrayItems);
    bladeMergeList(widget, ["General"], "hiddenItems", bladeHiddenTrayItems);
    var shown = bladeReadList(widget, ["General"], "shownItems");
    bladeStatusItems.forEach(function (item) {
        if (shown.indexOf(item) === -1) {
            shown.push(item);
        }
    });
    bladeWrite(widget, ["General"], {
        "shownItems": shown.filter(function (item) {
            return bladeHiddenTrayItems.indexOf(item) === -1;
        }),
        "showAllItems": false
    });
}

function bladeConfigureWidget(widget, type) {
    if (!widget) {
        return;
    }

    if (type === "org.kde.plasma.kickoff") {
        bladeWrite(widget, ["General"], {"icon": BLADE_ICON_PATH});
    } else if (type === "org.kde.plasma.icontasks") {
        bladeMergeList(widget, ["General"], "launchers", bladePinnedApplications);
        bladeWrite(widget, ["General"], {
            "groupingStrategy": 1,
            "indicateAudioStreams": true,
            "showOnlyCurrentActivity": false,
            "showOnlyCurrentDesktop": false,
            "showOnlyCurrentScreen": true,
            "wheelEnabled": true
        });
    } else if (type === "org.kde.plasma.pager") {
        bladeWrite(widget, ["General"], {
            "displayedText": "Number",
            "showWindowIcons": true,
            "wrapPage": true
        });
    } else if (type === "org.kde.plasma.systemtray") {
        bladeConfigureTray(widget);
    } else if (type === bladeSpacer) {
        bladeWrite(widget, ["General"], {"expanding": true});
    } else if (type === "org.kde.plasma.digitalclock") {
        bladeWrite(widget, ["Appearance"], {
            "showDate": true,
            "showSeconds": false
        });
    } else if (type === bladeEventCalendar) {
        bladeWrite(widget, ["General"], {
            "pin": false,
            "widgetShowMeteogram": false,
            "widgetShowTimer": false,
            "widgetShowAgenda": true,
            "widgetShowCalendar": true,
            "clockFontFamily": "Noto Sans",
            "clockTimeFormat1": "HH:mm",
            "clockTimeFormat2": "ddd d MMM",
            "clockShowLine2": true,
            "clockLine2HeightRatio": 0.32,
            "clockLineBold1": false,
            "clockLineBold2": false,
            "clockMaxHeight": 38,
            "showOutlines": false,
            "showBackground": false,
            "topRowHeight": 96,
            "bottomRowHeight": 420,
            "leftColumnWidth": 380,
            "rightColumnWidth": 440
        });
        bladeWrite(widget, ["Calendar"], {
            "monthShowBorder": false,
            "monthShowWeekNumbers": false,
            "monthEventBadgeType": "dots",
            "monthTodayStyle": "theme",
            "monthCellRadius": 0.34,
            "monthHighlightCurrentDayWeek": true,
            "monthHeightSingleColumn": 320,
            "firstDayOfWeek": -1
        });
        bladeWrite(widget, ["Agenda"], {
            "twoColumns": true,
            "agendaWeatherOnRight": true,
            "agendaWeatherShowIcon": true,
            "agendaWeatherShowText": false,
            "agendaInProgressColor": "#81c995",
            "agendaDaySpacing": 16,
            "agendaEventSpacing": 8,
            "agendaMaxDescriptionLines": 3,
            "agendaShowEventDescription": true,
            "agendaCondensedAllDayEvent": true
        });
        bladeWrite(widget, ["Weather"], {
            "weatherUnits": "metric",
            "meteogramTextColor": "#f0f6fc",
            "meteogramGridColor": "#263b55",
            "meteogramRainColor": "#54d1ff",
            "meteogramPositiveTempColor": "#81c995",
            "meteogramNegativeTempColor": "#8ab4f8",
            "meteogramIconColor": "#8ab4f8"
        });
    } else if (type === bladeTelemetry) {
        bladeConfigureTelemetry(widget);
    }
}

function bladeOrderFor(panel) {
    return panel.screen === 0 ? bladePrimaryOrder : bladeSecondaryOrder;
}

// Resolve each order entry to a widget; a type listed twice (the spacers)
// maps to its first and second instance. Missing widgets are added unless
// they are optional or `addMissing` is false.
function bladeLayoutWidgets(panel, order, addMissing) {
    var used = {};
    var widgets = [];
    order.forEach(function (type) {
        var index = used[type] || 0;
        used[type] = index + 1;
        var matches = bladeWidgetsOfType(panel, type);
        var widget = matches.length > index ? matches[index] : null;
        if (!widget && addMissing && bladeOptionalWidgets.indexOf(type) === -1) {
            widget = bladeAddWidget(panel, type);
        }
        widgets.push({type: type, widget: widget});
    });
    return widgets;
}

function bladeConfigurePanel(panel, screenIndex) {
    panel.screen = screenIndex;
    panel.location = "bottom";
    panel.height = 52;
    panel.floating = true;
    panel.alignment = "center";
    panel.lengthMode = "fill";
    // Translucent with blur over the wallpaper, solid next to maximized windows.
    panel.opacity = "adaptive";
    // Keep the primary panel steady; the additional-display panel reveals on hover.
    panel.hiding = screenIndex === 0 ? "none" : "autohide";

    var order = bladeOrderFor(panel);
    bladeRetiredWidgets.concat(order.indexOf("org.kde.plasma.pager") === -1 ? ["org.kde.plasma.pager"] : [])
        .forEach(function (type) {
            bladeWidgetsOfType(panel, type).forEach(function (widget) {
                widget.remove();
            });
        });

    var layout = bladeLayoutWidgets(panel, order, true);
    layout.forEach(function (entry) {
        bladeConfigureWidget(entry.widget, entry.type);
    });

    if (BLADE_REPLACE_CLOCK && bladeWidgetsOfType(panel, bladeEventCalendar).length > 0) {
        bladeWidgetsOfType(panel, "org.kde.plasma.digitalclock").forEach(function (widget) {
            widget.remove();
        });
    }
}

function bladeScreenCount() {
    var count = 1;
    desktops().forEach(function (desktop) {
        count = Math.max(count, desktop.screen + 1);
    });
    panels().forEach(function (panel) {
        count = Math.max(count, panel.screen + 1);
    });
    return count;
}

var bladePositionOnly = typeof BLADE_POSITION_ONLY !== "undefined" && BLADE_POSITION_ONLY;
var bladeCount = bladeScreenCount();
if (!bladePositionOnly) {
    if (BLADE_REPLACE_EXISTING) {
        panels().forEach(function (panel) {
            panel.remove();
        });
        for (var bladeScreen = 0; bladeScreen < bladeCount; ++bladeScreen) {
            var bladePanel = new Panel;
            bladeConfigurePanel(bladePanel, bladeScreen);
        }
    } else {
        for (var screenIndex = 0; screenIndex < bladeCount; ++screenIndex) {
            var candidates = panels().filter(function (panel) {
                return panel.screen === screenIndex;
            });
            var panel = candidates.length > 0 ? candidates[0] : new Panel;
            bladeConfigurePanel(panel, screenIndex);
        }
    }
}

// New applets join the panel only after the creating script returns, so the
// wrapper runs this pass again to put them in place.
panels().forEach(function (panel) {
    if (bladeWidgetsOfType(panel, "org.kde.plasma.icontasks").length === 0) {
        return;
    }
    bladeApplyOrder(panel, bladeLayoutWidgets(panel, bladeOrderFor(panel), false).map(function (entry) {
        return entry.widget;
    }));
});

print(bladePositionOnly
    ? "Blade panels: ordered launcher, music, telemetry, tray and clock"
    : "Blade panels: configured " + bladeCount + " display(s)");
